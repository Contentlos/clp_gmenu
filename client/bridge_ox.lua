--[[
    clp_gmenu - ox_target Kompatibilitaets-Bridge

    Stellt ox_target-kompatible Exports bereit, sodass Ressourcen die
    ox_target nutzen automatisch auf clp_gmenu umgeleitet werden.

    Unterstuetzte APIs:
      - addBoxZone / addSphereZone / removeZone
      - addTargetEntity / removeTargetEntity
      - addTargetModel / removeTargetModel
      - addGlobalPed / removeGlobalPed
      - addGlobalVehicle / removeGlobalVehicle
      - addGlobalObject / removeGlobalObject

    Die Bridge speichert registrierte Optionen und injiziert sie
    in den getActions-Flow wenn der Raycast ein passendes Ziel trifft.
]]

GMenu = GMenu or {}
GMenu.Bridge = {}

local B = GMenu.Bridge

-- ============================================================
--  REGISTRY
-- ============================================================
B.zones    = {}   -- name -> { type, center, size/radius, options, check }
B.entities = {}   -- entityHandle -> { options }     -- LOCAL entity handles
B.netIds   = {}   -- netId        -> { options }     -- networked entities
B.models   = {}   -- modelHash    -> { options }
B.globals  = {
    ped     = {},  -- [name] -> { options }
    vehicle = {},  -- [name] -> { options }
    object  = {},  -- [name] -> { options }
    player  = {},  -- [name] -> { options }
}
B.polys    = {}   -- name -> { points = {vec3,...}, minZ, maxZ, options }

-- Konvertiert ox_target Option-Format zu clp_gmenu Option-Format
local function convertOptions(oxOptions)
    if type(oxOptions) ~= 'table' then return {} end
    local out = {}
    for i = 1, #oxOptions do
        local o = oxOptions[i]
        out[i] = {
            id       = o.name or ('bridge_' .. i .. '_' .. GetGameTimer()),
            label    = o.label or o.name or 'Aktion',
            icon     = o.icon or 'fa-circle',
            onSelect = o.onSelect,
            canInteract = o.canInteract,
            _bridge  = true,
        }
    end
    return out
end

-- ============================================================
--  ZONE-BASIERTE INTERAKTIONEN
-- ============================================================

local function isInsideBox(pos, center, size, heading)
    local dx = pos.x - center.x
    local dy = pos.y - center.y
    local dz = pos.z - center.z
    if heading and heading ~= 0 then
        local rad = math.rad(-heading)
        local cos, sin = math.cos(rad), math.sin(rad)
        dx, dy = cos*dx - sin*dy, sin*dx + cos*dy
    end
    return math.abs(dx) <= (size.x or size[1] or 1) / 2
       and math.abs(dy) <= (size.y or size[2] or 1) / 2
       and math.abs(dz) <= (size.z or size[3] or 3) / 2
end

local function isInsideSphere(pos, center, radius)
    local dx = pos.x - center.x
    local dy = pos.y - center.y
    local dz = pos.z - center.z
    return (dx*dx + dy*dy + dz*dz) <= radius * radius
end

-- Ray-Casting Algorithmus fuer Point-in-Polygon
local function isInsidePoly(pos, points)
    local x, y = pos.x, pos.y
    local inside = false
    local n = #points
    local j = n
    for i = 1, n do
        local pi = points[i]
        local pj = points[j]
        local xi, yi = pi.x or pi[1], pi.y or pi[2]
        local xj, yj = pj.x or pj[1], pj.y or pj[2]
        if ((yi > y) ~= (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi + 1e-9) + xi) then
            inside = not inside
        end
        j = i
    end
    return inside
end

-- ============================================================
--  EXPORTS: ZONES
-- ============================================================

exports('addBoxZone', function(data)
    if type(data) ~= 'table' then return end
    local name = data.name or ('zone_' .. GetGameTimer())
    B.zones[name] = {
        type    = 'box',
        center  = data.coords or vector3(0,0,0),
        size    = data.size or vector3(2,2,2),
        heading = data.rotation or 0,
        options = convertOptions(data.options),
        debug   = data.debug,
    }
    return name
end)

exports('addSphereZone', function(data)
    if type(data) ~= 'table' then return end
    local name = data.name or ('sphere_' .. GetGameTimer())
    B.zones[name] = {
        type    = 'sphere',
        center  = data.coords or vector3(0,0,0),
        radius  = data.radius or 2.0,
        options = convertOptions(data.options),
        debug   = data.debug,
    }
    return name
end)

exports('removeZone', function(name)
    if name then
        B.zones[name] = nil
        B.polys[name] = nil
    end
end)

-- Polygon Zone (clp_target API)
exports('addPolyZone', function(data)
    if type(data) ~= 'table' or type(data.points) ~= 'table' then return end
    local name = data.name or ('poly_' .. GetGameTimer())
    -- Bounding box berechnen fuer Schnell-Check
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    for _, p in ipairs(data.points) do
        local px = p.x or p[1] or 0
        local py = p.y or p[2] or 0
        if px < minX then minX = px end
        if px > maxX then maxX = px end
        if py < minY then minY = py end
        if py > maxY then maxY = py end
    end
    B.polys[name] = {
        points  = data.points,
        minZ    = data.minZ or -math.huge,
        maxZ    = data.maxZ or math.huge,
        bbox    = { minX = minX, minY = minY, maxX = maxX, maxY = maxY },
        options = convertOptions(data.options),
        debug   = data.debug,
    }
    return name
end)

-- ============================================================
--  EXPORTS: ENTITY
-- ============================================================

exports('addTargetEntity', function(entities, data)
    if type(entities) ~= 'table' then entities = { entities } end
    if type(data) ~= 'table' then return end
    local opts = convertOptions(data.options)
    for _, e in ipairs(entities) do
        B.entities[e] = { options = opts, distance = data.distance or 3.0 }
    end
end)

exports('removeTargetEntity', function(entities)
    if type(entities) ~= 'table' then entities = { entities } end
    for _, e in ipairs(entities) do
        B.entities[e] = nil
    end
end)

-- clp_target / ox_target API: addEntity (netId-basiert)
exports('addEntity', function(arr, options)
    if type(arr) ~= 'table' or arr.label or arr.options then arr = { arr } end
    -- arr ist jetzt entweder {netId,...} ODER {{netId, options=...}, ...}
    -- Unterstuetze beide: addEntity(netId, optionsArr) UND addEntity({netIds}, optionsArr)
    local opts = options
    if not opts and arr[1] and (arr[1].options or arr[1].label) then
        -- alte Syntax addEntity({{netId=..., options=...}})
        for _, item in ipairs(arr) do
            local netId = item.netId or item.id
            if netId then
                B.netIds[netId] = { options = convertOptions(item.options or {}), distance = item.distance or 3.0 }
            end
        end
        return
    end
    opts = convertOptions(opts)
    for _, netId in ipairs(arr) do
        B.netIds[tonumber(netId)] = { options = opts, distance = 3.0 }
    end
end)

exports('removeEntity', function(arr, optionNames)
    if type(arr) ~= 'table' then arr = { arr } end
    for _, netId in ipairs(arr) do
        if optionNames and B.netIds[tonumber(netId)] then
            local opts = B.netIds[tonumber(netId)].options
            local toRemove = type(optionNames) == 'table' and optionNames or { optionNames }
            for i = #opts, 1, -1 do
                for j = 1, #toRemove do
                    if opts[i].id == toRemove[j] then table.remove(opts, i); break end
                end
            end
        else
            B.netIds[tonumber(netId)] = nil
        end
    end
end)

-- clp_target API: addLocalEntity (lokale Entity-Handles)
exports('addLocalEntity', function(arr, options)
    if type(arr) ~= 'table' then arr = { arr } end
    local opts = convertOptions(options or {})
    for _, e in ipairs(arr) do
        B.entities[e] = { options = opts, distance = 3.0 }
    end
end)

exports('removeLocalEntity', function(arr, optionNames)
    if type(arr) ~= 'table' then arr = { arr } end
    for _, e in ipairs(arr) do
        if optionNames and B.entities[e] then
            local opts = B.entities[e].options
            local toRemove = type(optionNames) == 'table' and optionNames or { optionNames }
            for i = #opts, 1, -1 do
                for j = 1, #toRemove do
                    if opts[i].id == toRemove[j] then table.remove(opts, i); break end
                end
            end
        else
            B.entities[e] = nil
        end
    end
end)

-- ============================================================
--  EXPORTS: MODEL
-- ============================================================

exports('addTargetModel', function(models, data)
    if type(models) ~= 'table' then models = { models } end
    if type(data) ~= 'table' then return end
    local opts = convertOptions(data.options)
    for _, m in ipairs(models) do
        local hash = type(m) == 'string' and joaat(m) or m
        B.models[hash] = { options = opts, distance = data.distance or 3.0 }
    end
end)

-- clp_target API: addModel(modelOrModels, options)
exports('addModel', function(arr, options)
    if type(arr) ~= 'table' then arr = { arr } end
    local opts = convertOptions(options or {})
    for _, m in ipairs(arr) do
        local hash = type(m) == 'string' and joaat(m) or m
        B.models[hash] = B.models[hash] or { options = {}, distance = 3.0 }
        for _, o in ipairs(opts) do
            B.models[hash].options[#B.models[hash].options + 1] = o
        end
    end
end)

exports('removeModel', function(arr, optionNames)
    if type(arr) ~= 'table' then arr = { arr } end
    for _, m in ipairs(arr) do
        local hash = type(m) == 'string' and joaat(m) or m
        if optionNames and B.models[hash] then
            local opts = B.models[hash].options
            local toRemove = type(optionNames) == 'table' and optionNames or { optionNames }
            for i = #opts, 1, -1 do
                for j = 1, #toRemove do
                    if opts[i].id == toRemove[j] then table.remove(opts, i); break end
                end
            end
            if #opts == 0 then B.models[hash] = nil end
        else
            B.models[hash] = nil
        end
    end
end)

exports('removeTargetModel', function(models)
    if type(models) ~= 'table' then models = { models } end
    for _, m in ipairs(models) do
        local hash = type(m) == 'string' and joaat(m) or m
        B.models[hash] = nil
    end
end)

-- ============================================================
--  EXPORTS: GLOBAL (ped/vehicle/object)
-- ============================================================

exports('addGlobalPed', function(data)
    if type(data) ~= 'table' then return end
    local name = data.name or ('gped_' .. GetGameTimer())
    B.globals.ped[name] = { options = convertOptions(data.options), distance = data.distance or 3.0 }
    return name
end)

exports('removeGlobalPed', function(name)
    if name then B.globals.ped[name] = nil end
end)

exports('addGlobalVehicle', function(data)
    if type(data) ~= 'table' then return end
    local name = data.name or ('gveh_' .. GetGameTimer())
    B.globals.vehicle[name] = { options = convertOptions(data.options), distance = data.distance or 3.0 }
    return name
end)

exports('removeGlobalVehicle', function(name)
    if name then B.globals.vehicle[name] = nil end
end)

exports('addGlobalObject', function(data)
    if type(data) ~= 'table' then return end
    local name = data.name or ('gobj_' .. GetGameTimer())
    B.globals.object[name] = { options = convertOptions(data.options), distance = data.distance or 3.0 }
    return name
end)

exports('removeGlobalObject', function(name)
    if name then B.globals.object[name] = nil end
end)

-- clp_target API: addGlobalPlayer / removeGlobalPlayer
exports('addGlobalPlayer', function(data)
    if type(data) ~= 'table' then return end
    -- Akzeptiere data.options ODER data direkt als options-Array
    local opts
    if data.options then
        opts = convertOptions(data.options)
    else
        opts = convertOptions(data)
    end
    local name = (data.name) or ('gplayer_' .. GetGameTimer())
    B.globals.player[name] = { options = opts, distance = data.distance or 3.0 }
    return name
end)

exports('removeGlobalPlayer', function(name)
    if name then B.globals.player[name] = nil end
end)

-- clp_target API: addGlobalOption — registriert auf ALLE Target-Typen
exports('addGlobalOption', function(data)
    if type(data) ~= 'table' then return end
    local name = data.name or ('gopt_' .. GetGameTimer())
    local opts = data.options and convertOptions(data.options) or convertOptions(data)
    local entry = { options = opts, distance = data.distance or 3.0 }
    B.globals.ped[name]     = entry
    B.globals.vehicle[name] = entry
    B.globals.object[name]  = entry
    B.globals.player[name]  = entry
    return name
end)

exports('removeGlobalOption', function(name)
    if not name then return end
    B.globals.ped[name]     = nil
    B.globals.vehicle[name] = nil
    B.globals.object[name]  = nil
    B.globals.player[name]  = nil
end)

-- ============================================================
--  BRIDGE-OPTIONEN SAMMELN (aufgerufen von menu.lua)
-- ============================================================

--- Gibt alle Bridge-Optionen zurueck, die fuer das aktuelle Target passen.
--- Wird nach dem Server-Result gemergt.
function B.getExtraOptions(target)
    local extras = {}
    if not target then return extras end

    local myPos = GetEntityCoords(PlayerPedId())

    -- 1a. NetId-basierte Optionen (clp_target API addEntity)
    if target.entity and target.entity ~= 0 and NetworkGetEntityIsNetworked(target.entity) then
        local netId = NetworkGetNetworkIdFromEntity(target.entity)
        if netId and B.netIds[netId] then
            local e = B.netIds[netId]
            if (target.distance or 0) <= (e.distance or 5) then
                for _, o in ipairs(e.options) do extras[#extras + 1] = o end
            end
        end
    end

    -- 1b. Lokale Entity-basierte Optionen
    if target.entity and B.entities[target.entity] then
        local e = B.entities[target.entity]
        if (target.distance or 0) <= (e.distance or 5) then
            for _, o in ipairs(e.options) do extras[#extras + 1] = o end
        end
    end

    -- 2. Modell-basierte Optionen
    if target.model and target.model ~= 0 then
        local m = B.models[target.model]
        if m and (target.distance or 0) <= (m.distance or 5) then
            for _, o in ipairs(m.options) do extras[#extras + 1] = o end
        end
    end

    -- 3. Globale Optionen (Ped/Vehicle/Object/Player)
    local globalList = nil
    if target.type == 'player' then
        globalList = B.globals.player
    elseif target.type == 'ped' then
        globalList = B.globals.ped
    elseif target.type == 'vehicle' then
        globalList = B.globals.vehicle
    elseif target.type == 'object' then
        globalList = B.globals.object
    end
    if globalList then
        for _, g in pairs(globalList) do
            if (target.distance or 0) <= (g.distance or 5) then
                for _, o in ipairs(g.options) do extras[#extras + 1] = o end
            end
        end
    end

    -- 4. Zone-basierte Optionen (Player-Position pruefen)
    for name, z in pairs(B.zones) do
        local inside = false
        if z.type == 'box' then
            inside = isInsideBox(myPos, z.center, z.size, z.heading)
        elseif z.type == 'sphere' then
            inside = isInsideSphere(myPos, z.center, z.radius)
        end
        if inside then
            for _, o in ipairs(z.options) do extras[#extras + 1] = o end
        end
    end

    -- 5. Polygon-Zonen
    for name, p in pairs(B.polys) do
        local zOk = (myPos.z >= p.minZ and myPos.z <= p.maxZ)
        local bb = p.bbox
        local bbOk = bb and (myPos.x >= bb.minX and myPos.x <= bb.maxX and myPos.y >= bb.minY and myPos.y <= bb.maxY)
        if zOk and bbOk and isInsidePoly(myPos, p.points) then
            for _, o in ipairs(p.options) do extras[#extras + 1] = o end
        end
    end

    -- canInteract Filter
    local filtered = {}
    for _, o in ipairs(extras) do
        local ok = true
        if type(o.canInteract) == 'function' then
            local pcallOk, result = pcall(o.canInteract, target.entity, target.distance, target.coords, target.label)
            if not pcallOk or not result then ok = false end
        end
        if ok then filtered[#filtered + 1] = o end
    end

    return filtered
end

-- ============================================================
--  BRIDGE-OPTION AUSFUEHREN (client-seitig, kein Server noetig)
-- ============================================================

function B.executeOption(optionId, target)
    -- In allen Registries suchen
    local function findOpt(opts)
        for _, o in ipairs(opts) do
            if o.id == optionId then return o end
        end
        return nil
    end

    -- Helper: Option ausfuehren (onSelect ODER event/serverEvent/command)
    local function fireOption(o, tgt)
        local entity = tgt and tgt.entity
        if type(o.onSelect) == 'function' then
            local ok, err = pcall(o.onSelect, entity, tgt)
            if not ok and type(err) == 'string' then
                print('^1[clp_gmenu]^0 Bridge onSelect Fehler: ' .. err)
            end
            return true
        end
        if o.serverEvent then
            local netId = (entity and entity ~= 0) and NetworkGetNetworkIdFromEntity(entity) or 0
            TriggerServerEvent(o.serverEvent, netId, tgt, o.args or o.payload)
            return true
        end
        if o.event then
            TriggerEvent(o.event, entity, tgt, o.args or o.payload)
            return true
        end
        if o.command then
            ExecuteCommand(o.command)
            return true
        end
        return false
    end

    -- NetId-basierte
    if target and target.entity and target.entity ~= 0 and NetworkGetEntityIsNetworked(target.entity) then
        local netId = NetworkGetNetworkIdFromEntity(target.entity)
        if netId and B.netIds[netId] then
            local o = findOpt(B.netIds[netId].options)
            if o and fireOption(o, target) then return true end
        end
    end

    -- Lokale Entity
    if target and target.entity and B.entities[target.entity] then
        local o = findOpt(B.entities[target.entity].options)
        if o and fireOption(o, target) then return true end
    end

    -- Model
    if target and target.model and B.models[target.model] then
        local o = findOpt(B.models[target.model].options)
        if o and fireOption(o, target) then return true end
    end

    -- Globals
    local lists = { B.globals.ped, B.globals.vehicle, B.globals.object, B.globals.player }
    for _, gl in ipairs(lists) do
        for _, g in pairs(gl) do
            local o = findOpt(g.options)
            if o and fireOption(o, target) then return true end
        end
    end

    -- Zones (box/sphere)
    for _, z in pairs(B.zones) do
        local o = findOpt(z.options)
        if o and fireOption(o, target) then return true end
    end

    -- Polygons
    for _, p in pairs(B.polys) do
        local o = findOpt(p.options)
        if o and fireOption(o, target) then return true end
    end

    return false
end

-- ============================================================
--  BRIDGE EXECUTE EVENT (vom Server, fuer handler-typed Bridge-Aktionen)
-- ============================================================

RegisterNetEvent('clp_gmenu:bridge:execute', function(actionId, target)
    -- Server hat eine Bridge-Aktion freigegeben — client soll sie lokal ausfuehren.
    -- Das ist der Pfad fuer onSelect-Callbacks die client-seitig registriert wurden.
    if not B.executeOption(actionId, target) then
        print(('^3[clp_gmenu]^0 Bridge execute: konnte Aktion "%s" nicht ausfuehren'):format(tostring(actionId)))
    end
end)

RegisterNetEvent('clp_gmenu:bridge:ui', function(action, target)
    -- UI-Aktion: oeffnet ein NUI-Panel oder ruft einen UI-Hook auf
    if action and action.event then
        TriggerEvent(action.event, target, action.payload)
    end
end)

print('^2[clp_gmenu]^0 ox_target Bridge geladen.')
