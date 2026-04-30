--[[
    clp_gmenu - Server Job Handler: RED CIRCLE (Spezial-Integration)

    Brueckt zu clp_redcircle:
      - Permission-Check via clp_redcircle eigenes Rang-System (callback redcircle:getMyRank)
      - Falls clp_redcircle nicht laeuft: Fallback auf eigene Rang-Permissions im Store
]]

local Registry = GMenu.Registry
local Perms = GMenu.Perms

local function notify(src, type_, msg)
    TriggerClientEvent('ox_lib:notify', src, { type = type_, title = 'Red Circle', description = msg })
end

local function rcAvailable()
    return GetResourceState('clp_redcircle') == 'started'
end

-- ============================================================
--  rc_search - Person abtasten (Security/Barkeeper/Manager+)
-- ============================================================
Registry.register('rc_search', function(src, target, payload, action)
    if not target.targetSrc then return false end
    if GetResourceState('ox_inventory') == 'started' then
        exports.ox_inventory:forceOpenInventory(src, 'player', target.targetSrc)
        return true
    end
    notify(src, 'inform', 'Inventar nicht verfuegbar.')
    return false
end)

-- ============================================================
--  rc_escort - Hinausbegleiten
-- ============================================================
Registry.register('rc_escort', function(src, target, payload, action)
    if not target.targetSrc then return false end
    TriggerClientEvent('clp_gmenu:rc:escort', target.targetSrc, src)
    notify(src, 'success', 'Person wird hinausbegleitet.')
    return true
end)

-- ============================================================
--  rc_request_ride - Limo anfordern (Chauffeur)
-- ============================================================
Registry.register('rc_request_ride', function(src, target, payload, action)
    if rcAvailable() then
        TriggerEvent('redcircle:limo:requestPickup', src, target.netId)
    else
        notify(src, 'error', 'Red Circle nicht aktiv.')
        return false
    end
    notify(src, 'success', 'Limo angefordert.')
    return true
end)

-- ============================================================
--  rc_serve_drink - Drink servieren (Barkeeper)
-- ============================================================
Registry.register('rc_serve_drink', function(src, target, payload, action)
    if not target.targetSrc then return false end
    if rcAvailable() then
        TriggerEvent('redcircle:bartender:serveExternal', src, target.targetSrc, payload.drink or 'beer')
    end
    notify(src, 'success', 'Drink serviert.')
    return true
end)

-- ============================================================
--  rc_hire - Mitarbeiter einstellen (Manager+)
-- ============================================================
Registry.register('rc_hire', function(src, target, payload, action)
    if not target.targetSrc then return false end
    if rcAvailable() then
        -- Brueckt zu clp_redcircle:management:hire (existiert in clp_redcircle/server/management.lua)
        TriggerEvent('redcircle:management:hire', src, target.targetSrc)
    else
        -- Fallback: ESX-Job direkt setzen (low-fidelity)
        local x = Perms.getXPlayer(target.targetSrc)
        if x then x.setJob('redcircle', 0) end
    end
    notify(src, 'success', 'Eingestellt.')
    return true
end)

-- ============================================================
--  rc_fire - Mitarbeiter kuendigen
-- ============================================================
Registry.register('rc_fire', function(src, target, payload, action)
    if not target.targetSrc then return false end
    if rcAvailable() then
        TriggerEvent('redcircle:management:fire', src, target.targetSrc)
    else
        local x = Perms.getXPlayer(target.targetSrc)
        if x then x.setJob('unemployed', 0) end
    end
    notify(src, 'success', 'Gekuendigt.')
    return true
end)

-- ============================================================
--  rc_promote - Befoerdern
-- ============================================================
Registry.register('rc_promote', function(src, target, payload, action)
    if not target.targetSrc then return false end
    if rcAvailable() then
        TriggerEvent('redcircle:management:promote', src, target.targetSrc, tonumber(payload.grade or 1))
    else
        local x = Perms.getXPlayer(target.targetSrc)
        if x and x.getJob then
            local job = x.getJob()
            if job.name == 'redcircle' then
                x.setJob('redcircle', math.min(6, (job.grade or 0) + 1))
            end
        end
    end
    notify(src, 'success', 'Befoerdert.')
    return true
end)

-- ============================================================
--  rc_finance - Finanz-Snapshot oeffnen
-- ============================================================
Registry.register('rc_finance', function(src, target, payload, action)
    if rcAvailable() then
        TriggerEvent('redcircle:management:openFinance', src)
    else
        notify(src, 'inform', 'Red Circle nicht aktiv.')
    end
    return true
end)
