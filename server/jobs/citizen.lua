--[[
    clp_gmenu - Server Job Handler: CITIZEN (Fallback fuer alle)
]]

local Registry = GMenu.Registry

local function notify(src, type_, msg)
    TriggerClientEvent('ox_lib:notify', src, { type = type_, description = msg })
end

-- ============================================================
--  civ_handshake - Hand schuetteln (beidseitig)
-- ============================================================
Registry.register('civ_handshake', function(src, target, payload, action)
    if not target.targetSrc then return false end
    TriggerClientEvent('clp_gmenu:civ:handshake', src,             target.targetSrc)
    TriggerClientEvent('clp_gmenu:civ:handshake', target.targetSrc, src)
    return true
end)

-- ============================================================
--  civ_trade - Handel (ox_inventory shop-modus oder native)
-- ============================================================
Registry.register('civ_trade', function(src, target, payload, action)
    if not target.targetSrc then return false end
    TriggerClientEvent('clp_gmenu:civ:tradeRequest', target.targetSrc, src)
    notify(src, 'inform', 'Handelsanfrage gesendet.')
    return true
end)

RegisterNetEvent('clp_gmenu:civ:tradeAccept', function(otherSrc)
    local src = source
    if GetResourceState('ox_inventory') == 'started' then
        -- Kein generisches "trade", aber wir koennen beiden gegenseitig den Player-Inv anzeigen
        exports.ox_inventory:forceOpenInventory(src,      'player', otherSrc)
        exports.ox_inventory:forceOpenInventory(otherSrc, 'player', src)
    else
        TriggerClientEvent('ox_lib:notify', src,      { type = 'inform', description = 'Handel gestartet.' })
        TriggerClientEvent('ox_lib:notify', otherSrc, { type = 'inform', description = 'Handel gestartet.' })
    end
end)

-- ============================================================
--  civ_help_up - Aufhelfen
-- ============================================================
Registry.register('civ_help_up', function(src, target, payload, action)
    if not target.entity or target.entity == 0 then return false end
    TriggerClientEvent('clp_gmenu:civ:helpUp', src, target.netId)
    if target.targetSrc then
        TriggerClientEvent('clp_gmenu:civ:helpUp', target.targetSrc, target.netId)
    end
    return true
end)

-- ============================================================
--  civ_check_plate - Kennzeichen ablesen (jeder darf das)
-- ============================================================
Registry.register('civ_check_plate', function(src, target, payload, action)
    local plate = payload.plate or 'UNKNOWN'
    notify(src, 'inform', ('Kennzeichen: %s'):format(plate))
    return true
end)

-- ============================================================
--  civ_give_money - Geld uebergeben (ox_lib Input)
-- ============================================================
Registry.register('civ_give_money', function(src, target, payload, action)
    if not target.targetSrc then return false end
    TriggerClientEvent('clp_gmenu:civ:giveMoneyPrompt', src, target.targetSrc)
    return true
end)

RegisterNetEvent('clp_gmenu:civ:giveMoneyConfirm', function(targetSrc, amount)
    local src = source
    amount = tonumber(amount) or 0
    if amount <= 0 then return end

    local ESX = exports['es_extended']:getSharedObject()
    local xPlayer = ESX.GetPlayerFromId(src)
    local xTarget = ESX.GetPlayerFromId(targetSrc)
    if not xPlayer or not xTarget then return end
    if xPlayer.getMoney() < amount then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Nicht genug Geld.' })
        return
    end
    xPlayer.removeMoney(amount)
    xTarget.addMoney(amount)
    TriggerClientEvent('ox_lib:notify', src,       { type = 'success', description = ('$%s uebergeben.'):format(amount) })
    TriggerClientEvent('ox_lib:notify', targetSrc, { type = 'success', description = ('$%s erhalten.'):format(amount) })
end)

-- ============================================================
--  civ_point - Auf Ziel zeigen (Anim)
-- ============================================================
Registry.register('civ_point', function(src, target, payload, action)
    TriggerClientEvent('clp_gmenu:civ:point', src, target.netId)
    return true
end)

-- ============================================================
--  civ_lock_vehicle - Fahrzeug ab-/aufschliessen (eigenes Fahrzeug)
-- ============================================================
Registry.register('civ_lock_vehicle', function(src, target, payload, action)
    if not target.entity or target.entity == 0 then return false end
    TriggerClientEvent('clp_gmenu:civ:toggleLock', src, target.netId)
    return true
end)
