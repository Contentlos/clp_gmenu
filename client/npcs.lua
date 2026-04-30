--[[
    clp_gmenu - NPC Spawner (Client)

    Spawnt persistente NPCs aus dem Server-Store.
      - Modell async laden, Ped erstellen, Position/Heading setzen
      - Optional invincible/frozen/blockEvents
      - Optional Scenario abspielen
      - NPCs werden auf der NPC-Seite mit ihrer ID markiert (StateBag),
        damit der Raycast sie als "konfigurierte NPCs" erkennt und beim
        getActions-Aufruf mit der NPC-ID an den Server sendet.

    Auto-Despawn: Wenn ein NPC ausserhalb von 100m vom Spieler ist, wird er
    nicht freigegeben (Despawn). Wenn der Spieler in 80m kommt, wird er gespawnt.
]]

GMenu = GMenu or {}
GMenu.NpcMgr = {}
local Mgr = GMenu.NpcMgr

Mgr.list   = {}    -- id -> def
Mgr.peds   = {}    -- id -> ped handle
Mgr.spawnDistance   = 80.0
Mgr.despawnDistance = 110.0

local function loadModel(modelHash)
    if not IsModelInCdimage(modelHash) then return false end
    if HasModelLoaded(modelHash) then return true end
    RequestModel(modelHash)
    local ts = GetGameTimer()
    while not HasModelLoaded(modelHash) do
        if GetGameTimer() - ts > 5000 then return false end
        Wait(10)
    end
    return true
end

local function spawn(def)
    if Mgr.peds[def.id] and DoesEntityExist(Mgr.peds[def.id]) then return Mgr.peds[def.id] end
    local hash = type(def.model) == 'string' and joaat(def.model) or def.model
    if not loadModel(hash) then return nil end
    local ped = CreatePed(4, hash, def.coords.x, def.coords.y, def.coords.z - 1.0, def.heading or 0.0, false, false)
    if ped == 0 then return nil end
    if def.invincible ~= false then SetEntityInvincible(ped, true) end
    if def.frozen ~= false then FreezeEntityPosition(ped, true) end
    if def.blockEvents ~= false then SetBlockingOfNonTemporaryEvents(ped, true) end
    SetPedCanRagdoll(ped, false)
    SetPedDiesWhenInjured(ped, false)
    SetPedDropsWeaponsWhenDead(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    SetPedDiesInstantlyInWater(ped, false)
    if type(def.scenario) == 'string' and def.scenario ~= '' then
        TaskStartScenarioInPlace(ped, def.scenario, 0, true)
    end
    -- StateBag fuer Raycast
    local state = Entity(ped).state
    if state then
        state:set('clp_npc_id', def.id, false)
    end
    Mgr.peds[def.id] = ped
    SetModelAsNoLongerNeeded(hash)
    return ped
end

local function despawn(id)
    local p = Mgr.peds[id]
    if p and DoesEntityExist(p) then
        DeleteEntity(p)
    end
    Mgr.peds[id] = nil
end

-- ============================================================
--  TICK: spawn/despawn around player
-- ============================================================

CreateThread(function()
    while true do
        if next(Mgr.list) ~= nil then
            local pos = GetEntityCoords(PlayerPedId())
            for id, def in pairs(Mgr.list) do
                if def and def.enabled ~= false and def.coords then
                    local d = #(pos - vector3(def.coords.x, def.coords.y, def.coords.z))
                    if d <= Mgr.spawnDistance and not Mgr.peds[id] then
                        spawn(def)
                    elseif d > Mgr.despawnDistance and Mgr.peds[id] then
                        despawn(id)
                    end
                end
            end
        end
        Wait(2500)
    end
end)

-- ============================================================
--  CLEANUP
-- ============================================================

local function cleanupAll()
    for id, _ in pairs(Mgr.peds) do despawn(id) end
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    cleanupAll()
end)

-- ============================================================
--  SYNC FROM SERVER
-- ============================================================

local function refreshList()
    lib.callback('clp_gmenu:npcs:list', false, function(list)
        if type(list) ~= 'table' then return end
        Mgr.list = list
        -- Despawn entries that no longer exist
        for id, _ in pairs(Mgr.peds) do
            if not Mgr.list[id] then despawn(id) end
        end
    end)
end

CreateThread(function()
    while not (GMenu.State and GMenu.State.storeReady) do Wait(200) end
    refreshList()
end)

RegisterNetEvent('clp_gmenu:store:patch', function(patch)
    if not patch or type(patch.path) ~= 'string' then return end
    if patch.path == 'npcs' or patch.path:find('^npcs%.') then refreshList() end
end)
RegisterNetEvent('clp_gmenu:store:snapshot', function() refreshList() end)

-- ============================================================
--  PUBLIC: get NPC ID from a ped entity (used by raycast/menu)
-- ============================================================

function Mgr.getIdForPed(ped)
    if not ped or ped == 0 then return nil end
    local state = Entity(ped).state
    if state then
        local id = state.clp_npc_id
        if id then return id end
    end
    -- Fallback: linear scan (slow but rare)
    for id, p in pairs(Mgr.peds) do
        if p == ped then return id end
    end
    return nil
end
