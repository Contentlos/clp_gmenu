--[[
    clp_gmenu - Impound (Standalone Abschlepphof-System)

    Funktionen:
      - Fahrzeuge werden physisch im Hof gespawnt (vom Client)
      - Tueren verriegelt + Motor blockiert bis Bezahlung
      - Beliebiger Job/Skript kann via Exports impoundieren / freigeben
      - Persistenz via SQL (oxmysql) oder In-Memory-Fallback

    Exports (Server):
      exports.clp_gmenu:impoundVehicle({
          plate = 'ABC123',          -- Pflicht
          fee   = 5000,              -- optional (Default = Config.Impound.DefaultFee)
          lotId = 'los_santos',      -- optional (Default = Config.Impound.DefaultLot)
          source = src,              -- optional (Spieler der impoundiert)
          reason = 'illegal parking',-- optional
          ownerIdentifier = '...'    -- optional (welcher char zahlen darf wenn 'owner_only' aktiv)
      })   -> ok:bool, lotId:string|nil

      exports.clp_gmenu:isVehicleImpounded(plate)        -> bool
      exports.clp_gmenu:getImpoundedVehicle(plate)       -> table|nil
      exports.clp_gmenu:releaseVehicle(plate)            -> bool   (force release ohne Bezahlung)
      exports.clp_gmenu:listImpoundedAtLot(lotId)        -> table  ({ {plate, fee, ...}, ... })
      exports.clp_gmenu:getImpoundLots()                 -> table  (Config.Impound.Lots)

    Events (zur Integration):
      'clp_gmenu:impound:added'    (plate, lotId, fee)
      'clp_gmenu:impound:released' (plate, lotId, paid:bool)
]]

GMenu = GMenu or {}
GMenu.Impound = {}

local Imp = GMenu.Impound

-- in-memory: plate -> { plate, fee, lotId, slotIndex, addedAt, ownerIdentifier, reason, modelHash }
local impounded = {}
-- recent releases (anti double-impound innerhalb ReleaseTimeoutSec)
local recentReleases = {}

local ESX
CreateThread(function()
    if GetResourceState('es_extended') == 'started' then
        ESX = exports['es_extended']:getSharedObject()
    end
end)

-- ============================================================
--  HELPERS
-- ============================================================

local function clampFee(fee)
    fee = tonumber(fee) or Config.Impound.DefaultFee
    if fee < Config.Impound.MinFee then fee = Config.Impound.MinFee end
    if fee > Config.Impound.MaxFee then fee = Config.Impound.MaxFee end
    return math.floor(fee)
end

local function getLot(lotId)
    lotId = lotId or Config.Impound.DefaultLot
    return Config.Impound.Lots[lotId], lotId
end

local function findFreeSlot(lotId)
    local lot = Config.Impound.Lots[lotId]
    if not lot then return nil end
    local used = {}
    for _, e in pairs(impounded) do
        if e.lotId == lotId and e.slotIndex then
            used[e.slotIndex] = true
        end
    end
    for i = 1, #lot.slots do
        if not used[i] then return i end
    end
    return nil
end

local function broadcastState()
    -- alle clients bekommen das aktuelle impound dict
    TriggerClientEvent('clp_gmenu:impound:sync', -1, impounded)
end

local function persistAdd(entry)
    if not Config.UseSqlFallback or not exports.oxmysql then return end
    pcall(function()
        exports.oxmysql:execute([[
            INSERT INTO clp_gmenu_impound (plate, lot_id, slot_index, fee, owner_identifier, reason, added_at)
            VALUES (?, ?, ?, ?, ?, ?, NOW())
            ON DUPLICATE KEY UPDATE lot_id=VALUES(lot_id), slot_index=VALUES(slot_index),
                                    fee=VALUES(fee), owner_identifier=VALUES(owner_identifier),
                                    reason=VALUES(reason), added_at=NOW();
        ]], { entry.plate, entry.lotId, entry.slotIndex, entry.fee,
              entry.ownerIdentifier or '', entry.reason or '' })
    end)
end

local function persistRemove(plate)
    if not Config.UseSqlFallback or not exports.oxmysql then return end
    pcall(function()
        exports.oxmysql:execute('DELETE FROM clp_gmenu_impound WHERE plate = ? LIMIT 1', { plate })
    end)
end

local function ensureSchema()
    if not Config.UseSqlFallback or not exports.oxmysql then return end
    pcall(function()
        exports.oxmysql:execute([[
            CREATE TABLE IF NOT EXISTS `clp_gmenu_impound` (
                `plate`            VARCHAR(16)  NOT NULL,
                `lot_id`           VARCHAR(48)  NOT NULL,
                `slot_index`       INT          NOT NULL DEFAULT 0,
                `fee`              INT          NOT NULL DEFAULT 0,
                `owner_identifier` VARCHAR(64)  NULL,
                `reason`           VARCHAR(128) NULL,
                `added_at`         TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`plate`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        ]])
    end)
end

local function loadFromSql()
    if not Config.UseSqlFallback or not exports.oxmysql then return end
    pcall(function()
        local rows = exports.oxmysql:executeSync('SELECT * FROM clp_gmenu_impound', {}) or {}
        for _, row in ipairs(rows) do
            impounded[row.plate] = {
                plate           = row.plate,
                lotId           = row.lot_id,
                slotIndex       = row.slot_index,
                fee             = row.fee,
                ownerIdentifier = row.owner_identifier,
                reason          = row.reason,
                addedAt         = os.time(),
            }
        end
        if next(impounded) then
            print(('^2[clp_gmenu]^0 Impound: %d Fahrzeuge geladen.'):format(#rows))
        end
    end)
end

CreateThread(function()
    Wait(2000)
    ensureSchema()
    loadFromSql()
    broadcastState()
end)

-- ============================================================
--  CORE API
-- ============================================================

function Imp.add(opts)
    if not Config.Impound.Enabled then return false, nil end
    if type(opts) ~= 'table' then return false, nil end

    local plate = opts.plate
    if type(plate) ~= 'string' or plate == '' then return false, nil end
    plate = plate:gsub('%s+', ''):upper()

    if impounded[plate] then return false, impounded[plate].lotId end

    -- Schutz vor Double-Impound nach Release
    if recentReleases[plate] and (os.time() - recentReleases[plate]) < (Config.Impound.ReleaseTimeoutSec or 600) then
        return false, nil
    end

    local lot, lotId = getLot(opts.lotId)
    if not lot then return false, nil end

    local slot = findFreeSlot(lotId)
    if not slot then
        -- Kein freier Slot -> Hof voll, fallback: erste Slot ueberschreiben? Nein, Fail.
        return false, nil
    end

    local entry = {
        plate           = plate,
        fee             = clampFee(opts.fee),
        lotId           = lotId,
        slotIndex       = slot,
        addedAt         = os.time(),
        ownerIdentifier = opts.ownerIdentifier,
        reason          = opts.reason,
        addedBy         = opts.source,
        modelHash       = opts.modelHash,        -- optional
    }
    impounded[plate] = entry

    persistAdd(entry)
    broadcastState()
    TriggerEvent('clp_gmenu:impound:added', plate, lotId, entry.fee)
    return true, lotId
end

function Imp.remove(plate, paid)
    if type(plate) ~= 'string' or plate == '' then return false end
    plate = plate:gsub('%s+', ''):upper()
    local entry = impounded[plate]
    if not entry then return false end

    impounded[plate] = nil
    recentReleases[plate] = os.time()
    persistRemove(plate)
    broadcastState()
    TriggerEvent('clp_gmenu:impound:released', plate, entry.lotId, paid == true)
    return true
end

function Imp.isImpounded(plate)
    if type(plate) ~= 'string' then return false end
    plate = plate:gsub('%s+', ''):upper()
    return impounded[plate] ~= nil
end

function Imp.get(plate)
    if type(plate) ~= 'string' then return nil end
    plate = plate:gsub('%s+', ''):upper()
    return impounded[plate]
end

function Imp.listAtLot(lotId)
    local out = {}
    for _, e in pairs(impounded) do
        if e.lotId == lotId then out[#out+1] = e end
    end
    return out
end

function Imp.list()
    local out = {}
    for _, e in pairs(impounded) do out[#out+1] = e end
    return out
end

-- ============================================================
--  PAYMENT-FLOW (vom Client getriggert)
-- ============================================================

local function getMoney(xPlayer, account)
    if not xPlayer then return 0 end
    if account == 'bank' then
        local acc = xPlayer.getAccount and xPlayer.getAccount('bank')
        return acc and acc.money or 0
    elseif account == 'black_money' then
        local acc = xPlayer.getAccount and xPlayer.getAccount('black_money')
        return acc and acc.money or 0
    else
        return xPlayer.getMoney and xPlayer.getMoney() or 0
    end
end

-- Server-seitiger Abstands-Check zum Hof. Verhindert Remote-Exploits wo
-- ein Client das Event von ueberall ausloest. Toleranz = InteractDistance * 3
-- (mit min 12m), weil der Server Position teils stale ist und der Client
-- ohnehin nur innerhalb InteractDistance interagieren kann.
local function isPlayerNearLot(src, lotId)
    if not src or src == 0 then return false end
    local lot = Config.Impound.Lots[lotId]
    if not lot then return false end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local p = GetEntityCoords(ped)

    local tol = math.max(12.0, (Config.Impound.InteractDistance or 3.5) * 3.0)
    local function near(x, y, z)
        local dx, dy, dz = p.x - x, p.y - y, p.z - z
        return (dx*dx + dy*dy + dz*dz) <= (tol * tol)
    end

    if lot.payCoords and near(lot.payCoords.x, lot.payCoords.y, lot.payCoords.z) then
        return true
    end
    if lot.slots then
        for i = 1, #lot.slots do
            local s = lot.slots[i].coords
            if s and near(s.x, s.y, s.z) then return true end
        end
    end
    return false
end

local function takeMoney(xPlayer, account, amount)
    if not xPlayer then return false end
    if account == 'bank' then
        if xPlayer.removeAccountMoney then
            xPlayer.removeAccountMoney('bank', amount)
            return true
        end
    elseif account == 'black_money' then
        if xPlayer.removeAccountMoney then
            xPlayer.removeAccountMoney('black_money', amount)
            return true
        end
    else
        if xPlayer.removeMoney then
            xPlayer.removeMoney(amount)
            return true
        end
    end
    return false
end

RegisterNetEvent('clp_gmenu:impound:requestRelease', function(plate)
    local src = source
    if not Config.Impound.Enabled then return end
    if type(plate) ~= 'string' then return end
    plate = plate:gsub('%s+', ''):upper()

    local entry = impounded[plate]
    if not entry then
        TriggerClientEvent('clp_gmenu:notify', src, { type = 'error', description = 'Dieses Fahrzeug ist nicht beschlagnahmt.' })
        return
    end

    -- Anti-Exploit: Spieler muss tatsaechlich am Hof stehen.
    if not isPlayerNearLot(src, entry.lotId) then
        if GMenu.Perms and GMenu.Perms.audit then
            GMenu.Perms.audit(src, 'impound_remote_release_attempt', { plate = plate, lotId = entry.lotId })
        end
        TriggerClientEvent('clp_gmenu:notify', src, { type = 'error', description = 'Du bist nicht am Abschlepphof.' })
        return
    end

    if not ESX then
        TriggerClientEvent('clp_gmenu:notify', src, { type = 'error', description = 'ESX nicht verfuegbar.' })
        return
    end
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local fee = entry.fee
    local account = Config.Impound.PaymentAccount or 'money'
    local cash = getMoney(xPlayer, account)

    if cash < fee then
        TriggerClientEvent('clp_gmenu:notify', src, {
            type = 'error',
            description = ('Du brauchst $%d (%s) um das Fahrzeug freizukaufen.'):format(fee, account),
        })
        return
    end

    if not takeMoney(xPlayer, account, fee) then
        TriggerClientEvent('clp_gmenu:notify', src, { type = 'error', description = 'Bezahlung fehlgeschlagen.' })
        return
    end

    Imp.remove(plate, true)
    TriggerClientEvent('clp_gmenu:impound:releaseConfirmed', src, plate, entry.lotId)
    TriggerClientEvent('clp_gmenu:notify', src, {
        type = 'success',
        description = ('Fahrzeug %s freigegeben (-$%d).'):format(plate, fee),
    })
end)

-- Fahrzeug beim Wieder-Einlagern (Spieler faehrt zurueck zum Hof, will einlagern)
RegisterNetEvent('clp_gmenu:impound:store', function(plate, lotId)
    local src = source
    if type(plate) ~= 'string' then return end
    plate = plate:gsub('%s+', ''):upper()

    lotId = lotId or Config.Impound.DefaultLot

    -- Anti-Exploit: Spieler muss am Hof stehen UND idealerweise ein Fahrzeug
    -- mit dieser Plate in der Naehe haben.
    if not isPlayerNearLot(src, lotId) then
        if GMenu.Perms and GMenu.Perms.audit then
            GMenu.Perms.audit(src, 'impound_remote_store_attempt', { plate = plate, lotId = lotId })
        end
        TriggerClientEvent('clp_gmenu:notify', src, { type = 'error', description = 'Du bist nicht am Abschlepphof.' })
        return
    end

    -- Plate-Vehicle-Match: das Fahrzeug muss in Spielernaehe existieren.
    local ped = GetPlayerPed(src)
    local pedVeh = ped and ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
    local hasMatch = false
    if pedVeh and pedVeh ~= 0 then
        local vp = GetVehicleNumberPlateText(pedVeh) or ''
        if vp:gsub('%s+', ''):upper() == plate then hasMatch = true end
    end
    if not hasMatch then
        TriggerClientEvent('clp_gmenu:notify', src, { type = 'error', description = 'Du sitzt nicht in dem Fahrzeug.' })
        return
    end

    local ok, lot = Imp.add({
        plate  = plate,
        fee    = 0,                                          -- Re-Einlagerung kostenlos
        lotId  = lotId or Config.Impound.DefaultLot,
        source = src,
        reason = 'self_store',
    })
    if ok then
        TriggerClientEvent('clp_gmenu:notify', src, {
            type = 'success',
            description = ('Fahrzeug %s eingelagert.'):format(plate),
        })
    else
        TriggerClientEvent('clp_gmenu:notify', src, {
            type = 'error',
            description = 'Einlagern fehlgeschlagen (Hof voll oder Fahrzeug bereits eingelagert).',
        })
    end
end)

-- ============================================================
--  ADMIN COMMAND (/impound <plate> <fee>)
-- ============================================================

RegisterCommand('impound', function(src, args)
    if src == 0 then
        local plate = (args[1] or ''):upper()
        local fee   = tonumber(args[2]) or Config.Impound.DefaultFee
        if plate == '' then
            print('Usage: impound <plate> [fee]')
            return
        end
        local ok = Imp.add({ plate = plate, fee = fee, source = 0, reason = 'console' })
        print(ok and ('Impounded ' .. plate) or 'Impound failed')
        return
    end
    -- Spieler-Aufruf: nur Admin oder erlaubter Job
    if not GMenu.Perms or not GMenu.Perms.isAdmin(src) then
        TriggerClientEvent('clp_gmenu:notify', src, { type = 'error', description = 'Keine Berechtigung.' })
        return
    end
    local plate = (args[1] or ''):upper()
    local fee   = tonumber(args[2]) or Config.Impound.DefaultFee
    if plate == '' then
        TriggerClientEvent('clp_gmenu:notify', src, { type = 'error', description = 'Usage: /impound <plate> [fee]' })
        return
    end
    local ok = Imp.add({ plate = plate, fee = fee, source = src, reason = 'admin' })
    TriggerClientEvent('clp_gmenu:notify', src, {
        type = ok and 'success' or 'error',
        description = ok and ('Fahrzeug ' .. plate .. ' beschlagnahmt.') or 'Impound fehlgeschlagen.',
    })
end, false)

-- ============================================================
--  CALLBACKS / EXPORTS
-- ============================================================

lib.callback.register('clp_gmenu:impound:list', function(_, lotId)
    if lotId then return Imp.listAtLot(lotId) end
    return Imp.list()
end)

exports('impoundVehicle',         function(opts) return Imp.add(opts) end)
exports('isVehicleImpounded',     function(plate) return Imp.isImpounded(plate) end)
exports('getImpoundedVehicle',    function(plate) return Imp.get(plate) end)
exports('releaseVehicle',         function(plate) return Imp.remove(plate, false) end)
exports('listImpoundedAtLot',     function(lotId) return Imp.listAtLot(lotId) end)
exports('getImpoundLots',         function() return Config.Impound.Lots end)

print('^2[clp_gmenu]^0 Impound system geladen.')
