--[[
    clp_gmenu - Client Aktions-Dispatcher

    Wenn der Spieler eine Option ausgewaehlt hat, sammeln wir hier alle
    relevanten Daten (netId, Kennzeichen, etc.) und schicken sie an den Server.
]]

GMenu = GMenu or {}
GMenu.Actions = {}

local A = GMenu.Actions

-- ============================================================
--  EXECUTE
-- ============================================================

--- Wird von menu.lua aufgerufen, wenn der Spieler eine Option waehlt.
--- target enthaelt mindestens: { entity, type, netId, isPlayer? }
--- Der Server hat die Aktionsliste bereits validiert und gefiltert.
function A.execute(actionId, target)
    if not actionId or not target then return end

    local netId = target.netId
    -- Falls netId aus dem Menue-Snapshot vorhanden, direkt nutzen
    if (not netId or netId == 0) and target.entity and target.entity ~= 0 then
        if NetworkGetEntityIsNetworked(target.entity) then
            netId = NetworkGetNetworkIdFromEntity(target.entity)
        end
    end
    -- Spieler/Fahrzeuge brauchen zwingend eine netId; NPCs + Self duerfen ohne
    if (not netId or netId == 0) and target.type ~= 'ped' and target.type ~= 'self' then
        lib.notify({ type = 'error', description = 'Ziel ist nicht synchronisiert.' })
        return
    end

    -- Zusatzdaten je nach Zieltyp (nur fuer Anzeige, Server validiert erneut)
    local extra = {}
    if target.type == 'vehicle' and target.entity and target.entity ~= 0 then
        extra.plate = (GetVehicleNumberPlateText(target.entity) or ''):gsub('^%s*(.-)%s*$', '%1')
        extra.model = GetEntityModel(target.entity)
    end

    -- Ped-Fallback-Daten (Koordinaten + Modell fuer Server-Aufloesung)
    local pedCoords, pedModel
    if target.type == 'ped' and target.entity and target.entity ~= 0 then
        pedCoords = GetEntityCoords(target.entity)
        pedModel  = GetEntityModel(target.entity)
    end

    -- Server-Event ausloesen (Server fuehrt ALLE Pruefungen durch)
    TriggerServerEvent('clp_gmenu:executeAction', {
        actionId   = actionId,
        netId      = netId or 0,
        targetType = target.type,
        extra      = extra,
        pedCoords  = pedCoords,
        pedModel   = pedModel,
    })
end

-- ============================================================
--  Client-Hooks aus generic_event (vom Server weitergeleitet)
-- ============================================================

RegisterNetEvent('clp_gmenu:custom:noop', function() end)

print('^2[clp_gmenu]^0 Aktionen geladen.')
