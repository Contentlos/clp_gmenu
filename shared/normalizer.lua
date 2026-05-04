--[[
    clp_gmenu - Action Normalizer (Shared)

    Wandelt Aktionen aus verschiedenen Quellen in das interne Format um.
    Das interne Format ist die "Single Source of Truth" fuer den Resolver
    und das NUI-Menue.

    Internes Format:
      {
        id           = 'unique_action_id',
        label        = 'Label',
        icon         = 'fa-solid fa-car',
        target       = 'player'|'ped'|'vehicle'|'object'|'zone'|'self'|'both',
        type         = 'clientEvent'|'serverEvent'|'command'|'handler'|'notify'|'ui',
        event        = 'event:name',
        payload      = {},
        requiredJob  = nil,
        requiredGrade= nil,
        requiredDuty = nil,
        permission   = nil,
        distance     = 2.5,
        canInteract  = nil,
        source       = 'clp'|'ox_bridge'|'custom'|'job'|'npc'|'zone'|'config',
      }
]]

GMenu = GMenu or {}
GMenu.Normalize = {}
local N = GMenu.Normalize

-- ============================================================
--  TYPE / TARGET WHITELIST
-- ============================================================
local VALID_TYPES = { clientEvent=true, serverEvent=true, command=true, handler=true, notify=true, ui=true }
local VALID_TARGETS = { player=true, ped=true, vehicle=true, object=true, zone=true, self=true, both=true, any=true }

local function safeIcon(icon)
    if type(icon) ~= 'string' or icon == '' then return 'fa-circle' end
    -- accept "fa-solid fa-car" or just "fa-car"
    return icon
end

local function safeId(id, fallback)
    if type(id) == 'string' and id ~= '' then return id end
    return fallback or ('act_' .. tostring(math.random(100000, 999999)))
end

-- ============================================================
--  CORE NORMALIZE
-- ============================================================

--- Normalisiert eine clp_gmenu Standard-Action (aus actions store).
function N.fromStandard(action, id)
    if type(action) ~= 'table' then return nil end
    return {
        id              = safeId(id or action.id),
        label           = action.label or 'Aktion',
        icon            = safeIcon(action.icon),
        target          = VALID_TARGETS[action.target] and action.target or 'any',
        type            = VALID_TYPES[action.type] and action.type or 'handler',
        event           = action.event,
        payload         = action.payload,
        requiredJob     = action.requiredJob,
        requiredGrade   = action.requiredGrade,
        requiredDuty    = action.requiredDuty,
        permission      = action.permission,
        distance        = tonumber(action.distance) or 3.0,
        canInteract     = action.canInteract,
        source          = action.source or 'clp',
        handler         = action.handler,
        requiresApproval= action.requiresApproval and true or false,
    }
end

--- Normalisiert eine Custom-Action (aus customActions store).
function N.fromCustom(action, id)
    if type(action) ~= 'table' then return nil end
    return {
        id              = safeId(id or action.id),
        label           = action.label or 'Custom',
        icon            = safeIcon(action.icon),
        target          = VALID_TARGETS[action.target] and action.target or 'any',
        type            = VALID_TYPES[action.type] and action.type or 'notify',
        event           = action.event,
        payload         = action.payload,
        permission      = action.permission,
        distance        = tonumber(action.distance) or 3.0,
        source          = 'custom',
        requiresApproval= action.requiresApproval and true or false,
    }
end

--- Normalisiert eine ox_target-Option in das interne Format.
function N.fromOxTarget(option, target)
    if type(option) ~= 'table' then return nil end
    local kind = 'handler'
    local event
    if option.serverEvent then
        kind = 'serverEvent'
        event = option.serverEvent
    elseif option.event then
        kind = 'clientEvent'
        event = option.event
    elseif option.command then
        kind = 'command'
        event = option.command
    elseif option.onSelect then
        kind = 'handler'   -- Will be invoked client-side via Bridge
    end
    return {
        id           = safeId(option.name or option.label),
        label        = option.label or 'Aktion',
        icon         = safeIcon(option.icon),
        target       = target or option.target or 'any',
        type         = kind,
        event        = event,
        payload      = option.args or option.payload,
        requiredJob  = option.job,
        requiredGrade= option.grade,
        permission   = option.permission,
        distance     = tonumber(option.distance) or 3.0,
        canInteract  = option.canInteract,
        source       = 'ox_bridge',
        _onSelect    = option.onSelect,   -- preserved for client dispatch
    }
end

--- Normalisiert eine NPC-spezifische Aktion (per NPC-ID definiert).
function N.fromNpc(action, npcId)
    local n = N.fromStandard(action, action and action.id)
    if n then n.source = 'npc'; n.npcId = npcId; n.target = n.target or 'ped' end
    return n
end

--- Normalisiert eine Zone-spezifische Aktion.
function N.fromZone(action, zoneName)
    local n = N.fromStandard(action, action and action.id)
    if n then n.source = 'zone'; n.zoneName = zoneName; n.target = n.target or 'zone' end
    return n
end

-- ============================================================
--  MERGE / DEDUP
-- ============================================================

--- Fuegt Listen normalisierter Aktionen zusammen, entfernt Duplikate (id-basiert).
--- Spaetere Listen ueberschreiben frueheres bei Konflikt - so kann Job > Default ueberschreiben.
function N.merge(...)
    local out = {}
    local seen = {}
    local lists = { ... }
    for i = 1, #lists do
        local list = lists[i]
        if type(list) == 'table' then
            for j = 1, #list do
                local a = list[j]
                if a and a.id then
                    if seen[a.id] then
                        out[seen[a.id]] = a   -- replace
                    else
                        out[#out + 1] = a
                        seen[a.id] = #out
                    end
                end
            end
        end
    end
    return out
end

--- Filtert eine normalisierte Liste auf Eintraege, die sichtbar sein duerfen.
--- ctx = { job = { name = 'police', grade = 1, duty = true }, permissions = {...}, distance = number, target = {type=...} }
function N.filterVisible(list, ctx)
    if type(list) ~= 'table' then return {} end
    ctx = ctx or {}
    local out = {}
    for i = 1, #list do
        local a = list[i]
        local ok = true

        if a.requiredJob and (not ctx.job or ctx.job.name ~= a.requiredJob) then
            -- default = true: if action is marked default, skip job requirement
            if not a.default then ok = false end
        end
        if ok and a.requiredGrade and ctx.job and (ctx.job.grade or 0) < a.requiredGrade then
            ok = false
        end
        if ok and a.requiredDuty and (not ctx.job or not ctx.job.duty) then
            ok = false
        end
        if ok and a.permission and a.permission ~= '' then
            if not ctx.permissions or ctx.permissions[a.permission] ~= true then
                ok = false
            end
        end
        if ok and a.distance and ctx.distance and ctx.distance > a.distance then
            ok = false
        end
        if ok and ctx.target and a.target and a.target ~= 'any' and a.target ~= 'both' then
            local tt = ctx.target.type
            if tt == 'ped' and a.target == 'player' then
                -- player actions valid on peds (NPCs)
            elseif tt ~= a.target then
                ok = false
            end
        end
        if ok and type(a.canInteract) == 'function' then
            local cok = pcall(a.canInteract, ctx.src, ctx.target)
            if not cok then ok = false end
        end

        if ok then out[#out + 1] = a end
    end
    return out
end

return N
