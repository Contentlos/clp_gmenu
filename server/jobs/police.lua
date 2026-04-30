--[[
    clp_gmenu - Server Job Handler: POLICE
]]

local Registry = GMenu.Registry
local Perms = GMenu.Perms

-- ============================================================
--  HELPER
-- ============================================================
local function notify(src, type_, msg)
    TriggerClientEvent('ox_lib:notify', src, { type = type_, title = 'Polizei', description = msg })
end

local function ensureOxInventory()
    return GetResourceState('ox_inventory') == 'started'
end

-- ============================================================
--  pd_check_id - Ausweis pruefen
-- ============================================================
Registry.register('pd_check_id', function(src, target, payload, action)
    if not target.targetSrc then
        notify(src, 'error', 'Person hat keine ID (NPC?).')
        return false
    end
    local x = Perms.getXPlayer(target.targetSrc)
    if not x then
        notify(src, 'error', 'Person nicht gefunden.')
        return false
    end
    local name = x.getName and x.getName() or 'Unbekannt'
    local job = x.getJob and x.getJob() or { label = '-' }
    local idn = x.identifier or ''

    notify(src, 'inform', ('Name: %s\nJob: %s\nID: %s'):format(name, job.label or '-', idn))
    -- Auch dem Geprueften kurz Bescheid geben
    TriggerClientEvent('ox_lib:notify', target.targetSrc, {
        type = 'inform', title = 'Polizei', description = 'Du wurdest kontrolliert.'
    })
    return true
end)

-- ============================================================
--  pd_search - Spieler durchsuchen (ox_inventory)
-- ============================================================
Registry.register('pd_search', function(src, target, payload, action)
    if not target.targetSrc then
        notify(src, 'error', 'Kein Spieler-Ziel.')
        return false
    end
    if ensureOxInventory() then
        -- ox_inventory: forceOpenInventory(src, 'player', target_id)
        exports.ox_inventory:forceOpenInventory(src, 'player', target.targetSrc)
        TriggerClientEvent('ox_lib:notify', target.targetSrc, {
            type = 'warning', title = 'Polizei', description = 'Du wirst durchsucht.'
        })
        return true
    end
    notify(src, 'inform', 'ox_inventory nicht aktiv - Aktion uebersprungen.')
    return false
end)

-- ============================================================
--  pd_cuff - Festnehmen (Toggle)
-- ============================================================
local cuffedPlayers = {}
Registry.register('pd_cuff', function(src, target, payload, action)
    if not target.targetSrc then return false, 'no player target' end
    local isCuffed = cuffedPlayers[target.targetSrc] or false
    cuffedPlayers[target.targetSrc] = not isCuffed
    TriggerClientEvent('clp_gmenu:police:cuff', target.targetSrc, not isCuffed)
    notify(src, 'success', isCuffed and 'Handschellen entfernt.' or 'Festgenommen.')
    return true
end)

AddEventHandler('playerDropped', function()
    cuffedPlayers[source] = nil
end)

-- ============================================================
--  pd_drag - Mitnehmen (an Officer attachen)
-- ============================================================
Registry.register('pd_drag', function(src, target, payload, action)
    if not target.targetSrc then return false, 'no player target' end
    if not cuffedPlayers[target.targetSrc] then
        notify(src, 'error', 'Person muss zuerst gefesselt werden.')
        return false
    end
    TriggerClientEvent('clp_gmenu:police:drag', target.targetSrc, src)
    return true
end)

-- ============================================================
--  pd_check_plate - Kennzeichen pruefen
-- ============================================================
Registry.register('pd_check_plate', function(src, target, payload, action)
    local plate = payload.plate or 'UNKNOWN'
    notify(src, 'inform', ('Kennzeichen: %s\nHalter: (DB-Lookup nicht angebunden)'):format(plate))
    return true
end)

-- ============================================================
--  pd_search_vehicle - Fahrzeug-Trunk oeffnen
-- ============================================================
Registry.register('pd_search_vehicle', function(src, target, payload, action)
    if not target.entity or target.entity == 0 then return false end
    if ensureOxInventory() then
        local plate = payload.plate or ('VEH%s'):format(target.netId)
        exports.ox_inventory:forceOpenInventory(src, 'trunk', plate)
        return true
    end
    notify(src, 'inform', 'ox_inventory nicht aktiv.')
    return false
end)

-- ============================================================
--  pd_impound - Fahrzeug beschlagnahmen
-- ============================================================
Registry.register('pd_impound', function(src, target, payload, action)
    if not target.entity or target.entity == 0 then return false end
    -- Sicherheits-Despawn (nur wenn Server Owner)
    DeleteEntity(target.entity)
    notify(src, 'success', 'Fahrzeug beschlagnahmt.')

    -- Optional: Geld an society_police via esx_addonaccount (wenn vorhanden)
    if GetResourceState('esx_addonaccount') == 'started' then
        local society = exports['esx_addonaccount']:GetSharedAccount('society_police')
        if society and society.addMoney then
            society.addMoney(500)
        end
    end
    return true
end)

-- ============================================================
--  pd_break_lock - Schloss aufbrechen
-- ============================================================
Registry.register('pd_break_lock', function(src, target, payload, action)
    if not target.entity or target.entity == 0 then return false end
    TriggerClientEvent('clp_gmenu:police:breakLock', src, target.netId)
    return true
end)
