--[[
    clp_gmenu - Server-Berechtigungen

    Zentrale Pruefungen:
      - ESX-Job + Rang des Spielers
      - Effektiver Rang (mit Vererbung) aus dem Store
      - Distanz-Pruefung (Anti-Teleport)
      - Durchsatz-Begrenzung (Token-Bucket pro Spieler)
      - Admin-Gruppen-Pruefung (ESX-Group + optional ACE)
]]

GMenu = GMenu or {}
GMenu.Perms = {}

local P = GMenu.Perms
local Store = GMenu.Store
local U = GMenu.Util

-- ============================================================
--  ESX
-- ============================================================
local ESX = exports['es_extended']:getSharedObject()

function P.getXPlayer(src)
    return ESX and ESX.GetPlayerFromId(src) or nil
end

--- Liefert { name=..., grade=... } oder nil.
function P.getJob(src)
    local x = P.getXPlayer(src)
    if not x then return nil end
    local job = x.getJob and x.getJob() or x.job
    if not job then return nil end
    return { name = job.name, grade = job.grade or 0, label = job.label }
end

--- Liefert true, wenn der Spieler aktuell im Dienst ist.
--- ESX hat keinen nativen Duty-Status; viele Server nutzen Metadaten oder Custom-State.
--- Default-Verhalten: Spieler gilt als "im Dienst", wenn er einen Job hat, der NICHT
--- 'unemployed'/'citizen' ist. Drittanbieter koennen dies via Export ueberschreiben.
function P.isOnDuty(src)
    if not src then return false end
    local x = P.getXPlayer(src)
    if not x then return false end

    -- Bevorzugte Quelle: x.metadata.onduty (wird von vielen Frameworks gesetzt)
    if x.getMeta then
        local meta = x.getMeta('onduty')
        if meta ~= nil then return meta == true end
    end

    -- StateBag (gesetzt durch /duty-Resourcen)
    local sb = Player(src).state.onDuty
    if sb ~= nil then return sb == true end

    -- Fallback: Job ist nicht 'unemployed' oder 'citizen'
    local job = P.getJob(src)
    if not job then return false end
    return job.name ~= 'unemployed' and job.name ~= 'citizen'
end

-- ============================================================
--  ADMIN-PRUEFUNG
-- ============================================================

--- Liefert true wenn der Spieler Admin ist (ESX-Group ODER ACE).
function P.isAdmin(src)
    if not src or src == 0 then return false end

    -- ESX-Gruppe
    local x = P.getXPlayer(src)
    if x and x.getGroup then
        local g = x.getGroup()
        if g then
            for i = 1, #(Config.AdminGroups or {}) do
                if Config.AdminGroups[i] == g then return true end
            end
        end
    end

    -- ACE-Berechtigung (optional)
    if Config.AdminAceCheck and Config.AdminAceCheck ~= '' then
        if IsPlayerAceAllowed(tostring(src), Config.AdminAceCheck) then
            return true
        end
    end

    return false
end

-- ============================================================
--  EFFEKTIVE BERECHTIGUNGEN (mit Cache)
-- ============================================================

local permCache = {}     -- [src] = { job = Name, grade = n, eff = Tabelle, ts = ms }
local PERM_CACHE_TTL = 5000  -- Max-Alter in ms (Sicherheits-Fallback, normalerweise aktiv invalidiert)

--- Invalidiert den Cache fuer einen Spieler (z.B. Job-Wechsel).
function P.invalidateCache(src)
    if src then
        permCache[src] = nil
    end
end

--- Invalidiert den Cache fuer ALLE Spieler (z.B. bei Store-Aenderung).
function P.invalidateAllCaches()
    permCache = {}
end

--- Liefert die effektiven Berechtigungen des Spielers basierend auf Job+Rang.
--- Ergebnis wird pro Spieler zwischengespeichert und bei Job-/Store-Aenderung invalidiert.
function P.getEffective(src)
    local job = P.getJob(src)
    if not job then return { permissions = {}, actions = { player = {}, vehicle = {}, ped = {}, self = {} }, jobName = nil, grade = 0 } end

    -- Cache-Treffer pruefen
    local cached = permCache[src]
    if cached and cached.job == job.name and cached.grade == job.grade
       and (GetGameTimer() - cached.ts) < PERM_CACHE_TTL then
        return cached.eff
    end

    local eff = Store.getEffectiveRank(job.name, job.grade)
    if not eff then
        -- Job existiert nicht im Store -> Buerger-Fallback
        eff = Store.getEffectiveRank('citizen', 0)
        if not eff then
            eff = { permissions = {}, actions = { player = {}, vehicle = {}, ped = {}, self = {} }, jobName = job.name, grade = job.grade }
            return eff
        end
    end

    eff.jobName = job.name
    eff.grade   = job.grade

    -- Im Cache ablegen
    permCache[src] = { job = job.name, grade = job.grade, eff = eff, ts = GetGameTimer() }
    return eff
end

--- Prueft ob der Spieler eine bestimmte Berechtigung hat.
function P.hasPermission(src, permKey)
    if not permKey or permKey == '' then return true end
    local eff = P.getEffective(src)
    return eff.permissions and eff.permissions[permKey] == true
end

--- Prueft ob der Spieler eine Aktion ueberhaupt zugewiesen hat (unabhaengig von Berechtigung).
--- 'ped' Zieltyp prueft ped-Liste UND player-Liste (Fallback, da player-Aktionen auf NPCs wirken).
function P.hasAction(src, actionId, target, ctx)
    local eff = P.getEffective(src)
    if not eff or not eff.actions then return false end

    -- Default-Aktionen: gelten fuer jeden Spieler
    if Store.getDefaults then
        local defaults = Store.getDefaults(target) or {}
        if U.tableContains(defaults, actionId) then return true end
        -- 'ped' faellt automatisch auf 'player'-Defaults zurueck
        if target == 'ped' then
            local pdef = Store.getDefaults('player') or {}
            if U.tableContains(pdef, actionId) then return true end
        end
    end

    -- NPC-spezifische Aktionen (ctx.npcId)
    if ctx and ctx.npcId and GMenu.NPCs and GMenu.NPCs.getActionIds then
        local npcActions = GMenu.NPCs.getActionIds(src, ctx.npcId) or {}
        if U.tableContains(npcActions, actionId) then return true end
    end

    -- Zone-spezifische Aktionen (ctx.zoneName)
    if ctx and ctx.zoneName and GMenu.Zones and GMenu.Zones.getActionIds then
        local zActions = GMenu.Zones.getActionIds(src, ctx.zoneName) or {}
        if U.tableContains(zActions, actionId) then return true end
    end

    -- Bridge-Aktionen
    if GMenu.Bridge then
        local list = GMenu.Bridge.getForTarget(target) or {}
        for i = 1, #list do if list[i].id == actionId then return true end end
        if ctx and ctx.npcId then
            local nl = GMenu.Bridge.getForNpc(ctx.npcId) or {}
            for i = 1, #nl do if nl[i].id == actionId then return true end end
        end
        if ctx and ctx.zoneName then
            local zl = GMenu.Bridge.getForZone(ctx.zoneName) or {}
            for i = 1, #zl do if zl[i].id == actionId then return true end end
        end
        if ctx and ctx.model and ctx.model ~= 0 then
            local ml = GMenu.Bridge.getForModel(ctx.model) or {}
            for i = 1, #ml do if ml[i].id == actionId then return true end end
        end
    end

    -- Job-zugewiesene Aktionen
    if target == 'vehicle' then
        return U.tableContains(eff.actions.vehicle or {}, actionId)
    elseif target == 'player' then
        return U.tableContains(eff.actions.player or {}, actionId)
    elseif target == 'ped' then
        return U.tableContains(eff.actions.ped or {}, actionId)
            or U.tableContains(eff.actions.player or {}, actionId)
    elseif target == 'self' then
        return U.tableContains(eff.actions.self or {}, actionId)
    elseif target == 'object' then
        return U.tableContains(eff.actions.object or {}, actionId)
    elseif target == 'zone' then
        return U.tableContains(eff.actions.zone or {}, actionId)
    else
        return U.tableContains(eff.actions.vehicle or {}, actionId)
            or U.tableContains(eff.actions.player or {}, actionId)
            or U.tableContains(eff.actions.ped or {}, actionId)
            or U.tableContains(eff.actions.self or {}, actionId)
            or U.tableContains(eff.actions.object or {}, actionId)
            or U.tableContains(eff.actions.zone or {}, actionId)
    end
end

-- ============================================================
--  DISTANZ-PRUEFUNG
-- ============================================================

--- Serverseitige Pruefung gegen Teleport-Exploits.
--- targetEntity ist eine Server-Entity (durch netId aufgeloest).
function P.checkDistance(src, targetEntity)
    if not src or src == 0 then return false end
    if not targetEntity or targetEntity == 0 or not DoesEntityExist(targetEntity) then return false end

    local srcPed = GetPlayerPed(src)
    if not srcPed or srcPed == 0 then return false end

    local a = GetEntityCoords(srcPed)
    local b = GetEntityCoords(targetEntity)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    local dist = math.sqrt(dx*dx + dy*dy + dz*dz)

    return dist <= (Config.MaxDistanceServer or 12.0)
end

-- ============================================================
--  DURCHSATZ-BEGRENZUNG (Token-Bucket pro Spieler)
-- ============================================================

local buckets = {}    -- [src] = { tokens = n, last = ms }
local adminBuckets = {}

local function checkBucket(src, tableRef, ratePerSec)
    local now = GetGameTimer()
    local b = tableRef[src]
    if not b then
        b = { tokens = ratePerSec, last = now }
        tableRef[src] = b
    end

    -- Token auffuellen
    local elapsed = (now - b.last) / 1000.0
    if elapsed > 0 then
        b.tokens = math.min(ratePerSec, b.tokens + elapsed * ratePerSec)
        b.last = now
    end

    if b.tokens >= 1 then
        b.tokens = b.tokens - 1
        return true
    end
    return false
end

function P.consumeAction(src)
    return checkBucket(src, buckets, Config.RateLimitPerSec or 4)
end

function P.consumeAdmin(src)
    return checkBucket(src, adminBuckets, Config.AdminRateLimitPerSec or 10)
end

-- ============================================================
--  PER-ACTION COOLDOWN (separate Logik fuer "max 1x alle X Sekunden pro Aktion")
--  Limits sind in Config.ActionCooldownMin (Sekunden) und Config.ActionCooldownMax
--  geclamped, um Missbrauch zu vermeiden.
-- ============================================================

local actionCooldowns = {}    -- [src] = { [actionId] = lastTs }

function P.checkActionCooldown(src, actionId, cooldownSec)
    if not src or not actionId or not cooldownSec or cooldownSec <= 0 then return true end
    local minC = Config.ActionCooldownMin or 0.1
    local maxC = Config.ActionCooldownMax or 300.0
    cooldownSec = math.max(minC, math.min(maxC, cooldownSec))

    local now = GetGameTimer() / 1000.0
    actionCooldowns[src] = actionCooldowns[src] or {}
    local last = actionCooldowns[src][actionId] or 0
    local elapsed = now - last
    if elapsed < cooldownSec then
        return false, cooldownSec - elapsed    -- false + verbleibende Sekunden
    end
    actionCooldowns[src][actionId] = now
    return true
end

-- ============================================================
--  ITEM-CHECK (ox_inventory)
-- ============================================================

function P.hasItems(src, requiredItems)
    if type(requiredItems) ~= 'table' then return true end
    if not GetResourceState or GetResourceState('ox_inventory') ~= 'started' then
        -- ohne ox_inventory: ESX-Fallback
        local x = P.getXPlayer(src)
        if not x or not x.getInventoryItem then return false end
        for itemName, count in pairs(requiredItems) do
            local item = x.getInventoryItem(itemName)
            if not item or (item.count or 0) < (tonumber(count) or 1) then return false end
        end
        return true
    end

    -- Mit ox_inventory
    for itemName, count in pairs(requiredItems) do
        local n = tonumber(count) or 1
        local total = exports.ox_inventory and exports.ox_inventory:Search(src, 'count', itemName) or 0
        if (total or 0) < n then return false end
    end
    return true
end

AddEventHandler('playerDropped', function()
    local src = source
    buckets[src] = nil
    adminBuckets[src] = nil
    permCache[src] = nil
    actionCooldowns[src] = nil
end)

-- ============================================================
--  PROTOKOLL (Audit-Log, Leichtgewichtig)
-- ============================================================

local auditCache = {}

local function pushAudit(entry)
    auditCache[#auditCache + 1] = entry
    -- Ringpuffer
    if #auditCache > (Config.AuditMaxEntries or 1000) then
        table.remove(auditCache, 1)
    end
end

function P.audit(src, action, details)
    local x = P.getXPlayer(src)
    local entry = {
        ts       = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        src      = src,
        name     = x and (x.getName and x.getName() or x.name) or 'unknown',
        identifier = x and (x.identifier or x.getIdentifier and x.getIdentifier()) or '',
        action   = action,
        details  = details,
    }
    pushAudit(entry)
    if Config.Debug then
        print(('^5[clp_gmenu:audit]^0 %s by %s (%s): %s'):format(
            action, entry.name, entry.identifier, json.encode(details or {})
        ))
    end

    -- Optional: in SQL duplizieren
    if Config.UseSqlFallback and GMenu.SqlStore and GMenu.SqlStore.appendAudit then
        GMenu.SqlStore.appendAudit(entry)
    end

    -- Discord-Webhook (abfeuern und vergessen)
    if Config.AdminWebhook and Config.AdminWebhook ~= '' then
        PerformHttpRequest(Config.AdminWebhook, function() end, 'POST',
            json.encode({
                username = 'clp_gmenu',
                content  = ('`%s` **%s** by %s — %s'):format(
                    entry.ts, action, entry.name, json.encode(details or {})
                ),
            }),
            { ['Content-Type'] = 'application/json' }
        )
    end
end

function P.getAudit(limit)
    limit = tonumber(limit) or 100
    local n = #auditCache
    local start = math.max(1, n - limit + 1)
    local out = {}
    for i = start, n do out[#out + 1] = auditCache[i] end
    return out
end
