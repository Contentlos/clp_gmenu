--[[
    clp_gmenu - Client Job: RED CIRCLE
]]

-- ============================================================
--  ESCORT - Hinausbegleiten (auf den Geprueften getriggert)
-- ============================================================
RegisterNetEvent('clp_gmenu:rc:escort', function(officerSrc)
    local officerName = GetPlayerName(GetPlayerFromServerId(officerSrc)) or 'Security'
    lib.notify({
        type = 'warning',
        title = 'Red Circle',
        description = ('Du wirst von %s hinausbegleitet.'):format(officerName),
    })

    -- Optionaler Marker auf dem Eingang setzen (Red Circle Coords aus clp_redcircle)
    SetNewWaypoint(-823.338, -693.908)
end)
