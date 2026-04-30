--[[
    clp_gmenu - Zone Erkennung (Client)

    Polling-basierte Erkennung von Box / Sphere / Polygon Zonen.
    Wird mit dem Raycast-Target-System verzahnt:
      - Wenn kein Entity-Ziel im Raycast erfasst wird, prueft Zones.getCurrent()
        ob der Spieler in einer Zone steht.
      - Zones bekommen ihre eigene Target-Type "zone" und werden ueber den Server
        auf passende Aktionen aufgeloest.
      - Optional: Bodenmarker + Blip rendering pro Zone.

    Sync: Server pusht via 'clp_gmenu:zones:list' Callback und Store-Patches.
]]

GMenu = GMenu or {}
GMenu.Zones = {}

local Z = GMenu.Zones
local U = GMenu.Util

Z.list = {}        -- name -> def
Z.current = nil    -- aktuell betretene Zone (Snapshot)

local function buildVec(c)
    return vector3(tonumber(c.x) or 0.0, tonumber(c.y) or 0.0, tonumber(c.z) or 0.0)
end

-- ============================================================
--  GEOMETRY
-- ============================================================

local function isInsideBox(pos, def)
    local dx = pos.x - def.coords.x
    local dy = pos.y - def.coords.y
    local dz = pos.z - def.coords.z
    if def.heading and def.heading ~= 0 then
        local rad = math.rad(-def.heading)
        local cos, sin = math.cos(rad), math.sin(rad)
        dx, dy = cos*dx - sin*dy, sin*dx + cos*dy
    end
    local sx = (def.size.x or 2) / 2
    local sy = (def.size.y or 2) / 2
    local sz = (def.size.z or 2) / 2
    return math.abs(dx) <= sx and math.abs(dy) <= sy and math.abs(dz) <= sz
end

local function isInsideSphere(pos, def)
    local dx = pos.x - def.coords.x
    local dy = pos.y - def.coords.y
    local dz = pos.z - def.coords.z
    local r = def.radius or 2
    return (dx*dx + dy*dy + dz*dz) <= r * r
end

local function isInsidePolygon(pos, def)
    -- Z-Achse: nur gueltig wenn pos.z innerhalb +-3m vom coords.z
    if math.abs(pos.z - def.coords.z) > (def.height or 3.0) then return false end
    local pts = def.points
    local inside = false
    local j = #pts
    for i = 1, #pts do
        local pi = pts[i]
        local pj = pts[j]
        if ((pi.y > pos.y) ~= (pj.y > pos.y))
           and (pos.x < (pj.x - pi.x) * (pos.y - pi.y) / ((pj.y - pi.y) + 1e-9) + pi.x) then
            inside = not inside
        end
        j = i
    end
    return inside
end

local function isInside(pos, def)
    if not def or def.enabled == false then return false end
    if def.type == 'box' then return isInsideBox(pos, def)
    elseif def.type == 'sphere' then return isInsideSphere(pos, def)
    elseif def.type == 'polygon' then return isInsidePolygon(pos, def) end
    return false
end

-- ============================================================
--  PUBLIC API
-- ============================================================

function Z.getCurrent() return Z.current end

function Z.findAt(pos)
    pos = pos or GetEntityCoords(PlayerPedId())
    -- pick smallest matching (priority: smaller radius/size wins so nested zones work)
    local best, bestArea
    for name, def in pairs(Z.list) do
        if def and def.enabled ~= false and isInside(pos, def) then
            local area = 1e18
            if def.type == 'sphere' then area = (def.radius or 1) ^ 2
            elseif def.type == 'box' then
                area = (def.size and ((def.size.x or 1) * (def.size.y or 1) * (def.size.z or 1))) or 1
            end
            if not best or area < bestArea then
                best = def; bestArea = area
            end
        end
    end
    return best
end

-- ============================================================
--  POLL LOOP
-- ============================================================

local enteredAt = 0
local function fireEnter(def)
    enteredAt = GetGameTimer()
    Z.current = def
    TriggerEvent('clp_gmenu:zone:enter', def)
end

local function fireExit(def)
    Z.current = nil
    TriggerEvent('clp_gmenu:zone:exit', def)
end

CreateThread(function()
    while true do
        local pos = GetEntityCoords(PlayerPedId())
        local hit = Z.findAt(pos)
        if hit then
            if not Z.current or Z.current.name ~= hit.name then
                if Z.current then fireExit(Z.current) end
                fireEnter(hit)
            end
            Wait(250)
        else
            if Z.current then fireExit(Z.current) end
            Wait(500)
        end
    end
end)

-- ============================================================
--  RENDER LOOP (markers + blips on map)
-- ============================================================

local blips = {}

local function syncBlips()
    -- remove orphaned
    for name, h in pairs(blips) do
        if not Z.list[name] or not Z.list[name].blip then
            RemoveBlip(h); blips[name] = nil
        end
    end
    -- add/update
    for name, def in pairs(Z.list) do
        if def.blip and def.coords then
            if not blips[name] then
                local b = AddBlipForCoord(def.coords.x, def.coords.y, def.coords.z)
                SetBlipSprite(b, tonumber(def.blip.sprite) or 480)
                SetBlipColour(b, tonumber(def.blip.color) or 2)
                SetBlipScale(b, tonumber(def.blip.scale) or 0.8)
                SetBlipAsShortRange(b, true)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentString(def.label or name)
                EndTextCommandSetBlipName(b)
                blips[name] = b
            end
        end
    end
end

CreateThread(function()
    while true do
        for _, def in pairs(Z.list) do
            if def.marker and def.coords then
                local pos = GetEntityCoords(PlayerPedId())
                local d = #(pos - vector3(def.coords.x, def.coords.y, def.coords.z))
                if d < 35.0 then
                    local m = def.marker
                    local color = m.color or '#00FFB4'
                    local rgb = U.hexToRgb(color)
                    DrawMarker(
                        tonumber(m.type) or 1,
                        def.coords.x, def.coords.y, def.coords.z - 1.0,
                        0,0,0, 0,0,0,
                        tonumber(m.scale) or 1.5, tonumber(m.scale) or 1.5, tonumber(m.scale) or 1.0,
                        rgb.r, rgb.g, rgb.b, 120,
                        false, false, 2, false, nil, nil, false
                    )
                end
            end
        end
        Wait(0)
    end
end)

-- ============================================================
--  SYNC FROM SERVER
-- ============================================================

local function refreshList()
    lib.callback('clp_gmenu:zones:list', false, function(list)
        if type(list) ~= 'table' then return end
        Z.list = list
        syncBlips()
    end)
end

CreateThread(function()
    while not (GMenu.State and GMenu.State.storeReady) do Wait(200) end
    refreshList()
end)

-- Re-fetch when admin updates store on this path
RegisterNetEvent('clp_gmenu:store:patch', function(patch)
    if not patch or type(patch.path) ~= 'string' then return end
    if patch.path == 'zones' or patch.path:find('^zones%.') then
        refreshList()
    end
end)
RegisterNetEvent('clp_gmenu:store:snapshot', function() refreshList() end)
