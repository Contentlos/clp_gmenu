--[[
    clp_gmenu - Approvals (Server)

    Generischer Bestaetigungs-Mechanismus fuer Aktionen, die mit
    `requiresApproval = true` markiert sind. Der Empfaenger sieht einen
    J/N Prompt und kann annehmen oder ablehnen. Erst nach Annahme wird
    die eigentliche Aktion ausgefuehrt.

    Public API:
      Approvals.request(srcFrom, srcTo, opts, onAnswer)
        opts = { actionId, actionLabel, fromLabel, timeoutMs }
        onAnswer = function(accepted, reason) -> nil   (im Server-Thread aufgerufen)

    Network:
      C->S clp_gmenu:approvals:respond  (token, accept)
      S->C clp_gmenu:approvals:incoming (token, fromLabel, actionLabel, timeoutMs)
]]

GMenu = GMenu or {}
GMenu.Approvals = {}
local A = GMenu.Approvals

local Identity = GMenu.Identity
local Perms    = GMenu.Perms

local DEFAULT_TIMEOUT_MS = 10000
local MAX_DISTANCE       = 5.0

-- token -> { fromSrc, toSrc, expiresAt, cb, actionId }
local Pending = {}

local function genToken()
    return string.format('%d-%d-%d', GetGameTimer(), math.random(1, 0xFFFFFF), math.random(1, 0xFFFFFF))
end

local function cleanup(token)
    Pending[token] = nil
end

local function distSrc(a, b)
    local pa = GetPlayerPed(a)
    local pb = GetPlayerPed(b)
    if not pa or not pb or pa == 0 or pb == 0 then return 9999 end
    return #(GetEntityCoords(pa) - GetEntityCoords(pb))
end

-- ============================================================
--  PUBLIC: Request
-- ============================================================

function A.request(srcFrom, srcTo, opts, onAnswer)
    if not srcFrom or not srcTo or srcFrom == srcTo then
        if onAnswer then pcall(onAnswer, false, 'invalid_pair') end
        return false
    end
    if not GetPlayerName(tostring(srcTo)) then
        if onAnswer then pcall(onAnswer, false, 'offline') end
        return false
    end
    if distSrc(srcFrom, srcTo) > MAX_DISTANCE then
        if onAnswer then pcall(onAnswer, false, 'too_far') end
        return false
    end

    opts = opts or {}
    local timeoutMs = tonumber(opts.timeoutMs) or DEFAULT_TIMEOUT_MS

    -- Sicht-Label fuer den Anfrager (Identitaets-bewusst)
    local fromLabel = opts.fromLabel
    if not fromLabel and Identity and Identity.getDisplayName then
        local ok, name = pcall(Identity.getDisplayName, srcTo, srcFrom)
        if ok and type(name) == 'string' then fromLabel = name end
    end
    fromLabel = fromLabel or ('Spieler #' .. tostring(srcFrom))

    local token = genToken()
    Pending[token] = {
        fromSrc    = srcFrom,
        toSrc      = srcTo,
        actionId   = opts.actionId,
        expiresAt  = GetGameTimer() + timeoutMs,
        cb         = onAnswer,
    }

    TriggerClientEvent('clp_gmenu:approvals:incoming', srcTo, {
        token       = token,
        fromLabel   = fromLabel,
        actionLabel = opts.actionLabel or opts.actionId or 'Aktion',
        timeoutMs   = timeoutMs,
    })

    -- Auto-Timeout
    SetTimeout(timeoutMs + 250, function()
        local p = Pending[token]
        if not p then return end
        cleanup(token)
        if p.cb then pcall(p.cb, false, 'timeout') end
    end)

    return true
end

-- ============================================================
--  NETWORK: Antwort vom Empfaenger
-- ============================================================

RegisterNetEvent('clp_gmenu:approvals:respond', function(payload)
    local src = source
    if type(payload) ~= 'table' then return end
    local token = tostring(payload.token or '')
    if token == '' then return end
    local p = Pending[token]
    if not p then return end
    -- Nur der Adressat darf antworten
    if p.toSrc ~= src then return end
    cleanup(token)
    if Perms and Perms.consumeAction then Perms.consumeAction(src) end
    if p.cb then pcall(p.cb, payload.accept == true, payload.accept and 'accepted' or 'declined') end
end)

-- ============================================================
--  CLEANUP bei Disconnect
-- ============================================================

AddEventHandler('playerDropped', function()
    local src = source
    for token, p in pairs(Pending) do
        if p.fromSrc == src or p.toSrc == src then
            cleanup(token)
            if p.cb then pcall(p.cb, false, 'dropped') end
        end
    end
end)
