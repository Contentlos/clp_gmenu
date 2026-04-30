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
