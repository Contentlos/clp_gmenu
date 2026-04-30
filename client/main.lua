--[[
    clp_gmenu - Client-Hauptmodul

    Aufgaben:
      - ESX-Bootstrap (Initialisierung)
      - Store-Snapshot vom Server holen + Patches anwenden
      - Effektive Berechtigungen des Spielers zwischenspeichern
      - Globalen GMenu-Namespace bereitstellen (von allen anderen Client-Dateien genutzt)
      - KVP-Einstellungen laden (Benutzer-Einstellungen fuer Theme/Farben)
]]

if not lib then
    print('^1[clp_gmenu]^0 ox_lib fehlt! Bitte ox_lib zuerst starten.')
    return
end

GMenu = GMenu or {}
GMenu.Util = GMenu.Util or {}      -- shared/utils.lua hat dies befuellt

local U = GMenu.Util

-- ============================================================
--  ESX
-- ============================================================
local ESX = exports['es_extended']:getSharedObject()
GMenu.ESX = ESX

-- ============================================================
--  ZUSTAND
-- ============================================================
GMenu.State = {
    storeReady   = false,
    store        = nil,    -- Vom Server empfangen
    perms        = nil,    -- Effektive Berechtigungen des Spielers
    job          = nil,    -- Aktueller ESX-Job-Cache
    settings     = {},     -- Benutzer-KVP-Einstellungen (lokal)
    debug        = Config.Debug,
}

local State = GMenu.State

-- ============================================================
--  KVP-EINSTELLUNGEN (lokale Benutzer-Einstellungen)
-- ============================================================

local KVP_KEYS = {
    theme        = 'clp_gmenu:theme',
    uiColor      = 'clp_gmenu:uiColor',
    outlineColor = 'clp_gmenu:outlineColor',
    markerColor  = 'clp_gmenu:markerColor',
    enableSounds = 'clp_gmenu:enableSounds',
    showStats    = 'clp_gmenu:showVehicleStats',
    maxDistance  = 'clp_gmenu:maxDistance',
}

local function loadKvp()
    local s = State.settings
    s.theme        = GetResourceKvpString(KVP_KEYS.theme)        or nil
    s.uiColor      = GetResourceKvpString(KVP_KEYS.uiColor)      or nil
    s.outlineColor = GetResourceKvpString(KVP_KEYS.outlineColor) or nil
    s.markerColor  = GetResourceKvpString(KVP_KEYS.markerColor)  or nil

    local sound    = GetResourceKvpInt(KVP_KEYS.enableSounds)
    s.enableSounds = sound ~= 0   -- default true

    local stats    = GetResourceKvpInt(KVP_KEYS.showStats)
    s.showStats    = stats ~= 0   -- default true

    local dist     = GetResourceKvpFloat(KVP_KEYS.maxDistance)
    s.maxDistance  = dist > 0 and dist or nil
end

function GMenu.SaveKvp(key, value)
    if not KVP_KEYS[key] then return end
    if type(value) == 'boolean' then
        SetResourceKvpInt(KVP_KEYS[key], value and 1 or 0)
    elseif type(value) == 'number' then
        SetResourceKvpFloat(KVP_KEYS[key], value)
    elseif type(value) == 'string' then
        SetResourceKvp(KVP_KEYS[key], value)
    end
    State.settings[key] = value
end

-- ============================================================
--  EFFEKTIVE FARBEN / EINSTELLUNGEN (kombiniert KVP > Server-Globals > Config)
-- ============================================================

--- Liefert effektive Farbe als RGB-Tabelle.
function GMenu.GetColor(name)
    local kvpHex
    if name == 'ui'      then kvpHex = State.settings.uiColor      end
    if name == 'outline' then kvpHex = State.settings.outlineColor end
    if name == 'marker'  then kvpHex = State.settings.markerColor  end

    if kvpHex then return U.hexToRgb(kvpHex) end

    local globals = State.store and State.store.globals or {}
    if name == 'ui'      and globals.uiColor      then return U.hexToRgb(globals.uiColor)      end
    if name == 'outline' and globals.outlineColor then return U.hexToRgb(globals.outlineColor) end
    if name == 'marker'  and globals.markerColor  then return U.hexToRgb(globals.markerColor)  end

    if name == 'ui'      then return Config.UIColor      end
    if name == 'outline' then return Config.OutlineColor end
    if name == 'marker'  then return Config.MarkerColor  end
    return { r = 255, g = 255, b = 255 }
end

function GMenu.GetTheme()
    return State.settings.theme or (State.store and State.store.globals and State.store.globals.defaultTheme) or Config.DefaultTheme
end

function GMenu.GetMaxDistance()
    return State.settings.maxDistance
        or (State.store and State.store.globals and State.store.globals.maxDistance)
        or Config.MaxDistance
end

function GMenu.GetGlobalBool(key, default)
    local g = State.store and State.store.globals or {}
    if g[key] ~= nil then return g[key] and true or false end
    return default
end

function GMenu.GetSetting(key, default)
    if State.settings[key] ~= nil then return State.settings[key] end
    return default
end

function GMenu.SoundsEnabled()
    if State.settings.enableSounds ~= nil then return State.settings.enableSounds end
    return GMenu.GetGlobalBool('enableSounds', Config.EnableSounds)
end

function GMenu.StatsEnabled()
    if State.settings.showStats ~= nil then return State.settings.showStats end
    return GMenu.GetGlobalBool('showVehicleStats', Config.ShowVehicleStats)
end

function GMenu.GetSoundPreset()
    if State.settings.soundPreset and State.settings.soundPreset ~= '' then
        return State.settings.soundPreset
    end
    local g = State.store and State.store.globals or {}
    return g.soundPreset or Config.DefaultSoundPreset or 'soft'
end

-- ============================================================
--  STORE-SYNCHRONISIERUNG
-- ============================================================

local function applySnapshot(snapshot)
    if type(snapshot) ~= 'table' then return end
    State.store = snapshot
    State.storeReady = true
    GMenu.RefreshPermissions()
    -- NUI ueber aktuelles Theme/Farben informieren (sofern Menue bereits initialisiert)
    if GMenu.PushUiTheme then GMenu.PushUiTheme() end
    U.debug('Store snapshot received, version', snapshot._version)
end

RegisterNetEvent('clp_gmenu:store:snapshot', function(snapshot)
    applySnapshot(snapshot)
end)

RegisterNetEvent('clp_gmenu:store:patch', function(patch)
    if not State.store or type(patch) ~= 'table' then return end
    if patch.path == '*' then
        return    -- voller Snapshot kommt separat
    end
    -- Aenderung anwenden
    if patch.value == nil then
        U.deleteByPath(State.store, patch.path)
    else
        U.setByPath(State.store, patch.path, patch.value)
    end
    State.store._version = patch.version or (State.store._version or 0) + 1

    -- Berechtigungen des Spielers neu laden, falls Job-/Aktions-Bereich betroffen
    local p = patch.path or ''
    if p:find('^jobs%.') or p:find('^actions%.') or p == 'jobs' or p == 'actions' then
        GMenu.RefreshPermissions()
        -- Action-Cache invalidieren (Admin hat etwas geaendert)
        if GMenu.InvalidateActionCache then GMenu.InvalidateActionCache() end
    end
    if p:find('^globals%.') and GMenu.PushUiTheme then
        GMenu.PushUiTheme()
    end
end)

-- ============================================================
--  BERECHTIGUNGEN / JOB-CACHE
-- ============================================================

function GMenu.RefreshPermissions()
    -- Asynchron per Callback
    lib.callback('clp_gmenu:store:myPermissions', false, function(perms)
        State.perms = perms or { permissions = {}, actions = { player = {}, vehicle = {}, ped = {}, self = {} } }
        State.job = perms and { name = perms.jobName, grade = perms.grade, label = perms.jobLabel } or nil
        U.debug('Perms refreshed:', perms and perms.jobName, perms and perms.grade)
    end)
end

function GMenu.GetPerms()
    return State.perms
end

function GMenu.HasPerm(key)
    return State.perms and State.perms.permissions and State.perms.permissions[key] == true
end

-- ============================================================
--  AKTIONS-AUFLOESUNG: Komplett servergesteuert
--  BuildOptions() und GetAction() wurden entfernt. Der Client
--  ruft lib.callback('clp_gmenu:getActions') auf und bekommt
--  die fertig gefilterte Optionsliste vom Server.
-- ============================================================

-- ============================================================
--  JOB-WECHSEL -> Aktualisierung
-- ============================================================

RegisterNetEvent('clp_gmenu:job:refresh', function()
    Wait(200)
    GMenu.RefreshPermissions()
    if GMenu.InvalidateActionCache then GMenu.InvalidateActionCache() end
end)

-- Server-Push: Admin hat Jobs/Actions geaendert -> Cache sofort leeren
RegisterNetEvent('clp_gmenu:cache:invalidate', function()
    if GMenu.InvalidateActionCache then GMenu.InvalidateActionCache() end
    GMenu.RefreshPermissions()
end)

RegisterNetEvent('esx:setJob', function()
    Wait(200)
    GMenu.RefreshPermissions()
    if GMenu.InvalidateActionCache then GMenu.InvalidateActionCache() end
end)

-- ============================================================
--  BOOT
-- ============================================================

CreateThread(function()
    -- Auf ESX-Spielerdaten warten
    while not ESX.GetPlayerData() or not ESX.GetPlayerData().job do
        Wait(200)
    end

    loadKvp()

    -- Snapshot anfordern (falls Server-Push noch nicht eingetroffen ist)
    if not State.storeReady then
        local snapshot = lib.callback.await('clp_gmenu:store:snapshot', false)
        if snapshot then applySnapshot(snapshot) end
    end

    GMenu.RefreshPermissions()
    print('^2[clp_gmenu]^0 Client bereit (Theme=' .. GMenu.GetTheme() .. ').')
end)

-- ============================================================
--  RESOURCE-STOP - Aufraeumen fuer andere Module
-- ============================================================

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    -- Andere Module nutzen dieses Event zum Aufraeumen
end)

-- ============================================================
--  EXPORTS (fuer externe Systeme)
-- ============================================================

exports('hasPerm',     function(key) return GMenu.HasPerm(key) end)
exports('getJob',      function() return State.job end)
exports('isStoreReady',function() return State.storeReady end)
