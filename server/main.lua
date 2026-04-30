--[[
    clp_gmenu - Server-Hauptmodul

    Aufgaben:
      - Snapshot-Callback fuer Clients (Erstsynchronisierung)
      - Aktions-Trigger per NetEvent
      - Store-Abonnement -> Synchronisierung an alle Clients
      - Job-Cache-Callback (Berechtigungen des Spielers -> ans Client-Menue)
]]

local Store = GMenu.Store
local Perms = GMenu.Perms
local Registry = GMenu.Registry
local U = GMenu.Util

-- ============================================================
--  CALLBACK: Snapshot fuer Clients (Erstsynchronisierung)
-- ============================================================

lib.callback.register('clp_gmenu:store:snapshot', function(src)
    return Store.getSnapshot()
end)

-- ============================================================
--  CALLBACK: Effektive Berechtigungen / Aktionen des Spielers
-- ============================================================

lib.callback.register('clp_gmenu:store:myPermissions', function(src)
    local eff = Perms.getEffective(src)
    -- Job-Definition fuer Label/Icon/Farbe
    local jobDef = Store.getJob(eff.jobName)
    return {
        jobName    = eff.jobName,
        jobLabel   = (jobDef and jobDef.label) or eff.jobName,
        jobIcon    = (jobDef and jobDef.icon)  or 'fa-user',
        jobColor   = (jobDef and jobDef.color) or '#9CA3AF',
        grade      = eff.grade,
        rankLabel  = eff.label or '',
        permissions= eff.permissions or {},
        actions    = eff.actions or { player = {}, vehicle = {}, ped = {}, self = {} },
    }
end)

-- ============================================================
--  CALLBACK: Servergesteuerte Aktions-Aufloesung
--  Client sendet nur netId + targetType, Server entscheidet alles.
-- ============================================================

lib.callback.register('clp_gmenu:getActions', function(src, targetData)
    if type(targetData) ~= 'table' then return nil end

    local targetType = targetData.targetType
    if targetType ~= 'player' and targetType ~= 'vehicle' and targetType ~= 'ped' and targetType ~= 'self' then return nil end

    -- Distanz-Pruefung fuer NPCs ohne netId (Fallback ueber pedCoords)
    if targetType == 'ped' and (not targetData.netId or targetData.netId == 0) then
        if targetData.pedCoords then
            local srcPed = GetPlayerPed(src)
            if srcPed and srcPed ~= 0 then
                local a = GetEntityCoords(srcPed)
                local pc = targetData.pedCoords
                local dx, dy, dz = a.x - (pc.x or 0), a.y - (pc.y or 0), a.z - (pc.z or 0)
                local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
                if dist > (Config.MaxDistanceServer or 12.0) then return nil end
            end
        end
    end

    local eff = Perms.getEffective(src)
    if not eff then return nil end

    -- Aktions-IDs fuer diesen Zieltyp
    local actionIds
    if targetType == 'self' then
        actionIds = eff.actions and eff.actions.self or {}
    elseif targetType == 'vehicle' then
        actionIds = eff.actions and eff.actions.vehicle or {}
    elseif targetType == 'ped' then
        -- Eigene ped-Aktionsliste hat Vorrang, sonst player-Aktionen
        local pedActions = eff.actions and eff.actions.ped
        local playerActions = eff.actions and eff.actions.player or {}
        if pedActions and #pedActions > 0 then
            -- ped-eigene + player-Aktionen zusammenfuehren (ohne Duplikate)
            local seen = {}
            actionIds = {}
            for _, list in ipairs({ pedActions, playerActions }) do
                for i = 1, #list do
                    if not seen[list[i]] then
                        seen[list[i]] = true
                        actionIds[#actionIds + 1] = list[i]
                    end
                end
            end
        else
            actionIds = playerActions
        end
    else
        actionIds = eff.actions and eff.actions.player or {}
    end

    -- Filtern: Aktion muss existieren + Berechtigung erfuellt + Zieltyp kompatibel
    local options = {}
    for i = 1, #actionIds do
        local id = actionIds[i]
        local action = Store.getAction(id)
        if action then
            local ok = true
            if action.permission and action.permission ~= '' then
                ok = eff.permissions and eff.permissions[action.permission] == true
            end
            -- Zieltyp-Filter: 'player'-Aktionen passen auch auf 'ped'
            if ok and action.target and action.target ~= 'both' then
                if targetType == 'ped' then
                    ok = (action.target == 'player' or action.target == 'ped')
                else
                    ok = (action.target == targetType)
                end
            end
            if ok then
                options[#options + 1] = {
                    id     = id,
                    label  = action.label or id,
                    icon   = action.icon  or 'fa-circle',
                    target = action.target or targetType,
                }
            end
        end
    end

    -- Job-Info mit zurueckgeben + Cache-Version fuer Client-seitiges Caching
    local jobDef = Store.getJob(eff.jobName)
    return {
        options  = options,
        job      = {
            name      = eff.jobName,
            label     = (jobDef and jobDef.label) or eff.jobName,
            icon      = (jobDef and jobDef.icon)  or 'fa-user',
            grade     = eff.grade,
            rankLabel = eff.label or '',
        },
        _cacheKey = eff.jobName .. ':' .. tostring(eff.grade) .. ':' .. targetType,
        _storeVer = Store.getVersion and Store.getVersion() or 0,
    }
end)

-- ============================================================
--  AKTIONS-TRIGGER (vom Client)
-- ============================================================

RegisterNetEvent('clp_gmenu:executeAction', function(payload)
    local src = source
    local ok, err = Registry.execute(src, payload)
    if not ok then
        if Config.Debug then
            print(('^3[clp_gmenu]^0 Aktion abgelehnt (src=%d, aktion=%s): %s'):format(
                src, tostring(payload and payload.actionId), tostring(err)
            ))
        end
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'error',
            description = 'Aktion nicht erlaubt' .. (Config.Debug and (': ' .. tostring(err)) or '')
        })
    end
end)

-- ============================================================
--  STORE-ABONNEMENT -> Synchronisierung an alle
-- ============================================================

Store.subscribe(function(path, value, by, version)
    -- Berechtigungs-Cache leeren wenn Jobs/Aktionen/CustomActions sich aendern
    local root = (path or ''):match('^([^.]+)') or ''
    if path == '*' or root == 'jobs' or root == 'actions' or root == 'customActions' then
        Perms.invalidateAllCaches()
    end

    -- An alle Clients senden (kompletter Snapshot bei Wildcard, sonst Patch)
    if path == '*' then
        TriggerClientEvent('clp_gmenu:store:snapshot', -1, Store.getSnapshot())
    else
        TriggerClientEvent('clp_gmenu:store:patch', -1, {
            version = version,
            path    = path,
            value   = value,
        })
    end

    -- Expliziter Cache-Invalidierungs-Broadcast bei relevanten Aenderungen
    -- (Clients leeren ihren Action-Cache sofort, nicht erst nach 3min TTL)
    if path == '*' or root == 'jobs' or root == 'actions' or root == 'customActions' then
        TriggerClientEvent('clp_gmenu:cache:invalidate', -1)
    end
end)

-- ============================================================
--  SPIELER-VERBINDUNG: SNAPSHOT SENDEN
-- ============================================================

AddEventHandler('esx:playerLoaded', function(src)
    -- Kleines Delay damit die Client-Listener bereit sind
    SetTimeout(2000, function()
        if not GetPlayerName(tostring(src)) then return end
        TriggerClientEvent('clp_gmenu:store:snapshot', src, Store.getSnapshot())
    end)
end)

-- Fallback fuer playerJoining (manche Server haben kein esx:playerLoaded)
AddEventHandler('playerJoining', function()
    local src = source
    SetTimeout(5000, function()
        if not GetPlayerName(tostring(src)) then return end
        TriggerClientEvent('clp_gmenu:store:snapshot', src, Store.getSnapshot())
    end)
end)

-- ============================================================
--  ESX:setJob -> Berechtigungs-Cache leeren + Client aktualisieren
-- ============================================================

AddEventHandler('esx:setJob', function(src, job, lastJob)
    if not job then return end
    Perms.invalidateCache(src)
    TriggerClientEvent('clp_gmenu:job:refresh', src)
end)

-- ============================================================
--  EXPORTS (fuer andere Ressourcen)
-- ============================================================

exports('hasPermission', function(src, permKey)
    return Perms.hasPermission(src, permKey)
end)

exports('hasAction', function(src, actionId, target)
    return Perms.hasAction(src, actionId, target)
end)

exports('isAdmin', function(src)
    return Perms.isAdmin(src)
end)

exports('getStoreSnapshot', function()
    return Store.getSnapshot()
end)

print('^2[clp_gmenu]^0 Server-Hauptmodul geladen.')
