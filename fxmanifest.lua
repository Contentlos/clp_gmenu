--[[
    clp_gmenu - Modern Entity Interaction System
    Author : CLP
    Version: 1.0.0

    Standalone, modulares Interaktionssystem fuer Fahrzeuge & Personen.
      - Kamera-Raycast (8-10m)
      - Outline fuer Fahrzeuge / Marker + Pfeil fuer Peds
      - Modernes Glas-NUI auf Taste G
      - Job-aware (mit Spezial-Support fuer clp_redcircle)
      - In-Game Admin-Editor (CRUD ohne Restart)
      - In-Game Settings-Panel (Theme + Farben)
      - Server-seitig validiert, Rate-Limit, Audit-Log

    Ersetzt ox_target / clp_target: Kompatibilitaets-Bridge fuer ox_target Exports.
    Self-Menu: G ohne Ziel oeffnet eigene Aktionen (Job-Info, GPS, Emotes).
    Action-Cache: 3min Client-Cache, automatische Invalidierung bei Admin-Aenderungen.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'clp_gmenu'
author 'CLP'
version '1.1.0'
description 'Modernes Entity-Interaktionssystem mit In-Game Admin-Editor, ox_target Bridge, Self-Menu'

-- ============================================================
--  NUI
-- ============================================================
ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/admin/admin.html',
    'html/admin/admin.css',
    'html/admin/admin.js',

    -- Persistenter Store. MUSS deklariert sein, sonst verweigert SaveResourceFile
    -- in manchen FXServer-Versionen das Schreiben.
    'data/jobs.json',
    'data/jobs.json.bak',
    'data/jobs.default.json',
    'data/admin_audit.json',
}

-- ============================================================
--  SHARED
-- ============================================================
shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'config/jobs.lua',
    'shared/utils.lua',
}

-- ============================================================
--  SERVER
--  Reihenfolge wichtig:
--    sql_store -> store -> permissions -> action_registry -> main -> jobs -> admin
--  (sql_store MUSS vor store.lua, weil store.lua's persist() bereits beim
--   ersten Seed-Save versuchen kann, GMenu.SqlStore zu nutzen.)
-- ============================================================
server_scripts {
    'server/sql_store.lua',
    'server/store.lua',
    'server/permissions.lua',
    'server/action_registry.lua',
    'server/main.lua',
    'server/jobs/*.lua',       -- Alle Job-Handler automatisch einlesen
    'server/admin.lua',
}

-- ============================================================
--  CLIENT
-- ============================================================
client_scripts {
    'client/main.lua',
    'client/raycast.lua',
    'client/highlight.lua',
    'client/bridge_ox.lua',    -- ox_target Kompatibilitaets-Bridge (vor menu.lua!)
    'client/menu.lua',
    'client/actions.lua',
    'client/settings.lua',
    'client/admin.lua',
    'client/jobs/*.lua',       -- Alle Job-Handler automatisch einlesen
}

-- ============================================================
--  DEPENDENCIES
-- ============================================================
dependencies {
    'es_extended',
    'ox_lib',
}

-- ox_inventory ist optional (fuer Search/Trade-Aktionen) - Fallback vorhanden.
