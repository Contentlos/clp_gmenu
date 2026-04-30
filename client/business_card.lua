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
