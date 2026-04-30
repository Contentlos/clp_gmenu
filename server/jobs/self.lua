--[[
    clp_gmenu - Server Job Handler: SELF-Aktionen

    Aktionen die auf den eigenen Spieler wirken (kein Target noetig).
]]

local Registry = GMenu.Registry
local Perms    = GMenu.Perms
local Store    = GMenu.Store

local function notify(src, type_, msg)
    TriggerClientEvent('ox_lib:notify', src, { type = type_, description = msg })
end

-- ============================================================
--  self_job_info - Job + Rang anzeigen
-- ============================================================
Registry.register('self_job_info', function(src, target, payload, action)
    local eff = Perms.getEffective(src)
    if not eff then return false end
    local jobDef = Store.getJob(eff.jobName)
    local jobLabel  = (jobDef and jobDef.label) or eff.jobName or 'Unbekannt'
    local rankLabel = eff.label or ('Rang ' .. (eff.grade or 0))
    local perms = {}
    if eff.permissions then
        for k, v in pairs(eff.permissions) do
            if v then perms[#perms + 1] = k end
        end
    end
    table.sort(perms)
    local permStr = #perms > 0 and table.concat(perms, ', ') or 'keine'
    notify(src, 'inform', ('Job: %s | Rang: %s\nBerechtigungen: %s'):format(jobLabel, rankLabel, permStr))
    return true
end)

-- ============================================================
--  self_gps - GPS-Position anzeigen
-- ============================================================
Registry.register('self_gps', function(src, target, payload, action)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local coords = GetEntityCoords(ped)
    notify(src, 'inform', ('GPS: X %.1f | Y %.1f | Z %.1f'):format(coords.x, coords.y, coords.z))
    return true
end)

-- ============================================================
--  self_emote - Emote abspielen (Client-Event)
-- ============================================================
Registry.register('self_emote', function(src, target, payload, action)
    local emoteId = (action and action.extra) or (payload and payload.extra) or 'wave'
    TriggerClientEvent('clp_gmenu:self:emote', src, emoteId)
    return true
end)

print('^2[clp_gmenu]^0 Self-Handler geladen.')
