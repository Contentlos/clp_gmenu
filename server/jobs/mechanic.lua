--[[
    clp_gmenu - Server Job Handler: MECHANIC
]]

local Registry = GMenu.Registry

local function notify(src, type_, msg)
    TriggerClientEvent('ox_lib:notify', src, { type = type_, title = 'Mechaniker', description = msg })
end

local function consumeItem(src, key)
    local items = GMenu.Store.getItems()
    local item = items[key]
    if not item or GetResourceState('ox_inventory') ~= 'started' then return true end
    local count = exports.ox_inventory:Search(src, 'count', item)
    if (count or 0) < 1 then return false end
    exports.ox_inventory:RemoveItem(src, item, 1)
    return true
end

-- ============================================================
--  mech_repair_light - kleine Reparatur (50% HP)
-- ============================================================
Registry.register('mech_repair_light', function(src, target, payload, action)
    if not target.entity or target.entity == 0 then return false end
    if not consumeItem(src, 'repairkit') then
        notify(src, 'error', 'Du brauchst ein Repair-Kit.')
        return false
    end
    TriggerClientEvent('clp_gmenu:mech:repair', src, target.netId, 600.0, 600.0)
    notify(src, 'success', 'Leichte Reparatur abgeschlossen.')
    return true
end)

-- ============================================================
--  mech_repair - volle Reparatur
-- ============================================================
Registry.register('mech_repair', function(src, target, payload, action)
    if not target.entity or target.entity == 0 then return false end
    if not consumeItem(src, 'repairkit') then
        notify(src, 'error', 'Du brauchst ein Repair-Kit.')
        return false
    end
    TriggerClientEvent('clp_gmenu:mech:repair', src, target.netId, 1000.0, 1000.0)
    notify(src, 'success', 'Fahrzeug komplett repariert.')
    return true
end)

-- ============================================================
--  mech_tires - Reifen flicken
-- ============================================================
Registry.register('mech_tires', function(src, target, payload, action)
    if not target.entity or target.entity == 0 then return false end
    if not consumeItem(src, 'tirekit') then
        notify(src, 'error', 'Du brauchst ein Tire-Kit.')
        return false
    end
    TriggerClientEvent('clp_gmenu:mech:tires', src, target.netId)
    notify(src, 'success', 'Reifen geflickt.')
    return true
end)

-- ============================================================
--  mech_tune - Tuning-Menue oeffnen
-- ============================================================
Registry.register('mech_tune', function(src, target, payload, action)
    if not target.entity or target.entity == 0 then return false end
    -- Generische Bridge: Client soll bestehende Tuning-Resource oeffnen.
    TriggerClientEvent('clp_gmenu:mech:tune', src, target.netId)
    return true
end)

-- ============================================================
--  mech_refuel - Tanken
-- ============================================================
Registry.register('mech_refuel', function(src, target, payload, action)
    if not target.entity or target.entity == 0 then return false end
    TriggerClientEvent('clp_gmenu:mech:refuel', src, target.netId)
    notify(src, 'success', 'Fahrzeug getankt.')
    return true
end)
