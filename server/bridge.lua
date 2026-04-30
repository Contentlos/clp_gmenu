--[[
    clp_gmenu - Bridge (Server)

    Server-seitige Bridge-Registry.
    Andere Resourcen koennen Aktionen registrieren, die im Menue auftauchen,
    ohne dass clp_gmenu sie kennt:

      exports.clp_gmenu:registerBridgeAction('vehicle', { id=..., label=..., serverEvent=... })
      exports.clp_gmenu:registerAction({ ... })       -- alias
      exports.clp_gmenu:removeBridgeAction(id)
      exports.clp_gmenu:registerNpcAction(npcId, { ... })
      exports.clp_gmenu:registerZoneAction(zoneName, { ... })

    Bridge-Aktionen werden bei jedem getActions-Aufruf nach den
    regulaeren Aktionen gemerged (per Action-Normalizer).
]]

GMenu = GMenu or {}
GMenu.Bridge = GMenu.Bridge or {}
local Bridge = GMenu.Bridge

local N = GMenu.Normalize
local Perms = GMenu.Perms

-- ============================================================
--  REGISTRIES
-- ============================================================

--  byTarget[target][id] = action
Bridge.byTarget = {
    player  = {},
    ped     = {},
    vehicle = {},
    object  = {},
    zone    = {},
    self    = {},
    any     = {},
}

--  byNpc[npcId][id] = action
Bridge.byNpc = {}

--  byZone[zoneName][id] = action
Bridge.byZone = {}

--  byModel[modelHash][id] = action  (Object-Modelle)
Bridge.byModel = {}

local function ensureTargetTable(target)
    if not target then return Bridge.byTarget.any end
    Bridge.byTarget[target] = Bridge.byTarget[target] or {}
    return Bridge.byTarget[target]
end

-- ============================================================
--  REGISTER / REMOVE
-- ============================================================

function Bridge.registerAction(target, action)
    local norm = N.fromOxTarget(action, target) or N.fromStandard(action)
    if not norm or not norm.id then return false, 'invalid_action' end
    norm.source = norm.source or 'ox_bridge'
    norm.target = norm.target or target or 'any'
    ensureTargetTable(norm.target)[norm.id] = norm
    return true, norm.id
end

function Bridge.removeAction(id)
    if not id then return false end
    for _, list in pairs(Bridge.byTarget) do
        if list[id] then list[id] = nil end
    end
    return true
end

function Bridge.registerNpcAction(npcId, action)
    if not npcId then return false, 'invalid_npc' end
    local norm = N.fromOxTarget(action, 'ped') or N.fromStandard(action)
    if not norm or not norm.id then return false end
    Bridge.byNpc[npcId] = Bridge.byNpc[npcId] or {}
    Bridge.byNpc[npcId][norm.id] = norm
    return true, norm.id
end

function Bridge.registerZoneAction(zoneName, action)
    if not zoneName then return false, 'invalid_zone' end
    local norm = N.fromOxTarget(action, 'zone') or N.fromStandard(action)
    if not norm or not norm.id then return false end
    Bridge.byZone[zoneName] = Bridge.byZone[zoneName] or {}
    Bridge.byZone[zoneName][norm.id] = norm
    return true, norm.id
end

function Bridge.registerModelAction(model, action)
    if not model then return false, 'invalid_model' end
    local hash = type(model) == 'string' and joaat(model) or model
    local norm = N.fromOxTarget(action, 'object') or N.fromStandard(action)
    if not norm or not norm.id then return false end
    Bridge.byModel[hash] = Bridge.byModel[hash] or {}
    Bridge.byModel[hash][norm.id] = norm
    return true, norm.id
end

-- ============================================================
--  GET ACTIONS for a target type / npc / zone / model
-- ============================================================

local function listValues(t)
    local out = {}
    if type(t) ~= 'table' then return out end
    for _, v in pairs(t) do out[#out + 1] = v end
    return out
end

function Bridge.getForTarget(target)
    local list = listValues(Bridge.byTarget[target] or {})
    -- 'any' applies to all
    for _, v in pairs(Bridge.byTarget.any or {}) do list[#list + 1] = v end
    return list
end

function Bridge.getForNpc(npcId)
    return listValues(Bridge.byNpc[npcId] or {})
end

function Bridge.getForZone(zoneName)
    return listValues(Bridge.byZone[zoneName] or {})
end

function Bridge.getForModel(model)
    if not model then return {} end
    local hash = type(model) == 'string' and joaat(model) or model
    return listValues(Bridge.byModel[hash] or {})
end

-- ============================================================
--  FIND ACTION BY ID (across all bridge tables) -- used by Registry.execute
-- ============================================================

--- Sucht eine Bridge-Aktion nach ID. Optional ctx mit npcId/zoneName/model
--- um die Suche einzugrenzen (sonst wird ueber alle Tabellen gesucht).
function Bridge.findAction(id, ctx)
    if not id then return nil end
    ctx = ctx or {}

    -- ctx-spezifische zuerst
    if ctx.npcId and Bridge.byNpc[ctx.npcId] and Bridge.byNpc[ctx.npcId][id] then
        return Bridge.byNpc[ctx.npcId][id]
    end
    if ctx.zoneName and Bridge.byZone[ctx.zoneName] and Bridge.byZone[ctx.zoneName][id] then
        return Bridge.byZone[ctx.zoneName][id]
    end
    if ctx.model and ctx.model ~= 0 then
        local hash = type(ctx.model) == 'string' and joaat(ctx.model) or ctx.model
        if Bridge.byModel[hash] and Bridge.byModel[hash][id] then
            return Bridge.byModel[hash][id]
        end
    end

    -- byTarget durchsuchen (alle Targets)
    for _, list in pairs(Bridge.byTarget) do
        if list[id] then return list[id] end
    end

    -- byNpc / byZone / byModel durchsuchen wenn ctx leer war
    for _, list in pairs(Bridge.byNpc) do
        if list[id] then return list[id] end
    end
    for _, list in pairs(Bridge.byZone) do
        if list[id] then return list[id] end
    end
    for _, list in pairs(Bridge.byModel) do
        if list[id] then return list[id] end
    end

    return nil
end

-- ============================================================
--  RE-REGISTRATION HOOK (Drittanbieter-Resourcen, die clp_gmenu nutzen)
-- ============================================================

-- Subscriber fuer onResourceStart, damit Drittanbieter-Resourcen ihre
-- Aktionen nach Restart wieder registrieren koennen.
local rereg = {}

function Bridge.onResourceStart(fn)
    if type(fn) == 'function' then
        rereg[#rereg + 1] = fn
    end
end

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then return end
    -- Kleines Delay damit der Drittanbieter seine Module geladen hat
    SetTimeout(2000, function()
        for i = 1, #rereg do
            local ok, err = pcall(rereg[i], resourceName)
            if not ok and Config and Config.Debug then
                print(('^3[clp_gmenu]^0 Bridge.reregister Fehler in %s: %s'):format(resourceName, tostring(err)))
            end
        end
        -- TriggerEvent damit Drittanbieter selbst lauschen koennen ("re-register
        -- your stuff!"). Empfaenger sollten ihre exports erneut aufrufen.
        TriggerEvent('clp_gmenu:bridge:reregister', resourceName)
    end)
end)

-- Aktionen einer bestimmten Resource entfernen (wenn diese stoppt)
local function removeByResource(resourceName)
    if not resourceName then return end
    local function purge(tbl)
        for key, list in pairs(tbl) do
            if type(list) == 'table' then
                for id, action in pairs(list) do
                    if action and action._resource == resourceName then
                        list[id] = nil
                    end
                end
            end
        end
    end
    purge(Bridge.byTarget)
    purge(Bridge.byNpc)
    purge(Bridge.byZone)
    purge(Bridge.byModel)
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then return end
    removeByResource(resourceName)
end)

-- Helper: bei Aktions-Registrierung die Source-Resource taggen
local origRegister = Bridge.registerAction
function Bridge.registerAction(target, action)
    local ok, idOrErr = origRegister(target, action)
    if ok then
        local invoking = GetInvokingResource() or 'unknown'
        for _, list in pairs(Bridge.byTarget) do
            if list[idOrErr] then list[idOrErr]._resource = invoking end
        end
    end
    return ok, idOrErr
end

local origRegisterNpc = Bridge.registerNpcAction
function Bridge.registerNpcAction(npcId, action)
    local ok, idOrErr = origRegisterNpc(npcId, action)
    if ok and Bridge.byNpc[npcId] and Bridge.byNpc[npcId][idOrErr] then
        Bridge.byNpc[npcId][idOrErr]._resource = GetInvokingResource() or 'unknown'
    end
    return ok, idOrErr
end

local origRegisterZone = Bridge.registerZoneAction
function Bridge.registerZoneAction(zoneName, action)
    local ok, idOrErr = origRegisterZone(zoneName, action)
    if ok and Bridge.byZone[zoneName] and Bridge.byZone[zoneName][idOrErr] then
        Bridge.byZone[zoneName][idOrErr]._resource = GetInvokingResource() or 'unknown'
    end
    return ok, idOrErr
end

local origRegisterModel = Bridge.registerModelAction
function Bridge.registerModelAction(model, action)
    local ok, idOrErr = origRegisterModel(model, action)
    if ok then
        local hash = type(model) == 'string' and joaat(model) or model
        if Bridge.byModel[hash] and Bridge.byModel[hash][idOrErr] then
            Bridge.byModel[hash][idOrErr]._resource = GetInvokingResource() or 'unknown'
        end
    end
    return ok, idOrErr
end

-- ============================================================
--  EXPORTS (other resources)
-- ============================================================

exports('registerBridgeAction', function(target, action) return Bridge.registerAction(target, action) end)
exports('registerAction',       function(action) return Bridge.registerAction(action and action.target or 'any', action) end)
exports('removeAction',         function(id) return Bridge.removeAction(id) end)
exports('registerNpcAction',    function(npcId, action) return Bridge.registerNpcAction(npcId, action) end)
exports('registerZoneAction',   function(zoneName, action) return Bridge.registerZoneAction(zoneName, action) end)
exports('registerModelAction',  function(model, action) return Bridge.registerModelAction(model, action) end)

-- ============================================================
--  EVENTS (for serverEvent style registration from other resources)
-- ============================================================

RegisterNetEvent('clp_gmenu:bridge:registerAction', function(target, action)
    -- only callable from server-context normally; reject when called from a client
    if source ~= 0 then return end
    Bridge.registerAction(target, action)
end)

print('^2[clp_gmenu]^0 Bridge (Server) geladen.')
