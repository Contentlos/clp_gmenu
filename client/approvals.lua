--[[
    clp_gmenu - Approvals (Client)

    Empfaengt eingehende Anfrage-Aktionen und zeigt den J/N-Prompt an.
    Antwortet zurueck an den Server. Identische UX zum Handschlag-Prompt
    via GMenu.ApprovalPrompt.
]]

GMenu = GMenu or {}

RegisterNetEvent('clp_gmenu:approvals:incoming', function(payload)
    if type(payload) ~= 'table' then return end
    local token = tostring(payload.token or '')
    if token == '' then return end

    local actionLabel = payload.actionLabel or 'Aktion'
    local fromLabel   = payload.fromLabel or 'Unbekannte Person'
    local timeoutMs   = tonumber(payload.timeoutMs) or 10000

    local function answer(accepted)
        TriggerServerEvent('clp_gmenu:approvals:respond', {
            token  = token,
            accept = accepted == true,
        })
    end

    if GMenu.ApprovalPrompt and GMenu.ApprovalPrompt.show then
        GMenu.ApprovalPrompt.show({
            title     = actionLabel,
            fromLabel = fromLabel,
            body      = 'moechte folgendes mit dir machen.',
            timeoutMs = timeoutMs,
        }, answer)
    elseif lib and lib.alertDialog then
        CreateThread(function()
            local result = lib.alertDialog({
                header   = actionLabel,
                content  = ('%s moechte: %s'):format(fromLabel, actionLabel),
                centered = true,
                cancel   = true,
                labels   = { confirm = 'Annehmen', cancel = 'Ablehnen' },
            })
            answer(result == 'confirm')
        end)
    else
        -- Kein UI verfuegbar -> automatisch ablehnen
        answer(false)
    end
end)
