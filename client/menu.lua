--[[
    clp_gmenu - Menu Controller

    Brueckt Lua <-> NUI fuer das Hauptmenue.

    Steuerung:
      G       - oeffnet Menue wenn ein gueltiges Target im Raycast ist
      G/ESC   - schliesst (NUI behandelt ESC selbst, schickt /close-Callback)
      1..9    - Hotkey-Auswahl (NUI-seitig)
      Klick   - Option auswaehlen
]]

GMenu = GMenu or {}
GMenu.Menu = {}

local M = GMenu.Menu
local R = GMenu.Raycast
local U = GMenu.Util

-- ============================================================
--  STATE
-- ============================================================
M.open = false
M.lastOpenAt = 0
M.openTarget = nil       -- snapshot des Targets beim Open

local function nowMs() return GetGameTimer() end

function M.isOpen() return M.open end

-- Delta-Detection State (deklariert hier damit in close_() erreichbar)
local lastStatsSent = nil

-- ============================================================
--  ACTION-CACHE (3 Minuten TTL, invalidiert bei Store-Aenderung)
-- ============================================================
local actionCache = {}   -- key = cacheKey, value = { result, ts }

local function getCached(targetType)
    local ttl = Config.ActionCacheTTL or 180000
    if ttl <= 0 then return nil end
    -- Cache-Key: Job + Rang + targetType (vereinfacht via perms)
    local perms = GMenu.GetPerms()
    if not perms then return nil end
    local key = (perms.jobName or 'nil') .. ':' .. tostring(perms.grade or 0) .. ':' .. targetType
    local c = actionCache[key]
    if c and (nowMs() - c.ts) < ttl then
        return c.result
    end
    return nil
 end

local function setCache(result)
    if not result or not result._cacheKey then return end
    local ttl = Config.ActionCacheTTL or 180000
    if ttl <= 0 then return end
    actionCache[result._cacheKey] = { result = result, ts = nowMs() }
end

function M.invalidateCache()
    actionCache = {}
end

-- Externe API fuer Cache-Invalidierung
GMenu.InvalidateActionCache = M.invalidateCache

-- ============================================================
--  THEME / COLORS PUSH zur NUI
-- ============================================================

-- Delta-Detection fuer Theme-Push
local lastThemePush = nil

function GMenu.PushUiTheme()
    local theme  = GMenu.GetTheme()
    local anchor = (GMenu.State.store and GMenu.State.store.globals and GMenu.State.store.globals.menuAnchor) or Config.MenuAnchor
    local ui      = U.rgbToHex(GMenu.GetColor('ui'))
    local outline = U.rgbToHex(GMenu.GetColor('outline'))
    local marker  = U.rgbToHex(GMenu.GetColor('marker'))

    -- Delta-Check: nur senden wenn etwas sich aendert
    if lastThemePush
        and lastThemePush.theme == theme
        and lastThemePush.anchor == anchor
        and lastThemePush.ui == ui
        and lastThemePush.outline == outline
        and lastThemePush.marker == marker then
        return
    end

    lastThemePush = { theme = theme, anchor = anchor, ui = ui, outline = outline, marker = marker }

    SendNUIMessage({
        event  = 'updateTheme',
        theme  = theme,
        anchor = anchor,
        colors = { ui = ui, outline = outline, marker = marker },
    })
end

-- ============================================================
--  OEFFNEN
-- ============================================================

M._opening = false  -- Verhindert doppeltes Oeffnen waehrend Server-Request

function M.open_()
    -- Anti-Spam: 250ms Cooldown
    if (nowMs() - M.lastOpenAt) < 250 then return end
    if M.open or M._opening then return end

    local target = R.getCurrent()
    if not target then
        if GMenu.SoundsEnabled() and Config.SoundOnDeny then
            PlaySoundFrontend(-1, Config.SoundOnDeny.name, Config.SoundOnDeny.lib, true)
        end
        return
    end

    if not GMenu.State.storeReady then return end

    -- NetId sicherstellen
    local netId = target.netId
    if (not netId or netId == 0) and NetworkGetEntityIsNetworked(target.entity) then
        netId = NetworkGetNetworkIdFromEntity(target.entity)
    end
    -- Fuer nicht-vernetzte Entities (lokale NPCs): Netzwerk-Kontrolle anfordern
    if (not netId or netId == 0) and DoesEntityExist(target.entity) then
        NetworkRequestControlOfEntity(target.entity)
        if not NetworkGetEntityIsNetworked(target.entity) then
            NetworkRegisterEntityAsNetworked(target.entity)
        end
        -- Kurz warten damit Netzwerk greift
        Wait(50)
        if NetworkGetEntityIsNetworked(target.entity) then
            netId = NetworkGetNetworkIdFromEntity(target.entity)
        end
    end
    -- Spieler/Fahrzeuge MUESSEN eine netId haben; NPCs/Objekte/Zonen duerfen ohne (Fallback)
    local needsNetId = (target.type == 'player' or target.type == 'vehicle')
    if (not netId or netId == 0) and needsNetId then
        if GMenu.SoundsEnabled() and Config.SoundOnDeny then
            PlaySoundFrontend(-1, Config.SoundOnDeny.name, Config.SoundOnDeny.lib, true)
        end
        return
    end

    M._opening = true
    M._openingTs = nowMs()

    -- Timeout-Guard: falls Callback nie zurueckkommt, _opening nach 5s zuruecksetzen
    SetTimeout(5000, function()
        if M._opening and M._openingTs and (nowMs() - M._openingTs) >= 4900 then
            M._opening = false
            M._openingTs = nil
            if Config.Debug then print('^3[clp_gmenu]^0 getActions Timeout (5s)') end
        end
    end)

    -- Cache pruefen
    local cached = getCached(target.type)
    if cached and cached.options and #cached.options > 0 then
        M._opening = false
        M._openingTs = nil
        M._finishOpen(target, cached, netId)
        return
    end

    -- Server-Driven: Aktionen vom Server holen
    lib.callback('clp_gmenu:getActions', false, function(result)
        M._opening = false
        M._openingTs = nil

        -- Pruefen ob Target noch da / gleich
        local curTarget = R.getCurrent()
        if not result or not result.options or M.open then return end
        if target.type ~= 'self' and (not curTarget or curTarget.entity ~= target.entity) then return end

        -- In Cache speichern
        setCache(result)

        if #result.options == 0 then
            if GMenu.SoundsEnabled() and Config.SoundOnDeny then
                PlaySoundFrontend(-1, Config.SoundOnDeny.name, Config.SoundOnDeny.lib, true)
            end
            return
        end

        M._finishOpen(target, result, netId)
    end, {
        netId      = netId or 0,
        targetType = target.type,
        pedCoords  = (target.type == 'ped') and target.coords or nil,
        pedModel   = (target.type == 'ped') and target.model or nil,
        npcId      = target.npcId,                       -- clp_gmenu NPC-Manager ID
        zoneName   = (target.type == 'zone') and target.zoneName or nil,
        model      = (target.type == 'object') and target.model or nil,
        coords     = target.coords,
        distance   = target.distance,
    })
end

--- Gemeinsame Logik fuer Menu-Oeffnung (aus Cache oder frischem Result)
function M._finishOpen(target, result, netId)
    -- Bridge-Optionen (ox_target Kompatibilitaet) mergen
    if GMenu.Bridge and GMenu.Bridge.getExtraOptions and target.type ~= 'self' then
        local bridgeTarget = {
            entity   = target.entity,
            model    = target.model or (target.entity and target.entity ~= 0 and GetEntityModel(target.entity) or 0),
            type     = target.type,
            distance = target.distance or 0,
            coords   = target.coords,
            label    = target.label,
        }
        local extras = GMenu.Bridge.getExtraOptions(bridgeTarget)
        if extras and #extras > 0 then
            local opts = result.options
            for _, e in ipairs(extras) do
                opts[#opts + 1] = {
                    id     = e.id,
                    label  = e.label,
                    icon   = e.icon or 'fa-circle',
                    _bridge = true,
                }
            end
        end
    end

    local payload = {
        event  = 'open',
        anchor = (GMenu.State.store and GMenu.State.store.globals and GMenu.State.store.globals.menuAnchor) or Config.MenuAnchor,
        theme  = GMenu.GetTheme(),
        sounds = GMenu.SoundsEnabled() and true or false,
        colors = {
            ui = U.rgbToHex(GMenu.GetColor('ui')),
            outline = U.rgbToHex(GMenu.GetColor('outline')),
            marker  = U.rgbToHex(GMenu.GetColor('marker')),
        },
        target = {
            type     = target.type,
            label    = target.label,
            sub      = target.type == 'vehicle' and (target.plate or '') or (target.type == 'self' and (result.job and result.job.rankLabel or '') or ''),
            isPlayer = target.isPlayer == true,
            distance = target.distance or 0,
            netId    = netId or 0,
        },
        options = result.options,
        stats   = (target.type ~= 'self') and GMenu.StatsEnabled() and R.getCurrentStats() or nil,
        job     = result.job or nil,
    }

    M.openTarget = U.deepCopy(payload.target)
    M.openTarget.entity   = target.entity
    M.openTarget.npcId    = target.npcId
    M.openTarget.zoneName = target.zoneName
    M.openTarget.model    = target.model
    M.openTarget.coords   = target.coords

    M.open = true
    M.lastOpenAt = nowMs()
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage(payload)
    -- NUI-Layer (script.js Sound.open()) uebernimmt das Akustik-Feedback,
    -- damit es ein einheitliches Sounddesign ueber alle Themes gibt.
end

-- ============================================================
--  SELF-MENU (G ohne Ziel)
-- ============================================================

function M.openSelf_()
    if M.open or M._opening then return end
    if not GMenu.State.storeReady then return end

    -- Virtuelles Self-Target
    local me = PlayerPedId()
    local perms = GMenu.GetPerms()
    local selfTarget = {
        type     = 'self',
        entity   = me,
        netId    = 0,
        isPlayer = true,
        label    = GetPlayerName(PlayerId()) or 'Du',
        distance = 0,
        coords   = GetEntityCoords(me),
    }

    M._opening = true
    M._openingTs = nowMs()

    SetTimeout(5000, function()
        if M._opening and M._openingTs and (nowMs() - M._openingTs) >= 4900 then
            M._opening = false
            M._openingTs = nil
        end
    end)

    local cached = getCached('self')
    if cached and cached.options and #cached.options > 0 then
        M._opening = false
        M._openingTs = nil
        M._finishOpen(selfTarget, cached, 0)
        return
    end

    lib.callback('clp_gmenu:getActions', false, function(result)
        M._opening = false
        M._openingTs = nil
        if not result or not result.options or M.open then return end

        setCache(result)

        if #result.options == 0 then
            if GMenu.SoundsEnabled() and Config.SoundOnDeny then
                PlaySoundFrontend(-1, Config.SoundOnDeny.name, Config.SoundOnDeny.lib, true)
            end
            return
        end

        M._finishOpen(selfTarget, result, 0)
    end, { netId = 0, targetType = 'self' })
end

-- ============================================================
--  SCHLIESSEN
-- ============================================================

function M.close_(skipNui)
    if not M.open then return end
    M.open = false
    M.openTarget = nil
    lastStatsSent = nil  -- Delta-Cache reset
    SetNuiFocus(false, false)
    if not skipNui then
        SendNUIMessage({ event = 'close' })
    end
    -- Raycast laeuft weiter (konstant aktiv)
end

-- ============================================================
--  RAYCAST-LISTENER: Statistiken live aktualisieren + bei Ziel-Verlust schliessen
-- ============================================================

R.onChange(function(newTarget, prevTarget)
    if M.open then
        -- Self-Menu: kein Raycast-Target noetig, nicht bei Aenderung schliessen
        if M.openTarget and M.openTarget.type == 'self' then return end
        -- Wenn das Ziel weg ist oder sich aendert -> schliessen
        if not newTarget or (M.openTarget and newTarget.entity ~= M.openTarget.entity) then
            M.close_()
        end
    end
end)

-- Delta-Detection: nur senden wenn Stats sich aendern
local function statsChanged(a, b)
    if not a and not b then return false end
    if not a or not b then return true end
    if a.kind ~= b.kind then return true end
    if a.kind == 'vehicle' then
        return a.engine ~= b.engine or a.body ~= b.body or a.speed ~= b.speed or a.plate ~= b.plate
    elseif a.kind == 'player' then
        return a.hp ~= b.hp or a.isDead ~= b.isDead or a.label ~= b.label
    end
    return true
end

R.onStats(function(stats)
    if M.open and stats then
        if statsChanged(stats, lastStatsSent) then
            lastStatsSent = stats
            SendNUIMessage({ event = 'updateStats', stats = stats })
        end
    end
end)

-- ============================================================
--  KEYBIND
-- ============================================================

lib.addKeybind({
    name = 'clp_gmenu_open',
    description = 'Interaktionsmenue oeffnen',
    defaultKey = Config.OpenKey or 'G',
    defaultMapper = 'keyboard',
    onPressed = function()
        if IsPauseMenuActive() then return end
        if IsNuiFocused() and not M.open then return end

        if M.open then
            M.close_()
            return
        end

        -- Raycast ist konstant aktiv -> direkt pruefen
        if R.getCurrent() then
            M.open_()
            return
        end

        -- Kurz warten falls Spieler knapp daneben schaut (~400ms)
        CreateThread(function()
            local deadline = GetGameTimer() + 400
            while GetGameTimer() < deadline do
                Wait(30)
                if R.getCurrent() then
                    M.open_()
                    return
                end
            end
            -- Kein Target -> Self-Menu oeffnen (falls aktiviert)
            if not M.open and Config.SelfMenuEnabled then
                M.openSelf_()
                return
            end
            -- Deny-Sound
            if not M.open and GMenu.SoundsEnabled() and Config.SoundOnDeny then
                PlaySoundFrontend(-1, Config.SoundOnDeny.name, Config.SoundOnDeny.lib, true)
            end
        end)
    end,
})

-- ============================================================
--  NUI-CALLBACKS
-- ============================================================

RegisterNUICallback('select', function(data, cb)
    cb(1)
    if not data or not data.id then return end
    if not M.openTarget then return end

    -- Bridge-Option zuerst pruefen (ox_target Kompatibilitaet, client-seitig)
    if GMenu.Bridge and GMenu.Bridge.executeOption then
        if GMenu.Bridge.executeOption(data.id, M.openTarget) then
            -- Bridge hat die Aktion uebernommen, kein Server-Dispatch noetig
        elseif GMenu.Actions and GMenu.Actions.execute then
            GMenu.Actions.execute(data.id, M.openTarget)
        end
    elseif GMenu.Actions and GMenu.Actions.execute then
        GMenu.Actions.execute(data.id, M.openTarget)
    end
    -- Select-Sound wird vom NUI-Layer (script.js Sound.select()) gespielt.

    -- Menue automatisch schliessen nach Auswahl
    M.close_()
end)

RegisterNUICallback('close', function(_, cb)
    cb(1)
    M.close_(true)
end)

RegisterNUICallback('cycleTheme', function(data, cb)
    cb(1)
    if data and data.theme then
        GMenu.SaveKvp('theme', data.theme)
        GMenu.PushUiTheme()
    end
end)

-- ============================================================
--  AUFRAEUMEN BEIM RESOURCE-STOP
-- ============================================================

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if M.open then
        SetNuiFocus(false, false)
    end
end)

print('^2[clp_gmenu]^0 Menue geladen.')
