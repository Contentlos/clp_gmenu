--[[
    clp_gmenu - Raycast / Zielerkennung

    Kamera-Raycast (8-10m), entdeckt Fahrzeuge & Personen.
    Liefert ueber Callback / Polling-Funktionen das aktuelle Ziel.

    Modus: KONSTANT AKTIV - scannt permanent im Hintergrund.

    Performance:
      - Idle: Wait(IdleWaitMs) wenn kein Ziel erkannt (~200ms)
      - Aktiv: Wait(ActiveWaitMs) waehrend Target gehalten wird (~0ms)
      - Pausiert: Pause-Menue, NUI-Focus, Tippen, im Wasser, etc.
]]

GMenu = GMenu or {}
GMenu.Raycast = {}

local R = GMenu.Raycast
local U = GMenu.Util

-- Lokalisierte Natives (Performance)
local PlayerPedId             = PlayerPedId
local IsPauseMenuActive       = IsPauseMenuActive
local IsNuiFocused            = IsNuiFocused
local GetEntityCoords         = GetEntityCoords
local DoesEntityExist         = DoesEntityExist
local IsEntityAVehicle        = IsEntityAVehicle
local IsEntityAPed            = IsEntityAPed
local IsPedAPlayer            = IsPedAPlayer
local GetVehicleNumberPlateText = GetVehicleNumberPlateText
local GetEntityModel          = GetEntityModel
local GetDisplayNameFromVehicleModel = GetDisplayNameFromVehicleModel
local GetLabelText            = GetLabelText
local NetworkGetEntityIsNetworked = NetworkGetEntityIsNetworked
local NetworkGetNetworkIdFromEntity = NetworkGetNetworkIdFromEntity
local GetEntityHealth         = GetEntityHealth
local GetVehicleEngineHealth  = GetVehicleEngineHealth
local GetVehicleBodyHealth    = GetVehicleBodyHealth
local GetEntitySpeed          = GetEntitySpeed
local IsPedDeadOrDying        = IsPedDeadOrDying

-- ============================================================
--  STATE
-- ============================================================

R.current = nil      -- Aktuelles Ziel oder nil
R.lastSwitchAt = 0   -- ms, wann das Ziel zuletzt gewechselt hat
R.paused = false     -- Kann extern pausiert werden (z.B. waehrend NUI-Focus)

local listeners = {} -- Callbacks die bei Ziel-Wechsel benachrichtigt werden: fn(neuesZiel, altesZiel)
local statsListeners = {} -- Callbacks fuer Statistik-Updates: fn(stats)

-- ============================================================
--  RAYCAST CORE
-- ============================================================

--- Liefert hit, entityHit, endCoords aus Kamera-Raycast.
--- Nutzt ox_lib falls vorhanden (sonst nativer Fallback).
local function performRaycast(maxDist)
    if lib and lib.raycast and lib.raycast.fromCamera then
        -- 511 = alle Layer; 4 = sich selbst ignorieren; maxDist
        local hit, entityHit, endCoords = lib.raycast.fromCamera(511, 4, maxDist)
        return hit, entityHit, endCoords
    end

    -- Nativer Fallback (Kamera-Richtungs-Raycast)
    local cameraRot = GetGameplayCamRot(2)
    local cameraCoord = GetGameplayCamCoord()
    local rotZ = math.rad(cameraRot.z)
    local rotX = math.rad(cameraRot.x)
    local cosX = math.abs(math.cos(rotX))
    local dir = vector3(-math.sin(rotZ) * cosX, math.cos(rotZ) * cosX, math.sin(rotX))
    local dest = cameraCoord + dir * maxDist
    local rayHandle = StartShapeTestRay(cameraCoord.x, cameraCoord.y, cameraCoord.z,
        dest.x, dest.y, dest.z, -1, PlayerPedId(), 0)
    local _, hit, endCoords, _, entityHit = GetShapeTestResult(rayHandle)
    return hit == 1, entityHit, endCoords
end

-- ============================================================
--  ZIEL-AUFLOESUNG
-- ============================================================

local IsEntityAnObject = IsEntityAnObject

-- Target priority: lower number wins in tiebreakers
R.PRIORITY = { player = 1, ped = 2, vehicle = 3, object = 4, zone = 5 }

local function resolveTarget(entity, hitCoords)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end

    local myPed = PlayerPedId()
    if entity == myPed then return nil end                                   -- Sich selbst anvisieren blockieren

    -- WICHTIG: Typ-Filter VOR dem Zugriff auf GetEntityModel usw.
    -- Der Kamera-Raycast kann Fragmente/Glas/Map-Props zurueckgeben, die
    -- DoesEntityExist=true haben, aber bei GetEntityModel einen nativen
    -- Fehler ausloesen (0x9f47b058362c84b5).
    local isVeh = IsEntityAVehicle(entity)
    local isPed = not isVeh and IsEntityAPed(entity)
    local isObj = (not isVeh and not isPed) and IsEntityAnObject(entity)
    if not isVeh and not isPed and not isObj then return nil end

    local t = {
        entity = entity,
        coords = hitCoords or GetEntityCoords(entity),
        netId  = NetworkGetEntityIsNetworked(entity) and NetworkGetNetworkIdFromEntity(entity) or 0,
    }

    -- Model defensiv holen (pcall als Sicherheitsnetz falls die Engine Fehler wirft)
    local okModel, model = pcall(GetEntityModel, entity)
    t.model = okModel and model or 0

    local distance = #(GetEntityCoords(myPed) - t.coords)
    t.distance = distance

    if isVeh then
        t.type   = 'vehicle'
        t.plate  = U.trim(GetVehicleNumberPlateText(entity) or '')
        local mn = t.model ~= 0 and GetDisplayNameFromVehicleModel(t.model) or ''
        local lbl = mn ~= '' and GetLabelText(mn) or nil
        t.label  = (lbl and lbl ~= 'NULL' and lbl ~= '' and lbl) or (mn ~= '' and mn) or 'Fahrzeug'
        return t
    end

    if isObj then
        -- Objects/Props werden NICHT mehr ueber Raycast erfasst (unzuverlaessig
        -- bei Map-Props mit defekten Bounds). Stattdessen uebernimmt
        -- `client/object_markers.lua` per Pool-Scan die Prop-Erkennung.
        return nil
    end

    -- isPed
    local myVeh = GetVehiclePedIsIn(myPed, false)
    if myVeh ~= 0 and entity == GetPedInVehicleSeat(myVeh, -1) then return nil end -- eigenen Fahrer ignorieren
    t.isPlayer = IsPedAPlayer(entity)

    if t.isPlayer then
        t.type = 'player'
        local sid = NetworkGetPlayerIndexFromPed(entity)
        t.serverId = sid >= 0 and GetPlayerServerId(sid) or nil
        -- Identity-aware Label (Fremder/Fremde oder echter Name)
        local pname
        if GMenu.Identity and GMenu.Identity.getDisplayNameForServerId and t.serverId then
            pname = GMenu.Identity.getDisplayNameForServerId(t.serverId)
        end
        if not pname or pname == '' then
            pname = sid >= 0 and GetPlayerName(sid) or 'Player'
        end
        t.label = ('%s (#%s)'):format(pname or 'Player', t.serverId or '?')
        t.isDead = IsPedDeadOrDying(entity, true)
        return t
    end

    -- NPCs werden ebenfalls nicht mehr per Raycast erkannt (zu viele
    -- Fehl-Hits bei Bevoelkerungs-Peds, Tieren, etc.). Statt dessen
    -- uebernimmt `client/npc_markers.lua` per Ped-Pool-Scan + StateBag-
    -- Filter (clp_npc_id) die NPC-Erkennung.
    return nil
end

-- ============================================================
--  STATISTIKEN (Fahrzeug-Zustand/Geschwindigkeit)
-- ============================================================

local function buildStats(target)
    if not target or not target.entity or not DoesEntityExist(target.entity) then return nil end
    if target.type == 'vehicle' then
        local engine = GetVehicleEngineHealth(target.entity)    -- 0..1000
        local body   = GetVehicleBodyHealth(target.entity)      -- 0..1000
        local speed  = GetEntitySpeed(target.entity) * 3.6      -- m/s -> km/h
        return {
            kind   = 'vehicle',
            label  = target.label,
            plate  = target.plate,
            engine = math.max(0, math.floor(engine / 10)),    -- in % (0..100)
            body   = math.max(0, math.floor(body / 10)),
            speed  = math.floor(speed),
        }
    elseif target.type == 'player' or target.type == 'ped' then
        local hp = GetEntityHealth(target.entity) - 100        -- 0..100
        return {
            kind  = 'player',
            label = target.label,
            hp    = math.max(0, math.floor(hp)),
            isDead= target.isDead,
        }
    end
    return nil
end

-- ============================================================
--  EREIGNIS-LISTENER (intern)
-- ============================================================

function R.onChange(callback)
    if type(callback) == 'function' then listeners[#listeners + 1] = callback end
end

function R.onStats(callback)
    if type(callback) == 'function' then statsListeners[#statsListeners + 1] = callback end
end

local function notifyChange(newTarget, prevTarget)
    R.lastSwitchAt = GetGameTimer()
    for i = 1, #listeners do
        local ok, err = pcall(listeners[i], newTarget, prevTarget)
        if not ok then print('^1[clp_gmenu]^0 Raycast-Listener Fehler:', err) end
    end
end

local function notifyStats(stats)
    for i = 1, #statsListeners do
        local ok, err = pcall(statsListeners[i], stats)
        if not ok then print('^1[clp_gmenu]^0 Statistik-Listener Fehler:', err) end
    end
end

-- ============================================================
--  PUBLIC: Pause / Fortsetzen
-- ============================================================

--- Pausiert den Raycast (z.B. waehrend Menue-Interaktion).
function R.pause()
    R.paused = true
end

--- Setzt den Raycast fort.
function R.resume()
    R.paused = false
end

--- Abwaertskompatibel: activate/deactivate als Alias
function R.activate()  R.paused = false end
function R.deactivate() R.paused = true end

-- ============================================================
--  OEFFENTLICH: Aktuelles Ziel abfragen
-- ============================================================

function R.getCurrent()
    return R.current
end

function R.getCurrentStats()
    return buildStats(R.current)
end

-- ============================================================
--  MAIN LOOP
-- ============================================================

local function isGameBusy()
    if IsPauseMenuActive() then return true end
    -- Chat-Eingabe
    if IsNuiFocused() and not (GMenu.Menu and GMenu.Menu.isOpen and GMenu.Menu.isOpen()) then return true end
    return false
end

CreateThread(function()
    while true do
        if not GMenu.State or not GMenu.State.storeReady then
            Wait(500)
        elseif R.paused then
            -- Extern pausiert (z.B. NUI-Settings offen)
            Wait(200)
        elseif isGameBusy() then
            if R.current then
                local prev = R.current
                R.current = nil
                notifyChange(nil, prev)
            end
            Wait(500)
        elseif Config.HideWhenInVehicle and IsPedInAnyVehicle(PlayerPedId(), false) then
            if R.current then
                local prev = R.current
                R.current = nil
                notifyChange(nil, prev)
            end
            Wait(500)
        else
            local maxDist = GMenu.GetMaxDistance()
            local hit, entityHit, endCoords = performRaycast(maxDist + 5.0)

            local target
            if hit and entityHit ~= 0 then
                target = resolveTarget(entityHit, endCoords)
                if target and target.distance > maxDist then
                    target = nil
                end
            end

            -- Marker-Fallback: kein Entity vom Raycast, aber NPC oder Prop in Reichweite?
            -- (Markers ersetzen Raycast fuer NPCs/Props - siehe npc_markers.lua / object_markers.lua)
            if not target and GMenu.NpcMarkers and GMenu.NpcMarkers.getCurrent then
                local npcTarget = GMenu.NpcMarkers.getCurrent()
                if npcTarget then
                    target = npcTarget
                end
            end
            if not target and GMenu.ObjectMarkers and GMenu.ObjectMarkers.getCurrent then
                local propTarget = GMenu.ObjectMarkers.getCurrent()
                if propTarget then
                    target = propTarget
                end
            end

            -- Zone-Fallback: kein Entity getroffen, aber im Zonenbereich?
            if not target and GMenu.Zones and GMenu.Zones.getCurrent then
                local zoneDef = GMenu.Zones.getCurrent()
                if zoneDef then
                    target = {
                        entity   = 0,
                        type     = 'zone',
                        zoneName = zoneDef.name,
                        label    = zoneDef.label or zoneDef.name,
                        coords   = zoneDef.coords or GetEntityCoords(PlayerPedId()),
                        netId    = 0,
                        model    = 0,
                        distance = 0.0,
                    }
                end
            end

            -- Wechsel-Erkennung mit Target Lock (200-350ms hold)
            -- (Verhindert Flackern bei kurzen Verlusten / Kameraruckeln)
            local prev = R.current
            local prevId = prev and (prev.entity ~= 0 and prev.entity or (prev.zoneName and ('zone:' .. prev.zoneName) or 0)) or 0
            local nextId = target and (target.entity ~= 0 and target.entity or (target.zoneName and ('zone:' .. target.zoneName) or 0)) or 0
            local now = GetGameTimer()
            local LOCK_MS = (Config and Config.TargetLockMs) or 250

            if prevId ~= nextId then
                -- Falls Target verloren: kurz halten, falls Lock noch aktiv
                if not target and prev and prev._lockedAt and (now - prev._lockedAt) < LOCK_MS then
                    -- Keep prev a moment longer
                else
                    if target then target._lockedAt = now end
                    R.current = target
                    notifyChange(target, prev)

                    -- Ton bei neuem Ziel
                    if target and GMenu.SoundsEnabled() and Config.SoundOnTarget then
                        PlaySoundFrontend(-1, Config.SoundOnTarget.name, Config.SoundOnTarget.lib, true)
                    end
                end
            else
                -- Gleiches Ziel: Aktualisierung (Distanz, Statistiken)
                if target then
                    R.current.distance = target.distance
                    R.current.coords   = target.coords
                end
            end

            -- Statistik-Aktualisierung (alle 250ms)
            if R.current and GMenu.StatsEnabled() then
                local now = GetGameTimer()
                if not R._lastStatsAt or (now - R._lastStatsAt) > 250 then
                    R._lastStatsAt = now
                    local s = buildStats(R.current)
                    if s then notifyStats(s) end
                end
            end

            Wait(R.current and (Config.ActiveWaitMs or 0) or (Config.IdleWaitMs or 200))
        end
    end
end)

print('^2[clp_gmenu]^0 Raycast geladen.')
