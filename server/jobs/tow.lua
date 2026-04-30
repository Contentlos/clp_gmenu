--[[
    clp_gmenu - Server Job Handler: TOW
]]

local Registry = GMenu.Registry

local function notify(src, type_, msg)
    TriggerClientEvent('ox_lib:notify', src, { type = type_, title = 'Abschleppdienst', description = msg })
end

-- ============================================================
--  tow_attach - Fahrzeug aufladen
-- ============================================================
Registry.register('tow_attach', function(src, target, payload, action)
    if not target.entity or target.entity == 0 then return false end
    -- Logik laeuft auf dem Client (AttachEntityToEntity), Server triggert nur.
    TriggerClientEvent('clp_gmenu:tow:attach', src, target.netId)
    return true
end)

-- ============================================================
--  tow_detach - Fahrzeug abladen
-- ============================================================
Registry.register('tow_detach', function(src, target, payload, action)
    if not target.entity or target.entity == 0 then return false end
    TriggerClientEvent('clp_gmenu:tow:detach', src, target.netId)
    return true
end)
