--[[
    clp_gmenu - Business Card Client

    Empfaengt Notifies vom Server und zeigt sie via lib.notify.
    Wird vom Identity-System getriggert: Spieler waehlt "Visitenkarte
    zeigen" im Menue, der Server uebergibt die Karte und beide werden
    benachrichtigt.
]]

RegisterNetEvent('clp_gmenu:notify', function(payload)
    if type(payload) ~= 'table' then return end
    if lib and lib.notify then
        lib.notify(payload)
    else
        local txt = payload.description or payload.title or ''
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(txt)
        EndTextCommandThefeedPostTicker(false, false)
    end
end)

-- B6: Visitenkarten-NUI Mockup statt Notify
RegisterNetEvent('clp_gmenu:businessCard:show', function(meta)
    if type(meta) ~= 'table' then return end
    SendNUIMessage({
        event = 'showBusinessCard',
        meta  = {
            firstName  = meta.firstName  or 'Unbekannt',
            lastName   = meta.lastName   or '',
            job        = meta.job        or '',
            jobLabel   = meta.jobLabel   or '',
            phone      = meta.phone      or '',
            handedAt   = meta.handedAt   or '',
            identifier = meta.identifier or '',
        },
    })
end)

RegisterNUICallback('businessCard:close', function(_, cb)
    cb(1)
end)
