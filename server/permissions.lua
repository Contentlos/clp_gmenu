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
function P.hasAction(src, actionId, target)
    local eff = P.getEffective(src)
    if not eff or not eff.actions then return false end
    if target == 'vehicle' then
        return U.tableContains(eff.actions.vehicle or {}, actionId)
    elseif target == 'player' then
        return U.tableContains(eff.actions.player or {}, actionId)
    elseif target == 'ped' then
        return U.tableContains(eff.actions.ped or {}, actionId)
            or U.tableContains(eff.actions.player or {}, actionId)
    elseif target == 'self' then
        return U.tableContains(eff.actions.self or {}, actionId)
    else
        return U.tableContains(eff.actions.vehicle or {}, actionId)
            or U.tableContains(eff.actions.player or {}, actionId)
            or U.tableContains(eff.actions.ped or {}, actionId)
            or U.tableContains(eff.actions.self or {}, actionId)
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

AddEventHandler('playerDropped', function()
    local src = source
    buckets[src] = nil
    adminBuckets[src] = nil
    permCache[src] = nil
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
