--[[
    clp_gmenu - Client Job Handler: NPC-Interaktionen

    Empfaengt Events von server/jobs/npc.lua und fuehrt
    clientseitige Aktionen aus (Animationen, UI, etc.).
    Andere Ressourcen koennen diese Events ebenfalls abfangen.
]]

-- ============================================================
--  npc_talk - NPC-Gespraech
-- ============================================================
RegisterNetEvent('clp_gmenu:npc:talk', function(data)
    -- Beispiel: Spieler dreht sich zum NPC und spielt Rede-Animation
    if data and data.netId and data.netId ~= 0 then
        local entity = NetworkGetEntityFromNetworkId(data.netId)
        if entity and entity ~= 0 and DoesEntityExist(entity) then
            TaskTurnPedToFaceEntity(PlayerPedId(), entity, 1000)
        end
    end
    -- Platzhalter: Andere Ressourcen koennen hier anknuepfen
end)

-- ============================================================
--  npc_trade - NPC-Handel
-- ============================================================
RegisterNetEvent('clp_gmenu:npc:trade', function(data)
    -- Bridge: Hier kann ein Shop-System gestartet werden
    -- z.B. TriggerEvent('myshop:open', data.model, data.coords)
end)

-- ============================================================
--  npc_rob - NPC-Ueberfall
-- ============================================================
RegisterNetEvent('clp_gmenu:npc:rob', function(data)
    -- Beispiel: NPC reagiert erschrocken + Hande hoch Animation
    if data and data.netId and data.netId ~= 0 then
        local entity = NetworkGetEntityFromNetworkId(data.netId)
        if entity and entity ~= 0 and DoesEntityExist(entity) then
            -- NPC: Hande hoch Animation
            TaskPlayAnim(entity, 'random@mugging3', 'handsup_standing_base',
                8.0, -8.0, -1, 49, 0, false, false, false)
        end
    end
end)

print('^2[clp_gmenu]^0 NPC-Client-Handler geladen.')
