--[[
    clp_gmenu - Server Job Handler: AMBULANCE
]]

local Registry = GMenu.Registry
local Perms = GMenu.Perms

local function notify(src, type_, msg)
    TriggerClientEvent('ox_lib:notify', src, { type = type_, title = 'Rettungsdienst', description = msg })
end

-- ============================================================
--  ems_vitals - Vitalwerte pruefen
-- ============================================================
Registry.register('ems_vitals', function(src, target, payload, action)
    if not target.entity or target.entity == 0 then return false end
    local ped = target.entity
    local hp  = GetEntityHealth(ped) - 100
    local maxHp = GetEntityMaxHealth(ped) - 100
    local dead = IsPedDeadOrDying(ped, true) or IsEntityDead(ped)
    notify(src, 'inform', ('HP: %d/%d\nStatus: %s'):format(
        math.max(0, hp), maxHp, dead and 'KRITISCH' or 'stabil'
    ))
    return true
end)

-- ============================================================
--  ems_heal - Behandeln
-- ============================================================
Registry.register('ems_heal', function(src, target, payload, action)
    if not target.entity or target.entity == 0 then return false end

    -- Optional: Item-Verbrauch (bandage)
    local items = GMenu.Store.getItems()
    if GetResourceState('ox_inventory') == 'started' and items.bandage then
        local count = exports.ox_inventory:Search(src, 'count', items.bandage)
        if (count or 0) < 1 then
            notify(src, 'error', 'Du brauchst einen Verband.')
            return false
        end
        exports.ox_inventory:RemoveItem(src, items.bandage, 1)
    end

    SetEntityHealth(target.entity, GetEntityMaxHealth(target.entity))
    notify(src, 'success', 'Person behandelt.')
    if target.targetSrc then
        TriggerClientEvent('ox_lib:notify', target.targetSrc, {
            type = 'success', title = 'Rettungsdienst', description = 'Du wurdest behandelt.'
        })
    end
    return true
end)

-- ============================================================
--  ems_revive - Wiederbeleben
-- ============================================================
Registry.register('ems_revive', function(src, target, payload, action)
    if not target.targetSrc then
        notify(src, 'error', 'Nur Spieler koennen wiederbelebt werden.')
        return false
    end

    -- Wenn esx_ambulancejob da ist: dessen Event triggern (kompatibel)
    if GetResourceState('esx_ambulancejob') == 'started' then
        TriggerClientEvent('esx_ambulancejob:revive', target.targetSrc)
    else
        -- Native-Fallback
        TriggerClientEvent('clp_gmenu:ems:revive', target.targetSrc)
    end

    -- Optional: medikit verbrauchen
    local items = GMenu.Store.getItems()
    if GetResourceState('ox_inventory') == 'started' and items.medikit then
        local count = exports.ox_inventory:Search(src, 'count', items.medikit)
        if (count or 0) >= 1 then
            exports.ox_inventory:RemoveItem(src, items.medikit, 1)
        end
    end

    notify(src, 'success', 'Spieler wiederbelebt.')
    return true
end)

-- ============================================================
--  ems_transport - Transport-Marker an Krankenhaus senden
-- ============================================================
Registry.register('ems_transport', function(src, target, payload, action)
    if not target.targetSrc then return false end
    TriggerClientEvent('clp_gmenu:ems:transport', target.targetSrc)
    notify(src, 'success', 'Transport eingeleitet.')
    return true
end)
