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

local Bridge   = GMenu.Bridge      -- server-side bridge
local Identity = GMenu.Identity
local NPCs     = GMenu.NPCs
local Zones    = GMenu.Zones
local N        = GMenu.Normalize

local VALID_TARGET_TYPES = {
    player=true, vehicle=true, ped=true, self=true, object=true, zone=true,
}

lib.callback.register('clp_gmenu:getActions', function(src, targetData)
    if type(targetData) ~= 'table' then return nil end

    local targetType = targetData.targetType
    if not VALID_TARGET_TYPES[targetType] then return nil end

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

    -- Aktions-IDs fuer diesen Zieltyp aus Job/Rang
    local actionIds
    if targetType == 'self' then
        actionIds = eff.actions and eff.actions.self or {}
    elseif targetType == 'vehicle' then
        actionIds = eff.actions and eff.actions.vehicle or {}
    elseif targetType == 'object' then
        actionIds = eff.actions and eff.actions.object or {}
    elseif targetType == 'zone' then
        actionIds = eff.actions and eff.actions.zone or {}
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

    -- Default-Actions fuer alle Spieler (egal welcher Job) zusammenfuehren.
    -- Diese werden im Store unter "defaults.<targetType>" gehalten.
    local defaults = Store.getDefaults and Store.getDefaults(targetType) or {}
    if #defaults > 0 then
        local seen = {}
        for i = 1, #actionIds do seen[actionIds[i]] = true end
        for i = 1, #defaults do
            if not seen[defaults[i]] then
                seen[defaults[i]] = true
                actionIds[#actionIds + 1] = defaults[i]
            end
        end
    end

    -- NPC-spezifische Aktionen (wenn Client npcId schickt)
    if targetType == 'ped' and targetData.npcId and NPCs and NPCs.getActionIds then
        local extra = NPCs.getActionIds(src, targetData.npcId)
        if extra and #extra > 0 then
            local seen = {}
            for i = 1, #actionIds do seen[actionIds[i]] = true end
            for i = 1, #extra do
                if not seen[extra[i]] then
                    seen[extra[i]] = true
                    actionIds[#actionIds + 1] = extra[i]
                end
            end
        end
    end

    -- Zone-spezifische Aktionen
    if targetType == 'zone' and targetData.zoneName and Zones and Zones.getActionIds then
        local extra = Zones.getActionIds(src, targetData.zoneName)
        if extra and #extra > 0 then
            local seen = {}
            for i = 1, #actionIds do seen[actionIds[i]] = true end
            for i = 1, #extra do
                if not seen[extra[i]] then
                    seen[extra[i]] = true
                    actionIds[#actionIds + 1] = extra[i]
                end
            end
        end
    end

    -- Filtern: Aktion muss existieren + Berechtigung erfuellt + Zieltyp kompatibel
    local options = {}
    local seenOptionIds = {}
    for i = 1, #actionIds do
        local id = actionIds[i]
        local action = Store.getAction(id)
        if action and not seenOptionIds[id] then
            local ok = true
            if action.permission and action.permission ~= '' then
                ok = eff.permissions and eff.permissions[action.permission] == true
            end
            -- Duty-Anforderung
            if ok and action.requiredDuty == true and Perms.isOnDuty then
                ok = Perms.isOnDuty(src) == true
            end
            -- Rang-Anforderung
            if ok and action.requiredGrade and (eff.grade or 0) < action.requiredGrade then
                ok = false
            end
            -- Zieltyp-Filter: 'player'-Aktionen passen auch auf 'ped'
            if ok and action.target and action.target ~= 'both' and action.target ~= 'any' then
                if targetType == 'ped' then
                    ok = (action.target == 'player' or action.target == 'ped')
                else
                    ok = (action.target == targetType)
                end
            end
            if ok then
                seenOptionIds[id] = true
                options[#options + 1] = {
                    id     = id,
                    label  = action.label or id,
                    icon   = action.icon  or 'fa-circle',
                    target = action.target or targetType,
                }
            end
        end
    end

    -- Bridge-Aktionen einsammeln (Server-seitig registriert)
    if Bridge then
        local bridgeList = {}
        local fromTarget = Bridge.getForTarget(targetType) or {}
        for i = 1, #fromTarget do bridgeList[#bridgeList + 1] = fromTarget[i] end
        if targetType == 'ped' and targetData.npcId then
            local fromNpc = Bridge.getForNpc(targetData.npcId) or {}
            for i = 1, #fromNpc do bridgeList[#bridgeList + 1] = fromNpc[i] end
        end
        if targetType == 'zone' and targetData.zoneName then
            local fromZone = Bridge.getForZone(targetData.zoneName) or {}
            for i = 1, #fromZone do bridgeList[#bridgeList + 1] = fromZone[i] end
        end
        if targetType == 'object' and targetData.model and targetData.model ~= 0 then
            local fromModel = Bridge.getForModel(targetData.model) or {}
            for i = 1, #fromModel do bridgeList[#bridgeList + 1] = fromModel[i] end
        end
        for i = 1, #bridgeList do
            local a = bridgeList[i]
            if a and a.id and not seenOptionIds[a.id] then
                local ok = true
                if a.requiredJob and (not eff.jobName or eff.jobName ~= a.requiredJob) then ok = false end
                if ok and a.requiredGrade and (eff.grade or 0) < a.requiredGrade then ok = false end
                if ok and a.permission and a.permission ~= '' and (not eff.permissions or eff.permissions[a.permission] ~= true) then ok = false end
                if ok then
                    seenOptionIds[a.id] = true
                    options[#options + 1] = {
                        id     = a.id,
                        label  = a.label,
                        icon   = a.icon or 'fa-circle',
                        target = a.target or targetType,
                        _bridge = true,
                    }
                end
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
    if path == '*' or root == 'jobs' or root == 'actions' or root == 'customActions'
       or root == 'defaults' or root == 'npcs' or root == 'zones' then
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
    if path == '*' or root == 'jobs' or root == 'actions' or root == 'customActions'
       or root == 'defaults' or root == 'npcs' or root == 'zones' then
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

-- ============================================================
--  UNIVERSAL FRAMEWORK EXPORTS
-- ============================================================

exports('registerAction', function(target, action)
    if not Bridge then return false end
    return Bridge.registerAction(target, action)
end)

exports('removeAction', function(actionId)
    if not Bridge then return false end
    return Bridge.removeAction(actionId)
end)

exports('registerNpcAction', function(npcId, action)
    if not Bridge then return false end
    return Bridge.registerNpcAction(npcId, action)
end)

exports('registerZoneAction', function(zoneName, action)
    if not Bridge then return false end
    return Bridge.registerZoneAction(zoneName, action)
end)

exports('registerModelAction', function(model, action)
    if not Bridge then return false end
    return Bridge.registerModelAction(model, action)
end)

exports('knowPlayer', function(src, targetSrc)
    if not Identity then return false end
    return Identity.knowPlayer(src, targetSrc)
end)

exports('getDisplayName', function(src, targetSrc)
    if not Identity then return 'Spieler' end
    return Identity.getDisplayName(src, targetSrc)
end)

exports('getAvailableActions', function(src, targetData)
    -- Synchroner Helper: einfache Wrapper um die getActions-Logik
    if type(targetData) ~= 'table' then return nil end
    local cb = lib.callback
    if cb and cb.fetch then
        -- Fuer interne Verwendung; Drittanbieter sollten lib.callback verwenden.
        return nil
    end
    return nil
end)

print('^2[clp_gmenu]^0 Server-Hauptmodul geladen.')
