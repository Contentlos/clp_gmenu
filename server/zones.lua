--[[
    clp_gmenu - Zone Manager (Server)

    Verwaltet vorgespeicherte Zonen (Box / Sphere / Polygon) mit Aktionen.
    Live-Sync an alle Clients ueber Store-Pfad "zones".

    Schema (data.zones[name]):
      {
        name    = 'cityhall_entry',
        type    = 'box' | 'sphere' | 'polygon',
        label   = 'Buergeramt',
        coords  = { x=..., y=..., z=... },
        size    = { x=2, y=2, z=3 },     -- box
        radius  = 5.0,                   -- sphere
        points  = { {x,y}, ... },        -- polygon (outline, z = coords.z)
        heading = 0.0,
        marker  = { type=1, scale=2.0, color='#00FFB4' },  -- optional ground marker
        blip    = { sprite=480, color=2, scale=0.8 },      -- optional minimap blip
        actions = { 'open_shop', 'open_garage' },
        requiredJob = nil,
        requiredDuty = nil,
        enabled = true,
      }
]]

GMenu = GMenu or {}
GMenu.Zones = {}

local Zones = GMenu.Zones
local Store = GMenu.Store
local Perms = GMenu.Perms
local U     = GMenu.Util

local function getList()
    local snap = Store.getSnapshot and Store.getSnapshot() or {}
    return snap.zones or {}
end

function Zones.list() return getList() end

function Zones.get(name)
    if type(name) ~= 'string' then return nil end
    return getList()[name]
end

local function isValidName(name)
    return type(name) == 'string' and name:match('^[a-z][a-z0-9_]*$') ~= nil and #name <= 48
end

local function validateZone(def)
    if type(def) ~= 'table' then return false, 'no_table' end
    if type(def.label) ~= 'string' or def.label == '' then return false, 'label_required' end
    if def.type ~= 'box' and def.type ~= 'sphere' and def.type ~= 'polygon' then
        return false, 'type_invalid'
    end
    if type(def.coords) ~= 'table' then return false, 'coords_required' end
    if def.type == 'sphere' then
        if not tonumber(def.radius) or tonumber(def.radius) <= 0 then return false, 'radius_invalid' end
    elseif def.type == 'box' then
        if type(def.size) ~= 'table' then return false, 'size_invalid' end
    elseif def.type == 'polygon' then
        if type(def.points) ~= 'table' or #def.points < 3 then return false, 'points_invalid' end
    end
    if def.actions and type(def.actions) ~= 'table' then return false, 'actions_invalid' end
    return true
end

local function normalize(def)
    def.coords = {
        x = tonumber(def.coords.x) or 0.0,
        y = tonumber(def.coords.y) or 0.0,
        z = tonumber(def.coords.z) or 0.0,
    }
    if def.type == 'box' and def.size then
        def.size = {
            x = tonumber(def.size.x) or 2.0,
            y = tonumber(def.size.y) or 2.0,
            z = tonumber(def.size.z) or 2.0,
        }
        def.heading = tonumber(def.heading) or 0.0
    end
    if def.type == 'sphere' then
        def.radius = tonumber(def.radius) or 2.0
    end
    def.actions = def.actions or {}
    def.enabled = def.enabled ~= false
    return def
end

-- ============================================================
--  CRUD
-- ============================================================

function Zones.set(name, def, by)
    if not isValidName(name) then return false, 'invalid_name' end
    local ok, err = validateZone(def)
    if not ok then return false, err end
    def.name = name
    normalize(def)
    Store.set('zones.' .. name, def, by or 'system')
    return true
end

function Zones.delete(name, by)
    if not isValidName(name) then return false, 'invalid_name' end
    Store.delete('zones.' .. name, by or 'system')
    return true
end

-- ============================================================
--  ACTIONS for a zone (server-side resolution)
-- ============================================================

function Zones.getActionIds(src, zoneName)
    local def = Zones.get(zoneName)
    local ids = {}
    if not def then return ids end
    if def.requiredJob then
        local job = Perms.getJob(src)
        if not job or job.name ~= def.requiredJob then return ids end
    end
    if def.requiredDuty and Perms.isOnDuty then
        if not Perms.isOnDuty(src) then return ids end
    end
    if type(def.actions) == 'table' then
        for i = 1, #def.actions do ids[#ids + 1] = def.actions[i] end
    end
    return ids
end

-- ============================================================
--  CLIENT CALLBACK
-- ============================================================

lib.callback.register('clp_gmenu:zones:list', function(src)
    return getList()
end)

-- ============================================================
--  ADMIN
-- ============================================================

local function adminGuard(src)
    if not Perms.isAdmin(src) then return false end
    if not Perms.consumeAdmin(src) then return false end
    return true
end

RegisterNetEvent('clp_gmenu:admin:zone:set', function(payload)
    local src = source
    if not adminGuard(src) then return end
    if type(payload) ~= 'table' then return end
    local ok, err = Zones.set(payload.name, payload.def, ('admin:%d'):format(src))
    if not ok then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Zone: ' .. tostring(err) })
        return
    end
    Perms.audit(src, 'zone_set', { name = payload.name })
    TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = 'Zone gespeichert.' })
end)

RegisterNetEvent('clp_gmenu:admin:zone:delete', function(name)
    local src = source
    if not adminGuard(src) then return end
    Zones.delete(name, ('admin:%d'):format(src))
    Perms.audit(src, 'zone_delete', { name = name })
    TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = 'Zone entfernt.' })
end)

print('^2[clp_gmenu]^0 Zone-Manager geladen.')
