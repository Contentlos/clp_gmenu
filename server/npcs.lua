--[[
    clp_gmenu - NPC Manager (Server)

    Persistente NPCs: ID, Modell, Coords, Heading, Label, Aktionen.
    Werden in Store unter "npcs" gehalten und an alle Clients gesynct.
    Clients spawnen die NPCs lokal (clientseitig) anhand der Liste.

    Schema (data.npcs[id]):
      {
        id      = 'cityhall_worker',
        label   = 'Sachbearbeiter',
        model   = 'a_m_y_business_01',
        coords  = { x=..., y=..., z=... },
        heading = 0.0,
        actions = { 'open_cityhall', 'ask_documents' },  -- action IDs
        scenario = 'WORLD_HUMAN_CLIPBOARD',  -- optional
        invincible = true,
        frozen = true,
        blockEvents = true,
        enabled = true,
      }

    Der Server verwaltet CRUD; die Aktionen werden ueber den Action-Resolver
    ('npc' targetType) aus dem Store ausgeliefert.
]]

GMenu = GMenu or {}
GMenu.NPCs = {}

local NPCs  = GMenu.NPCs
local Store = GMenu.Store
local Perms = GMenu.Perms
local U     = GMenu.Util

-- ============================================================
--  HELPERS
-- ============================================================

local function getList()
    local snap = Store.getSnapshot and Store.getSnapshot() or {}
    return snap.npcs or {}
end

function NPCs.list()
    return getList()
end

function NPCs.get(id)
    if type(id) ~= 'string' then return nil end
    local list = getList()
    return list[id]
end

local function isValidId(id)
    return type(id) == 'string' and id:match('^[a-z][a-z0-9_]*$') ~= nil and #id <= 48
end

local function validateNpc(def)
    if type(def) ~= 'table' then return false, 'no_table' end
    if type(def.label) ~= 'string' or def.label == '' then return false, 'label_required' end
    if type(def.model) ~= 'string' or def.model == '' then return false, 'model_required' end
    if type(def.coords) ~= 'table' then return false, 'coords_required' end
    local x, y, z = tonumber(def.coords.x), tonumber(def.coords.y), tonumber(def.coords.z)
    if not x or not y or not z then return false, 'coords_invalid' end
    if def.actions and type(def.actions) ~= 'table' then return false, 'actions_invalid' end
    return true
end

local function normalize(def)
    def.coords = {
        x = tonumber(def.coords.x) or 0.0,
        y = tonumber(def.coords.y) or 0.0,
        z = tonumber(def.coords.z) or 0.0,
    }
    def.heading    = tonumber(def.heading) or 0.0
    def.actions    = def.actions or {}
    def.enabled    = def.enabled ~= false
    def.invincible = def.invincible ~= false
    def.frozen     = def.frozen ~= false
    def.blockEvents = def.blockEvents ~= false
    return def
end

-- ============================================================
--  CRUD
-- ============================================================

function NPCs.set(id, def, by)
    if not isValidId(id) then return false, 'invalid_id' end
    local ok, err = validateNpc(def)
    if not ok then return false, err end
    def.id = id
    normalize(def)
    Store.set('npcs.' .. id, def, by or 'system')
    return true
end

function NPCs.delete(id, by)
    if not isValidId(id) then return false, 'invalid_id' end
    Store.delete('npcs.' .. id, by or 'system')
    return true
end

-- ============================================================
--  ACTIONS for an NPC ID (default + per-NPC)
-- ============================================================

--- Returns the action IDs available on a given NPC for src.
function NPCs.getActionIds(src, npcId)
    local def = NPCs.get(npcId)
    local ids = {}
    if def and type(def.actions) == 'table' then
        for i = 1, #def.actions do ids[#ids + 1] = def.actions[i] end
    end
    return ids
end

-- ============================================================
--  CLIENT CALLBACKS
-- ============================================================

lib.callback.register('clp_gmenu:npcs:list', function(src)
    return getList()
end)

-- ============================================================
--  ADMIN EVENTS
-- ============================================================

local function adminGuard(src)
    if not Perms.isAdmin(src) then return false end
    if not Perms.consumeAdmin(src) then
        TriggerClientEvent('ox_lib:notify', src, { type = 'warning', description = 'Bitte langsamer.' })
        return false
    end
    return true
end

RegisterNetEvent('clp_gmenu:admin:npc:set', function(payload)
    local src = source
    if not adminGuard(src) then return end
    if type(payload) ~= 'table' then return end
    local ok, err = NPCs.set(payload.id, payload.def, ('admin:%d'):format(src))
    if not ok then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'NPC ungueltig: ' .. tostring(err) })
        return
    end
    Perms.audit(src, 'npc_set', { id = payload.id })
    TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = 'NPC gespeichert.' })
end)

RegisterNetEvent('clp_gmenu:admin:npc:delete', function(id)
    local src = source
    if not adminGuard(src) then return end
    NPCs.delete(id, ('admin:%d'):format(src))
    Perms.audit(src, 'npc_delete', { id = id })
    TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = 'NPC entfernt.' })
end)

print('^2[clp_gmenu]^0 NPC-Manager geladen.')
