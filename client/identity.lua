--[[
    clp_gmenu - Identity (Client)

    Aufgaben:
      - Ueberkopf-Anzeige fuer Spieler in der Naehe ("Fremder"/echter Name)
      - Animation fuer Handschlag
      - Cache von "bekannten" Identifiern (vom Server gepusht)
      - Anfrage/Annehmen-System fuer Handschlag mit ox_lib alert dialog

    Optional aktivierbar/deaktivierbar via Settings/Globals "identityNameplates".
]]

GMenu = GMenu or {}
GMenu.Identity = {}
local I = GMenu.Identity

I.knownByIdentifier = {}         -- ident -> name
I.serverIdToIdentifier = {}      -- serverId -> ident   (filled lazily)
I.serverIdToName       = {}      -- serverId -> displayName (resolved)
I.lastResolveAt = 0
local RESOLVE_INTERVAL_MS = 4000
local NAMEPLATE_DISTANCE = 12.0

-- ============================================================
--  EVENTS FROM SERVER
-- ============================================================

RegisterNetEvent('clp_gmenu:identity:learned', function(payload)
    if type(payload) ~= 'table' then return end
    if payload.identifier and payload.name then
        I.knownByIdentifier[payload.identifier] = payload.name
    end
    if payload.serverId then
        I.serverIdToName[tostring(payload.serverId)] = payload.name
    end
    -- Force-Refresh: lastResolveAt zuruecksetzen, damit das naechste resolveNearby
    -- garantiert den Server fragt und die jetzt bekannte Identitaet aktualisiert
    -- (auch wichtig wenn beide Spieler durch andere Mechaniken gelernt wurden).
    I.lastResolveAt = 0
    if GMenu.UI then
        GMenu.UI.notify({
            type = 'success',
            title = 'Identitaet',
            description = ('Du kennst jetzt: %s'):format(payload.name or '?'),
        })
    end
end)

RegisterNetEvent('clp_gmenu:identity:forgotten', function(payload)
    if type(payload) ~= 'table' then return end
    if payload.identifier then I.knownByIdentifier[payload.identifier] = nil end
end)

RegisterNetEvent('clp_gmenu:identity:incomingHandshake', function(payload)
    if type(payload) ~= 'table' then return end
    local fromSrc = tonumber(payload.fromSrc)
    if not fromSrc then return end
    local label = payload.fromLabel or 'Unbekannte Person'
    local timeout = tonumber(payload.timeoutMs) or 10000

    -- Native J/N Prompt (keine ox_lib-Abhaengigkeit, einheitliche UX)
    if GMenu.ApprovalPrompt and GMenu.ApprovalPrompt.show then
        GMenu.ApprovalPrompt.show({
            title     = 'Hand geben?',
            fromLabel = label,
            body      = 'moechte dir die Hand geben.',
            timeoutMs = timeout,
        }, function(accepted)
            TriggerServerEvent('clp_gmenu:identity:respondHandshake', {
                fromSrc = fromSrc,
                accept  = accepted == true,
            })
        end)
    elseif lib and lib.alertDialog then
        CreateThread(function()
            local result = lib.alertDialog({
                header = 'Hand geben?',
                content = ('%s moechte dir die Hand geben.'):format(label),
                centered = true,
                cancel = true,
                labels = { confirm = 'Annehmen', cancel = 'Ablehnen' },
            })
            TriggerServerEvent('clp_gmenu:identity:respondHandshake', {
                fromSrc = fromSrc,
                accept = result == 'confirm',
            })
        end)
    else
        TriggerServerEvent('clp_gmenu:identity:respondHandshake', { fromSrc = fromSrc, accept = false })
    end
end)

RegisterNetEvent('clp_gmenu:identity:handshakeWaiting', function(payload)
    if GMenu.UI then GMenu.UI.notify({ type = 'inform', description = 'Handschlag-Anfrage gesendet...' }) end
end)

RegisterNetEvent('clp_gmenu:identity:handshakeTimeout', function()
    if GMenu.UI then GMenu.UI.notify({ type = 'error', description = 'Handschlag-Anfrage verfallen.' }) end
end)

RegisterNetEvent('clp_gmenu:identity:handshakeDeclined', function()
    if GMenu.UI then GMenu.UI.notify({ type = 'error', description = 'Handschlag wurde abgelehnt.' }) end
end)

RegisterNetEvent('clp_gmenu:identity:playHandshake', function(payload)
    if type(payload) ~= 'table' then return end
    local me = PlayerPedId()
    -- Standard Greet animation
    RequestAnimDict('mp_ped_interaction')
    local ts = GetGameTimer()
    while not HasAnimDictLoaded('mp_ped_interaction') do
        if GetGameTimer() - ts > 3000 then break end
        Wait(10)
    end
    TaskPlayAnim(me, 'mp_ped_interaction', 'handshake_guy_a', 8.0, -8.0, 2400, 0, 0, false, false, false)
    SetTimeout(2700, function() ClearPedTasks(me) end)
end)

-- ============================================================
--  RESOLVE NEARBY PLAYERS
-- ============================================================

local function getNearbyPlayerServerIds()
    local me = PlayerPedId()
    local mePos = GetEntityCoords(me)
    local out = {}
    for _, p in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(p)
        if ped ~= 0 and ped ~= me then
            local d = #(mePos - GetEntityCoords(ped))
            if d <= NAMEPLATE_DISTANCE then
                local sid = GetPlayerServerId(p)
                if sid and sid > 0 then out[#out + 1] = sid end
            end
        end
    end
    return out
end

local function resolveNearby()
    local now = GetGameTimer()
    if (now - I.lastResolveAt) < RESOLVE_INTERVAL_MS then return end
    I.lastResolveAt = now
    local sids = getNearbyPlayerServerIds()
    if #sids == 0 then return end
    lib.callback('clp_gmenu:identity:resolve', false, function(map)
        if type(map) ~= 'table' then return end
        for k, v in pairs(map) do
            I.serverIdToName[k] = v.name
        end
    end, sids)
end

-- ============================================================
--  RENDER NAMEPLATES (3D text)
-- ============================================================

local function world3dToScreen2d(x, y, z)
    return GetScreenCoordFromWorldCoord(x, y, z)
end

local function drawText3D(x, y, z, text)
    SetDrawOrigin(x, y, z, 0)
    SetTextScale(0.32, 0.32)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(255, 255, 255, 220)
    SetTextDropshadow(2, 0, 0, 0, 200)
    SetTextEdge(2, 0, 0, 0, 200)
    SetTextOutline()
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString(text)
    DrawText(0.0, 0.0)
    ClearDrawOrigin()
end

CreateThread(function()
    while true do
        if GMenu.State and GMenu.State.storeReady and (GMenu.GetGlobalBool and GMenu.GetGlobalBool('identityNameplates', true)) then
            resolveNearby()
            local me = PlayerPedId()
            local mePos = GetEntityCoords(me)
            for _, p in ipairs(GetActivePlayers()) do
                local ped = GetPlayerPed(p)
                if ped ~= 0 and ped ~= me then
                    local pos = GetEntityCoords(ped)
                    local d = #(mePos - pos)
                    if d <= NAMEPLATE_DISTANCE then
                        local sid = GetPlayerServerId(p)
                        local name = I.serverIdToName[tostring(sid)]
                        if name then
                            drawText3D(pos.x, pos.y, pos.z + 1.05, name)
                        end
                    end
                end
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- ============================================================
--  PUBLIC API
-- ============================================================

function I.getDisplayNameForServerId(sid)
    return I.serverIdToName[tostring(sid)] or 'Unbekannt'
end

function I.requestHandshake(targetSrc)
    if not targetSrc then return end
    TriggerServerEvent('clp_gmenu:identity:handshake', tonumber(targetSrc))
end

-- Trigger handshake when "handshake" action is selected (handled by actions.lua dispatch)
RegisterNetEvent('clp_gmenu:identity:doHandshake', function(serverId)
    I.requestHandshake(serverId)
end)
