--[[
    clp_gmenu - Client Job Handler: SELF-Aktionen

    Emote-Ausfuehrung und andere clientseitige Self-Aktionen.
]]

local EMOTES = {
    sit = {
        dict = 'anim@heists@heist_corona@single_team',
        anim = 'single_team_loop_boss',
        flag = 1,
    },
    wave = {
        dict = 'friends@frj@ig_1',
        anim = 'wave_a',
        flag = 49,
    },
    surrender = {
        dict = 'random@mugging3',
        anim = 'handsup_standing_base',
        flag = 49,
    },
}

local activeEmote = nil

RegisterNetEvent('clp_gmenu:self:emote', function(emoteId)
    local ped = PlayerPedId()
    if not ped or ped == 0 then return end

    -- Laufende Emote abbrechen
    if activeEmote then
        ClearPedTasks(ped)
        activeEmote = nil
        return
    end

    local e = EMOTES[emoteId]
    if not e then return end

    lib.requestAnimDict(e.dict)
    TaskPlayAnim(ped, e.dict, e.anim, 8.0, -8.0, -1, e.flag, 0, false, false, false)
    activeEmote = emoteId

    -- Nach 30s automatisch beenden
    SetTimeout(30000, function()
        if activeEmote == emoteId then
            ClearPedTasks(PlayerPedId())
            activeEmote = nil
        end
    end)
end)

print('^2[clp_gmenu]^0 Self-Client-Handler geladen.')
