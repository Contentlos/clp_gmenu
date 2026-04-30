--[[
    clp_gmenu - Client Job: FIRE
]]

-- ============================================================
--  EXTINGUISH - Feuer am Fahrzeug loeschen
-- ============================================================
RegisterNetEvent('clp_gmenu:fire:extinguish', function(netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end

    if lib.progressBar({
        duration = 5000,
        label = 'Feuer loeschen...',
        useWhileDead = false,
        canCancel = true,
        anim = { dict = 'weapons@projectile@', clip = 'throw_m_fb_stand' },
    }) then
        StopEntityFire(veh)
        SetVehicleEngineHealth(veh, math.max(GetVehicleEngineHealth(veh), 200.0))
        SetVehicleBodyHealth(veh, math.max(GetVehicleBodyHealth(veh), 200.0))
        local coords = GetEntityCoords(veh)
        for i = 1, 5 do
            StopFireInRange(coords.x, coords.y, coords.z, 6.0)
            Wait(100)
        end
    end
    ClearPedTasks(PlayerPedId())
end)

-- ============================================================
--  RESCUE VEHICLE - Insassen aus brennendem Fahrzeug ziehen
-- ============================================================
RegisterNetEvent('clp_gmenu:fire:rescueVeh', function(netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end

    if lib.progressBar({
        duration = 4000,
        label = 'Person bergen...',
        useWhileDead = false,
        canCancel = true,
        anim = { dict = 'mp_arresting', clip = 'a_uncuff' },
    }) then
        for seat = -1, 7 do
            local p = GetPedInVehicleSeat(veh, seat)
            if p ~= 0 and DoesEntityExist(p) then
                ClearPedTasksImmediately(p)
                TaskLeaveVehicle(p, veh, 0)
            end
        end
        lib.notify({ type = 'success', title = 'Feuerwehr', description = 'Person geborgen.' })
    end
    ClearPedTasks(PlayerPedId())
end)

-- ============================================================
--  RESCUE PED - Person tragen
-- ============================================================
RegisterNetEvent('clp_gmenu:fire:rescuePed', function(netId, targetSrc)
    local target = NetworkGetEntityFromNetworkId(netId)
    if not target or target == 0 then return end

    local me = PlayerPedId()
    AttachEntityToEntity(target, me, 24818, 0.27, 0.35, 0.65,
        0.0, 0.0, 0.0, false, false, false, false, 2, true)
    RequestAnimDict('missfinale_c2ig_11')
    while not HasAnimDictLoaded('missfinale_c2ig_11') do Wait(10) end
    TaskPlayAnim(me, 'missfinale_c2ig_11', 'lestercarry', 8.0, -8.0, -1, 49, 0, false, false, false)
    lib.notify({ description = 'Du traegst die Person. Erneut druecken zum Absetzen.' })
end)
