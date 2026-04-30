--[[
    clp_gmenu - ox_lib UI Bridge (Client)

    Wrapper rund um ox_lib UI-Funktionen.
    Wenn ox_lib vorhanden ist (was Standard ist), werden die Aufrufe
    weitergeleitet. Andernfalls greift ein eigener NUI-basierter Fallback.

    Exports:
      exports.clp_gmenu:notify(data)
      exports.clp_gmenu:progress(data)
      exports.clp_gmenu:context(data)
      exports.clp_gmenu:inputDialog(data)

    Optional kompatibel (lib.* alias):
      lib.notify, lib.progressBar, lib.registerContext, lib.showContext, lib.inputDialog
      (werden NICHT ueberschrieben, sondern zusaetzlich angeboten ueber GMenu.UI.*)
]]

GMenu = GMenu or {}
GMenu.UI = {}
local UI = GMenu.UI

local hasOxLib = lib ~= nil

-- ============================================================
--  NOTIFY
-- ============================================================
function UI.notify(data)
    if type(data) ~= 'table' then return end
    if hasOxLib and lib.notify then
        lib.notify(data)
        return
    end
    -- Fallback: ESX
    local esx = exports['es_extended']:getSharedObject()
    if esx and esx.ShowNotification then
        esx.ShowNotification(data.description or data.title or '')
        return
    end
    -- Last resort: SetNotification natives
    SetNotificationTextEntry('STRING')
    AddTextComponentSubstringPlayerName(tostring(data.description or data.title or ''))
    DrawNotification(false, false)
end

-- ============================================================
--  PROGRESS BAR
-- ============================================================
function UI.progress(data)
    if type(data) ~= 'table' then return false end
    if hasOxLib and lib.progressBar then
        return lib.progressBar(data)
    end
    -- Fallback: simple busyspinner
    local label = data.label or 'Bitte warten...'
    local duration = tonumber(data.duration) or 2000
    BeginTextCommandBusyspinnerOn('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandBusyspinnerOn(4)
    Wait(duration)
    BusyspinnerOff()
    return true
end

-- ============================================================
--  CONTEXT MENU
-- ============================================================
local registeredContexts = {}

function UI.registerContext(data)
    if type(data) ~= 'table' or not data.id then return end
    if hasOxLib and lib.registerContext then
        lib.registerContext(data)
    end
    registeredContexts[data.id] = data
end

function UI.showContext(id)
    if hasOxLib and lib.showContext then
        return lib.showContext(id)
    end
    -- Fallback: Open in our own NUI menu via SendNUIMessage
    local ctx = registeredContexts[id]
    if not ctx then return end
    SendNUIMessage({
        event   = 'open',
        anchor  = 'right',
        theme   = GMenu.GetTheme and GMenu.GetTheme() or 'glass',
        target  = { type = 'context', label = ctx.title or 'Menue' },
        options = ctx.options or {},
    })
end

function UI.context(data)
    UI.registerContext(data)
    UI.showContext(data.id)
end

-- ============================================================
--  INPUT DIALOG
-- ============================================================
function UI.inputDialog(title, fields, options)
    if hasOxLib and lib.inputDialog then
        return lib.inputDialog(title, fields, options)
    end
    -- Minimal fallback: prompts via NUI
    local p = promise and promise.new() or nil
    SendNUIMessage({
        event = 'inputDialog',
        title = title,
        fields = fields,
    })
    -- Without ox_lib we can't truly await; return nil
    return nil
end

-- ============================================================
--  EXPORTS
-- ============================================================
exports('notify',      function(data) UI.notify(data) end)
exports('progress',    function(data) return UI.progress(data) end)
exports('context',     function(data) UI.context(data) end)
exports('inputDialog', function(title, fields, options) return UI.inputDialog(title, fields, options) end)
