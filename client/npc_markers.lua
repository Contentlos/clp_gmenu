--[[
    clp_gmenu - NPC-Marker

    Raycast erkennt zwar `IsEntityAPed`-Hits, aber er trifft auch Bevoelkerungs-
    Peds, Tiere, Gangmember etc. die nichts mit unserem System zu tun haben.
    Das fuehrt zu falschen Treffern und schlechter UX.

    Statt Raycast scannen wir direkt die vom NPC-Manager gespawnten Peds
    (`GMenu.NpcMgr.peds`) und blenden Marker ueber genau diesen Peds ein.
    Wenn der Spieler in Aktivierungs-Reichweite steht, wird der naechste
    NPC ueber `NM.getCurrent()` als aktives Ziel veroeffentlicht und
    `client/raycast.lua` uebernimmt ihn als ped-typisches Ziel.

    Konfigurierbar via `Config.ObjectMarkers` (gleiche Settings - bleibt einheitlich).
]]

GMenu = GMenu or {}
GMenu.NpcMarkers = {}

local NM  = GMenu.NpcMarkers
local Mgr = GMenu.NpcMgr   -- aus client/npcs.lua

local PlayerPedId       = PlayerPedId
local GetEntityCoords   = GetEntityCoords
local GetEntityModel    = GetEntityModel
local DoesEntityExist   = DoesEntityExist
local DrawMarker        = DrawMarker
local IsPauseMenuActive = IsPauseMenuActive
local IsPedInAnyVehicle = IsPedInAnyVehicle
local NetworkGetEntityIsNetworked   = NetworkGetEntityIsNetworked
local NetworkGetNetworkIdFromEntity = NetworkGetNetworkIdFromEntity

NM._tracked = {}    -- ped -> { coords, distance, npcId }
NM._current = nil

-- ============================================================
--  CONFIG
-- ============================================================
-- Wir verwenden die gleichen Globals wie ObjectMarkers fuer einheitliches
-- Verhalten. Spezifische NPC-Overrides koennen ueber globals.npcMarkers
-- gesetzt werden (Admin-Panel).

local function pickBool(o, b, fallback)
    if o ~= nil then return o and true or false end
    if b ~= nil then return b and true or false end
    return fallback and true or false
end

local function pickNum(o, b, fallback)
    return o or b or fallback
end

local function cfg()
    local g = GMenu.State and GMenu.State.store and GMenu.State.store.globals or {}
    local base = Config.ObjectMarkers or {}
    local omOv = g.objectMarkers or {}
    local npOv = g.npcMarkers or {}
    -- Reihenfolge: npcMarkers > objectMarkers > Config.ObjectMarkers > Hardcode
    return {
        enabled            = pickBool(npOv.enabled, omOv.enabled, base.enabled),
        markerType         = pickNum(npOv.markerType,         omOv.markerType,         base.markerType,         2),
        markerScale        = pickNum(npOv.markerScale,        omOv.markerScale,        base.markerScale,        0.35),
        drawDistance       = pickNum(npOv.drawDistance,       omOv.drawDistance,       base.drawDistance,       8.0),
        activationDistance = pickNum(npOv.activationDistance, omOv.activationDistance, base.activationDistance, 1.8),
        bobbing            = pickBool(npOv.bobbing, omOv.bobbing, base.bobbing),
        yOffset            = pickNum(npOv.yOffset, omOv.yOffset, base.yOffset, 1.15),
        scanIntervalIdle   = pickNum(npOv.scanIntervalIdle,   omOv.scanIntervalIdle,   base.scanIntervalIdle,   600),
        scanIntervalActive = pickNum(npOv.scanIntervalActive, omOv.scanIntervalActive, base.scanIntervalActive, 200),
    }
end

-- ============================================================
--  SCAN
-- ============================================================

local function rebuildTracked()
    local c = cfg()
    if not c.enabled or not Mgr or not Mgr.peds then
        NM._tracked = {}
        NM._current = nil
        return
    end

    local myPos = GetEntityCoords(PlayerPedId())
    local tracked = {}
    local closest, closestDist = nil, math.huge

    for npcId, ped in pairs(Mgr.peds) do
        if ped and DoesEntityExist(ped) then
            local pos = GetEntityCoords(ped)
            local dx, dy, dz = pos.x - myPos.x, pos.y - myPos.y, pos.z - myPos.z
            local sqr = dx*dx + dy*dy + dz*dz
            if sqr <= (c.drawDistance + 2.0) * (c.drawDistance + 2.0) then
                local dist = math.sqrt(sqr)
                tracked[ped] = {
                    coords   = pos,
                    distance = dist,
                    npcId    = npcId,
                }
                if dist < closestDist and dist <= c.activationDistance then
                    closest, closestDist = ped, dist
                end
            end
        end
    end

    NM._tracked = tracked

    if closest then
        local entry = tracked[closest]
        local def = (Mgr.list and Mgr.list[entry.npcId]) or nil
        local label = (def and (def.label or def.name)) or 'NPC'
        NM._current = {
            entity   = closest,
            type     = 'ped',
            isPlayer = false,
            label    = label,
            coords   = entry.coords,
            distance = entry.distance,
            npcId    = entry.npcId,
            netId    = NetworkGetEntityIsNetworked(closest) and NetworkGetNetworkIdFromEntity(closest) or 0,
            model    = GetEntityModel(closest),
        }
    else
        NM._current = nil
    end
end

-- ============================================================
--  PUBLIC
-- ============================================================

function NM.getCurrent()
    return NM._current
end

function NM.getTracked()
    return NM._tracked
end

-- ============================================================
--  THREADS
-- ============================================================

CreateThread(function()
    while not (GMenu.State and GMenu.State.storeReady) do Wait(200) end

    while true do
        local c = cfg()
        if not c.enabled or IsPauseMenuActive() then
            NM._tracked = {}
            NM._current = nil
            Wait(800)
        else
            if Config.HideWhenInVehicle and IsPedInAnyVehicle(PlayerPedId(), false) then
                NM._tracked = {}
                NM._current = nil
                Wait(800)
            else
                rebuildTracked()
                local hasAny = next(NM._tracked) ~= nil
                Wait(hasAny and c.scanIntervalActive or c.scanIntervalIdle)
            end
        end
    end
end)

CreateThread(function()
    while not (GMenu.State and GMenu.State.storeReady) do Wait(200) end

    while true do
        local c = cfg()
        if not c.enabled or not next(NM._tracked) then
            Wait(300)
        else
            local rgb = (GMenu.GetColor and GMenu.GetColor('marker')) or { r = 50, g = 150, b = 255 }
            local now = GetGameTimer()
            local bob = c.bobbing and (math.sin(now / 380.0) * 0.06) or 0.0
            local drawSqr = c.drawDistance * c.drawDistance
            local myPos = GetEntityCoords(PlayerPedId())

            for ped, entry in pairs(NM._tracked) do
                if DoesEntityExist(ped) then
                    local p = GetEntityCoords(ped)
                    local dx, dy, dz = p.x - myPos.x, p.y - myPos.y, p.z - myPos.z
                    if dx*dx + dy*dy + dz*dz <= drawSqr then
                        local isActive = NM._current and NM._current.entity == ped
                        local alpha = isActive and 220 or 130
                        local scaleMul = isActive and 1.25 or 1.0
                        local size = c.markerScale * scaleMul
                        DrawMarker(
                            tonumber(c.markerType) or 2,
                            p.x, p.y, p.z + (c.yOffset or 1.15) + bob,
                            0,0,0, 0,0,0,
                            size, size, size,
                            rgb.r, rgb.g, rgb.b, alpha,
                            false, true, 2, false, nil, nil, false
                        )
                    end
                end
            end

            Wait(0)
        end
    end
end)

print('^2[clp_gmenu]^0 NPC-Markers geladen.')
