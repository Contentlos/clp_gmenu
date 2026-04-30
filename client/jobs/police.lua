--[[
    clp_gmenu - Client Job: POLICE
    Reagiert auf Server-Events (Cuff/Drag/BreakLock) und spielt Animationen
    bzw. Effekte auf dem Client ab.
]]

local cuffed = false
local dragger = nil

-- ============================================================
--  CUFF / UNCUFF (auf den BETROFFENEN Spieler getriggert)
-- ============================================================

RegisterNetEvent('clp_gmenu:police:cuff', function(state)
    cuffed = state and true or false
    local ped = PlayerPedId()
    if cuffed then
        RequestAnimDict('mp_arresting')
        local t = GetGameTimer()
        while not HasAnimDictLoaded('mp_arresting') and (GetGameTimer() - t) < 3000 do Wait(10) end
        TaskPlayAnim(ped, 'mp_arresting', 'idle', 8.0, -8.0, -1, 49, 0, false, false, false)
        SetEnableHandcuffs(ped, true)
        DisablePlayerFiring(PlayerId(), true)
        DisableControlAction(0, 24, true)   -- attack
        DisableControlAction(0, 257, true)
        SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
        lib.notify({ type = 'warning', description = 'Du wurdest in Handschellen gelegt.' })
    else
        ClearPedTasks(ped)
        SetEnableHandcuffs(ped, false)
        lib.notify({ type = 'success', description = 'Handschellen entfernt.' })
    end
end)

-- Block Bewegung waehrend Cuffed
CreateThread(function()
    while true do
        if cuffed then
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 47, true)
            DisableControlAction(0, 58, true)
            DisableControlAction(0, 263, true)
            DisableControlAction(0, 264, true)
            DisableControlAction(0, 257, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(0, 143, true)
            DisableControlAction(0, 75, true)   -- exit vehicle
            DisableControlAction(27, 75, true)
            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- ============================================================
--  DRAG (an Officer attachen / detachen)
-- ============================================================

RegisterNetEvent('clp_gmenu:police:drag', function(officerSrc)
    if not cuffed then return end
    local me = PlayerPedId()
    if dragger then
        DetachEntity(me, true, false)
        dragger = nil
        lib.notify({ description = 'Wurdest losgelassen.' })
        return
    end
    local officerPed = GetPlayerPed(GetPlayerFromServerId(officerSrc))
    if officerPed and officerPed ~= 0 and DoesEntityExist(officerPed) then
        AttachEntityToEntity(me, officerPed, 11816, 0.45, 0.4, 0.0,
            0.0, 0.0, 0.0, false, false, false, false, 2, true)
        dragger = officerSrc
        lib.notify({ description = 'Du wirst gefuehrt.' })
    end
end)

-- ============================================================
--  BREAK LOCK (Officer-Side Anim)
-- ============================================================

RegisterNetEvent('clp_gmenu:police:breakLock', function(netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end

    local ped = PlayerPedId()
    if lib.progressBar({
        duration = 4000,
        label = 'Schloss aufbrechen...',
        useWhileDead = false,
        canCancel = true,
        anim = { dict = 'veh@break_in@0h@p_m_one@', clip = 'low_force_entry_ds' },
    }) then
        SetVehicleDoorsLocked(veh, 1)
        SetVehicleDoorsLockedForAllPlayers(veh, false)
        lib.notify({ type = 'success', description = 'Schloss aufgebrochen.' })
    end
    ClearPedTasks(ped)
end)

-- ============================================================
--  AUF RESPAWN/DROP CLEANUP
-- ============================================================

AddEventHandler('esx:onPlayerSpawn', function()
    cuffed = false
    dragger = nil
end)
