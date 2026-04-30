--[[
    clp_gmenu - Server Job Handler: NPC-Interaktionen

    Handler fuer allgemeine NPC/Ped-Aktionen.
    Diese wirken auf nicht-spielergesteuerte Peds (Ambient, Script-NPCs etc.).
]]

local Registry = GMenu.Registry

local function notify(src, type_, msg)
    TriggerClientEvent('ox_lib:notify', src, { type = type_, description = msg })
end

-- ============================================================
--  npc_talk - NPC ansprechen (Client-Event zur Darstellung)
-- ============================================================
Registry.register('npc_talk', function(src, target, payload, action)
    -- Generisches Event fuer andere Ressourcen / Client-Handler
    TriggerClientEvent('clp_gmenu:npc:talk', src, {
        netId  = target.netId,
        model  = target._pedModel,
        coords = target._pedCoords,
    })
    notify(src, 'inform', 'Du sprichst mit dem NPC.')
    return true
end)

-- ============================================================
--  npc_trade - Mit NPC handeln (Bridge zu Shop-Systemen)
-- ============================================================
Registry.register('npc_trade', function(src, target, payload, action)
    -- Bridge: Andere Ressourcen koennen dieses Event abfangen
    TriggerClientEvent('clp_gmenu:npc:trade', src, {
        netId  = target.netId,
        model  = target._pedModel,
        coords = target._pedCoords,
    })
    notify(src, 'inform', 'Handeln gestartet.')
    return true
end)

-- ============================================================
--  npc_rob - NPC ausrauben (Beispiel, erweiterbar)
-- ============================================================
Registry.register('npc_rob', function(src, target, payload, action)
    -- Sicherheits-Hinweis: sollte mit Cooldown/Polizei-Alert ergaenzt werden
    TriggerClientEvent('clp_gmenu:npc:rob', src, {
        netId  = target.netId,
        model  = target._pedModel,
        coords = target._pedCoords,
    })
    notify(src, 'inform', 'Ueberfall gestartet...')
    return true
end)

print('^2[clp_gmenu]^0 NPC-Handler geladen.')
