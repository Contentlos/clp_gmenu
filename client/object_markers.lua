--[[
    clp_gmenu - Object-Marker (Props)

    Raycast ist auf statischen Map-Props (Drittanbieter-`registerModelAction` /
    `addModel` / `addLocalEntity`) unzuverlaessig: Map-Props haben oft kaputte
    Bounds, sodass `lib.raycast.fromCamera` zwar einen Treffer meldet, aber das
    Entity-Handle nicht das angezielte Modell ist.

    Loesung: Statt Raycast scannen wir periodisch alle Props im Spieler-Umkreis
    (`scanRadius`) und prueften welche davon im clp_gmenu Bridge-Registry
    registriert sind (Modell-Hash / lokales Entity / NetId).

    - Fuer alle gefundenen Props: kleinen Marker zeichnen (DrawMarker)
    - Naechstes Prop innerhalb `activationDistance` wird als aktives Ziel
      veroeffentlicht (`GMenu.ObjectMarkers.getCurrent()`).
    - `client/raycast.lua` fragt diesen Wert als Fallback ab, wenn der Raycast
      kein Entity-Ziel zurueckgibt.

    Konfigurierbar via `Config.ObjectMarkers` (siehe config.lua).
]]

GMenu = GMenu or {}
GMenu.ObjectMarkers = {}

local OM = GMenu.ObjectMarkers
local U  = GMenu.Util
local B  = GMenu.Bridge   -- aus client/bridge_ox.lua (B.models / B.entities / B.netIds)

-- Lokalisierte Natives
local PlayerPedId          = PlayerPedId
local GetEntityCoords      = GetEntityCoords
local GetEntityModel       = GetEntityModel
local DoesEntityExist      = DoesEntityExist
local GetGamePool          = GetGamePool
local DrawMarker           = DrawMarker
local NetworkGetEntityIsNetworked   = NetworkGetEntityIsNetworked
local NetworkGetNetworkIdFromEntity = NetworkGetNetworkIdFromEntity
local IsPauseMenuActive    = IsPauseMenuActive
local IsPedInAnyVehicle    = IsPedInAnyVehicle

-- ============================================================
--  STATE
-- ============================================================

OM._tracked = {}    -- entity -> { coords, distance, modelHash, options, source }
OM._current = nil   -- aktives Ziel (innerhalb activationDistance)

-- ============================================================
--  CONFIG-ZUGRIFF (live-reload aware)
-- ============================================================

local function cfg()
    local g = GMenu.State and GMenu.State.store and GMenu.State.store.globals or {}
    local base = Config.ObjectMarkers or {}
    -- Globals duerfen einzelne Felder ueberschreiben (Admin-Panel)
    local override = g.objectMarkers or {}
    return {
        enabled            = (override.enabled            ~= nil) and override.enabled            or base.enabled,
        markerType         = override.markerType          or base.markerType         or 2,
        markerScale        = override.markerScale         or base.markerScale        or 0.35,
        drawDistance       = override.drawDistance        or base.drawDistance       or 8.0,
        activationDistance = override.activationDistance  or base.activationDistance or 1.8,
        bobbing            = (override.bobbing            ~= nil) and override.bobbing            or base.bobbing,
        yOffset            = override.yOffset             or base.yOffset            or 1.1,
        scanRadius         = override.scanRadius          or base.scanRadius         or 12.0,
        scanIntervalIdle   = override.scanIntervalIdle    or base.scanIntervalIdle   or 600,
        scanIntervalActive = override.scanIntervalActive  or base.scanIntervalActive or 200,
    }
end

-- ============================================================
--  REGISTRY-LOOKUP
-- ============================================================

--- Liefert {options=..., source='model'|'entity'|'netId'} fuer ein Prop, falls registriert.
local function lookupProp(entity)
    if not B then return nil end
    -- 1) Lokales Entity-Handle
    local byEnt = B.entities and B.entities[entity]
    if byEnt and byEnt.options and #byEnt.options > 0 then
        return { options = byEnt.options, source = 'entity', distance = byEnt.distance or 3.0 }
    end
    -- 2) NetId
    if NetworkGetEntityIsNetworked(entity) then
        local nid = NetworkGetNetworkIdFromEntity(entity)
        local byNid = B.netIds and B.netIds[nid]
        if byNid and byNid.options and #byNid.options > 0 then
            return { options = byNid.options, source = 'netId', distance = byNid.distance or 3.0 }
        end
    end
    -- 3) Modell-Hash
    local okModel, model = pcall(GetEntityModel, entity)
    if okModel and model and model ~= 0 then
        local byMod = B.models and B.models[model]
        if byMod and byMod.options and #byMod.options > 0 then
            return { options = byMod.options, source = 'model', modelHash = model, distance = byMod.distance or 3.0 }
        end
    end
    return nil
end

-- ============================================================
--  SCAN-LOOP
-- ============================================================

local function rebuildTracked()
    local c = cfg()
    if not c.enabled then
        OM._tracked = {}
        OM._current = nil
        return
    end

    local myPed = PlayerPedId()
    local myPos = GetEntityCoords(myPed)
    local radius = c.scanRadius
    local sqrRadius = radius * radius

    local pool = GetGamePool('CObject')
    local tracked = {}
    local closest, closestDist = nil, math.huge

    for i = 1, #pool do
        local ent = pool[i]
        if ent and DoesEntityExist(ent) then
            local pos = GetEntityCoords(ent)
            local dx, dy, dz = pos.x - myPos.x, pos.y - myPos.y, pos.z - myPos.z
            local sqr = dx*dx + dy*dy + dz*dz
            if sqr <= sqrRadius then
                local hit = lookupProp(ent)
                if hit then
                    local dist = math.sqrt(sqr)
                    tracked[ent] = {
                        coords    = pos,
                        distance  = dist,
                        modelHash = hit.modelHash,
                        options   = hit.options,
                        source    = hit.source,
                    }
                    if dist < closestDist and dist <= c.activationDistance then
                        closest, closestDist = ent, dist
                    end
                end
            end
        end
    end

    OM._tracked = tracked

    if closest then
        local entry = tracked[closest]
        OM._current = {
            entity   = closest,
            type     = 'object',
            label    = 'Objekt',
            coords   = entry.coords,
            distance = entry.distance,
            model    = entry.modelHash or 0,
            netId    = NetworkGetEntityIsNetworked(closest) and NetworkGetNetworkIdFromEntity(closest) or 0,
            _bridgeOptions = entry.options,
            _bridgeSource  = entry.source,
        }
    else
        OM._current = nil
    end
end

-- ============================================================
--  PUBLIC API
-- ============================================================

--- Liefert das aktuell aktive Prop-Ziel (oder nil).
function OM.getCurrent()
    return OM._current
end

--- Liefert die getrackten Props (Marker-Quelle).
function OM.getTracked()
    return OM._tracked
end

-- ============================================================
--  MAIN-THREAD: SCAN + RENDER
-- ============================================================

CreateThread(function()
    while not (GMenu.State and GMenu.State.storeReady) do Wait(200) end

    while true do
        local c = cfg()
        if not c.enabled or IsPauseMenuActive() then
            OM._tracked = {}
            OM._current = nil
            Wait(800)
        else
            -- Im Fahrzeug skippen wir das Scannen (HideWhenInVehicle parallelisiert)
            if Config.HideWhenInVehicle and IsPedInAnyVehicle(PlayerPedId(), false) then
                OM._tracked = {}
                OM._current = nil
                Wait(800)
            else
                rebuildTracked()
                local hasAny = next(OM._tracked) ~= nil
                Wait(hasAny and c.scanIntervalActive or c.scanIntervalIdle)
            end
        end
    end
end)

CreateThread(function()
    while not (GMenu.State and GMenu.State.storeReady) do Wait(200) end

    while true do
        local c = cfg()
        if not c.enabled or not next(OM._tracked) then
            Wait(300)
        else
            local rgb = (GMenu.GetColor and GMenu.GetColor('marker')) or { r = 50, g = 150, b = 255 }
            local now = GetGameTimer()
            local bob = c.bobbing and (math.sin(now / 380.0) * 0.06) or 0.0
            local drawSqr = c.drawDistance * c.drawDistance
            local myPos = GetEntityCoords(PlayerPedId())
            local activate = c.activationDistance

            for ent, entry in pairs(OM._tracked) do
                if DoesEntityExist(ent) then
                    local p = GetEntityCoords(ent)
                    local dx, dy, dz = p.x - myPos.x, p.y - myPos.y, p.z - myPos.z
                    if dx*dx + dy*dy + dz*dz <= drawSqr then
                        local s = c.markerScale
                        -- Naechstes (aktives) Ziel etwas groesser + voller Alpha
                        local isActive = OM._current and OM._current.entity == ent
                        local alpha = isActive and 220 or 130
                        local scaleMul = isActive and 1.25 or 1.0
                        local size = s * scaleMul
                        DrawMarker(
                            tonumber(c.markerType) or 2,
                            p.x, p.y, p.z + (c.yOffset or 1.1) + bob,
                            0,0,0, 0,0,0,
                            size, size, size,
                            rgb.r, rgb.g, rgb.b, alpha,
                            false, true,    -- bobUpAndDown=false (wir bobben selbst), faceCamera=true
                            2, false, nil, nil, false
                        )
                    end
                end
            end

            -- Aktivierungs-Hint kurz oberhalb des aktiven Props (Hilfetext)
            if OM._current and OM._current.coords then
                local cp = OM._current.coords
                local d = #(myPos - cp)
                if d <= activate then
                    -- Sanfter zweiter, kleinerer Marker als visuelles "ready"-Signal
                    DrawMarker(
                        25,
                        cp.x, cp.y, cp.z + (c.yOffset or 1.1) - 0.4,
                        0,0,0, 0,0,0,
                        0.55, 0.55, 0.10,
                        rgb.r, rgb.g, rgb.b, 60,
                        false, false, 2, false, nil, nil, false
                    )
                end
            end

            Wait(0)
        end
    end
end)

print('^2[clp_gmenu]^0 Object-Markers geladen.')
