--[[
    clp_gmenu - Client Admin (NUI-Bridge fuer Editor)

    Command: /gmenuadmin

    Der Editor laeuft in einem iframe (html/admin/admin.html), das vom
    Hauptpanel (script.js) gemounted wird. Wir kommunizieren ueber die
    'openAdmin'/'closeAdmin'/'adminToFrame' Events sowie ueber NUI-Callbacks
    (Praefix 'admin:').
]]

GMenu = GMenu or {}
GMenu.Admin = {}

local Admin = GMenu.Admin
local U = GMenu.Util

Admin.open = false

-- ============================================================
--  OPEN
-- ============================================================

local function openEditor()
    if Admin.open then return end

    -- Server-Bootstrap holen (erlaubt nur Admins)
    local boot = lib.callback.await('clp_gmenu:admin:bootstrap', false)
    if not boot then
        lib.notify({ type = 'error', description = 'Keine Berechtigung fuer den Editor.' })
        return
    end

    Admin.open = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)

    SendNUIMessage({
        event    = 'openAdmin',
        snapshot = boot.snapshot,
        knownPermissions     = boot.knownPermissions,
        allowedCustomEvents  = boot.allowedCustomEvents,
        allowedCustomCommands= boot.allowedCustomCommands,
        isAdmin  = true,
    })
end

local function closeEditor()
    if not Admin.open then return end
    Admin.open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ event = 'closeAdmin' })
end

-- ============================================================
--  COMMAND-FALLBACK (Server triggert Editor-Open)
-- ============================================================

RegisterNetEvent('clp_gmenu:admin:openEditor', function()
    openEditor()
end)

RegisterCommand(Config.AdminCommand or 'gmenuadmin', function()
    -- Server-Side prueft erneut, hier nur UI-Bootstrap.
    openEditor()
end, false)

-- ============================================================
--  SNAPSHOT-UPDATES PUSHEN, WAEHREND EDITOR OFFEN IST
--  (z.B. wenn ein anderer Admin gleichzeitig editiert)
-- ============================================================

RegisterNetEvent('clp_gmenu:store:snapshot', function(snapshot)
    if Admin.open then
        SendNUIMessage({
            event    = 'adminToFrame',
            subEvent = 'snapshot',
            payload  = snapshot,
        })
    end
end)

RegisterNetEvent('clp_gmenu:store:patch', function(patch)
    if Admin.open then
        SendNUIMessage({
            event    = 'adminToFrame',
            subEvent = 'patch',
            payload  = patch,
        })
    end
end)

-- ============================================================
--  NUI-CALLBACKS (vom iframe ueber Hauptpanel weitergeleitet)
--  Praefix 'admin:'
-- ============================================================

RegisterNUICallback('admin:close', function(_, cb)
    cb(1)
    closeEditor()
end)

RegisterNUICallback('admin:patch', function(data, cb)
    cb(1)
    if type(data) ~= 'table' or type(data.path) ~= 'string' then return end
    TriggerServerEvent('clp_gmenu:admin:patch', { path = data.path, value = data.value })
end)

RegisterNUICallback('admin:replace', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end
    TriggerServerEvent('clp_gmenu:admin:replace', data)
end)

RegisterNUICallback('admin:reset', function(_, cb)
    cb(1)
    TriggerServerEvent('clp_gmenu:admin:reset')
end)

RegisterNUICallback('admin:export', function(_, cb)
    -- Liefere JSON zurueck, damit NUI Download anstossen kann
    local snapshot = lib.callback.await('clp_gmenu:admin:export', false)
    cb(snapshot or {})
end)

RegisterNUICallback('admin:audit', function(data, cb)
    -- data kann jetzt { limit, actor, action, since, until_ } sein
    local opts = data or { limit = 200 }
    local list = lib.callback.await('clp_gmenu:admin:audit', false, opts)
    cb(list or {})
end)

RegisterNUICallback('admin:bridges', function(_, cb)
    local data = lib.callback.await('clp_gmenu:admin:bridges', false)
    cb(data or { byTarget = {}, byNpc = {}, byZone = {}, byModel = {} })
end)

RegisterNUICallback('admin:bridgeStats', function(_, cb)
    local data = lib.callback.await('clp_gmenu:admin:bridgeStats', false)
    cb(data or { totals = {}, resources = {} })
end)

RegisterNUICallback('admin:storage', function(_, cb)
    local data = lib.callback.await('clp_gmenu:admin:storage', false)
    cb(data or {})
end)

RegisterNUICallback('admin:impound', function(_, cb)
    local data = lib.callback.await('clp_gmenu:admin:impound', false)
    cb(data or { lots = {}, perLot = {}, total = 0, owners = {}, totalFee = 0 })
end)

-- ============================================================
--  RESOURCE STOP CLEANUP
-- ============================================================

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if Admin.open then SetNuiFocus(false, false) end
end)

print('^2[clp_gmenu]^0 Admin client loaded.')
