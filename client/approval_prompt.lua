--[[
    clp_gmenu - Approval Prompt (J / N)

    Generischer J/N-Bestaetigungs-Prompt fuer eingehende Anfragen
    (Handschlag, Visitenkarte, Custom-Actions mit "requiresApproval").

    Native Draw-Calls (kein NUI noetig). Spieler druecken physisch:
      - J  -> Annehmen
      - N  -> Ablehnen
      - Timeout (Default 10s) -> Ablehnen automatisch

    Public API:
      AP.show({ title, body, fromLabel, timeoutMs }, onAnswer)
      AP.cancel()
]]

GMenu = GMenu or {}
GMenu.ApprovalPrompt = {}
local AP = GMenu.ApprovalPrompt

local active = nil  -- { title, body, fromLabel, expiresAt, cb }

-- Native key-codes (FiveM "InputKey" / Control)
local KEY_J = 36   -- 0x4A (Keyboard J)
local KEY_N = 249  -- 0x4E (Keyboard N) - using INPUT group input value

-- Tatsaechliche Raw-Keyboard Codes:
--   J = 0x4A = 74    (mit IsDisabledControlPressed Group 0)
--   N = 0x4E = 78
-- IsControlJustPressed funktioniert hier nicht zuverlaessig fuer alle Tasten,
-- daher nutzen wir IsRawKeyPressed mit Edge-Detection.

local lastJState = false
local lastNState = false

local function isKeyPressedEdge(vk, lastFlag)
    local now = IsRawKeyPressed(vk)
    if now and not lastFlag then
        return true, true
    end
    return false, now
end

-- ============================================================
--  DRAW LOOP
-- ============================================================

local function drawPrompt(p)
    -- Kasten oben mittig
    local cx, cy = 0.5, 0.10
    local w, h = 0.32, 0.13

    -- Hintergrund (Boxen)
    DrawRect(cx, cy, w, h, 0, 0, 0, 200)
    DrawRect(cx, cy - h*0.5 + 0.001, w, 0.003, 0, 255, 180, 255)  -- Akzent-Strich oben

    -- Titel
    SetTextFont(4)
    SetTextScale(0.0, 0.40)
    SetTextColour(0, 255, 180, 255)
    SetTextProportional(true)
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString(p.title or 'Anfrage')
    DrawText(cx, cy - h*0.5 + 0.012)

    -- Fromlabel
    if p.fromLabel and p.fromLabel ~= '' then
        SetTextFont(4)
        SetTextScale(0.0, 0.32)
        SetTextColour(255, 255, 255, 220)
        SetTextProportional(true)
        SetTextEntry('STRING')
        SetTextCentre(true)
        AddTextComponentString(p.fromLabel)
        DrawText(cx, cy - h*0.5 + 0.034)
    end

    -- Body
    if p.body and p.body ~= '' then
        SetTextFont(4)
        SetTextScale(0.0, 0.34)
        SetTextColour(220, 220, 220, 220)
        SetTextProportional(true)
        SetTextEntry('STRING')
        SetTextCentre(true)
        AddTextComponentString(p.body)
        DrawText(cx, cy - h*0.5 + 0.058)
    end

    -- Tasten-Hint (J Annehmen / N Ablehnen)
    SetTextFont(4)
    SetTextScale(0.0, 0.36)
    SetTextProportional(true)
    SetTextEntry('STRING')
    SetTextColour(120, 255, 180, 255)
    SetTextCentre(true)
    AddTextComponentString('[J] Annehmen')
    DrawText(cx - w*0.22, cy + h*0.5 - 0.030)

    SetTextFont(4)
    SetTextScale(0.0, 0.36)
    SetTextProportional(true)
    SetTextEntry('STRING')
    SetTextColour(255, 120, 120, 255)
    SetTextCentre(true)
    AddTextComponentString('[N] Ablehnen')
    DrawText(cx + w*0.22, cy + h*0.5 - 0.030)

    -- Timer-Bar
    local left = math.max(0, p.expiresAt - GetGameTimer())
    local total = p.timeoutMs or 10000
    local pct = math.max(0.0, math.min(1.0, left / total))
    local barW = (w - 0.02) * pct
    local barX = cx - (w - 0.02)*0.5 + barW*0.5
    DrawRect(barX, cy + h*0.5 - 0.005, barW, 0.004, 0, 255, 180, 200)
end

-- ============================================================
--  THREAD
-- ============================================================

CreateThread(function()
    while true do
        if active then
            local p = active
            -- Render
            drawPrompt(p)

            -- Timeout?
            if GetGameTimer() >= p.expiresAt then
                local cb = p.cb
                active = nil
                if type(cb) == 'function' then pcall(cb, false, 'timeout') end
            else
                -- Key Edge Detection
                local jPressed
                jPressed, lastJState = isKeyPressedEdge(0x4A, lastJState)
                local nPressed
                nPressed, lastNState = isKeyPressedEdge(0x4E, lastNState)

                if jPressed then
                    local cb = p.cb
                    active = nil
                    if type(cb) == 'function' then pcall(cb, true, 'accepted') end
                elseif nPressed then
                    local cb = p.cb
                    active = nil
                    if type(cb) == 'function' then pcall(cb, false, 'declined') end
                end
            end

            Wait(0)
        else
            lastJState = false
            lastNState = false
            Wait(250)
        end
    end
end)

-- ============================================================
--  PUBLIC
-- ============================================================

function AP.show(opts, onAnswer)
    if type(opts) ~= 'table' then opts = {} end
    if active and active.cb then
        -- Vorherige Anfrage abbrechen (declined)
        local prev = active
        active = nil
        pcall(prev.cb, false, 'cancelled')
    end
    local timeout = tonumber(opts.timeoutMs) or 10000
    active = {
        title     = opts.title or 'Anfrage',
        body      = opts.body or '',
        fromLabel = opts.fromLabel or '',
        timeoutMs = timeout,
        expiresAt = GetGameTimer() + timeout,
        cb        = onAnswer,
    }
end

function AP.cancel()
    if active then
        local cb = active.cb
        active = nil
        if type(cb) == 'function' then pcall(cb, false, 'cancelled') end
    end
end

function AP.isActive()
    return active ~= nil
end
