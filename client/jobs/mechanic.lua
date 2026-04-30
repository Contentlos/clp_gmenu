--[[
    clp_gmenu - Client Job: MECHANIC
]]

-- ============================================================
--  REPAIR (light & full)
-- ============================================================
RegisterNetEvent('clp_gmenu:mech:repair', function(netId, engineHp, bodyHp)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end

    if lib.progressBar({
        duration = 6000,
        label = 'Fahrzeug reparieren...',
        useWhileDead = false,
        canCancel = true,
        anim = { dict = 'mini@repair', clip = 'fixing_a_player' },
    }) then
        SetVehicleEngineHealth(veh, engineHp or 1000.0)
        SetVehicleBodyHealth(veh, bodyHp or 1000.0)
        SetVehicleFixed(veh)
        SetVehicleDeformationFixed(veh)
        SetVehicleUndriveable(veh, false)
        SetVehicleEngineOn(veh, true, true, false)
    end
    ClearPedTasks(PlayerPedId())
end)

-- ============================================================
--  TIRES - alle platten Reifen flicken
-- ============================================================
RegisterNetEvent('clp_gmenu:mech:tires', function(netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end

    if lib.progressBar({
        duration = 4000,
        label = 'Reifen flicken...',
        useWhileDead = false,
        canCancel = true,
        anim = { dict = 'mini@repair', clip = 'fixing_a_ped' },
    }) then
        for i = 0, 7 do
            SetVehicleTyreFixed(veh, i)
        end
    end
    ClearPedTasks(PlayerPedId())
end)

-- ============================================================
--  TUNE - Tuning oeffnen (bridges to common tuning resources)
-- ============================================================
RegisterNetEvent('clp_gmenu:mech:tune', function(netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end

    -- Versuche bekannte Tuning-Resources der Reihe nach
    if GetResourceState('lscustoms') == 'started' then
        TriggerEvent('lscustoms:openMenu', veh)
    elseif GetResourceState('esx_vehicleshop') == 'started' then
        TriggerEvent('esx_vehicleshop:openShopMenu')
    else
        -- Fallback: Native-Modshop
        local model = GetEntityModel(veh)
        SetVehicleModKit(veh, 0)
        lib.notify({ description = 'Kein Tuning-System aktiv. Modkit auf 0 gesetzt.' })
    end
end)

-- ============================================================
--  REFUEL - 100% tanken
-- ============================================================
RegisterNetEvent('clp_gmenu:mech:refuel', function(netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end

    if lib.progressBar({
        duration = 3000,
        label = 'Auftanken...',
        useWhileDead = false,
        canCancel = true,
    }) then
        -- Probier verschiedene Fuel-Resources
        if GetResourceState('LegacyFuel') == 'started' then
            exports['LegacyFuel']:SetFuel(veh, 100.0)
        elseif GetResourceState('ox_fuel') == 'started' then
            Entity(veh).state.fuel = 100.0
        else
            SetVehicleFuelLevel(veh, 100.0)
            DecorSetFloat(veh, 'Fuel', 100.0)
        end
    end
    ClearPedTasks(PlayerPedId())
end)
