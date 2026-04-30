--[[
    clp_gmenu - SQL Store (Optional Fallback fuer JSON-Persistenz)

    Nutzt oxmysql. Eine einzige Tabelle 'clp_gmenu_store' mit dem
    serialisierten Snapshot als JSON-Blob, plus separate Tabelle fuer
    den Audit-Log.

    Aktivierung:
      Config.UseSqlFallback = true   (in config.lua)

    API:
      GMenu.SqlStore.isAvailable()    -> bool
      GMenu.SqlStore.save(data)       -> bool        (true bei Erfolg)
      GMenu.SqlStore.load()           -> table|nil   (geladene Snapshot oder nil)
      GMenu.SqlStore.appendAudit(e)   -> bool

    Bei jedem call wird einmalig die Tabelle erstellt, falls noch nicht da.
]]

GMenu = GMenu or {}
GMenu.SqlStore = {}

local Sql = GMenu.SqlStore

local STORE_ROW_ID = 'main'
local schemaReady  = false

-- ============================================================
--  AVAILABILITY-CHECK
-- ============================================================

local function hasOxmysql()
    return GetResourceState('oxmysql') == 'started'
        and exports.oxmysql ~= nil
end

function Sql.isAvailable()
    return Config.UseSqlFallback == true and hasOxmysql()
end

-- ============================================================
--  SCHEMA
-- ============================================================

local function ensureSchema()
    if schemaReady then return true end
    if not hasOxmysql() then return false end

    local ok = pcall(function()
        exports.oxmysql:execute([[
            CREATE TABLE IF NOT EXISTS `clp_gmenu_store` (
                `id`         VARCHAR(32)  NOT NULL,
                `data`       LONGTEXT     NOT NULL,
                `version`    INT          NOT NULL DEFAULT 0,
                `updated_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
                                          ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        ]])

        exports.oxmysql:execute([[
            CREATE TABLE IF NOT EXISTS `clp_gmenu_audit` (
                `id`        BIGINT       NOT NULL AUTO_INCREMENT,
                `ts`        VARCHAR(32)  NOT NULL,
                `src`       INT          NULL,
                `name`      VARCHAR(96)  NULL,
                `action`    VARCHAR(64)  NOT NULL,
                `details`   LONGTEXT     NULL,
                PRIMARY KEY (`id`),
                INDEX `idx_action` (`action`),
                INDEX `idx_ts`     (`ts`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        ]])
    end)

    if ok then
        schemaReady = true
        print('^2[clp_gmenu]^0 SqlStore: Schema ready.')
    else
        print('^1[clp_gmenu]^0 SqlStore: Schema-Init fehlgeschlagen.')
    end
    return ok
end

-- ============================================================
--  IDENTITY / USER SETTINGS / NPCS / ZONES SCHEMA
--  Independent from main store schema; needed by the Identity
--  System (known_players) and the Universal Framework.
-- ============================================================

local extSchemaReady = false
function Sql.ensureIdentitySchema()
    if extSchemaReady then return true end
    if not hasOxmysql() then return false end

    local ok = pcall(function()
        exports.oxmysql:execute([[
            CREATE TABLE IF NOT EXISTS `clp_gmenu_known_players` (
                `id`                INT          NOT NULL AUTO_INCREMENT,
                `identifier`        VARCHAR(64)  NOT NULL,
                `known_identifier`  VARCHAR(64)  NOT NULL,
                `known_name`        VARCHAR(128) NOT NULL,
                `created_at`        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                UNIQUE KEY `unique_known_pair` (`identifier`, `known_identifier`),
                INDEX `idx_identifier` (`identifier`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        ]])

        exports.oxmysql:execute([[
            CREATE TABLE IF NOT EXISTS `clp_gmenu_user_settings` (
                `identifier` VARCHAR(64)  NOT NULL,
                `data`       LONGTEXT     NOT NULL,
                `updated_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
                                          ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`identifier`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        ]])
    end)

    if ok then
        extSchemaReady = true
        print('^2[clp_gmenu]^0 SqlStore: Identity/Settings schema ready.')
    else
        print('^1[clp_gmenu]^0 SqlStore: Identity-Schema-Init fehlgeschlagen.')
    end
    return ok
end

-- ============================================================
--  USER SETTINGS API (per-Identifier JSON blob)
-- ============================================================

function Sql.loadUserSettings(identifier)
    if not identifier or identifier == '' then return nil end
    if not Sql.ensureIdentitySchema() then return nil end
    local rows
    local ok = pcall(function()
        rows = exports.oxmysql:executeSync(
            'SELECT `data` FROM `clp_gmenu_user_settings` WHERE `identifier` = ? LIMIT 1',
            { identifier }
        )
    end)
    if not ok or not rows or not rows[1] or not rows[1].data then return nil end
    local okDec, decoded = pcall(json.decode, rows[1].data)
    if not okDec or type(decoded) ~= 'table' then return nil end
    return decoded
end

function Sql.saveUserSettings(identifier, settings)
    if not identifier or identifier == '' or type(settings) ~= 'table' then return false end
    if not Sql.ensureIdentitySchema() then return false end
    local okEnc, encoded = pcall(json.encode, settings)
    if not okEnc or type(encoded) ~= 'string' then return false end
    local ok = pcall(function()
        exports.oxmysql:prepare(
            'INSERT INTO `clp_gmenu_user_settings` (`identifier`,`data`) VALUES (?,?) '
            .. 'ON DUPLICATE KEY UPDATE `data`=VALUES(`data`)',
            { identifier, encoded }
        )
    end)
    return ok
end

-- ============================================================
--  SAVE
-- ============================================================

function Sql.save(data)
    if not Sql.isAvailable() then return false end
    if not ensureSchema() then return false end

    local okEnc, encoded = pcall(json.encode, data)
    if not okEnc or type(encoded) ~= 'string' then
        print('^1[clp_gmenu]^0 SqlStore: encode failed.')
        return false
    end

    local version = tonumber(data and data._version) or 0

    local ok = pcall(function()
        exports.oxmysql:prepare(
            'INSERT INTO `clp_gmenu_store` (`id`,`data`,`version`) VALUES (?,?,?) '
            .. 'ON DUPLICATE KEY UPDATE `data`=VALUES(`data`), `version`=VALUES(`version`)',
            { STORE_ROW_ID, encoded, version }
        )
    end)

    if not ok then
        print('^1[clp_gmenu]^0 SqlStore: INSERT/UPDATE fehlgeschlagen.')
        return false
    end
    return true
end

-- ============================================================
--  LOAD
-- ============================================================

function Sql.load()
    if not Sql.isAvailable() then return nil end
    if not ensureSchema() then return nil end

    local rows
    local ok = pcall(function()
        rows = exports.oxmysql:executeSync(
            'SELECT `data` FROM `clp_gmenu_store` WHERE `id` = ? LIMIT 1',
            { STORE_ROW_ID }
        )
    end)

    if not ok or not rows or not rows[1] or not rows[1].data then return nil end

    local okDec, decoded = pcall(json.decode, rows[1].data)
    if not okDec or type(decoded) ~= 'table' then
        print('^1[clp_gmenu]^0 SqlStore: SELECT-Decode fehlgeschlagen.')
        return nil
    end
    return decoded
end

-- ============================================================
--  AUDIT-LOG
-- ============================================================

function Sql.appendAudit(entry)
    if not Sql.isAvailable() then return false end
    if not ensureSchema() then return false end
    if type(entry) ~= 'table' then return false end

    local detailsJson = ''
    if entry.details then
        local okE, enc = pcall(json.encode, entry.details)
        detailsJson = (okE and type(enc) == 'string') and enc or ''
    end

    local ok = pcall(function()
        exports.oxmysql:prepare(
            'INSERT INTO `clp_gmenu_audit` (`ts`,`src`,`name`,`action`,`details`) VALUES (?,?,?,?,?)',
            {
                tostring(entry.ts or os.date('!%Y-%m-%dT%H:%M:%SZ')),
                tonumber(entry.src) or nil,
                tostring(entry.name or ''),
                tostring(entry.action or 'unknown'),
                detailsJson,
            }
        )
    end)
    return ok
end

print('^2[clp_gmenu]^0 SqlStore module loaded (UseSqlFallback=' .. tostring(Config.UseSqlFallback) .. ').')
