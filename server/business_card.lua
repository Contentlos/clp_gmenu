--[[
    clp_gmenu - Business Card Item (ox_inventory)

    Erzeugt ein "business_card" Item, das beim Geben automatisch mit
    Char-Metadaten (Name/Job/Phone/Identifier) befuellt wird.

    Kompatibel mit:
      - ox_inventory  (preferred): Item via createItem registriert + Use-Hook
      - ESX Inventar  (Fallback): Item-Name + Useable-Item Trigger

    Ausloesung:
      - Spieler waehlt im G-Menue "Visitenkarte zeigen" -> erhaelt Card mit Metadata
      - Wenn ox_inventory: Card kann angeklickt werden -> Show-Detail-Notify

    Item-Metadata-Struktur:
      {
          firstName  = 'John',
          lastName   = 'Doe',
          job        = 'police',
          jobLabel   = 'Polizei',
          phone      = '555-1234',
          identifier = 'char1:abcdef',
          handedAt   = '2025-04-30 12:34:56',
      }

    Exports:
      exports.clp_gmenu:giveBusinessCard(srcGiver, srcReceiver) -> bool
]]

GMenu = GMenu or {}
GMenu.BusinessCard = {}
local BC = GMenu.BusinessCard

local ITEM_NAME = 'business_card'
local ESX

CreateThread(function()
    if GetResourceState('es_extended') == 'started' then
        ESX = exports['es_extended']:getSharedObject()
    end
end)

local function hasOxInventory()
    return GetResourceState('ox_inventory') == 'started' and exports.ox_inventory ~= nil
end

-- ============================================================
--  METADATA-BUILDER
-- ============================================================

local function buildMetadata(src)
    if not ESX then return nil end
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return nil end

    local meta = {
        identifier = xPlayer.identifier,
        job        = xPlayer.job and xPlayer.job.name or 'unemployed',
        jobLabel   = xPlayer.job and xPlayer.job.label or 'Arbeitslos',
        handedAt   = os.date('%Y-%m-%d %H:%M:%S'),
    }
    -- Try to fetch character name from ESX or DB
    if xPlayer.get and xPlayer.get('firstName') then
        meta.firstName = xPlayer.get('firstName')
        meta.lastName  = xPlayer.get('lastName') or ''
    elseif xPlayer.getName then
        local full = xPlayer.getName() or 'Unbekannt'
        local fn, ln = full:match('^(%S+)%s+(.+)$')
        meta.firstName = fn or full
        meta.lastName  = ln or ''
    else
        meta.firstName = 'Unbekannt'
        meta.lastName  = ''
    end
    -- Optional phone (ESX-Variants: lb-phone, qs-smartphone, ...)
    if xPlayer.get and xPlayer.get('phone') then
        meta.phone = xPlayer.get('phone')
    end
    meta.description = ('%s %s%s'):format(
        meta.firstName, meta.lastName,
        meta.jobLabel and (' | ' .. meta.jobLabel) or ''
    )
    meta.label = ('Visitenkarte: %s %s'):format(meta.firstName, meta.lastName or '')
    return meta
end

-- ============================================================
--  GIVE-CARD-FLOW
-- ============================================================

function BC.give(srcGiver, srcReceiver)
    if not srcGiver or not srcReceiver then return false end
    if srcGiver == srcReceiver then return false end

    local meta = buildMetadata(srcGiver)
    if not meta then return false end

    if hasOxInventory() then
        local ok = exports.ox_inventory:AddItem(srcReceiver, ITEM_NAME, 1, meta)
        if ok then return true end
    end

    -- Fallback: ESX inventory (kein Metadata-Support, nur Item-Add)
    if ESX then
        local xR = ESX.GetPlayerFromId(srcReceiver)
        if xR then
            local item = xR.getInventoryItem and xR.getInventoryItem(ITEM_NAME)
            if item then
                xR.addInventoryItem(ITEM_NAME, 1)
                -- Speichere meta in user_settings als hint
                if GMenu.SqlStore and GMenu.SqlStore.saveUserSettings then
                    GMenu.SqlStore.saveUserSettings(xR.identifier, {
                        last_card = meta,
                    })
                end
                return true
            end
        end
    end
    return false
end

-- Event-Trigger (vom Identity-System, wenn Spieler "Visitenkarte zeigen" waehlt)
-- Anti-Exploit:
--   - Rate-Limit (P.consumeAction) verhindert Spam
--   - Distanz-Check zwischen Giver und Receiver (max 5m) verhindert Cross-Map-Abuse
--   - receiverSrc muss ein gueltiger, online Spieler sein
RegisterNetEvent('clp_gmenu:identity:giveBusinessCard', function(receiverSrc)
    local src = source
    if not src or src == 0 then return end
    receiverSrc = tonumber(receiverSrc)
    if not receiverSrc or receiverSrc == src then return end

    local Perms = GMenu and GMenu.Perms
    if Perms and Perms.consumeAction and not Perms.consumeAction(src) then
        TriggerClientEvent('clp_gmenu:notify', src, {
            type = 'error', description = 'Zu viele Anfragen, kurz warten.',
        })
        return
    end

    local giverPed    = GetPlayerPed(src)
    local receiverPed = GetPlayerPed(receiverSrc)
    if not giverPed or not receiverPed or giverPed == 0 or receiverPed == 0 then return end
    local d = #(GetEntityCoords(giverPed) - GetEntityCoords(receiverPed))
    if d > 5.0 then
        TriggerClientEvent('clp_gmenu:notify', src, {
            type = 'error', description = 'Empfaenger ist zu weit entfernt.',
        })
        return
    end

    local ok = BC.give(src, receiverSrc)
    TriggerClientEvent('clp_gmenu:notify', src, {
        type = ok and 'success' or 'error',
        description = ok and 'Visitenkarte ueberreicht.' or 'Konnte Visitenkarte nicht uebergeben.',
    })
    if ok then
        local meta = buildMetadata(src)
        if meta then
            TriggerClientEvent('clp_gmenu:businessCard:show', receiverSrc, meta)
        else
            TriggerClientEvent('clp_gmenu:notify', receiverSrc, {
                type = 'inform',
                description = 'Du hast eine Visitenkarte erhalten.',
            })
        end
    end
end)

-- ============================================================
--  USE-HOOK (ox_inventory)
-- ============================================================

CreateThread(function()
    Wait(1500)
    if not hasOxInventory() then return end

    -- Item registrieren falls noch nicht vorhanden
    pcall(function()
        local items = exports.ox_inventory:Items()
        if not items[ITEM_NAME] then
            -- ox_inventory items werden ueblicherweise via items.lua deklariert.
            -- Wir loggen nur einen Hinweis, weil dynamic-create nicht garantiert ist.
            print(('^3[clp_gmenu]^0 Hinweis: Item "%s" nicht in ox_inventory items.lua deklariert.'):format(ITEM_NAME))
            print('^3[clp_gmenu]^0 Bitte ergaenze: ' .. ITEM_NAME .. ' = { label="Visitenkarte", weight=1, stack=true, close=true }')
        end
    end)

    pcall(function()
        exports.ox_inventory:registerHook('useItem', function(payload)
            if not payload or not payload.item or payload.item.name ~= ITEM_NAME then return end
            local src = payload.source
            local meta = payload.item.metadata or {}
            TriggerClientEvent('clp_gmenu:businessCard:show', src, meta)
            return false        -- Item wird nicht verbraucht
        end, { itemFilter = { [ITEM_NAME] = true } })
    end)
end)

-- ============================================================
--  EXPORTS
-- ============================================================

exports('giveBusinessCard', function(srcGiver, srcReceiver)
    return BC.give(srcGiver, srcReceiver)
end)

print('^2[clp_gmenu]^0 Business Card system geladen.')
