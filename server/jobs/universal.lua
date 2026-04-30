--[[
    clp_gmenu - Universal / Default Actions (Server)

    Implementiert die Standard-Aktionen, die jeder Spieler hat:
      - Hand geben (handshake -> Identity-System)
      - Begruessen / Aufhelfen / Anschauen / Visitenkarte
      - Fahrzeug Motor/Schloss/Tueren/Kofferraum/Motorhaube/Inspektion
      - NPC Reden / Anschauen
      - Objekt Untersuchen / Benutzen / Aufheben
]]

local Registry = GMenu.Registry
local Identity = GMenu.Identity

-- ============================================================
--  PLAYER ACTIONS
-- ============================================================

Registry.register('universal_handshake', function(src, target, payload, action)
    if not target.isPlayer or not target.targetSrc then return false, 'no_target' end
    if not Identity then return false, 'no_identity' end
    Identity.requestHandshake(src, target.targetSrc)
    return true
end)

Registry.register('universal_greet', function(src, target, payload, action)
    if not target.targetSrc then return false, 'no_target' end
    TriggerClientEvent('clp_gmenu:emote', src, 'wave')
    return true
end)

Registry.register('universal_help_up', function(src, target, payload, action)
    if not target.targetSrc then return false, 'no_target' end
    -- Custom event that other resources can hook
    TriggerEvent('clp_gmenu:helpUp', src, target.targetSrc)
    TriggerClientEvent('clp_gmenu:emote', src, 'help_up')
    return true
end)

Registry.register('universal_look_at', function(src, target, payload, action)
    local label = 'Unbekannt'
    if target.isPlayer and target.targetSrc and Identity then
        label = Identity.getDisplayName(src, target.targetSrc)
    elseif target.type == 'ped' then
        label = 'NPC'
    end
    TriggerClientEvent('ox_lib:notify', src, {
        type = 'inform',
        title = 'Du siehst:',
        description = label,
    })
    return true
end)

Registry.register('universal_card', function(src, target, payload, action)
    if not target.isPlayer or not target.targetSrc then return false, 'no_target' end
    -- Visiting card == handshake equivalent (mutual recognition)
    if Identity then
        Identity.knowPlayer(src, target.targetSrc)
    end
    TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = 'Visitenkarte uebergeben.' })
    return true
end)

-- ============================================================
--  VEHICLE ACTIONS
-- ============================================================

Registry.register('universal_engine', function(src, target)
    if target.type ~= 'vehicle' or target.entity == 0 then return false end
    TriggerClientEvent('clp_gmenu:vehicle:toggleEngine', src, NetworkGetNetworkIdFromEntity(target.entity))
    return true
end)

Registry.register('universal_lock', function(src, target)
    if target.type ~= 'vehicle' or target.entity == 0 then return false end
    TriggerClientEvent('clp_gmenu:vehicle:toggleLock', src, NetworkGetNetworkIdFromEntity(target.entity))
    return true
end)

Registry.register('universal_doors', function(src, target)
    if target.type ~= 'vehicle' or target.entity == 0 then return false end
    TriggerClientEvent('clp_gmenu:vehicle:toggleDoors', src, NetworkGetNetworkIdFromEntity(target.entity))
    return true
end)

Registry.register('universal_trunk', function(src, target)
    if target.type ~= 'vehicle' or target.entity == 0 then return false end
    TriggerClientEvent('clp_gmenu:vehicle:toggleTrunk', src, NetworkGetNetworkIdFromEntity(target.entity))
    return true
end)

Registry.register('universal_hood', function(src, target)
    if target.type ~= 'vehicle' or target.entity == 0 then return false end
    TriggerClientEvent('clp_gmenu:vehicle:toggleHood', src, NetworkGetNetworkIdFromEntity(target.entity))
    return true
end)

Registry.register('universal_inspect_veh', function(src, target)
    if target.type ~= 'vehicle' or target.entity == 0 then return false end
    local plate = (GetVehicleNumberPlateText(target.entity) or ''):gsub('%s+$', '')
    local model = GetEntityModel(target.entity)
    TriggerClientEvent('ox_lib:notify', src, {
        type = 'inform',
        title = 'Fahrzeug',
        description = ('Plate: %s\nModel: %d'):format(plate, model),
    })
    return true
end)

-- ============================================================
--  NPC ACTIONS
-- ============================================================

Registry.register('universal_npc_talk', function(src, target)
    if target.type ~= 'ped' then return false end
    TriggerClientEvent('ox_lib:notify', src, {
        type = 'inform', title = 'NPC',
        description = '...',
    })
    return true
end)

-- ============================================================
--  OBJECT ACTIONS
-- ============================================================

Registry.register('universal_obj_inspect', function(src, target)
    if target.type ~= 'object' then return false end
    TriggerClientEvent('ox_lib:notify', src, {
        type = 'inform', title = 'Untersuchen',
        description = ('Modell-Hash: %s'):format(tostring(target.model or '?')),
    })
    return true
end)

Registry.register('universal_obj_use', function(src, target)
    if target.type ~= 'object' then return false end
    TriggerEvent('clp_gmenu:object:use', src, target)
    return true
end)

Registry.register('universal_obj_pickup', function(src, target)
    if target.type ~= 'object' then return false end
    TriggerEvent('clp_gmenu:object:pickup', src, target)
    return true
end)

-- ============================================================
--  ZONE ACTIONS
-- ============================================================

Registry.register('universal_zone_open', function(src, target, payload, action)
    if target.type ~= 'zone' then return false end
    TriggerEvent('clp_gmenu:zone:open', src, target)
    return true
end)

print('^2[clp_gmenu]^0 Universal action handlers loaded.')
