# clp_gmenu v1.1.0

**Modernes Entity-Interaktionssystem fuer FiveM (ESX Legacy) — ersetzt ox_target vollstaendig.**

Anvisieren via Kamera-Raycast, transparentes Glas-NUI auf Taste **G**, Outline fuer Fahrzeuge,
animierte Marker fuer Personen und NPCs, job- und rang-aware Aktionen, Self-Menu, ox_target
Bridge, Action-Cache — und ein vollstaendiger In-Game Admin-Editor.

---

## Features

- **Kamera-Raycast** (8-12m) erkennt Fahrzeuge, Personen und NPCs — konstant aktiv, kein Tastendruck noetig.
- **NPC-Interaktionen**: NPCs (type `ped`) werden automatisch erkannt, Netzwerk-Kontrolle angefordert, Fallback ueber Koordinaten/Modell.
- **Self-Menu**: **G ohne Ziel** oeffnet eigene Aktionen (Job-Info, GPS, Emotes: Sitzen, Winken, Haende hoch).
- **ox_target Bridge**: Vollstaendiger Ersatz — Exports fuer `addBoxZone`, `addSphereZone`, `addTargetEntity`, `addTargetModel`, `addGlobalPed/Vehicle/Object`.
- **Action-Cache**: Client cached Server-Antworten 3 Minuten (konfigurierbar), sofortige Invalidierung bei Admin-Aenderungen oder Job-Wechsel.
- **Vererbung**: Alle Jobs erben automatisch Buerger-Aktionen (Handshake, Handel, Aufhelfen, Geld geben, Zeigen, Kennzeichen, Lock/Unlock).
- **Visuelle Hervorhebung**: Outline fuer Fahrzeuge, Bodenkreis + Pfeil fuer Peds/NPCs — farb- und animations-konfigurierbar.
- **Glas-NUI-Menue** mit Themes (`glass`, `dark`, `neon`, `redcircle`), Hover-Glow, Fade-In, Vehicle-Stats, HP-Bar, Self-Icon.
- **Job-System**: 8 vordefinierte Jobs mit ~50 Aktionen — inkl. NPC-Aktionen und Self-Aktionen.
- **In-Game Admin-Editor** (`/gmenuadmin`): Jobs/Raenge/Permissions/Aktionen komplett im Spiel verwalten. Aenderungen sind LIVE auf allen Clients.
- **Custom-Action-Builder**: Eigene Aktionen ohne Lua erstellen (Notify/Event/ServerEvent/Command), Whitelist-gesichert.
- **Settings-Panel** (`/gmenusettings`): pro-Spieler Theme + Farben mit KVP-Persistenz.
- **Sicherheit**: Server-seitige Job/Permission/Distance-Validierung + Rate-Limiting + Audit-Log + optionaler Discord-Webhook.

---

## Installation

1. Resource nach `resources/[CLP]/clp_gmenu` kopieren (ist sie schon).
2. In `server.cfg`:
   ```cfg
   ensure ox_lib
   ensure es_extended
   ensure ox_inventory   # optional, fuer Search/Trade-Aktionen
   ensure clp_gmenu
   ```
3. Server starten. Beim ersten Start wird `data/jobs.json` automatisch aus `config/jobs.lua` geseedet.
4. **Fertig.** Spieler druecken **G** zum Anvisieren, Admins tippen **`/gmenuadmin`** zum Editor.

---

## Steuerung

| Taste                | Aktion                                                |
|----------------------|-------------------------------------------------------|
| **G** (Tap)          | Menue oeffnen wenn ein Ziel anvisiert ist             |
| **G** (ohne Ziel)    | Self-Menu oeffnen (Job-Info, GPS, Emotes)              |
| **ESC** / **G**      | Menue schliessen                                      |
| **1-9**              | Direkte Optionswahl (Hotkey) im offenen Menue         |
| **Mausklick**        | Option auswaehlen                                     |
| `/gmenusettings`     | Eigenes Settings-Panel (Theme + Farben)               |
| `/gmenuadmin`        | Admin-Editor (nur ESX-Admin/Superadmin)               |

---

## Bootstrap-Konfiguration (`config.lua`)

Diese Werte muessen beim Start vorhanden sein. Alles andere ist im Editor (`/gmenuadmin`) editierbar.

```lua
Config.AdminGroups   = { 'admin', 'superadmin' }   -- ESX-Gruppen mit Editor-Zugang
Config.AdminAceCheck = 'command.gmenuadmin'        -- optional: ACE-Permission

Config.OpenKey       = 'G'
Config.MaxDistance   = 9.0   -- Default 9m, im Editor + Settings ueberschreibbar
Config.ActionCacheTTL = 180000  -- 3 Min Client-Cache (0 = aus)
Config.SelfMenuEnabled = true   -- G ohne Ziel oeffnet Self-Menu

-- Whitelist fuer Custom-Actions (Sicherheit!)
Config.AllowedCustomEvents = {
    'esx:showNotification',
    'ox_lib:notify',
    'clp_gmenu:custom:noop',
}
Config.AllowedCustomCommands = { 'me', 'do' }
```

> **Wichtig**: Werte in `config/jobs.lua` (Jobs, Aktionen) sind nur der **erste Seed**. Spaetere Aenderungen
> macht man im Editor — die landen in `data/jobs.json` und werden live an alle Clients gepusht.

---

## Datenmodell (`data/jobs.json`)

```jsonc
{
  "_version": 17,
  "_lastModified": "2025-04-27T08:14:22Z",
  "_lastModifiedBy": "admin:42",

  "globals": {
    "uiColor": "#00FFB4", "outlineColor": "#FF3232", "markerColor": "#3296FF",
    "maxDistance": 9.0, "defaultTheme": "glass",
    "outlinePulse": true, "markerArrowBobbing": true, "showVehicleStats": true,
    "menuAnchor": "right"
  },

  "items": { "bandage": "bandage", "medikit": "medikit", "repairkit": "repairkit" },

  "jobs": {
    "redcircle": {
      "label": "Red Circle", "icon": "fa-wine-glass", "color": "#FF2C2C",
      "enabled": true, "inherits": null,
      "ranks": {
        "1": {
          "label": "Security",
          "permissions": { "canSearch": true, "canEscort": true },
          "actions": { "player": ["rc_search","rc_escort"], "vehicle": [] }
        }
      }
    }
  },

  "actions": { /* Standard-Library, ~40 Eintraege */ },
  "customActions": { /* vom Admin erstellt */ }
}
```

Atomic-Write: bei jedem Save wird der vorherige Stand nach `data/jobs.json.bak` rotiert.
"Reset to Default" stellt `data/jobs.default.json` wieder her (wurde beim Erst-Seed angelegt).

---

## Admin-Editor (`/gmenuadmin`)

| Tab               | Inhalt                                                                  |
|-------------------|-------------------------------------------------------------------------|
| **Jobs**          | Add/Edit/Delete Jobs, Raenge, Permissions, Action-Zuweisungen, Vererbung |
| **Aktionen**      | Read-Only Browser der ~40 Standard-Library-Aktionen                     |
| **Custom-Actions**| Eigene Aktionen erstellen (Notify/Event/ServerEvent/Command)            |
| **Items**         | ox_inventory Item-Mapping pflegen                                       |
| **Globals**       | Server-weite Defaults (Farben, Theme, Distanz, Animationen)             |
| **Audit**         | Wer hat wann was geaendert                                              |
| **Header**        | Export (JSON-Download), Import (JSON-Upload), Reset to Default          |

### Workflow: Neuen Job hinzufuegen

1. `/gmenuadmin` -> Tab "Jobs" -> **+ Job hinzufuegen**
2. Job-Name eingeben (z.B. `taxi_premium`)
3. Label, Icon (FontAwesome z.B. `fa-taxi`), Akzent-Farbe waehlen
4. Optional: **Erbt von** -> `taxi` (uebernimmt alle Permissions/Actions automatisch)
5. Raenge ergaenzen, Checkboxen fuer Permissions + Aktionen setzen
6. **Fertig**, Aenderung ist sofort live.

### Workflow: Custom-Action ohne Lua

1. Tab "Custom-Actions" -> **+ Neue Custom-Action**
2. ID `notify_thanks`, Label "Danke sagen", Target `player`, Type `notify`, Payload `Vielen Dank!`
3. Speichern -> Action ist sofort in der Action-Library verfuegbar
4. In Tab "Jobs" einem Rang zuweisen.

---

## Aktionen (Standard-Library)

| Job             | Aktionen                                                                 |
|-----------------|--------------------------------------------------------------------------|
| **police**      | check_id, search, cuff, drag, check_plate, search_vehicle, impound, break_lock |
| **ambulance**   | vitals, heal, revive, transport                                          |
| **fire**        | extinguish, rescue (Vehicle), rescue_ped, first_aid                      |
| **mechanic**    | repair_light, repair, tires, tune, refuel                                |
| **tow**         | attach, detach                                                           |
| **taxi**        | offer (mit Tarif-Bestaetigung beim Fahrgast)                             |
| **redcircle**   | search, escort, request_ride, serve_drink, hire, fire, promote, finance  |
| **citizen**     | handshake, trade, help_up, give_money, point, check_plate, lock_vehicle  |
| **npc**         | npc_talk, npc_trade, npc_rob (auf NPCs/Peds)                            |
| **self**        | job_info, gps, emote_sit, emote_wave, emote_surrender                    |
| **generic**     | notify, command, event (Whitelist-gesichert)                             |

**Red Circle**-Aktionen brueckten zu `clp_redcircle`:
- `rc_request_ride` -> `redcircle:limo:requestPickup`
- `rc_hire/fire/promote` -> `redcircle:management:*`
- `rc_serve_drink`     -> `redcircle:bartender:serveExternal`
- Wenn `clp_redcircle` nicht laeuft, fallen die Aktionen sauber auf ESX-Native-Pfade zurueck.

---

## Sicherheit

Alle Aktionen + Editor-Events durchlaufen folgende Pruefungen serverseitig:

1. **Source-Validitaet** (`GetPlayerName(src)`)
2. **Job/Grade-Check** ueber `xPlayer.getJob()` (NIE Client-Trust)
3. **Effective-Rank** mit Vererbung aus dem Store
4. **Action-Zuweisung** + **Permission-Key**
5. **Distance-Sanity** (max 12m, Anti-Teleport)
6. **Rate-Limit** (Token-Bucket: 4 Aktionen/Sek pro Spieler, 10 Edits/Sek pro Admin)
7. **Custom-Action-Whitelist** (nur Events/Commands aus `Config.AllowedCustomEvents`/`...Commands`)
8. **Schema-Validation** auf allen Patches im Editor
9. **Audit-Log** + optionaler Discord-Webhook

---

## Exports

### Server

```lua
exports.clp_gmenu:hasPermission(src, 'canSearch')         -> bool
exports.clp_gmenu:hasAction(src, 'pd_search', 'player')    -> bool
exports.clp_gmenu:isAdmin(src)                              -> bool
exports.clp_gmenu:getStoreSnapshot()                        -> table
exports.clp_gmenu:audit(src, 'my_event', { ... })
```

### Client

```lua
exports.clp_gmenu:hasPerm('canRepair')                      -> bool
exports.clp_gmenu:hasAction('mech_repair', 'vehicle')       -> bool
exports.clp_gmenu:getJob()                                  -> { name, grade, label }
exports.clp_gmenu:isStoreReady()                            -> bool
```

### ox_target Bridge (Client)

```lua
exports.clp_gmenu:addBoxZone({ name='myzone', coords=vec3(...), size=vec3(2,2,2), options={...} })
exports.clp_gmenu:addSphereZone({ name='mysphere', coords=vec3(...), radius=3.0, options={...} })
exports.clp_gmenu:removeZone('myzone')

exports.clp_gmenu:addTargetEntity(entity, { options={...}, distance=3.0 })
exports.clp_gmenu:removeTargetEntity(entity)

exports.clp_gmenu:addTargetModel('s_m_y_cop_01', { options={...}, distance=3.0 })
exports.clp_gmenu:removeTargetModel('s_m_y_cop_01')

exports.clp_gmenu:addGlobalPed({ name='myglobalped', options={...}, distance=3.0 })
exports.clp_gmenu:removeGlobalPed('myglobalped')

exports.clp_gmenu:addGlobalVehicle({ name='myglobalveh', options={...} })
exports.clp_gmenu:removeGlobalVehicle('myglobalveh')
```

Jede `options`-Tabelle folgt dem ox_target-Format:
```lua
{ { name='opt1', label='Optionslabel', icon='fa-star', onSelect=function(entity) ... end, canInteract=function(entity) ... end } }
```

---

## Erweitern (eigene Server-Handler in Lua)

Wenn eine Custom-Action im Editor nicht reicht (z.B. komplexer DB-Lookup):

```lua
-- in einer eigenen Resource oder server/jobs/myjob.lua

local Registry = exports.clp_gmenu  -- nicht direkt verfuegbar; nutze direkt
-- Alternativ: eigenes server-Modul ins fxmanifest aufnehmen und

GMenu.Registry.register('my_handler', function(src, target, payload, action)
    -- src       : Player-Source
    -- target    : { entity, type, netId, isPlayer, targetSrc }
    -- payload   : Extra-Daten vom Client (z.B. { plate, model })
    -- action    : Action-Definition aus dem Store
    -- Vorabchecks (Distance/Permission/Rate-Limit) sind bereits durch.

    -- ... deine Logik ...
    return true
end)
```

Im Editor: erstelle eine Standard-Action-Definition (oder editiere `config/jobs.lua` als Seed)
mit `handler = 'my_handler'`. Weisen die Action einem Job-Rang zu.

---

## Konflikte & Kompatibilitaet

- **ox_target wird ersetzt**: `clp_gmenu` bietet eine Bridge mit identischen Exports. Andere Ressourcen koennen `exports.clp_gmenu:addBoxZone(...)` etc. verwenden.
- `ox_inventory` ist optional. Wenn nicht aktiv: Search/Trade-Aktionen geben nur Notify aus.
- `esx_addonaccount` ist optional fuer `pd_impound` (Society-Konto).
- `esx_ambulancejob` ist optional fuer `ems_revive` (sonst Native-Fallback).
- `LegacyFuel` / `ox_fuel` werden von `mech_refuel` automatisch erkannt.
- `clp_redcircle` Integration ist optional — alle `rc_*`-Aktionen haben Fallback.

---

## Dateistruktur

```
clp_gmenu/
├── fxmanifest.lua
├── config.lua
├── README.md
├── config/
│   └── jobs.lua                 -- Seed-Daten (nur Erststart + Reset)
├── shared/
│   └── utils.lua
├── data/                        -- zur Laufzeit erstellt
│   ├── jobs.json                -- Live-Store (Source-of-Truth)
│   ├── jobs.json.bak
│   ├── jobs.default.json        -- "Reset to Default"-Source
│   └── admin_audit.json         -- Audit-Log
├── server/
│   ├── store.lua
│   ├── permissions.lua
│   ├── action_registry.lua
│   ├── main.lua
│   ├── admin.lua
│   └── jobs/
│       ├── police.lua
│       ├── ambulance.lua
│       ├── fire.lua
│       ├── mechanic.lua
│       ├── tow.lua
│       ├── taxi.lua
│       ├── citizen.lua
│       ├── redcircle.lua
│       ├── npc.lua              -- NPC-Interaktionen (talk, trade, rob)
│       └── self.lua             -- Self-Aktionen (job_info, gps, emotes)
├── client/
│   ├── main.lua
│   ├── raycast.lua
│   ├── highlight.lua
│   ├── bridge_ox.lua            -- ox_target Kompatibilitaets-Bridge
│   ├── menu.lua
│   ├── actions.lua
│   ├── settings.lua
│   ├── admin.lua
│   └── jobs/
│       ├── police.lua
│       ├── ambulance.lua
│       ├── fire.lua
│       ├── mechanic.lua
│       ├── tow.lua
│       ├── taxi.lua
│       ├── citizen.lua
│       ├── redcircle.lua
│       ├── npc.lua              -- NPC-Client-Handler
│       └── self.lua             -- Self-Client-Handler (Emotes)
└── html/
    ├── index.html
    ├── style.css
    ├── script.js
    └── admin/
        ├── admin.html
        ├── admin.css
        └── admin.js
```

---

## Troubleshooting

| Problem                                              | Loesung                                                            |
|------------------------------------------------------|--------------------------------------------------------------------|
| `/gmenuadmin` -> "Keine Berechtigung"                | ESX-Gruppe nicht in `Config.AdminGroups`. `setgroup ID admin`      |
| Aenderungen werden nicht uebernommen                 | F8 -> `restart clp_gmenu`. Pruefen: `data/jobs.json` schreibbar?   |
| Spieler sieht keine Aktionen trotz Job               | Job/Rang im Editor zugewiesen? `/showjob` zum Pruefen, `Config.Debug = true`. |
| Outline flackert / verschwindet                      | Andere Resource setzt `SetEntityDrawOutline` zurueck. `Config.OutlinePulse = false`. |
| ox_inventory-Aktionen tun nichts                     | `ensure ox_inventory` ueberpruefen, ggf. Item-Namen im Editor (Tab "Items") anpassen. |
| Custom-Action feuert nicht                           | Event in `Config.AllowedCustomEvents` whitelisten.                 |

Debug aktivieren:
```lua
Config.Debug = true
```
-> Verbose-Logs auf Client + Server, Audit-Logs werden in der Console gedruckt.

---

## Lizenz / Credits

Eigenstaendige Resource fuer den CLP-Server. Vollstaendiger Ersatz fuer ox_target.
Entity-zentriertes Kontextmenue + NPC-Support + Self-Menu + In-Game-Administration.
