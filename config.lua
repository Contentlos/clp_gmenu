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
Config.AdminGroups   = { 'owner', 'admin', 'superadmin' }    -- ESX-Group-Names
Config.AdminAceCheck = 'command.gmenuadmin'         -- optional: zusaetzlich ACE
Config.AdminCommand  = 'gmenuadmin'                  -- Command-Name fuer Editor

-- Settings-Command (fuer ALLE Spieler)
Config.SettingsCommand = 'gmenusettings'

-- ============================================================
--  KEYBINDS
-- ============================================================
Config.OpenKey     = 'G'      -- oeffnet Target-Menue (NUR wenn Ziel sichtbar)
Config.SelfMenuKey = 'J'      -- oeffnet Self-Menue (eigener Charakter, kein Ziel)
Config.CloseKey    = 'ESCAPE' -- schliesst Menue (zusaetzlich zu G erneut druecken)

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
Config.DefaultTheme    = 'glass'
Config.AvailableThemes = {
    'glass', 'dark', 'neon', 'redcircle', 'minimal', 'custom',
    -- Phase 6 neue Themes:
    'cyberpunk', 'midnight', 'sunset', 'royal', 'hologram', 'matrix',
}

-- Sound-Preset (UI-Toene). Eingestellt im Settings-Panel,
-- ueberschreibt die WebAudio-Toene des NUI-Layers.
-- Optionen: 'soft' | 'crisp' | 'retro' | 'sci_fi' | 'off'
Config.DefaultSoundPreset = 'soft'

-- Lokalisierung: 'de' | 'en' (NUI-Strings, ladbar via locales/<code>.json)
Config.Locale = 'de'
Config.MenuAnchor      = 'right'                                       -- right|center|bottom
Config.ShowVehicleStats = true                                         -- Header zeigt HP/Speed/Plate

-- ============================================================
--  SICHERHEIT
-- ============================================================
Config.RateLimitPerSec     = 4    -- max Aktionen / Sekunde / Spieler (normale Actions)
Config.AdminRateLimitPerSec= 10   -- max Admin-Edits / Sekunde / Admin
Config.MaxDistanceServer   = 12.0 -- Server-seitige Sanity (Anti-Teleport-Exploit)

-- Per-Action-Cooldown: Aktionen koennen ein 'cooldown' (Sekunden) Feld setzen.
-- Wird auf [Min, Max] geclamped, um Missbrauch zu vermeiden.
Config.ActionCooldownMin   = 0.1   -- minimaler Cooldown
Config.ActionCooldownMax   = 300.0 -- maximaler Cooldown (5 Minuten Hard-Cap)

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
--  IMPOUND (Standalone-Subsystem)
--
--  Kann von beliebigen Jobs/Skripten genutzt werden:
--      exports.clp_gmenu:impoundVehicle({ plate='ABC123', fee=5000, lotId='los_santos' })
--      exports.clp_gmenu:isVehicleImpounded(plate)        -> bool
--      exports.clp_gmenu:releaseVehicle(plate)            -> bool
--
--  Die Fahrzeuge werden physisch im Hof gespawnt, Tueren verriegelt
--  und Motor blockiert, bis der Besitzer (oder ein anderer Spieler)
--  die Freigabegebuehr bezahlt hat.
-- ============================================================
Config.Impound = {
    Enabled       = true,
    DefaultFee    = 5000,                                -- Standardgebuehr in $
    MinFee        = 100,
    MaxFee        = 100000,
    PaymentAccount = 'money',                             -- 'money' | 'bank' | 'black_money'
    InteractDistance = 3.5,                               -- Distanz fuer Bezahl-Prompt
    ReleaseTimeoutSec = 600,                              -- Auto wird nach Freigabe X Sek nicht erneut beschlagnahmt
    PolicePersistEnabled = true,                          -- Welche Jobs duerfen impoundieren? (lookup, nur Hinweis)
    AllowedJobs   = { 'police', 'sheriff', 'sasp', 'mechanic' },
    Lots = {
        los_santos = {
            label  = 'Abschlepphof Los Santos',
            blip   = { sprite = 68, color = 47, scale = 0.85, label = 'Abschlepphof' },
            slots  = {
                { coords = vector4(409.5, -1623.4, 28.3, 320.0) },
                { coords = vector4(412.0, -1626.6, 28.3, 320.0) },
                { coords = vector4(414.5, -1629.8, 28.3, 320.0) },
                { coords = vector4(417.0, -1633.0, 28.3, 320.0) },
                { coords = vector4(419.5, -1636.2, 28.3, 320.0) },
                { coords = vector4(422.0, -1639.4, 28.3, 320.0) },
                { coords = vector4(424.5, -1642.6, 28.3, 320.0) },
                { coords = vector4(427.0, -1645.8, 28.3, 320.0) },
            },
            payCoords = vector3(409.6, -1622.3, 29.3),
            -- Cinematic-Kamera nach Auskauf: Position + Look-Richtung
            releaseCam = vector4(445.886, -1622.327, 37.313, 82.253),
        },
        sandy_shores = {
            label  = 'Abschlepphof Sandy Shores',
            blip   = { sprite = 68, color = 47, scale = 0.85, label = 'Abschlepphof' },
            slots  = {
                { coords = vector4(1648.4, 3793.2, 34.6, 30.0) },
                { coords = vector4(1651.1, 3796.4, 34.6, 30.0) },
                { coords = vector4(1653.8, 3799.6, 34.6, 30.0) },
                { coords = vector4(1656.5, 3802.8, 34.6, 30.0) },
                { coords = vector4(1659.2, 3806.0, 34.6, 30.0) },
                { coords = vector4(1661.9, 3809.2, 34.6, 30.0) },
            },
            payCoords  = vector3(1644.0, 3789.5, 34.7),
            releaseCam = vector4(1670.0, 3795.0, 38.0, 210.0),
        },
        paleto_bay = {
            label  = 'Abschlepphof Paleto Bay',
            blip   = { sprite = 68, color = 47, scale = 0.85, label = 'Abschlepphof' },
            slots  = {
                { coords = vector4(-179.4, 6273.1, 31.5, 135.0) },
                { coords = vector4(-176.4, 6270.1, 31.5, 135.0) },
                { coords = vector4(-173.4, 6267.1, 31.5, 135.0) },
                { coords = vector4(-170.4, 6264.1, 31.5, 135.0) },
                { coords = vector4(-167.4, 6261.1, 31.5, 135.0) },
                { coords = vector4(-164.4, 6258.1, 31.5, 135.0) },
            },
            payCoords  = vector3(-181.0, 6276.0, 31.6),
            releaseCam = vector4(-155.0, 6253.0, 35.0, 315.0),
        },
    },
    DefaultLot   = 'los_santos',
}

-- ============================================================
--  DEBUG
-- ============================================================
Config.Debug = false

-- ============================================================
--  VERSION
-- ============================================================
Config.Version = '1.1.0'
