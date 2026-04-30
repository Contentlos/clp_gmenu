--[[
    clp_gmenu - Client Settings (NUI-Panel + KVP-Persistenz)

    Command: /gmenusettings  (oder Config.SettingsCommand)
    Auch via Footer-Button "Einstellungen" im Hauptmenue erreichbar.
]]

local U = GMenu.Util

-- ============================================================
--  HELPERS
-- ============================================================

local function buildSettingsPayload()
    local globals = GMenu.State.store and GMenu.State.store.globals or {}
    return {
        theme            = GMenu.GetTheme(),
        uiColor          = U.rgbToHex(GMenu.GetColor('ui')),
        outlineColor     = U.rgbToHex(GMenu.GetColor('outline')),
        markerColor      = U.rgbToHex(GMenu.GetColor('marker')),
        enableSounds     = GMenu.SoundsEnabled(),
        showVehicleStats = GMenu.StatsEnabled(),
        maxDistance      = GMenu.GetMaxDistance(),
        soundPreset      = GMenu.GetSoundPreset and GMenu.GetSoundPreset() or 'soft',
    }
end

local function openSettingsUi()
    -- Wenn das Menue offen ist, schliessen wir es zuerst
    if GMenu.Menu and GMenu.Menu.isOpen and GMenu.Menu.isOpen() then
        GMenu.Menu.close_(true)
        Wait(150)
    end

    SetNuiFocus(true, true)
    SendNUIMessage({
        event = 'openSettings',
        data  = buildSettingsPayload(),
    })
end

-- ============================================================
--  COMMAND
-- ============================================================

RegisterCommand(Config.SettingsCommand or 'gmenusettings', function()
    if not GMenu.State or not GMenu.State.storeReady then
        lib.notify({ type = 'error', description = 'System noch nicht bereit.' })
        return
    end
    openSettingsUi()
end, false)

-- Auch ueber Hauptmenue-Footer-Button erreichbar
RegisterNUICallback('openSettings', function(_, cb)
    cb(1)
    openSettingsUi()
end)

-- ============================================================
--  SAVE / RESET / CLOSE
-- ============================================================

RegisterNUICallback('saveSettings', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end

    -- Theme
    if type(data.theme) == 'string' and #data.theme <= 24 then
        GMenu.SaveKvp('theme', data.theme)
    end

    -- Farben (HEX)
    local function isHex(s) return type(s) == 'string' and s:match('^#%x%x%x%x%x%x$') ~= nil end
    if isHex(data.uiColor)      then GMenu.SaveKvp('uiColor',      data.uiColor)      end
    if isHex(data.outlineColor) then GMenu.SaveKvp('outlineColor', data.outlineColor) end
    if isHex(data.markerColor)  then GMenu.SaveKvp('markerColor',  data.markerColor)  end

    -- Toggles
    if type(data.enableSounds) == 'boolean' then GMenu.SaveKvp('enableSounds', data.enableSounds) end
    if type(data.showStats)    == 'boolean' then GMenu.SaveKvp('showStats',    data.showStats)    end

    -- Sound-Preset
    if type(data.soundPreset) == 'string' and #data.soundPreset <= 24 then
        GMenu.SaveKvp('soundPreset', data.soundPreset)
    end

    -- Distance
    local d = tonumber(data.maxDistance)
    if d and d >= 5.0 and d <= 12.0 then
        GMenu.SaveKvp('maxDistance', d)
    end

    -- NUI Theme/Colors sofort updaten
    if GMenu.PushUiTheme then GMenu.PushUiTheme() end

    lib.notify({ type = 'success', description = 'Einstellungen gespeichert.' })
end)

RegisterNUICallback('resetSettings', function(_, cb)
    cb(1)
    -- Lokale KVPs loeschen
    for _, key in ipairs({ 'clp_gmenu:theme', 'clp_gmenu:uiColor', 'clp_gmenu:outlineColor',
                            'clp_gmenu:markerColor', 'clp_gmenu:enableSounds',
                            'clp_gmenu:showVehicleStats', 'clp_gmenu:maxDistance',
                            'clp_gmenu:soundPreset' }) do
        DeleteResourceKvp(key)
    end
    -- Lokalen Cache leeren
    GMenu.State.settings = {}
    if GMenu.PushUiTheme then GMenu.PushUiTheme() end
    lib.notify({ type = 'inform', description = 'Einstellungen zurueckgesetzt.' })
end)

RegisterNUICallback('closeSettings', function(_, cb)
    cb(1)
    SetNuiFocus(false, false)
end)

print('^2[clp_gmenu]^0 Einstellungen geladen.')
