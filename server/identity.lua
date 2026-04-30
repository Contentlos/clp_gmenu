--[[
    clp_gmenu - Identity System (Server)

    Verwaltet "bekannte Spieler" pro Identifier:
      - Wenn unbekannt -> "Fremder"/"Fremde"
      - Wenn bekannt   -> echter RP-Name (Vorname Nachname)
    Bekannt werden Spieler durch:
      - Hände geben (handshake)
      - Visitenkarte geben
      - Admin-Befehl
      - optional gemeinsame Fraktion / Job (Config.IdentityShareJob = true)

    Persistenz: SQL (clp_gmenu_known_players). Cache pro Spieler im RAM.

    API:
      Identity.getIdentifier(src)            -> string|nil       (esx-style)
      Identity.getRpName(src)                -> string           (Vorname Nachname)
      Identity.getStrangerLabel(src)         -> string           (Fremder/Fremde/Unbekannte Person)
      Identity.knowPlayer(src, targetSrc)    -> ok               (gegenseitig)
      Identity.doesKnow(src, targetIdent)    -> bool
      Identity.getDisplayName(src, targetSrc)-> string
      Identity.forget(src, targetIdent)      -> ok
      Identity.listKnown(src)                -> { ident -> name }
      Identity.handshake(srcA, srcB)         -> ok, err

    Cache:
      KnownCache[srcIdentifier] = { [otherIdentifier] = name }

    Events:
      clp_gmenu:identity:syncSelf            (S->C, schickt Cache an Client)
      clp_gmenu:identity:resolveBatch        (Callback, liefert Names fuer Identifier-Liste)
]]

GMenu = GMenu or {}
GMenu.Identity = {}

local Identity = GMenu.Identity
local Perms    = GMenu.Perms
local U        = GMenu.Util

-- ============================================================
--  STATE / CACHE
-- ============================================================

-- KnownCache[selfIdentifier] = { [otherIdentifier] = displayName }
local KnownCache = {}

-- IdentifierCache[src] = identifier (per-session cache)
local IdentifierCache = {}

-- Pending handshake requests:
--   PendingHandshakes[srcA] = { targetSrc = srcB, ts = ms }
local PendingHandshakes = {}

local HANDSHAKE_TIMEOUT_MS = 10000
local HANDSHAKE_MAX_DIST   = 3.5

-- ============================================================
--  HELPERS
-- ============================================================

local function nowMs() return GetGameTimer() end

local function rpNameFromXPlayer(xp)
    if not xp then return 'Unbekannt' end
    local first = (xp.get and xp.get('firstName')) or (xp.variables and xp.variables.firstName)
    local last  = (xp.get and xp.get('lastName'))  or (xp.variables and xp.variables.lastName)
    if first and last and first ~= '' and last ~= '' then
        return tostring(first) .. ' ' .. tostring(last)
    end
    if xp.getName then return tostring(xp.getName()) end
    return tostring(xp.name or 'Unbekannt')
end

local function sexFromXPlayer(xp)
    if not xp then return 'm' end
    local s = (xp.get and xp.get('sex')) or (xp.variables and xp.variables.sex)
    if not s then
        local skin = (xp.get and xp.get('skin')) or (xp.variables and xp.variables.skin)
        if type(skin) == 'table' and skin.sex ~= nil then
            s = (tonumber(skin.sex) == 1) and 'f' or 'm'
        end
    end
    s = tostring(s or 'm'):lower()
    if s == 'female' or s == 'f' or s == 'w' then return 'f' end
    return 'm'
end

function Identity.getXPlayer(src)
    return Perms and Perms.getXPlayer and Perms.getXPlayer(src) or nil
end

function Identity.getIdentifier(src)
    if not src or src == 0 then return nil end
    if IdentifierCache[src] then return IdentifierCache[src] end
    local xp = Identity.getXPlayer(src)
    if not xp then return nil end
    local id = xp.identifier or (xp.getIdentifier and xp.getIdentifier())
    if id then IdentifierCache[src] = id end
    return id
end

function Identity.getRpName(src)
    return rpNameFromXPlayer(Identity.getXPlayer(src))
end

function Identity.getSex(src)
    return sexFromXPlayer(Identity.getXPlayer(src))
end

function Identity.getStrangerLabel(src)
    local sex = Identity.getSex(src)
    if Config.IdentityStrangerLabels then
        return Config.IdentityStrangerLabels[sex] or Config.IdentityStrangerLabels.unknown or 'Fremder'
    end
    if sex == 'f' then return 'Fremde' end
    return 'Fremder'
end

-- ============================================================
--  SQL LOADER (lazy per src)
-- ============================================================

local function ensureSqlSchema()
    if not GMenu.SqlStore or not GMenu.SqlStore.ensureIdentitySchema then return false end
    return GMenu.SqlStore.ensureIdentitySchema()
end

local function loadKnown(identifier)
    if not identifier or identifier == '' then return {} end
    if KnownCache[identifier] then return KnownCache[identifier] end
    local out = {}
    if ensureSqlSchema() and exports.oxmysql then
        local ok, rows = pcall(function()
            return exports.oxmysql:executeSync(
                'SELECT `known_identifier`, `known_name` FROM `clp_gmenu_known_players` WHERE `identifier` = ?',
                { identifier }
            )
        end)
        if ok and type(rows) == 'table' then
            for i = 1, #rows do
                local r = rows[i]
                if r and r.known_identifier then
                    out[r.known_identifier] = r.known_name or 'Unbekannt'
                end
            end
        end
    end
    KnownCache[identifier] = out
    return out
end

local function persistKnown(identifier, otherIdent, name)
    if not identifier or not otherIdent then return false end
    if not (ensureSqlSchema() and exports.oxmysql) then return false end
    local ok = pcall(function()
        exports.oxmysql:prepare(
            'INSERT INTO `clp_gmenu_known_players` (`identifier`, `known_identifier`, `known_name`) VALUES (?,?,?) '
            .. 'ON DUPLICATE KEY UPDATE `known_name` = VALUES(`known_name`)',
            { identifier, otherIdent, name }
        )
    end)
    return ok
end

local function deletePersisted(identifier, otherIdent)
    if not identifier or not otherIdent then return false end
    if not (ensureSqlSchema() and exports.oxmysql) then return false end
    local ok = pcall(function()
        exports.oxmysql:prepare(
            'DELETE FROM `clp_gmenu_known_players` WHERE `identifier` = ? AND `known_identifier` = ?',
            { identifier, otherIdent }
        )
    end)
    return ok
end

-- ============================================================
--  PUBLIC API
-- ============================================================

function Identity.doesKnow(src, otherIdent)
    local me = Identity.getIdentifier(src)
    if not me or not otherIdent then return false end
    local cache = loadKnown(me)
    return cache[otherIdent] ~= nil
end

--- Mutual: sourceA learns name of B and vice versa.
function Identity.knowPlayer(srcA, srcB)
    if not srcA or not srcB or srcA == srcB then return false, 'invalid_pair' end
    local idA = Identity.getIdentifier(srcA)
    local idB = Identity.getIdentifier(srcB)
    if not idA or not idB then return false, 'no_identifier' end

    local nameA = Identity.getRpName(srcA)
    local nameB = Identity.getRpName(srcB)

    -- Update caches
    KnownCache[idA] = KnownCache[idA] or loadKnown(idA)
    KnownCache[idB] = KnownCache[idB] or loadKnown(idB)
    KnownCache[idA][idB] = nameB
    KnownCache[idB][idA] = nameA

    -- Persist
    persistKnown(idA, idB, nameB)
    persistKnown(idB, idA, nameA)

    -- Push to clients (so their nameplate updates instantly)
    TriggerClientEvent('clp_gmenu:identity:learned', srcA, { identifier = idB, name = nameB, serverId = srcB })
    TriggerClientEvent('clp_gmenu:identity:learned', srcB, { identifier = idA, name = nameA, serverId = srcA })

    return true
end

function Identity.forget(src, otherIdent)
    local me = Identity.getIdentifier(src)
    if not me or not otherIdent then return false end
    KnownCache[me] = KnownCache[me] or {}
    KnownCache[me][otherIdent] = nil
    deletePersisted(me, otherIdent)
    TriggerClientEvent('clp_gmenu:identity:forgotten', src, { identifier = otherIdent })
    return true
end

function Identity.getDisplayName(src, targetSrc)
    if not src or not targetSrc then return 'Unbekannt' end
    if src == targetSrc then return Identity.getRpName(src) end
    local targetIdent = Identity.getIdentifier(targetSrc)
    if not targetIdent then return Identity.getStrangerLabel(targetSrc) end

    -- Optional: same job means known automatically
    if Config.IdentityShareJob then
        local a = Perms.getJob and Perms.getJob(src)
        local b = Perms.getJob and Perms.getJob(targetSrc)
        if a and b and a.name and a.name == b.name and a.name ~= 'unemployed' and a.name ~= 'citizen' then
            return Identity.getRpName(targetSrc)
        end
    end

    if Identity.doesKnow(src, targetIdent) then
        return Identity.getRpName(targetSrc)
    end
    return Identity.getStrangerLabel(targetSrc)
end

function Identity.listKnown(src)
    local me = Identity.getIdentifier(src)
    if not me then return {} end
    return loadKnown(me)
end

--- Total relationships persisted in SQL (for admin overview). Returns 0 if SQL not available.
function Identity.countKnownPairs()
    if not GMenu.SqlStore or not GMenu.SqlStore.isAvailable or not GMenu.SqlStore.isAvailable() then
        return 0
    end
    local ok, res = pcall(MySQL.scalar.await, 'SELECT COUNT(*) FROM clp_gmenu_known_players')
    if not ok then return 0 end
    return tonumber(res or 0) or 0
end

-- ============================================================
--  HANDSHAKE PROTOCOL
-- ============================================================

local function distSrc(a, b)
    local pa = GetPlayerPed(a)
    local pb = GetPlayerPed(b)
    if not pa or not pb or pa == 0 or pb == 0 then return 9999 end
    local ca, cb = GetEntityCoords(pa), GetEntityCoords(pb)
    return #(ca - cb)
end

--- A initiated handshake towards B.
function Identity.requestHandshake(srcA, srcB)
    if not srcA or not srcB or srcA == srcB then return false, 'invalid_pair' end
    if distSrc(srcA, srcB) > HANDSHAKE_MAX_DIST then return false, 'too_far' end

    -- B already pending towards A? -> auto-accept (mutual click)
    local pendingFromB = PendingHandshakes[srcB]
    if pendingFromB and pendingFromB.targetSrc == srcA and (nowMs() - pendingFromB.ts) < HANDSHAKE_TIMEOUT_MS then
        PendingHandshakes[srcB] = nil
        Identity.acceptHandshake(srcB, srcA)
        return true, 'auto_accept'
    end

    PendingHandshakes[srcA] = { targetSrc = srcB, ts = nowMs() }

    -- Notify B about request
    TriggerClientEvent('clp_gmenu:identity:incomingHandshake', srcB, {
        fromSrc = srcA,
        fromLabel = Identity.getDisplayName(srcB, srcA),  -- shows "Fremder" if not yet known
        timeoutMs = HANDSHAKE_TIMEOUT_MS,
    })

    -- Ack to A (waiting)
    TriggerClientEvent('clp_gmenu:identity:handshakeWaiting', srcA, { toSrc = srcB })

    -- Auto-cleanup after timeout
    SetTimeout(HANDSHAKE_TIMEOUT_MS + 200, function()
        local p = PendingHandshakes[srcA]
        if p and p.targetSrc == srcB and (nowMs() - p.ts) >= HANDSHAKE_TIMEOUT_MS then
            PendingHandshakes[srcA] = nil
            TriggerClientEvent('clp_gmenu:identity:handshakeTimeout', srcA, { toSrc = srcB })
        end
    end)
    return true
end

function Identity.acceptHandshake(srcB, srcA)
    -- srcB accepts srcA's pending request
    local p = PendingHandshakes[srcA]
    if not p or p.targetSrc ~= srcB then return false, 'no_pending' end
    if (nowMs() - p.ts) > HANDSHAKE_TIMEOUT_MS then
        PendingHandshakes[srcA] = nil
        return false, 'expired'
    end
    if distSrc(srcA, srcB) > HANDSHAKE_MAX_DIST then
        PendingHandshakes[srcA] = nil
        return false, 'too_far'
    end
    PendingHandshakes[srcA] = nil

    -- Trigger animations on both
    TriggerClientEvent('clp_gmenu:identity:playHandshake', srcA, { with = srcB })
    TriggerClientEvent('clp_gmenu:identity:playHandshake', srcB, { with = srcA })

    -- Persist after a short delay so the animation starts before name update notification
    SetTimeout(1500, function()
        Identity.knowPlayer(srcA, srcB)
    end)

    return true
end

function Identity.declineHandshake(srcB, srcA)
    local p = PendingHandshakes[srcA]
    if not p or p.targetSrc ~= srcB then return false end
    PendingHandshakes[srcA] = nil
    TriggerClientEvent('clp_gmenu:identity:handshakeDeclined', srcA, { byEnt = srcB })
    return true
end

-- ============================================================
--  NETWORK EVENTS
-- ============================================================

RegisterNetEvent('clp_gmenu:identity:handshake', function(targetSrc)
    local src = source
    targetSrc = tonumber(targetSrc)
    if not targetSrc then return end
    if not Perms.consumeAction(src) then return end
    Identity.requestHandshake(src, targetSrc)
end)

RegisterNetEvent('clp_gmenu:identity:respondHandshake', function(payload)
    local src = source
    if type(payload) ~= 'table' then return end
    local fromSrc = tonumber(payload.fromSrc)
    if not fromSrc then return end
    if payload.accept then
        Identity.acceptHandshake(src, fromSrc)
    else
        Identity.declineHandshake(src, fromSrc)
    end
end)

RegisterNetEvent('clp_gmenu:identity:forget', function(targetIdent)
    local src = source
    if type(targetIdent) ~= 'string' or targetIdent == '' then return end
    if not Perms.consumeAction(src) then return end
    Identity.forget(src, targetIdent)
end)

-- ============================================================
--  RESOLVE: Client requests display names for a list of nearby player serverIds
-- ============================================================

lib.callback.register('clp_gmenu:identity:resolve', function(src, serverIds)
    if type(serverIds) ~= 'table' then return {} end
    local out = {}
    for i = 1, #serverIds do
        local sid = tonumber(serverIds[i])
        if sid then
            out[tostring(sid)] = {
                serverId = sid,
                name     = Identity.getDisplayName(src, sid),
                known    = Identity.doesKnow(src, Identity.getIdentifier(sid) or ''),
            }
        end
    end
    return out
end)

lib.callback.register('clp_gmenu:identity:listKnown', function(src)
    return {
        self = {
            serverId   = src,
            identifier = Identity.getIdentifier(src),
            name       = Identity.getRpName(src),
            sex        = Identity.getSex(src),
        },
        known = Identity.listKnown(src),
    }
end)

-- ============================================================
--  ADMIN: Force-know two players (or self <-> player)
-- ============================================================

RegisterNetEvent('clp_gmenu:identity:adminLink', function(payload)
    local src = source
    if not Perms.isAdmin(src) then return end
    if type(payload) ~= 'table' then return end
    local a = tonumber(payload.a) or src
    local b = tonumber(payload.b)
    if not b then return end
    Identity.knowPlayer(a, b)
    Perms.audit(src, 'identity_admin_link', { a = a, b = b })
end)

-- ============================================================
--  CLEANUP
-- ============================================================

AddEventHandler('playerDropped', function()
    local src = source
    IdentifierCache[src] = nil
    PendingHandshakes[src] = nil
end)

-- ============================================================
--  EXPORTS
-- ============================================================

exports('knowPlayer',       function(a, b)     return Identity.knowPlayer(a, b) end)
exports('getDisplayName',   function(a, b)     return Identity.getDisplayName(a, b) end)
exports('doesKnow',         function(a, ident) return Identity.doesKnow(a, ident) end)
exports('forgetIdentity',   function(a, ident) return Identity.forget(a, ident) end)

print('^2[clp_gmenu]^0 Identity module loaded.')
