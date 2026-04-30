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
B.entities = {}   -- entityHandle -> { options }
B.models   = {}   -- modelHash -> { options }
B.globals  = {
    ped     = {},  -- [name] -> { options }
    vehicle = {},  -- [name] -> { options }
    object  = {},  -- [name] -> { options }
}

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
    if name then B.zones[name] = nil end
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

-- ============================================================
--  BRIDGE-OPTIONEN SAMMELN (aufgerufen von menu.lua)
-- ============================================================

--- Gibt alle Bridge-Optionen zurueck, die fuer das aktuelle Target passen.
--- Wird nach dem Server-Result gemergt.
function B.getExtraOptions(target)
    local extras = {}
    if not target then return extras end

    local myPos = GetEntityCoords(PlayerPedId())

    -- 1. Entity-basierte Optionen
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

    -- 3. Globale Optionen (Ped/Vehicle)
    local globalList = nil
    if target.type == 'player' or target.type == 'ped' then
        globalList = B.globals.ped
    elseif target.type == 'vehicle' then
        globalList = B.globals.vehicle
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

    -- canInteract Filter
    local filtered = {}
    for _, o in ipairs(extras) do
        if not o.canInteract or o.canInteract(target.entity, target.distance, target.coords, target.label) then
            filtered[#filtered + 1] = o
        end
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
            if o.id == optionId and o.onSelect then return o end
        end
        return nil
    end

    -- Entity
    if target and target.entity and B.entities[target.entity] then
        local o = findOpt(B.entities[target.entity].options)
        if o then o.onSelect(target.entity) return true end
    end

    -- Model
    if target and target.model and B.models[target.model] then
        local o = findOpt(B.models[target.model].options)
        if o then o.onSelect(target.entity) return true end
    end

    -- Globals
    local lists = { B.globals.ped, B.globals.vehicle, B.globals.object }
    for _, gl in ipairs(lists) do
        for _, g in pairs(gl) do
            local o = findOpt(g.options)
            if o then o.onSelect(target and target.entity) return true end
        end
    end

    -- Zones
    for _, z in pairs(B.zones) do
        local o = findOpt(z.options)
        if o then o.onSelect(target and target.entity) return true end
    end

    return false
end

print('^2[clp_gmenu]^0 ox_target Bridge geladen.')
