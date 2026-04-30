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

lib.callback.register('clp_gmenu:admin:audit', function(src, limit)
    if not Perms.isAdmin(src) then return {} end
    return Perms.getAudit(limit or 100)
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
