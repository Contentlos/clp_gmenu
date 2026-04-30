--[[
    clp_gmenu - Universal Client-Handler

    Vehicle-Aktionen (Motor, Schloss, Tueren, Kofferraum, Motorhaube)
    plus Default-Emotes.
]]

-- ============================================================
--  EMOTES
-- ============================================================

local EMOTE_DICTS = {
    wave         = { dict = 'gestures@m@standing@casual', anim = 'gesture_hello' },
    help_up      = { dict = 'amb@medic@standing@kneel@enter', anim = 'enter' },
    sit          = { dict = 'amb@world_human_seat_wall@male@arms_up@idle_a', anim = 'idle_a' },
    surrender    = { dict = 'random@arrests@busted', anim = 'idle_a' },
    point        = { dict = 'gestures@f@standing@casual', anim = 'gesture_point' },
}

RegisterNetEvent('clp_gmenu:emote', function(name)
    local def = EMOTE_DICTS[name]
    if not def then return end
    RequestAnimDict(def.dict)
    local t = GetGameTimer()
    while not HasAnimDictLoaded(def.dict) and (GetGameTimer() - t) < 3000 do Wait(10) end
    TaskPlayAnim(PlayerPedId(), def.dict, def.anim, 8.0, -8.0, 2500, 0, 0, false, false, false)
end)

-- ============================================================
--  HELPER
-- ============================================================

local function getVehicleByNetId(netId)
    if not netId or netId == 0 then return 0 end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return 0 end
    return veh
end

local function ensureControl(veh)
    if not NetworkHasControlOfEntity(veh) then
        NetworkRequestControlOfEntity(veh)
        local t = GetGameTimer()
        while not NetworkHasControlOfEntity(veh) and (GetGameTimer() - t) < 1000 do Wait(50) end
    end
end

-- ============================================================
--  ENGINE
-- ============================================================
RegisterNetEvent('clp_gmenu:vehicle:toggleEngine', function(netId)
    local veh = getVehicleByNetId(netId); if veh == 0 then return end
    ensureControl(veh)
    local on = GetIsVehicleEngineRunning(veh)
    SetVehicleEngineOn(veh, not on, false, true)
    if GMenu.UI then GMenu.UI.notify({ type = 'inform', description = on and 'Motor aus' or 'Motor an' }) end
end)

-- ============================================================
--  LOCK
-- ============================================================
RegisterNetEvent('clp_gmenu:vehicle:toggleLock', function(netId)
    local veh = getVehicleByNetId(netId); if veh == 0 then return end
    ensureControl(veh)
    local s = GetVehicleDoorLockStatus(veh)
    if s == 1 or s == 0 then
        SetVehicleDoorsLocked(veh, 2)
        if GMenu.UI then GMenu.UI.notify({ type = 'inform', description = 'Fahrzeug abgeschlossen.' }) end
    else
        SetVehicleDoorsLocked(veh, 1)
        if GMenu.UI then GMenu.UI.notify({ type = 'inform', description = 'Fahrzeug aufgeschlossen.' }) end
    end
    PlaySoundFrontend(-1, 'CONFIRM_BEEP', 'HUD_MINI_GAME_SOUNDSET', true)
end)

-- ============================================================
--  DOORS / TRUNK / HOOD
-- ============================================================

local function toggleDoor(veh, doorIndex)
    if IsVehicleDoorDamaged(veh, doorIndex) then return end
    local angle = GetVehicleDoorAngleRatio(veh, doorIndex)
    if angle > 0.0 then
        SetVehicleDoorShut(veh, doorIndex, false)
    else
        SetVehicleDoorOpen(veh, doorIndex, false, false)
    end
end

RegisterNetEvent('clp_gmenu:vehicle:toggleDoors', function(netId)
    local veh = getVehicleByNetId(netId); if veh == 0 then return end
    ensureControl(veh)
    -- Open/close all 4 main doors
    for i = 0, 3 do toggleDoor(veh, i) end
end)

RegisterNetEvent('clp_gmenu:vehicle:toggleTrunk', function(netId)
    local veh = getVehicleByNetId(netId); if veh == 0 then return end
    ensureControl(veh)
    toggleDoor(veh, 5)   -- Door 5 = trunk
end)

RegisterNetEvent('clp_gmenu:vehicle:toggleHood', function(netId)
    local veh = getVehicleByNetId(netId); if veh == 0 then return end
    ensureControl(veh)
    toggleDoor(veh, 4)   -- Door 4 = hood
end)
