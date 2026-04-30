--[[
    clp_gmenu - Client Job: TAXI
]]

-- ============================================================
--  Taxi-Angebot beim Fahrgast bestaetigen
-- ============================================================
RegisterNetEvent('clp_gmenu:taxi:offer', function(driverSrc, fare)
    local driverName = GetPlayerName(GetPlayerFromServerId(driverSrc)) or ('#' .. driverSrc)

    local choice = lib.alertDialog({
        header  = 'Taxi-Angebot',
        content = ('%s bietet eine Fahrt fuer **$%d** an. Annehmen?'):format(driverName, fare),
        centered = true,
        cancel = true,
        labels = { confirm = 'Annehmen', cancel = 'Ablehnen' },
    })

    if choice == 'confirm' then
        TriggerServerEvent('clp_gmenu:taxi:accept', driverSrc, fare)
        lib.notify({ type = 'success', description = 'Angebot angenommen.' })
    else
        lib.notify({ description = 'Angebot abgelehnt.' })
    end
end)
