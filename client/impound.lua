--[[
    clp_gmenu - Impound Client

    - Spawnt impoundierte Fahrzeuge physisch in den Hof-Slots
    - Verriegelt sie & blockiert den Motor (kein Einsteigen moeglich)
    - Bietet Pay-Prompt (Taste E) wenn Spieler nahe ist
    - Wenn bezahlt: Fahrzeug freigegeben, Spieler kann einsteigen
    - Wenn der Spieler ein freigegebenes Fahrzeug zum Hof zurueckfaehrt
      und aussteigt, wird ein "Einlagern"-Prompt angezeigt
]]

if not Config.Impound or not Config.Impound.Enabled then return end

local Imp = {}
local lotBlips     = {}
local spawnedVehs  = {}             -- plate -> entity
local spawnedByEnt = {}             -- entity -> plate
local impState     = {}             -- plate -> entry (synced from server)
local recentlyReleased = {}         -- plate -> os.time() (paid by this client)

-- ============================================================
--  BLIPS / LOTS
-- ============================================================

CreateThread(function()
    for _, lot in pairs(Config.Impound.Lots) do
        if lot.blip and lot.slots and lot.slots[1] then
            local first = lot.slots[1].coords
            local b = AddBlipForCoord(first.x, first.y, first.z)
            SetBlipSprite(b, lot.blip.sprite or 68)
            SetBlipColour(b, lot.blip.color or 47)
            SetBlipScale (b, lot.blip.scale or 0.85)
            SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(lot.blip.label or lot.label or 'Abschlepphof')
            EndTextCommandSetBlipName(b)
            lotBlips[#lotBlips+1] = b
        end
    end
end)

-- ============================================================
--  SPAWN / DESPAWN
-- ============================================================

local function loadModel(hash)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return false end
    RequestModel(hash)
    local t = GetGameTimer()
    while not HasModelLoaded(hash) and (GetGameTimer() - t) < 5000 do
        Wait(20)
    end
    return HasModelLoaded(hash)
end

local function spawnVehicleForEntry(plate, entry)
    if spawnedVehs[plate] then return spawnedVehs[plate] end
    local lot = Config.Impound.Lots[entry.lotId]
    if not lot then return nil end
    local slot = lot.slots[entry.slotIndex]
    if not slot then return nil end
    local hash = entry.modelHash or GetHashKey('tow')
    if not loadModel(hash) then return nil end

    local c = slot.coords
    local veh = CreateVehicle(hash, c.x, c.y, c.z, c.w or 0.0, false, false)
    if veh == 0 then return nil end

    SetVehicleNumberPlateText(veh, plate)
    SetVehicleOnGroundProperly(veh)
    SetVehicleDoorsLocked(veh, 2)                     -- locked
    SetVehicleEngineOn(veh, false, true, true)
    SetEntityAsMissionEntity(veh, true, true)
    FreezeEntityPosition(veh, true)
    SetVehicleNumberPlateTextIndex(veh, 0)
    SetModelAsNoLongerNeeded(hash)

    spawnedVehs[plate] = veh
    spawnedByEnt[veh] = plate
    return veh
end

local function despawnVehicle(plate)
    local veh = spawnedVehs[plate]
    if veh and DoesEntityExist(veh) then
        spawnedByEnt[veh] = nil
        SetEntityAsMissionEntity(veh, true, true)
        DeleteVehicle(veh)
    end
    spawnedVehs[plate] = nil
end

local function syncSpawns()
    -- Despawn was nicht mehr im State ist.
    -- Plates erst sammeln, dann despawnen -- in Lua 5.4 ist Mutation
    -- waehrend pairs() undefiniert (Eintraege koennten uebersprungen werden).
    local toDespawn = {}
    for plate, _ in pairs(spawnedVehs) do
        if not impState[plate] then
            toDespawn[#toDespawn + 1] = plate
        end
    end
    for i = 1, #toDespawn do
        despawnVehicle(toDespawn[i])
    end
    -- Spawn was im State ist aber noch nicht da
    for plate, entry in pairs(impState) do
        if not spawnedVehs[plate] then
            spawnVehicleForEntry(plate, entry)
        end
    end
end

RegisterNetEvent('clp_gmenu:impound:sync', function(state)
    if type(state) ~= 'table' then return end
    impState = state
    syncSpawns()
end)

-- ============================================================
--  CINEMATIC RELEASE (C11)
--  Wenn der Spieler ein Auto auskauft:
--    1. Kamera schwenkt an `lot.releaseCam` (Position + look-Heading)
--    2. Fahrzeug wird entriegelt + Hupe (kurz)
--    3. Nach ~3.5s: Kamera-Fade zurueck zur Spielerperspektive
-- ============================================================

local function quatLookFrom(camCoords, heading)
    -- Heading -> rotation Z. Pitch leicht nach unten (-12°) damit Auto im Bild
    -- bleibt. Wir setzen Rotation als (pitch, roll, yaw).
    return vector3(-12.0, 0.0, heading or 0.0)
end

local function cinematicRelease(plate, lotId)
    local lot = Config.Impound.Lots[lotId]
    local cam = lot and lot.releaseCam
    local veh = spawnedVehs[plate]

    -- Vehicle entriegeln (synchron, so dass es waehrend der Cam schon befahrbar ist)
    if veh and DoesEntityExist(veh) then
        SetVehicleDoorsLocked(veh, 1)
        SetVehicleEngineOn(veh, true, true, false)
        FreezeEntityPosition(veh, false)
        StartVehicleHorn(veh, 600, joaat('NORMAL'), false)
    end

    if not cam then return end

    local cc = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    if cc == 0 then return end
    SetCamCoord(cc, cam.x, cam.y, cam.z)
    local rot = quatLookFrom(cam, cam.w or 0.0)
    SetCamRot(cc, rot.x, rot.y, rot.z, 2)
    SetCamFov(cc, 55.0)
    SetCamActive(cc, true)
    RenderScriptCams(true, true, 600, true, true)

    SetTimeout(3500, function()
        RenderScriptCams(false, true, 600, true, true)
        DestroyCam(cc, false)
    end)
end

RegisterNetEvent('clp_gmenu:impound:releaseConfirmed', function(plate, lotId)
    plate = plate and plate:upper() or ''
    recentlyReleased[plate] = GetGameTimer()
    cinematicRelease(plate, lotId)
    -- Server sendet ohnehin direkt impound:sync hinterher; safety:
    SetTimeout(900, function()
        despawnVehicle(plate)
        impState[plate] = nil
    end)
end)

-- Beim Resource-Stop: alles aufraeumen
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    -- Plates erst sammeln, dann despawnen (Lua 5.4: keine Mutation in pairs())
    local toClean = {}
    for plate, _ in pairs(spawnedVehs) do
        toClean[#toClean + 1] = plate
    end
    for i = 1, #toClean do
        despawnVehicle(toClean[i])
    end
    for _, b in ipairs(lotBlips) do RemoveBlip(b) end
end)

-- ============================================================
--  PAY-INTERAKTION
-- ============================================================

local function getNearestImpoundedVeh(playerCoords)
    local closest, closestDist, closestPlate
    for plate, veh in pairs(spawnedVehs) do
        if DoesEntityExist(veh) then
            local d = #(playerCoords - GetEntityCoords(veh))
            if d <= (Config.Impound.InteractDistance or 3.5) and (not closestDist or d < closestDist) then
                closest, closestDist, closestPlate = veh, d, plate
            end
        end
    end
    return closest, closestPlate
end

CreateThread(function()
    while true do
        local sleep = 750
        local ply = PlayerPedId()
        if not IsPedInAnyVehicle(ply, false) then
            local pos = GetEntityCoords(ply)
            local _, plate = getNearestImpoundedVeh(pos)
            if plate then
                sleep = 0
                local entry = impState[plate]
                if entry then
                    local txt = ('[E] %s freikaufen ($%d)'):format(plate, entry.fee or 0)
                    SetTextComponentFormat('STRING')
                    AddTextComponentString(txt)
                    DisplayHelpTextFromStringLabel(0, false, false, -1)
                    if IsControlJustReleased(0, 38) then    -- E
                        TriggerServerEvent('clp_gmenu:impound:requestRelease', plate)
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

-- ============================================================
--  EINLAGERUNG (Spieler faehrt zum Hof zurueck)
-- ============================================================

local function isAtAnyLot(coords)
    for lotId, lot in pairs(Config.Impound.Lots) do
        for _, slot in ipairs(lot.slots) do
            local d = #(coords - vector3(slot.coords.x, slot.coords.y, slot.coords.z))
            if d <= 6.0 then return lotId end
        end
    end
    return nil
end

CreateThread(function()
    while true do
        local sleep = 1500
        local ply = PlayerPedId()
        if IsPedInAnyVehicle(ply, false) then
            local veh = GetVehiclePedIsIn(ply, false)
            if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ply then
                local plate = (GetVehicleNumberPlateText(veh) or ''):gsub('%s+', ''):upper()
                if plate ~= '' and (recentlyReleased[plate] or 0) > 0 then
                    local lotId = isAtAnyLot(GetEntityCoords(veh))
                    if lotId then
                        sleep = 0
                        SetTextComponentFormat('STRING')
                        AddTextComponentString(('[H] %s einlagern (Abschlepphof %s)'):format(plate, lotId))
                        DisplayHelpTextFromStringLabel(0, false, false, -1)
                        if IsControlJustReleased(0, 74) then    -- H
                            -- Server-Event ZUERST, damit der Server-Distanz-Check
                            -- den Spieler noch im Fahrzeug sieht. TaskLeaveVehicle
                            -- danach, damit visuelle Animation nicht haengt.
                            TriggerServerEvent('clp_gmenu:impound:store', plate, lotId)
                            TaskLeaveVehicle(ply, veh, 0)
                            recentlyReleased[plate] = nil
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

-- ============================================================
--  INITIAL SYNC (beim Resource-Start)
-- ============================================================

CreateThread(function()
    Wait(2500)
    -- Server pusht state via 'clp_gmenu:impound:sync' beim Boot;
    -- als Fallback callback nachfragen:
    if lib and lib.callback then
        local list = lib.callback.await('clp_gmenu:impound:list', false, nil)
        if type(list) == 'table' then
            local map = {}
            for _, e in ipairs(list) do
                if e.plate then map[e.plate] = e end
            end
            impState = map
            syncSpawns()
        end
    end
end)

print('^2[clp_gmenu]^0 Impound client geladen.')

return Imp
