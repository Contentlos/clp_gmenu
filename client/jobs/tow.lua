--[[
    clp_gmenu - Client Job: TOW
]]

local attached = nil   -- aktuelles aufgeladenes Fahrzeug

-- ============================================================
--  ATTACH - Fahrzeug auf den naechsten Tow-Truck packen
-- ============================================================
RegisterNetEvent('clp_gmenu:tow:attach', function(netId)
    local target = NetworkGetEntityFromNetworkId(netId)
    if not target or target == 0 or not DoesEntityExist(target) then return end

    -- Tow-Truck des Spielers finden (eigenes Fahrzeug oder naechstgelegenes)
    local me = PlayerPedId()
    local mePos = GetEntityCoords(me)
    local truck = GetVehiclePedIsIn(me, false)

    if truck == 0 then
        -- Naechsten Truck im Umkreis finden
        local handle, vehicle = FindFirstVehicle()
        local closestDist = 15.0
        local closest = 0
        local success = true
        repeat
            if DoesEntityExist(vehicle) then
                local model = GetEntityModel(vehicle)
                if model == GetHashKey('flatbed') or model == GetHashKey('towtruck') or model == GetHashKey('towtruck2') then
                    local d = #(GetEntityCoords(vehicle) - mePos)
                    if d < closestDist then
                        closestDist = d
                        closest = vehicle
                    end
                end
            end
            success, vehicle = FindNextVehicle(handle)
        until not success
        EndFindVehicle(handle)
        truck = closest
    end

    if truck == 0 or truck == target then
        lib.notify({ type = 'error', description = 'Kein Tow-Truck in der Naehe.' })
        return
    end

    if lib.progressBar({
        duration = 4000,
        label = 'Fahrzeug aufladen...',
        canCancel = true,
    }) then
        AttachEntityToEntity(target, truck, 20,
            0.0, -2.5, 1.0, 0.0, 0.0, 0.0,
            false, false, false, false, 20, true)
        attached = target
        lib.notify({ type = 'success', description = 'Fahrzeug aufgeladen.' })
    end
end)

-- ============================================================
--  DETACH
-- ============================================================
RegisterNetEvent('clp_gmenu:tow:detach', function(netId)
    local target = NetworkGetEntityFromNetworkId(netId) or attached
    if not target or target == 0 or not DoesEntityExist(target) then
        lib.notify({ type = 'error', description = 'Kein aufgeladenes Fahrzeug.' })
        return
    end

    if lib.progressBar({ duration = 2500, label = 'Abladen...', canCancel = true }) then
        DetachEntity(target, true, true)
        attached = nil
        lib.notify({ type = 'success', description = 'Fahrzeug abgeladen.' })
    end
end)
