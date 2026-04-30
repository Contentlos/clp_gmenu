--[[
    clp_gmenu - Persistenter Datenspeicher (Server)

    Zentrale Datenquelle fuer Jobs, Aktionen, Items und Globale Einstellungen.

    Datenfluss:
      1. Beim Resource-Start: Load data/jobs.json
         - Wenn fehlt/korrupt -> Seed aus Config.JobsSeed + Config.ActionsSeed
      2. Aenderungen via Store.set() / Store.delete() / Store.replace()
         - Bumpt Version, schreibt sofort auf Disk (atomic via .bak-Rotation),
           triggert Sync-Event an alle Clients.
      3. Clients holen sich Snapshot via Callback 'clp_gmenu:store:snapshot'.

    API:
      Store.getSnapshot()             -> deepCopy der gesamten Daten
      Store.getJobs()                 -> jobs-Tabelle (read-only-Convention)
      Store.getJob(name)              -> ein Job
      Store.getActions()              -> actions-Tabelle
      Store.getAction(id)             -> eine Action (Standard ODER Custom)
      Store.getCustomActions()        -> nur Custom-Actions
      Store.getGlobals()              -> globals-Tabelle (Farben, Distanz, Theme)
      Store.getItems()                -> items-Tabelle
      Store.getVersion()              -> aktuelle Version (number)
      Store.set(path, value, by)      -> Pfad-basiert setzen, persistieren, syncen
      Store.delete(path, by)          -> Pfad-basiert loeschen
      Store.replace(newData, by)      -> komplette Daten ersetzen (Import)
      Store.resetToDefault(by)        -> Re-Seed aus Config.JobsSeed
      Store.save()                    -> manuelles Speichern
]]

GMenu = GMenu or {}
GMenu.Store = {}

local Store = GMenu.Store
local U = GMenu.Util

-- ============================================================
--  INTERNER ZUSTAND
-- ============================================================
local data       -- aktueller Store
local dirty      -- Aenderungen ausstehend
local saveLock   -- Schreibsperre
local lastSaveTs -- letzter erfolgreicher Speicherzeitpunkt (Zeit-String)
local subscribers = {}   -- Callbacks die bei Aenderung benachrichtigt werden
local debounceTimer = nil  -- Verzoegerungs-Timer fuer persist()
local DEBOUNCE_MS = 500    -- Verzoegerungs-Intervall fuer Schreibvorgaenge

-- ============================================================
--  SEED
-- ============================================================

--- Erstellt einen frischen Store aus den config-Seeds.
local function buildSeed()
    -- Hex-Helper aus Default-Farben (Config.UIColor etc.)
    local function hex(rgb)
        return U.rgbToHex(rgb)
    end

    local jobs = U.deepCopy(Config.JobsSeed or {})
    local actions = U.deepCopy(Config.ActionsSeed or {})

    return {
        _version       = 1,
        _lastModified  = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        _lastModifiedBy= 'system:seed',

        items   = U.deepCopy(Config.Items or {}),

        globals = {
            uiColor      = hex(Config.UIColor),
            outlineColor = hex(Config.OutlineColor),
            markerColor  = hex(Config.MarkerColor),
            maxDistance  = Config.MaxDistance,
            defaultTheme = Config.DefaultTheme,
            outlinePulse        = Config.OutlinePulse,
            markerArrowBobbing  = Config.MarkerArrowBobbing,
            markerCircleSpin    = Config.MarkerCircleSpin,
            highlightFadeMs     = Config.HighlightFadeMs,
            enableSounds        = Config.EnableSounds,
            showVehicleStats    = Config.ShowVehicleStats,
            menuAnchor          = Config.MenuAnchor,
        },

        jobs    = jobs,
        actions = actions,            -- Standard-Library (read-mostly im Editor)

        customActions = {},           -- vom Admin erstellte

        -- Universal Framework (Phase 2):
        defaults = U.deepCopy(Config.DefaultActionsSeed or {
            player  = {},
            ped     = {},
            vehicle = {},
            object  = {},
            zone    = {},
            self    = {},
        }),
        npcs    = U.deepCopy(Config.NPCsSeed or {}),
        zones   = U.deepCopy(Config.ZonesSeed or {}),
        identity = U.deepCopy(Config.IdentitySeed or {
            shareJob       = false,
            allowAdminLink = true,
            nameplates     = true,
        }),
    }
end

-- ============================================================
--  IO
-- ============================================================

local function readJsonFile(path)
    local raw = LoadResourceFile(GetCurrentResourceName(), path)
    if not raw or raw == '' then return nil end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then return nil end
    return decoded
end

local function writeJsonFile(path, tbl)
    local ok, encoded = pcall(json.encode, tbl, { indent = true })
    if not ok or type(encoded) ~= 'string' then
        print('^1[clp_gmenu]^0 Store: JSON-Kodierung fehlgeschlagen:', tostring(encoded))
        return false, 'json_encode'
    end

    local result = SaveResourceFile(GetCurrentResourceName(), path, encoded, -1)
    -- SaveResourceFile gibt true/1 bei Erfolg, false/0 bei Fehler.
    -- Wir behandeln BEIDE Falsy-Varianten konsequent:
    local success = (result == true) or (result == 1)
    if not success then
        return false, ('SaveResourceFile=' .. tostring(result) .. ' bytes=' .. #encoded)
    end
    return true
end

--- Validiert die Mindeststruktur. Gibt true zurueck oder false + Fehlermeldung.
local function validateData(d)
    if type(d) ~= 'table' then return false, 'Daten sind keine Tabelle' end
    if type(d.jobs) ~= 'table' then return false, 'data.jobs fehlt' end
    if type(d.actions) ~= 'table' then return false, 'data.actions fehlt' end
    if type(d.globals) ~= 'table' then return false, 'data.globals fehlt' end
    if type(d.items) ~= 'table' then return false, 'data.items fehlt' end
    return true
end

--- Normalisiert geladene Daten: setzt fehlende Felder mit Defaults.
local function normalize(d)
    d._version       = tonumber(d._version) or 1
    d._lastModified  = d._lastModified or os.date('!%Y-%m-%dT%H:%M:%SZ')
    d._lastModifiedBy= d._lastModifiedBy or 'system'
    d.items          = d.items or {}
    d.globals        = d.globals or {}
    d.jobs           = d.jobs or {}
    d.actions        = d.actions or {}
    d.customActions  = d.customActions or {}
    d.defaults       = d.defaults or {
        player  = {},
        ped     = {},
        vehicle = {},
        object  = {},
        zone    = {},
        self    = {},
    }
    d.npcs           = d.npcs or {}
    d.zones          = d.zones or {}
    d.identity       = d.identity or { shareJob = false, allowAdminLink = true, nameplates = true }
    return d
end

-- ============================================================
--  ATOMARER SCHREIBVORGANG (Backup-Rotation)
-- ============================================================

local function persist()
    if saveLock then
        -- Sicherheitsnetz: Lock loesen falls steckengeblieben (>5s alt)
        if saveLock + 5000 < GetGameTimer() then
            print('^3[clp_gmenu]^0 Store: Veraltete Schreibsperre erkannt, wird freigegeben.')
            saveLock = nil
        else
            return false
        end
    end
    saveLock = GetGameTimer()

    -- 1) Aktuellen Stand als Backup sichern (Sicherheitskopie)
    local current = LoadResourceFile(GetCurrentResourceName(), Config.StorePath)
    if current and current ~= '' then
        SaveResourceFile(GetCurrentResourceName(), Config.StoreBackupPath, current, -1)
    end

    -- 2) Neue Daten auf Platte schreiben
    local ok, why = writeJsonFile(Config.StorePath, data)

    saveLock = nil

    if not ok then
        print(('^1[clp_gmenu]^0 Store: Speichern fehlgeschlagen (%s) -> "%s"'):format(
            tostring(why or 'unbekannt'), Config.StorePath
        ))
        print('^3[clp_gmenu]^0   Tipps:')
        print('^3[clp_gmenu]^0   - "data/jobs.json" ist im fxmanifest deklariert?')
        print('^3[clp_gmenu]^0   - Schreibrechte auf resources/[CLP]/clp_gmenu/data/?')
        print('^3[clp_gmenu]^0   - Pruefe SQL-Fallback ueber Config.UseSqlFallback = true')

        -- Fallback: SQL-Persistenz, falls aktiviert (siehe sql_store.lua)
        if Config.UseSqlFallback and GMenu.SqlStore and GMenu.SqlStore.save then
            local sok = GMenu.SqlStore.save(data)
            if sok then
                print('^2[clp_gmenu]^0 Store: SQL-Fallback war erfolgreich.')
                dirty = false
                return true
            end
        end
        return false
    end

    dirty = false
    lastSaveTs = os.date('%Y-%m-%d %H:%M:%S')
    return true
end

-- ============================================================
--  VERZOEGERTES SPEICHERN
-- ============================================================

--- Plant einen Schreibvorgang mit Verzoegerung (~500ms).
--- Mehrere Aufrufe innerhalb des Fensters werden zu einem einzigen Schreibvorgang gebuendelt.
local function schedulePersist()
    dirty = true
    if debounceTimer then return end  -- bereits geplant
    debounceTimer = true
    SetTimeout(DEBOUNCE_MS, function()
        debounceTimer = nil
        if dirty then persist() end
    end)
end

-- ============================================================
--  LADEN (Start)
-- ============================================================

local function load()
    -- 1) Versuche die aktuelle Datei
    local loaded = readJsonFile(Config.StorePath)

    -- 2) Falls korrupt: Backup versuchen
    if loaded and not select(1, validateData(loaded)) then
        print('^3[clp_gmenu]^0 Store: jobs.json ungueltig, versuche Backup...')
        loaded = readJsonFile(Config.StoreBackupPath)
    end

    -- 3) SQL-Fallback (nur wenn JSON nichts brachte und Fallback aktiv ist)
    if not loaded and Config.UseSqlFallback and GMenu.SqlStore and GMenu.SqlStore.load then
        local sqlData = GMenu.SqlStore.load()
        if sqlData then
            print('^2[clp_gmenu]^0 Store: Aus SQL-Fallback geladen.')
            loaded = sqlData
        end
    end

    -- 4) Validieren
    if loaded then
        local valid, err = validateData(loaded)
        if not valid then
            print(('^3[clp_gmenu]^0 Store: Backup ungueltig (%s) - wird neu erstellt.'):format(err))
            loaded = nil
        end
    end

    -- 5) Falls nichts geladen: Erstbefuellung
    if not loaded then
        print('^2[clp_gmenu]^0 Store: Erstbefuellung aus config/jobs.lua (erster Start).')
        data = buildSeed()
        persist()
        -- Standard-Snapshot fuer "Auf Standard zuruecksetzen" anlegen
        writeJsonFile(Config.StoreDefaultPath, data)
    else
        data = normalize(loaded)
        print(('^2[clp_gmenu]^0 Store: jobs.json geladen (v%d, %d Jobs, %d Custom-Aktionen).'):format(
            data._version, U.tableCount(data.jobs), U.tableCount(data.customActions)
        ))
    end
end

-- ============================================================
--  AENDERUNGS-BENACHRICHTIGUNG
-- ============================================================

local function notifySubscribers(path, value, by)
    for i = 1, #subscribers do
        local ok, err = pcall(subscribers[i], path, value, by, data._version)
        if not ok then
            print('^1[clp_gmenu]^0 Store-Abonnent Fehler:', err)
        end
    end
end

--- Registriert einen Listener (Zuhörer): callback(pfad, wert, von, version)
function Store.subscribe(callback)
    if type(callback) == 'function' then
        subscribers[#subscribers + 1] = callback
    end
end

-- ============================================================
--  OEFFENTLICHE API - LESE-ZUGRIFFE
-- ============================================================

function Store.getSnapshot()
    return U.deepCopy(data)
end

function Store.getLastSaveTs()
    return lastSaveTs
end

function Store.getVersion()
    return data and data._version or 0
end

function Store.getJobs()
    return data.jobs
end

function Store.getJob(name)
    return data.jobs and data.jobs[name] or nil
end

function Store.getActions()
    return data.actions
end

function Store.getCustomActions()
    return data.customActions
end

--- Liefert eine Aktion (Standard oder Custom). Custom hat Vorrang bei Konflikt.
function Store.getAction(id)
    if not id then return nil end
    return (data.customActions and data.customActions[id])
        or (data.actions and data.actions[id])
        or nil
end

function Store.getGlobals()
    return data.globals
end

function Store.getItems()
    return data.items
end

-- ============================================================
--  DEFAULTS / NPCs / ZONES (Universal Framework)
-- ============================================================

--- Gibt die Default-Aktions-IDs zurueck, die jeder Spieler fuer einen Zieltyp hat.
--- Schema in data: data.defaults = { player = { ... }, vehicle = { ... }, ... }
function Store.getDefaults(targetType)
    if not data or type(data.defaults) ~= 'table' then return {} end
    local list = data.defaults[targetType]
    if type(list) == 'table' then return list end
    -- Fallback: 'player'-Defaults gelten auch fuer 'ped'
    if targetType == 'ped' and type(data.defaults.player) == 'table' then
        return data.defaults.player
    end
    return {}
end

function Store.getNpcs()
    return data and data.npcs or {}
end

function Store.getZones()
    return data and data.zones or {}
end

--- Liefert effektive Berechtigungen+Aktionen fuer Job+Rang inklusive Vererbung.
function Store.getEffectiveRank(jobName, rankIndex)
    local job = Store.getJob(jobName)
    if not job or not job.enabled then return nil end

    local rankKey = tostring(rankIndex)
    local rank = job.ranks and job.ranks[rankKey]
    if not rank then return nil end

    -- Vererbung: Eltern-Job mit gleichem Rang-Key wird zuerst zusammengefuehrt.
    local merged = { permissions = {}, actions = { player = {}, vehicle = {}, ped = {}, self = {} } }

    if job.inherits and job.inherits ~= '' then
        local parent = Store.getEffectiveRank(job.inherits, rankIndex)
        if parent then
            merged.permissions = U.deepCopy(parent.permissions or {})
            merged.actions.player  = U.deepCopy(parent.actions and parent.actions.player or {})
            merged.actions.vehicle = U.deepCopy(parent.actions and parent.actions.vehicle or {})
            merged.actions.ped     = U.deepCopy(parent.actions and parent.actions.ped or {})
            merged.actions.self    = U.deepCopy(parent.actions and parent.actions.self or {})
        end
    end

    -- Eigene Berechtigungen ueberschreiben
    if rank.permissions then
        for k, v in pairs(rank.permissions) do
            merged.permissions[k] = v
        end
    end

    -- Aktionen: Vereinigung (vermeide Duplikate)
    local function unionList(target, src)
        if not src then return end
        local seen = {}
        for i = 1, #target do seen[target[i]] = true end
        for i = 1, #src do
            if not seen[src[i]] then
                target[#target + 1] = src[i]
                seen[src[i]] = true
            end
        end
    end
    if rank.actions then
        unionList(merged.actions.player,  rank.actions.player)
        unionList(merged.actions.vehicle, rank.actions.vehicle)
        unionList(merged.actions.ped,     rank.actions.ped)
        unionList(merged.actions.self,    rank.actions.self)
    end

    merged.label = rank.label
    return merged
end

-- ============================================================
--  OEFFENTLICHE API - SCHREIB-ZUGRIFFE
-- ============================================================

local function bumpVersion(by)
    data._version       = (data._version or 0) + 1
    data._lastModified  = os.date('!%Y-%m-%dT%H:%M:%SZ')
    data._lastModifiedBy= by or 'system'
end

--- Setzt einen Wert per Pfad ('jobs.police.label' = 'Polizei').
--- Loest Speichern + Benachrichtigung aus.
function Store.set(path, value, by)
    if type(path) ~= 'string' or path == '' then return false, 'Ungueltiger Pfad' end

    local ok = U.setByPath(data, path, value)
    if not ok then return false, 'Pfad konnte nicht gesetzt werden' end

    bumpVersion(by)
    schedulePersist()
    notifySubscribers(path, value, by or 'system')
    return true
end

function Store.delete(path, by)
    if type(path) ~= 'string' or path == '' then return false, 'Ungueltiger Pfad' end
    U.deleteByPath(data, path)
    bumpVersion(by)
    schedulePersist()
    notifySubscribers(path, nil, by or 'system')
    return true
end

--- Komplette Daten ersetzen (z.B. JSON-Import). Validiert das Schema.
function Store.replace(newData, by)
    if type(newData) ~= 'table' then return false, 'Keine Tabelle' end

    local valid, err = validateData(newData)
    if not valid then return false, err end

    local merged = normalize(newData)
    -- Version IMMER hochzaehlen, importierte Version ignorieren (verhindert Wiederholungen)
    merged._version       = (data._version or 0) + 1
    merged._lastModified  = os.date('!%Y-%m-%dT%H:%M:%SZ')
    merged._lastModifiedBy= by or 'system'

    data = merged
    dirty = true  -- Sicherstellen, dass Autosave bei Fehlschlag wiederholt
    local pOk = persist()
    if not pOk then
        print('^3[clp_gmenu]^0 Store: Ersetzen im Speicher erfolgreich, Schreiben auf Disk wird per Autosave nachgeholt.')
    end
    notifySubscribers('*', nil, by or 'system')
    return true
end

--- Stellt den urspruenglichen Seed aus config/jobs.lua wieder her.
function Store.resetToDefault(by)
    -- Versuche zuerst data/jobs.default.json (vom ersten Start gespeichert)
    local def = readJsonFile(Config.StoreDefaultPath)
    if not def then
        def = buildSeed()
        writeJsonFile(Config.StoreDefaultPath, def)
    end

    def._version       = (data._version or 0) + 1
    def._lastModified  = os.date('!%Y-%m-%dT%H:%M:%SZ')
    def._lastModifiedBy= by or 'system:reset'

    data = normalize(def)
    dirty = true  -- Sicherstellen, dass Autosave bei Fehlschlag wiederholt
    local pOk = persist()
    if not pOk then
        print('^3[clp_gmenu]^0 Store: Zuruecksetzen im Speicher erfolgreich, Schreiben auf Disk wird per Autosave nachgeholt.')
    end
    notifySubscribers('*', nil, by or 'system:reset')
    return true
end

function Store.save()
    return persist()
end

-- ============================================================
--  START (synchron) - laedt sofort, damit andere Module nicht warten muessen
-- ============================================================

load()

-- ============================================================
--  AUTOMATISCHES SPEICHERN
-- ============================================================

CreateThread(function()
    while true do
        Wait((Config.StoreAutosaveSeconds or 60) * 1000)
        if dirty then persist() end
    end
end)

-- ============================================================
--  AUFRAEUMEN BEIM RESOURCE-STOP
-- ============================================================

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if dirty and data then persist() end
end)
