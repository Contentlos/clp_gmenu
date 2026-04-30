--[[
    clp_gmenu - Server-Admin Verwaltung (CRUD)

    Alle In-Game-Editor-Events. Jeder Event prueft:
      1. Quelle ist ESX-Admin (Perms.isAdmin)
      2. Durchsatz-Begrenzung (consumeAdmin)
      3. Schema-Validierung (Util)
      4. Pfad-Whitelist (nur jobs/actions/customActions/items/globals editierbar)
    Bei jedem erfolgreichen Schreibvorgang -> Protokoll + Store-Sync (automatisch via Abonnement).
]]

local Store = GMenu.Store
local Perms = GMenu.Perms
local U = GMenu.Util

-- ============================================================
--  WHITELIST DER BEARBEITUNGS-PFADE
--  Ein Admin darf NUR diese obersten Bereiche aendern.
-- ============================================================
local EDITABLE_ROOTS = {
    jobs          = true,
    actions       = true,
    customActions = true,
    items         = true,
    globals       = true,
    -- Universal Framework
    defaults      = true,
    npcs          = true,
    zones         = true,
    identity      = true,
    -- Phase 7
    impound       = true,    -- A1: Impound-Tab (Lots, Fees, Defaults)
    themes        = true,    -- A2: Themes-Tab (custom accent colors)
}

local function rootOf(path)
    return (path or ''):match('^([^.]+)') or ''
end

local function pathAllowed(path)
    return EDITABLE_ROOTS[rootOf(path)] == true
end

-- ============================================================
--  SCHUTZ - kombiniert Admin-Pruefung + Durchsatz-Begrenzung
-- ============================================================
local function guard(src)
    if not Perms.isAdmin(src) then
        return false, 'kein_admin'
    end
    if not Perms.consumeAdmin(src) then
        TriggerClientEvent('ox_lib:notify', src, { type = 'warning', description = 'Bitte langsamer (Durchsatz-Begrenzung).' })
        return false, 'rate_limitiert'
    end
    return true
end

-- ============================================================
--  CALLBACK: Snapshot + Admin-Pruefung (fuer Editor-Oberflaeche)
-- ============================================================

lib.callback.register('clp_gmenu:admin:check', function(src)
    return Perms.isAdmin(src)
end)

lib.callback.register('clp_gmenu:admin:bootstrap', function(src)
    if not Perms.isAdmin(src) then return nil end
    return {
        snapshot = Store.getSnapshot(),
        knownPermissions = Config.KnownPermissions or {},
        allowedCustomEvents = Config.AllowedCustomEvents or {},
        allowedCustomCommands = Config.AllowedCustomCommands or {},
    }
end)

lib.callback.register('clp_gmenu:admin:audit', function(src, opts)
    if not Perms.isAdmin(src) then return {} end
    -- Backwards compat: opts kann eine Zahl sein (alte API) oder Tabelle.
    local limit, filter
    if type(opts) == 'number' then
        limit = opts
    elseif type(opts) == 'table' then
        limit  = opts.limit or 200
        filter = {
            actor   = opts.actor   and tostring(opts.actor):lower() or nil,
            action  = opts.action  and tostring(opts.action):lower() or nil,
            since   = tonumber(opts.since),    -- unix timestamp
            until_  = tonumber(opts.until_),
        }
    else
        limit = 200
    end
    local raw = Perms.getAudit(limit) or {}
    if not filter then return raw end

    local out = {}
    for i = 1, #raw do
        local e = raw[i]
        local pass = true
        if filter.actor then
            local s = tostring(e.actor or e.src or ''):lower()
            if not s:find(filter.actor, 1, true) then pass = false end
        end
        if pass and filter.action then
            local s = tostring(e.action or ''):lower()
            if not s:find(filter.action, 1, true) then pass = false end
        end
        if pass and filter.since and e.ts and e.ts < filter.since then pass = false end
        if pass and filter.until_ and e.ts and e.ts > filter.until_ then pass = false end
        if pass then out[#out + 1] = e end
    end
    return out
end)

-- Phase 7: Impound Live-View (A1, C12)
lib.callback.register('clp_gmenu:admin:impound', function(src)
    if not Perms.isAdmin(src) then return nil end
    if GMenu.Impound and GMenu.Impound.adminSnapshot then
        return GMenu.Impound.adminSnapshot()
    end
    return { lots = {}, perLot = {}, total = 0, owners = {}, totalFee = 0 }
end)

-- Phase 7: Bridge-Stats (D14)
lib.callback.register('clp_gmenu:admin:bridgeStats', function(src)
    if not Perms.isAdmin(src) then return nil end
    if GMenu.Bridge and GMenu.Bridge.getStats then
        return GMenu.Bridge.getStats()
    end
    return { totals = {}, resources = {} }
end)

-- ============================================================
--  PATCH (granular: einzelner Pfad aendern)
-- ============================================================

RegisterNetEvent('clp_gmenu:admin:patch', function(payload)
    local src = source
    local ok, reason = guard(src); if not ok then return end

    if type(payload) ~= 'table' or type(payload.path) ~= 'string' then return end
    if not pathAllowed(payload.path) then
        Perms.audit(src, 'admin_patch_denied', { path = payload.path, reason = 'path_not_allowed' })
        return
    end

    -- Schema-Stichprobe: wenn ein gesamter Job geschrieben wird, validieren
    if payload.path:match('^jobs%.[a-z0-9_]+$') and type(payload.value) == 'table' then
        local valid, err = U.validateJob(payload.value)
        if not valid then
            TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Job-Schema: ' .. tostring(err) })
            return
        end
    end

    if payload.path:match('^customActions%.[a-z0-9_]+$') and type(payload.value) == 'table' then
        local valid, err = U.validateCustomAction(payload.value)
        if not valid then
            TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Custom-Action: ' .. tostring(err) })
            return
        end
    end

    if payload.value == nil then
        Store.delete(payload.path, ('admin:%d'):format(src))
        Perms.audit(src, 'admin_delete', { path = payload.path })
    else
        Store.set(payload.path, payload.value, ('admin:%d'):format(src))
        Perms.audit(src, 'admin_set',    { path = payload.path })
    end

    TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = 'Gespeichert.' })
end)

-- ============================================================
--  ERSETZEN (Komplett-Import)
-- ============================================================

RegisterNetEvent('clp_gmenu:admin:replace', function(newData)
    local src = source
    local ok = guard(src); if not ok then return end

    if type(newData) ~= 'table' then return end

    -- Jeden Job einzeln validieren
    if type(newData.jobs) == 'table' then
        for jname, jdef in pairs(newData.jobs) do
            if not U.isValidJobName(jname) then
                TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Job-Name "' .. tostring(jname) .. '" ungueltig.' })
                return
            end
            local v, err = U.validateJob(jdef)
            if not v then
                TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = ('Job "%s": %s'):format(jname, err) })
                return
            end
        end
    end

    if type(newData.customActions) == 'table' then
        for aid, adef in pairs(newData.customActions) do
            if not U.isValidActionId(aid) then
                TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Custom-Action-ID "' .. tostring(aid) .. '" ungueltig.' })
                return
            end
            local v, err = U.validateCustomAction(adef)
            if not v then
                TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = ('Custom-Action "%s": %s'):format(aid, err) })
                return
            end
        end
    end

    local success, err = Store.replace(newData, ('admin:%d'):format(src))
    if not success then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Ersetzen fehlgeschlagen: ' .. tostring(err) })
        return
    end

    Perms.audit(src, 'admin_replace', { jobs = U.tableCount(newData.jobs or {}) })
    TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = 'Komplett ersetzt.' })
end)

-- ============================================================
--  AUF STANDARD ZURUECKSETZEN
-- ============================================================

RegisterNetEvent('clp_gmenu:admin:reset', function()
    local src = source
    local ok = guard(src); if not ok then return end

    Store.resetToDefault(('admin:%d'):format(src))
    Perms.audit(src, 'admin_reset', {})
    TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = 'Auf Standard zurueckgesetzt.' })
end)

-- ============================================================
--  EXPORT / IMPORT (NUI Download/Upload Bruecke)
-- ============================================================

lib.callback.register('clp_gmenu:admin:export', function(src)
    if not Perms.isAdmin(src) then return nil end
    return Store.getSnapshot()
end)

-- ============================================================
--  BRIDGES (read-only Snapshot der Laufzeit-Registry)
-- ============================================================

lib.callback.register('clp_gmenu:admin:bridges', function(src)
    if not Perms.isAdmin(src) then return nil end
    local Bridge = GMenu.Bridge
    if not Bridge then
        return { byTarget = {}, byNpc = {}, byZone = {}, byModel = {} }
    end
    local function flatten(map)
        local out = {}
        for k, list in pairs(map or {}) do
            local arr = {}
            for _, action in pairs(list or {}) do
                arr[#arr + 1] = {
                    id     = action.id,
                    label  = action.label,
                    icon   = action.icon,
                    target = action.target,
                    event  = action.event or action.serverEvent,
                    source = action.source,
                }
            end
            out[tostring(k)] = arr
        end
        return out
    end
    return {
        byTarget = flatten(Bridge.byTarget),
        byNpc    = flatten(Bridge.byNpc),
        byZone   = flatten(Bridge.byZone),
        byModel  = flatten(Bridge.byModel),
    }
end)

-- ============================================================
--  STORAGE-STATUS
-- ============================================================

lib.callback.register('clp_gmenu:admin:storage', function(src)
    if not Perms.isAdmin(src) then return nil end
    local snap = Store.getSnapshot()
    local sqlOk = (GMenu.SqlStore and GMenu.SqlStore.isAvailable and GMenu.SqlStore.isAvailable()) or false
    local known = 0
    if GMenu.Identity and GMenu.Identity.countKnownPairs then
        known = GMenu.Identity.countKnownPairs() or 0
    end
    local lastSave = (Store.getLastSaveTs and Store.getLastSaveTs()) or '—'
    return {
        version       = Store.getVersion(),
        sql           = sqlOk,
        jobs          = U.tableCount(snap.jobs or {}),
        actions       = U.tableCount(snap.actions or {}),
        customActions = U.tableCount(snap.customActions or {}),
        npcs          = U.tableCount(snap.npcs or {}),
        zones         = U.tableCount(snap.zones or {}),
        knownPlayers  = known,
        lastSave      = lastSave,
    }
end)

-- ============================================================
--  BEFEHL: /gmenuadmin
-- ============================================================

RegisterCommand(Config.AdminCommand or 'gmenuadmin', function(src, args, raw)
    if src == 0 then
        -- Server-Konsole: Diagnose
        print(('^2[clp_gmenu]^0 Store v%d, %d Jobs, %d Custom-Aktionen.'):format(
            Store.getVersion(),
            U.tableCount(Store.getJobs()),
            U.tableCount(Store.getCustomActions() or {})
        ))
        return
    end

    if not Perms.isAdmin(src) then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Keine Berechtigung.' })
        return
    end

    -- Editor beim Spieler oeffnen
    TriggerClientEvent('clp_gmenu:admin:openEditor', src)
end, false)

-- ============================================================
--  EXPORTS
-- ============================================================
exports('audit', function(src, action, details) Perms.audit(src, action, details) end)
exports('setStorePath', function(path, value, by) return Store.set(path, value, by) end)

print('^2[clp_gmenu]^0 Admin-Server geladen.')
