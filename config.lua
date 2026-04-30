--[[
    clp_gmenu - Start-Konfiguration

    Diese Datei enthaelt nur die Werte, die zwingend BEIM START vorhanden sein
    muessen (Admin-Auth, Pfade, Standard-Farben).

    Alles andere (Jobs, Permissions, Actions, Items, Themes...) lebt in
    data/jobs.json und ist komplett in-game ueber /gmenuadmin editierbar.
    Beim ersten Start wird config/jobs.lua als Seed in data/jobs.json
    geschrieben - danach wird config/jobs.lua nur noch fuer "Reset to Default"
    verwendet.
]]

Config = {}

-- ============================================================
--  ADMIN-EDITOR ZUGANG
-- ============================================================
-- Wer darf /gmenuadmin oeffnen?
Config.AdminGroups   = { 'admin', 'superadmin' }    -- ESX-Group-Names
Config.AdminAceCheck = 'command.gmenuadmin'         -- optional: zusaetzlich ACE
Config.AdminCommand  = 'gmenuadmin'                  -- Command-Name fuer Editor

-- Settings-Command (fuer ALLE Spieler)
Config.SettingsCommand = 'gmenusettings'

-- ============================================================
--  KEYBINDS
-- ============================================================
Config.OpenKey  = 'G'        -- oeffnet Menue bei gueltigem Ziel
Config.CloseKey = 'ESCAPE'   -- schliesst Menue (zusaetzlich zu G erneut druecken)

-- ============================================================
--  RAYCAST / DISTANZ
-- ============================================================
Config.MaxDistance       = 9.0    -- 8-10m wie gefordert (Spieler kann via Settings 5-12 setzen)
Config.IdleWaitMs        = 200    -- Loop-Wait wenn Spieler nichts anvisiert
Config.ActiveWaitMs      = 0      -- Loop-Wait waehrend ein Target aktiv ist
Config.HideWhenInVehicle = false  -- Optional: deaktiviere Targeting im Auto
Config.TargetLockMs      = 250    -- Target-Lock (200-350ms) gegen Flackern
-- Raycast ist jetzt konstant aktiv (kein Aktivierungs-Timeout mehr noetig)

-- Action-Cache: Client cached Server-Antworten (Performance)
Config.ActionCacheTTL    = 180000  -- 3 Minuten (ms). 0 = kein Cache.

-- Self-Menu: G ohne Ziel oeffnet eigenes Menue (Job-Info, GPS, Emotes)
Config.SelfMenuEnabled   = true

-- ============================================================
--  DEFAULT-FARBEN (RGB 0-255)
--  Ueberschreibbar via /gmenusettings (KVP) oder /gmenuadmin (Server-Globals)
-- ============================================================
Config.UIColor      = { r = 0,   g = 255, b = 180 }
Config.OutlineColor = { r = 255, g = 50,  b = 50  }
Config.MarkerColor  = { r = 50,  g = 150, b = 255 }

-- ============================================================
--  EFFEKTE / ANIMATIONEN
-- ============================================================
Config.OutlinePulse       = true     -- Fahrzeug-Outline pulsiert sanft
Config.MarkerArrowBobbing = true     -- Pfeil ueber Kopf wippt
Config.MarkerCircleSpin   = true     -- Bodenkreis dreht sich langsam
Config.HighlightFadeMs    = 120      -- Fade-In/Out Dauer

-- ============================================================
--  SOUND
-- ============================================================
Config.EnableSounds  = true
Config.SoundOnTarget = { lib = 'HUD_FRONTEND_DEFAULT_SOUNDSET', name = 'NAV_UP_DOWN' }
Config.SoundOnOpen   = { lib = 'HUD_FRONTEND_DEFAULT_SOUNDSET', name = 'SELECT' }
Config.SoundOnSelect = { lib = 'HUD_LIQUOR_STORE_SOUNDSET',     name = 'PURCHASE' }
Config.SoundOnDeny   = { lib = 'HUD_FRONTEND_DEFAULT_SOUNDSET', name = 'ERROR' }

-- ============================================================
--  UI-DEFAULTS
-- ============================================================
Config.DefaultTheme    = 'glass'                                       -- glass|dark|neon|redcircle|minimal
Config.AvailableThemes = { 'glass', 'dark', 'neon', 'redcircle', 'minimal' }
Config.MenuAnchor      = 'right'                                       -- right|center|bottom
Config.ShowVehicleStats = true                                         -- Header zeigt HP/Speed/Plate

-- ============================================================
--  SICHERHEIT
-- ============================================================
Config.RateLimitPerSec     = 4   -- max Aktionen / Sekunde / Spieler (normale Actions)
Config.AdminRateLimitPerSec= 10  -- max Admin-Edits / Sekunde / Admin
Config.MaxDistanceServer   = 12.0 -- Server-seitige Sanity (Anti-Teleport-Exploit)

-- Whitelist fuer Custom-Actions (Admin-Editor)
-- Custom-Actions koennen NUR Events aus dieser Liste feuern.
-- Leeres Array = alles erlaubt (NICHT empfohlen).
Config.AllowedCustomEvents = {
    -- Beispiele - der Admin definiert spaeter selbst:
    'esx:showNotification',
    'ox_lib:notify',
    'clp_gmenu:custom:noop',
}

-- Allow-List fuer Custom-Commands (sehr restriktiv halten!)
Config.AllowedCustomCommands = {
    'me', 'do',  -- z.B. RP-Commands erlaubt
}

-- ============================================================
--  ITEM-NAMEN (ox_inventory)
--  Im Admin-Editor unter Tab "Items" anpassbar.
-- ============================================================
Config.Items = {
    bandage    = 'bandage',
    medikit    = 'medikit',
    repairkit  = 'repairkit',
    tirekit    = 'tirekit',
    cuffs      = 'handcuffs',
    lockpick   = 'lockpick',
    extinguisher = 'fire_extinguisher',
}

-- ============================================================
--  PFADE
-- ============================================================
Config.StorePath        = 'data/jobs.json'
Config.StoreBackupPath  = 'data/jobs.json.bak'
Config.StoreDefaultPath = 'data/jobs.default.json'   -- "Reset to Default" Source
Config.AuditPath        = 'data/admin_audit.json'

-- ============================================================
--  AUTOSAVE
-- ============================================================
Config.StoreAutosaveSeconds = 60     -- regelmaessiges Save (falls Patches puffert)
Config.AuditMaxEntries      = 1000   -- Ringbuffer fuer Audit-Log

-- ============================================================
--  SQL-FALLBACK (Optional, benoetigt oxmysql)
--  Wenn aktiviert:
--    - store.lua persist() versucht SQL, falls JSON-Speichern fehlschlaegt
--    - store.lua load() versucht SQL, falls JSON-Datei leer/korrupt ist
--    - permissions.lua audit() schreibt zusaetzlich in clp_gmenu_audit
--  Tabellen werden automatisch erstellt (siehe server/sql_store.lua).
-- ============================================================
Config.UseSqlFallback = false

-- ============================================================
--  DISCORD WEBHOOK (optional)
-- ============================================================
Config.AdminWebhook = ''      -- leer = aus. URL fuer Discord-Logs

-- ============================================================
--  DEBUG
-- ============================================================
Config.Debug = false

-- ============================================================
--  VERSION
-- ============================================================
Config.Version = '1.1.0'
