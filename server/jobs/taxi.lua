--[[
    clp_gmenu - Server Job Handler: TAXI
]]

local Registry = GMenu.Registry
local Perms = GMenu.Perms

local function notify(src, type_, msg)
    TriggerClientEvent('ox_lib:notify', src, { type = type_, title = 'Taxi', description = msg })
end

-- ============================================================
--  taxi_offer - Mitfahrgelegenheit anbieten
-- ============================================================
Registry.register('taxi_offer', function(src, target, payload, action)
    if not target.targetSrc then
        notify(src, 'error', 'Kein Spieler-Ziel.')
        return false
    end

    local fare = tonumber(payload.fare) or 50
    fare = math.max(0, math.min(5000, fare))

    -- Bestaetigung beim Ziel anfragen
    TriggerClientEvent('clp_gmenu:taxi:offer', target.targetSrc, src, fare)
    notify(src, 'inform', ('Angebot ueber $%d gesendet.'):format(fare))
    return true
end)

-- ============================================================
--  taxi_accept - vom Ziel-Client zurueck (akzeptiert)
-- ============================================================
RegisterNetEvent('clp_gmenu:taxi:accept', function(driverSrc, fare)
    local passenger = source
    if not Perms.getXPlayer(driverSrc) or not Perms.getXPlayer(passenger) then return end

    local p = Perms.getXPlayer(passenger)
    local d = Perms.getXPlayer(driverSrc)
    if not p or not d then return end

    fare = tonumber(fare) or 0
    if fare < 0 or fare > 5000 then return end

    if p.getMoney() < fare then
        TriggerClientEvent('ox_lib:notify', passenger, {
            type = 'error', title = 'Taxi', description = 'Nicht genug Bargeld.'
        })
        return
    end

    p.removeMoney(fare)
    d.addMoney(fare)
    TriggerClientEvent('ox_lib:notify', driverSrc, {
        type = 'success', title = 'Taxi', description = ('Fahrgast hat $%d bezahlt.'):format(fare)
    })
    TriggerClientEvent('ox_lib:notify', passenger, {
        type = 'success', title = 'Taxi', description = 'Fahrt bezahlt.'
    })
end)
