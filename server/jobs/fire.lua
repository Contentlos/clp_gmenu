--[[
    clp_gmenu - Server Job Handler: FIRE
]]

local Registry = GMenu.Registry

local function notify(src, type_, msg)
    TriggerClientEvent('ox_lib:notify', src, { type = type_, title = 'Feuerwehr', description = msg })
end

-- ============================================================
--  fire_extinguish - Feuer am Fahrzeug loeschen
-- ============================================================
Registry.register('fire_extinguish', function(src, target, payload, action)
    if not target.entity or target.entity == 0 then return false end
    local items = GMenu.Store.getItems()
    if GetResourceState('ox_inventory') == 'started' and items.extinguisher then
        local count = exports.ox_inventory:Search(src, 'count', items.extinguisher)
        if (count or 0) < 1 then
            notify(src, 'error', 'Du brauchst einen Feuerloescher.')
            return false
        end
    end
    -- Client triggert: Stop-Fire + Animation + Health-Boost
    TriggerClientEvent('clp_gmenu:fire:extinguish', src, target.netId)
    notify(src, 'success', 'Feuer geloescht.')
    return true
end)

-- ============================================================
--  fire_rescue - Insassen aus brennendem Fahrzeug bergen
-- ============================================================
Registry.register('fire_rescue', function(src, target, payload, action)
    if not target.entity or target.entity == 0 then return false end
    TriggerClientEvent('clp_gmenu:fire:rescueVeh', src, target.netId)
    notify(src, 'success', 'Bergung gestartet.')
    return true
end)

-- ============================================================
--  fire_rescue_ped - Verletzte Person tragen
-- ============================================================
Registry.register('fire_rescue_ped', function(src, target, payload, action)
    if not target.entity or target.entity == 0 then return false end
    TriggerClientEvent('clp_gmenu:fire:rescuePed', src, target.netId, target.targetSrc)
    return true
end)

-- ============================================================
--  fire_first_aid - Erste Hilfe (kleine Heilung)
-- ============================================================
Registry.register('fire_first_aid', function(src, target, payload, action)
    if not target.entity or target.entity == 0 then return false end
    local hp = GetEntityHealth(target.entity)
    SetEntityHealth(target.entity, math.min(GetEntityMaxHealth(target.entity), hp + 50))
    notify(src, 'success', 'Erste Hilfe geleistet.')
    if target.targetSrc then
        TriggerClientEvent('ox_lib:notify', target.targetSrc, {
            type = 'success', title = 'Feuerwehr', description = 'Du erhieltst Erste Hilfe.'
        })
    end
    return true
end)
