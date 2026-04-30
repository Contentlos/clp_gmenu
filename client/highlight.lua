--[[
    clp_gmenu - Visuelles Hervorhebungssystem

    Fahrzeuge:  SetEntityDrawOutline mit pulsierender Transparenz
    Personen:   Bodenkreis (Marker 25) + Pfeil ueber Kopf (Marker 20)
                Beide animiert, mit Ein-/Ausblendung beim Wechsel.
]]

local R = GMenu.Raycast

-- Lokalisierte Natives
local SetEntityDrawOutline      = SetEntityDrawOutline
local SetEntityDrawOutlineColor = SetEntityDrawOutlineColor
local SetEntityDrawOutlineShader= SetEntityDrawOutlineShader
local DrawMarker                = DrawMarker
local GetEntityCoords           = GetEntityCoords
local DoesEntityExist           = DoesEntityExist
local GetGameTimer              = GetGameTimer

-- ============================================================
--  STATE
-- ============================================================

local activeVehicle = nil    -- Aktuell hervorgehobenes Fahrzeug
local activePed     = nil    -- Aktuell markierte Person
local fadeStart     = 0
local fading        = 'in'   -- 'in' | 'out' | 'idle'
local fadeAlpha     = 0      -- 0..255

-- ============================================================
--  HILFSFUNKTIONEN
-- ============================================================

local function clearVehicle()
    if activeVehicle and DoesEntityExist(activeVehicle) then
        SetEntityDrawOutline(activeVehicle, false)
    end
    activeVehicle = nil
end

local function clearPed()
    activePed = nil
end

local function clearAll()
    clearVehicle()
    clearPed()
end

local function fadeMs()
    return Config.HighlightFadeMs or 120
end

-- ============================================================
--  RAYCAST-ABONNEMENT
-- ============================================================

R.onChange(function(newTarget, prevTarget)
    -- Ausblendung fuer altes Ziel
    if prevTarget then
        clearVehicle()
        -- Person wird im Render-Loop transparent ausgeblendet
    end

    fadeStart = GetGameTimer()
    fadeAlpha = 0

    if not newTarget then
        fading = 'out'
        clearAll()
        return
    end

    fading = 'in'

    if newTarget.type == 'vehicle' then
        clearPed()
        activeVehicle = newTarget.entity
    elseif newTarget.type == 'player' or newTarget.type == 'ped' then
        clearVehicle()
        activePed = newTarget.entity
    end
end)

-- ============================================================
--  RENDER-SCHLEIFE (Fahrzeug-Umriss)
-- ============================================================
--  Die Farben sind Tabelle.r/g/b (0..255). Umriss-Farbe reagiert auf
--  Pulsieren, Ein-/Ausblendung und Live-Updates ueber Einstellungen.

CreateThread(function()
    while true do
        if not activeVehicle then
            Wait(150)
        else
            if not DoesEntityExist(activeVehicle) then
                clearVehicle()
                Wait(100)
            else
                local color = GMenu.GetColor('outline')
                local alpha = 255

                -- Pulsierender Effekt
                if Config.OutlinePulse then
                    local t = (GetGameTimer() % 1500) / 1500.0
                    local s = math.sin(t * math.pi * 2.0)
                    alpha = math.floor(160 + s * 60)            -- 100..220
                end

                -- Fade-In/Out
                if fading == 'in' then
                    local p = math.min(1.0, (GetGameTimer() - fadeStart) / fadeMs())
                    alpha = math.floor(alpha * p)
                    if p >= 1 then fading = 'idle' end
                end

                SetEntityDrawOutlineShader(0)
                SetEntityDrawOutline(activeVehicle, true)
                SetEntityDrawOutlineColor(color.r, color.g, color.b, math.max(40, alpha))

                Wait(0)
            end
        end
    end
end)

-- ============================================================
--  RENDER-SCHLEIFE (Personen-Marker + Pfeil)
-- ============================================================

CreateThread(function()
    while true do
        if not activePed or not DoesEntityExist(activePed) then
            Wait(150)
        else
            local coords = GetEntityCoords(activePed)
            local color = GMenu.GetColor('marker')

            -- Fade-In
            local alpha = 200
            if fading == 'in' then
                local p = math.min(1.0, (GetGameTimer() - fadeStart) / fadeMs())
                alpha = math.floor(200 * p)
                if p >= 1 then fading = 'idle' end
            end

            local now = GetGameTimer() / 1000.0

            -- Bodenkreis (Marker 25 = flacher Ring)
            local circleRot = 0.0
            if Config.MarkerCircleSpin then circleRot = (now * 60.0) % 360.0 end
            DrawMarker(
                25,                                          -- Type 25: ringFlat (kreisformig)
                coords.x, coords.y, coords.z - 0.97,         -- knapp ueberm Boden
                0.0, 0.0, 0.0,                               -- direction
                0.0, 0.0, circleRot,                         -- rotation
                0.85, 0.85, 0.5,                             -- scale
                color.r, color.g, color.b, alpha,
                false, false, 2, false, nil, nil, false
            )

            -- Pfeil ueber dem Kopf (Marker 20 = Pfeil nach oben, gespiegelt = nach unten zeigend)
            local arrowZ = coords.z + 1.15
            if Config.MarkerArrowBobbing then
                arrowZ = arrowZ + math.sin(now * 4.0) * 0.06
            end
            DrawMarker(
                20,                                          -- Type 20: chevron-up
                coords.x, coords.y, arrowZ,
                0.0, 0.0, 0.0,
                180.0, 0.0, 0.0,                             -- 180 X-rot -> Pfeil zeigt nach unten
                0.40, 0.40, 0.40,
                color.r, color.g, color.b, math.min(255, alpha + 40),
                true,  -- bobUpAndDown (Native-Bobbing zusaetzlich)
                false, 2, false, nil, nil, false
            )

            Wait(0)
        end
    end
end)

-- ============================================================
--  3D-TEXT "[G]" UEBER DEM ZIEL
-- ============================================================
--  Zeigt einen schwebenden Hinweis "[G] Interagieren" an,
--  wenn ein Ziel erkannt wird und das Menue NICHT offen ist.

local function drawText3D(x, y, z, text, scale, r, g, b, a)
    SetTextScale(scale, scale)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(r, g, b, a)
    SetTextDropshadow(1, 0, 0, 0, 200)
    SetTextEdge(1, 0, 0, 0, 200)
    SetTextDropShadow()
    SetTextOutline()
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString(text)
    SetDrawOrigin(x, y, z, 0)
    DrawText(0.0, 0.0)
    ClearDrawOrigin()
end

CreateThread(function()
    local M = GMenu.Menu
    while true do
        local target = R.current
        if not target or not target.entity or not DoesEntityExist(target.entity) then
            Wait(200)
        elseif M and M.open then
            -- Menue ist offen -> kein 3D-Text noetig
            Wait(100)
        else
            local coords = GetEntityCoords(target.entity)
            local color = GMenu.GetColor('ui')

            -- Position: ueber dem Ziel (Fahrzeug etwas hoeher als Person)
            local zOff = target.type == 'vehicle' and 1.5 or 1.3
            local keyLabel = Config.OpenKey or 'G'
            drawText3D(
                coords.x, coords.y, coords.z + zOff,
                ('[%s] Interagieren'):format(keyLabel),
                0.35,
                color.r, color.g, color.b, 220
            )
            Wait(0) -- Muss jeden Frame zeichnen
        end
    end
end)

-- ============================================================
--  AUFRAEUMEN BEIM STOPPEN
-- ============================================================

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    clearAll()
end)

print('^2[clp_gmenu]^0 Hervorhebung geladen.')
