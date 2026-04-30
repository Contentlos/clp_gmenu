--[[
    clp_gmenu - Client Job: CITIZEN
]]

-- ============================================================
--  HANDSHAKE - beidseitige Animation
-- ============================================================
RegisterNetEvent('clp_gmenu:civ:handshake', function(otherSrc)
    local me = PlayerPedId()
    RequestAnimDict('mp_ped_interaction')
    local t = GetGameTimer()
    while not HasAnimDictLoaded('mp_ped_interaction') and (GetGameTimer() - t) < 3000 do Wait(10) end

    -- Drehe zum Anderen, falls online
    local other = GetPlayerPed(GetPlayerFromServerId(otherSrc))
    if other and other ~= 0 and DoesEntityExist(other) then
        TaskTurnPedToFaceEntity(me, other, 1500)
        Wait(800)
    end

    TaskPlayAnim(me, 'mp_ped_interaction', 'handshake_guy_a', 8.0, -8.0, 3500, 0, 0, false, false, false)
end)

-- ============================================================
--  TRADE-ANFRAGE - beim Empfaenger Bestaetigung anzeigen
-- ============================================================
RegisterNetEvent('clp_gmenu:civ:tradeRequest', function(fromSrc)
    local fromName = GetPlayerName(GetPlayerFromServerId(fromSrc)) or ('#' .. fromSrc)
    local choice = lib.alertDialog({
        header  = 'Handelsanfrage',
        content = ('%s moechte mit dir handeln. Annehmen?'):format(fromName),
        centered = true,
        cancel = true,
        labels = { confirm = 'Annehmen', cancel = 'Ablehnen' },
    })
    if choice == 'confirm' then
        TriggerServerEvent('clp_gmenu:civ:tradeAccept', fromSrc)
    else
        lib.notify({ description = 'Handel abgelehnt.' })
    end
end)

-- ============================================================
--  HELP UP - bewusstlosen Spieler aufhelfen (Animation)
-- ============================================================
RegisterNetEvent('clp_gmenu:civ:helpUp', function(netId)
    local me = PlayerPedId()
    RequestAnimDict('amb@medic@standing@kneel@enter')
    local t = GetGameTimer()
    while not HasAnimDictLoaded('amb@medic@standing@kneel@enter') and (GetGameTimer() - t) < 3000 do Wait(10) end
    TaskPlayAnim(me, 'amb@medic@standing@kneel@enter', 'enter', 8.0, -8.0, 2500, 0, 0, false, false, false)
end)

-- ============================================================
--  GELD GEBEN - ox_lib Input-Dialog
-- ============================================================
RegisterNetEvent('clp_gmenu:civ:giveMoneyPrompt', function(targetSrc)
    local input = lib.inputDialog('Geld uebergeben', {
        { type = 'number', label = 'Betrag ($)', icon = 'dollar-sign', required = true, min = 1 },
    })
    if input and input[1] and tonumber(input[1]) > 0 then
        TriggerServerEvent('clp_gmenu:civ:giveMoneyConfirm', targetSrc, tonumber(input[1]))
    end
end)

-- ============================================================
--  ZEIGEN - Zeige-Animation Richtung Ziel
-- ============================================================
RegisterNetEvent('clp_gmenu:civ:point', function(netId)
    local me = PlayerPedId()
    local entity = netId and netId ~= 0 and NetworkGetEntityFromNetworkId(netId) or nil
    if entity and entity ~= 0 and DoesEntityExist(entity) then
        TaskTurnPedToFaceEntity(me, entity, 500)
        Wait(300)
    end
    lib.requestAnimDict('gestures@f@standing@casual')
    TaskPlayAnim(me, 'gestures@f@standing@casual', 'gesture_point', 8.0, -8.0, 2000, 49, 0, false, false, false)
end)

-- ============================================================
--  FAHRZEUG AB-/AUFSCHLIESSEN
-- ============================================================
RegisterNetEvent('clp_gmenu:civ:toggleLock', function(netId)
    if not netId or netId == 0 then return end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end

    local lockState = GetVehicleDoorLockStatus(veh)
    if lockState == 1 or lockState == 0 then
        SetVehicleDoorsLocked(veh, 2)
        lib.notify({ description = 'Fahrzeug abgeschlossen.', type = 'inform' })
    else
        SetVehicleDoorsLocked(veh, 1)
        lib.notify({ description = 'Fahrzeug aufgeschlossen.', type = 'inform' })
    end
    -- Sound
    PlaySoundFrontend(-1, 'CONFIRM_BEEP', 'HUD_MINI_GAME_SOUNDSET', true)
end)
