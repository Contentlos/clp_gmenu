--[[
    clp_gmenu - Client Job: AMBULANCE
]]

-- ============================================================
--  REVIVE - Spieler Native-Wiederbelebung (Fallback wenn esx_ambulancejob fehlt)
-- ============================================================
RegisterNetEvent('clp_gmenu:ems:revive', function()
    local ped = PlayerPedId()
    NetworkResurrectLocalPlayer(GetEntityCoords(ped), GetEntityHeading(ped), true, false)
    SetPlayerInvincible(PlayerId(), false)
    ClearPedBloodDamage(ped)
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    lib.notify({ type = 'success', title = 'Rettungsdienst', description = 'Du wurdest wiederbelebt.' })
end)

-- ============================================================
--  TRANSPORT - GPS-Marker zum Krankenhaus (Pillbox als Default)
-- ============================================================
RegisterNetEvent('clp_gmenu:ems:transport', function()
    SetNewWaypoint(307.7, -1433.4)
    lib.notify({ type = 'inform', title = 'Rettungsdienst', description = 'Krankenhaus markiert auf der Karte.' })
end)
