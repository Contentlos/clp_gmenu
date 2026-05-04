--[[
    clp_gmenu - Aktions-Registry (Server)

    Zentrale Dispatch-Stelle fuer alle Aktionen, die ein Spieler ueber das
    Menue ausloesen kann.

    Konzept:
      - Jede Standard-Aktion hat eine Handler-Funktion (registriert via
        Registry.register('id', fn)). Die Job-Module (server/jobs/*.lua)
        registrieren ihre Handler hier.
      - Custom-Aktionen (vom Admin-Editor) haben keinen Code, sondern werden
        ueber Typ+Payload generisch dispatched (notify/event/serverEvent/command),
        gegen Whitelists abgesichert.

    Handler-Signatur:
      function(src, target, payload, action) -> ok:boolean, err:string|nil
        src      - Spieler-Source
        target   - { type = 'vehicle'|'player'|'ped', entity = ServerHandle, netId = id, isPlayer = bool, targetSrc = number|nil }
        payload  - Vom Client mitgeschickte Zusatzdaten (validieren!)
        action   - Die komplette Aktions-Definition aus dem Store

    Dispatch ist VOR-validiert: Distanz, Berechtigung, Rate-Limit wurden
    bereits geprueft, bevor der Handler aufgerufen wird.
]]

GMenu = GMenu or {}
GMenu.Registry = {}

local Registry = GMenu.Registry
local Store = GMenu.Store
local Perms = GMenu.Perms
local U = GMenu.Util

-- ============================================================
--  HANDLER-TABELLE
-- ============================================================
local handlers = {}    -- [actionId oder handlerKey] = function(src, target, payload, action)

--- Registriert einen Handler.
function Registry.register(key, fn)
    if type(key) ~= 'string' or type(fn) ~= 'function' then
        print('^1[clp_gmenu]^0 Registry: Ungueltiger register-Aufruf')
        return
    end
    if handlers[key] then
        print(('^3[clp_gmenu]^0 Registry: Handler "%s" wird ueberschrieben'):format(key))
    end
    handlers[key] = fn
end

function Registry.has(key)
    return handlers[key] ~= nil
end

-- ============================================================
--  ZIEL-AUFLOESUNG (NetId -> Server-Entity)
-- ============================================================

--- Loest den Ziel-Handle aus einer NetId auf.
local function resolveTarget(payload)
    payload = payload or {}
    local netId = tonumber(payload.netId or 0)
    local target = {
        type      = payload.targetType or 'unknown',
        netId     = netId,
        entity    = 0,
        isPlayer  = false,
        targetSrc = nil,
        npcId     = payload.npcId,
        zoneName  = payload.zoneName,
        model     = payload.model,
        coords    = payload.coords,
    }

    if netId and netId ~= 0 and NetworkGetEntityFromNetworkId then
        target.entity = NetworkGetEntityFromNetworkId(netId)
    end

    if target.entity ~= 0 and DoesEntityExist(target.entity) then
        local etype = GetEntityType(target.entity)
        if etype == 1 then     -- Ped
            target.isPlayer = IsPedAPlayer(target.entity)
            if target.isPlayer then
                target.type = 'player'
                target.targetSrc = NetworkGetEntityOwner(target.entity)
                -- Robuster: aus Spieler-Liste den Ped vergleichen
                local players = GetPlayers()
                for i = 1, #players do
                    local pid = tonumber(players[i])
                    if pid and GetPlayerPed(pid) == target.entity then
                        target.targetSrc = pid
                        break
                    end
                end
            else
                target.type = 'ped'    -- NPC/Ped
            end
        elseif etype == 2 then -- Fahrzeug
            target.type = 'vehicle'
        elseif etype == 3 then -- Objekt
            target.type = 'object'
            target.model = target.model or GetEntityModel(target.entity)
        end
    end

    -- Fallback: Entity nicht aufloesbar, aber Ped-Koordinaten vom Client vorhanden
    if (target.entity == 0 or not DoesEntityExist(target.entity)) and payload.pedCoords then
        target.type = 'ped'
        target._pedCoords = payload.pedCoords
        target._pedModel  = payload.pedModel
    end

    -- Zone-Aktionen: kein Entity erforderlich
    if payload.targetType == 'zone' and payload.zoneName then
        target.type = 'zone'
    end

    return target
end

-- ============================================================
--  CUSTOM-AKTION-DISPATCH (Benachrichtigung/Event/Befehl)
-- ============================================================

local function isInWhitelist(list, value)
    if type(list) ~= 'table' then return false end
    for i = 1, #list do
        if list[i] == value then return true end
    end
    return false
end

local function dispatchCustomAction(src, target, action)
    local kind = action.type
    local payload = action.payload

    if kind == 'notify' then
        local msg = type(payload) == 'string' and payload or (payload and payload.text) or 'Notify'
        TriggerClientEvent('ox_lib:notify', src, { type = 'inform', title = action.label or 'Aktion', description = msg })
        return true

    elseif kind == 'command' then
        if not isInWhitelist(Config.AllowedCustomCommands, tostring(payload)) then
            return false, 'Befehl nicht in Whitelist'
        end
        ExecuteCommand(tostring(payload))
        return true

    elseif kind == 'event' or kind == 'serverEvent' then
        local evtName = type(payload) == 'table' and payload.name or tostring(payload)
        if not isInWhitelist(Config.AllowedCustomEvents, evtName) then
            return false, 'Event nicht in Whitelist'
        end
        local evtArgs = (type(payload) == 'table' and payload.args) or {}

        if kind == 'event' then
            -- Client-Event beim Auslosenden Spieler triggern
            TriggerClientEvent(evtName, src, target, evtArgs)
        else
            -- Server-Event direkt
            TriggerEvent(evtName, src, target, evtArgs)
        end
        return true
    end

    return false, 'Unbekannter Custom-Aktionstyp'
end

-- ============================================================
--  BRIDGE-AKTION DISPATCH
--
--  Bridge-Aktionen kommen aus Drittanbieter-Resource-Code (vertraut).
--  Sie unterstuetzen die ox_target-Felder: serverEvent, event, command,
--  und auch das normalisierte type-Feld (clientEvent/serverEvent/handler/notify/ui).
-- ============================================================

local function buildTargetForBridge(target, payload)
    return {
        type     = target.type,
        entity   = target.entity,
        netId    = target.netId,
        coords   = target.coords or payload.coords,
        npcId    = target.npcId,
        zoneName = target.zoneName,
        model    = target.model,
        targetSrc= target.targetSrc,
        isPlayer = target.isPlayer,
    }
end

local function dispatchBridgeAction(src, target, action, payload)
    local extra = payload.extra or {}
    local tgt = buildTargetForBridge(target, payload)

    -- Per-Action Cooldown (falls definiert)
    if action.cooldown and action.cooldown > 0 then
        Perms = Perms or GMenu.Perms
        if Perms and Perms.checkActionCooldown then
            local okCool, remainSec = Perms.checkActionCooldown(src, action.id, action.cooldown)
            if not okCool then
                TriggerClientEvent('ox_lib:notify', src, {
                    type = 'warning',
                    description = ('Bitte warten (%.1fs)'):format(remainSec or action.cooldown),
                })
                return false, 'Action-Cooldown'
            end
        end
    end

    -- Bridge-spezifische requiredItems / requiredGroups Filter
    if action.requiredItems and not (Perms.hasItems and Perms.hasItems(src, action.requiredItems)) then
        return false, 'Fehlende Items'
    end

    -- Dispatch nach normalisiertem type-Feld
    local kind = action.type
    local event = action.event

    if kind == 'serverEvent' and event then
        TriggerEvent(event, src, tgt, extra, action.payload)
        return true

    elseif kind == 'clientEvent' and event then
        -- Beim auslosenden Spieler einen Event triggern
        TriggerClientEvent(event, src, tgt, extra, action.payload)
        return true

    elseif kind == 'command' and event then
        ExecuteCommand(event)
        return true

    elseif kind == 'notify' then
        local payloadMsg = action.payload or {}
        TriggerClientEvent('ox_lib:notify', src, {
            type        = payloadMsg.type or 'inform',
            title       = payloadMsg.title or action.label or 'Aktion',
            description = (type(payloadMsg) == 'string') and payloadMsg or (payloadMsg.text or payloadMsg.description or action.label or ''),
        })
        return true

    elseif kind == 'ui' then
        -- UI-Aktionen werden client-seitig ausgewertet (z.B. via clp_gmenu:ui:open)
        TriggerClientEvent('clp_gmenu:bridge:ui', src, action, tgt)
        return true

    elseif kind == 'handler' then
        -- onSelect-Callback existiert client-seitig (msgpack-serialisiert via ox_lib).
        -- Server triggert ein Client-Event, das die Bridge-Layer dort ausfuehrt.
        TriggerClientEvent('clp_gmenu:bridge:execute', src, action.id, tgt)
        return true
    end

    -- Fallback: ueber dispatchCustomAction (alte Whitelist-Variante)
    if action.type then
        return dispatchCustomAction(src, target, action)
    end

    return false, 'Bridge-Aktion: kein Dispatch-Pfad'
end

-- ============================================================
--  HAUPT-DISPATCH
-- ============================================================

--- Wird aus server/main.lua aufgerufen, wenn der Client eine Aktion ausloest.
--- payload = { actionId = 'pd_search', netId = ..., targetType = 'player'|'vehicle'|'ped'|'self', extra = {...} }
function Registry.execute(src, payload)
    if type(payload) ~= 'table' or type(payload.actionId) ~= 'string' then
        return false, 'Ungueltiges Payload'
    end

    -- Rate-Limit (Durchsatz-Begrenzung)
    if not Perms.consumeAction(src) then
        TriggerClientEvent('ox_lib:notify', src, { type = 'warning', description = 'Bitte langsamer.' })
        return false, 'Rate-Limit erreicht'
    end

    -- Aktions-Definition holen (Standard / Custom / Bridge)
    local action = Store.getAction(payload.actionId)
    local isBridge = false
    if not action and GMenu.Bridge and GMenu.Bridge.findAction then
        action = GMenu.Bridge.findAction(payload.actionId, {
            npcId    = payload.npcId,
            zoneName = payload.zoneName,
            model    = payload.model,
        })
        isBridge = action ~= nil
    end
    if not action then return false, 'Unbekannte Aktion' end

    -- Self-Aktionen: kein Ziel noetig, eigener Ped ist das Ziel
    local target
    if payload.targetType == 'self' then
        local ped = GetPlayerPed(src)
        target = {
            entity    = ped or 0,
            netId     = 0,
            type      = 'self',
            isPlayer  = true,
            targetSrc = src,
        }
    else
        target = resolveTarget(payload)
        -- Entity muss existieren ODER es ist ein Ped mit Fallback-Koordinaten
        -- ODER ein Zone/Objekt-Target (entity-frei zulaessig).
        -- ODER ein Bridge-Target mit npcId/model-Hint (z.B. registerModelAction
        -- auf nicht-vernetztes Objekt).
        local needsEntity = not (
            target.type == 'zone'
            or target.type == 'object'
            or target._pedCoords
            or (target.npcId and target.npcId ~= 0)
            or (target.model and target.model ~= 0)
            or target.zoneName
        )
        if needsEntity and (not target.entity or target.entity == 0) then
            return false, 'Ziel nicht aufloesbar'
        end

        -- Distanz-Pruefung (Anti-Exploit)
        if target.entity and target.entity ~= 0 and not Perms.checkDistance(src, target.entity) then
            Perms.audit(src, 'distance_violation', { actionId = payload.actionId, netId = payload.netId })
            return false, 'Zu weit entfernt'
        end
    end

    -- Zieltyp-Pruefung (Aktion erwartet: target = 'player'|'vehicle'|'ped'|'object'|'zone'|'self'|'both'|'any')
    if action.target and action.target ~= 'both' and action.target ~= 'any' then
        local compatible = (action.target == target.type)
            or (action.target == 'player' and target.type == 'ped')
            or (action.target == 'ped' and target.type == 'player')
        if not compatible then
            return false, ('Aktion erwartet %s, aber Ziel ist %s'):format(action.target, target.type)
        end
    end

    -- Berechtigung + Aktions-Zuweisung pruefen
    -- Custom-Aktionen haben ggf. keinen permission-Key -> nur Zuweisung pruefen
    if action.permission and not Perms.hasPermission(src, action.permission) then
        return false, 'Fehlende Berechtigung: ' .. action.permission
    end
    if not Perms.hasAction(src, payload.actionId, target.type, {
        npcId    = target.npcId,
        zoneName = target.zoneName,
        model    = target.model,
    }) then
        return false, 'Aktion nicht deinem Job/Rang zugewiesen'
    end

    -- Protokoll (nur kritische Aktionen — mit Berechtigung oder Admin)
    if action.permission then
        Perms.audit(src, 'action_executed', {
            actionId = payload.actionId,
            target   = target.type,
            netId    = target.netId,
            targetSrc= target.targetSrc,
        })
    end

    -- ============================================================
    -- Eigentliche Ausfuehrung (kann durch Approval-Gate zeitversetzt werden)
    -- ============================================================
    local function runFinal()
        if isBridge then
            return dispatchBridgeAction(src, target, action, payload)
        end
        if action.handler and handlers[action.handler] then
            local ok, err = pcall(handlers[action.handler], src, target, payload.extra or {}, action)
            if not ok then
                print(('^1[clp_gmenu]^0 Handler "%s" Fehler: %s'):format(action.handler, tostring(err)))
                return false, 'Handler-Fehler'
            end
            return err == nil or err == true or type(err) == 'table'
        end
        if action.type then
            return dispatchCustomAction(src, target, action)
        end
        return false, 'Kein Handler gefunden'
    end

    -- ============================================================
    -- Approval-Gate: action.requiresApproval == true erfordert J/N vom Empfaenger
    -- (gilt nur fuer Spieler-Targets, nicht fuer self/object/zone/ped/vehicle)
    -- ============================================================
    if action.requiresApproval and target.isPlayer and target.targetSrc and target.targetSrc ~= src then
        if not GMenu.Approvals or not GMenu.Approvals.request then
            -- Module noch nicht geladen -> direkt ausfuehren (degradiert sicher)
            return runFinal()
        end
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'inform',
            description = 'Anfrage gesendet, warte auf Antwort...',
        })
        GMenu.Approvals.request(src, target.targetSrc, {
            actionId    = payload.actionId,
            actionLabel = action.label or payload.actionId,
        }, function(accepted, reason)
            if accepted then
                runFinal()
            else
                local msg = 'Anfrage wurde abgelehnt.'
                if reason == 'timeout' then msg = 'Anfrage abgelaufen.'
                elseif reason == 'too_far' then msg = 'Empfaenger zu weit weg.'
                elseif reason == 'offline' then msg = 'Empfaenger offline.'
                end
                TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = msg })
            end
        end)
        return true
    end

    return runFinal()
end

-- ============================================================
--  GENERISCHE HANDLER (immer verfuegbar)
-- ============================================================

Registry.register('generic_notify', function(src, target, payload, action)
    local msg = (payload and payload.text) or 'Hallo!'
    TriggerClientEvent('ox_lib:notify', src, { type = 'inform', title = action.label, description = msg })
    if target.targetSrc then
        TriggerClientEvent('ox_lib:notify', target.targetSrc, { type = 'inform', title = action.label, description = msg })
    end
    return true
end)

Registry.register('generic_command', function(src, target, payload, action)
    local cmd = (payload and payload.command) or ''
    if not U.tableContains(Config.AllowedCustomCommands, cmd) then
        return false, 'Befehl nicht in Whitelist'
    end
    ExecuteCommand(cmd)
    return true
end)

Registry.register('generic_event', function(src, target, payload, action)
    local evt = (payload and payload.event) or ''
    if not U.tableContains(Config.AllowedCustomEvents, evt) then
        return false, 'Event nicht in Whitelist'
    end
    TriggerEvent(evt, src, target, payload.args or {})
    return true
end)
