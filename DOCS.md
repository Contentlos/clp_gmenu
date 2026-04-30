# clp_gmenu — Entwickler-Doku

## Action-Resolver Pipeline

Wenn ein Spieler eine Aktion auswaehlt (Tasten 1–9 oder Mausklick), durchlaeuft die Anfrage folgende Pipeline:

```
+----------------+   +-------------------+   +---------------+   +-------------+
| Client klickt  +-->| Server prueft     +-->| Permission OK +-->| Action wird |
| Action im UI   |   | Existenz + Rechte |   | + Cooldown OK |   | dispatched  |
+----------------+   +-------------------+   +---------------+   +-------------+
                              |
                              v
                       Action-Quelle?
                              |
        +---------------------+---------------------+----------------------+
        |                     |                     |                      |
   1. Defaults            2. Job/Grade          3. Bridge             4. NPC/Zone
   (Player/Vehicle/      (job in Store        (ox_target /            (per-NPC oder
    Object Standard-     erlaubt diesen       clp_target              per-Zone-Override
    Aktionen)            Player.id?)          haben Action            aus Admin-Editor)
                                              registriert)
```

### Quellen-Reihenfolge (resolveActions)

`server/action_registry.lua` `Registry.resolveActions(src, target)` kombiniert die Quellen in dieser Reihenfolge:

1. **Defaults**: Aus `data/jobs.json` `defaults.<targetType>` (z.B. `defaults.player.handshake`)
2. **Job-Aktionen**: `jobs.<jobName>.actions` filtert nach `requiredJob` / `requiredGrade` / `requiredDuty`
3. **Bridge-Aktionen**: `GMenu.Bridge.byTarget[targetId]`, `byNpc[npcId]`, `byZone[zoneName]`, `byModel[modelHash]`
4. **NPC/Zone Overrides**: Wenn das Target ein konfigurierter NPC oder eine Zone ist, werden deren `actions[]` haengig

Jede Quelle erzeugt eine Liste normalisierter Actions. Die finale Liste wird dedupliziert (per `id`) — fruehe Quellen gewinnen.

### Permission-Check (Perms.hasAction)

`server/permissions.lua` `Perms.hasAction(src, actionId, target)` prueft fuer jede einzelne Action:

- **Admin-Override**: Admin sieht alles
- **requiredGroup**: ESX-Group muss matchen (`admin`, `superadmin`)
- **requiredJob / requiredGrade**: Job + Grade muessen passen
- **requiredDuty**: `xPlayer.job.onDuty == true` (lookup ueber esx_service / qb-policejob)
- **requiredItems**: `Perms.hasItems(src, items)` checkt ox_inventory oder ESX
- **canInteract**: Vorhandenes serverseitiges Lambda (selten genutzt)
- **Distance-Check**: Server validiert `target.coords` gegen `Config.MaxDistanceServer`

Wenn die Action aus der **Bridge** kommt, ruft `Perms.hasAction` `Bridge.findAction(id, ctx)` auf und prueft die Bridge-Filter (groups/items/canInteract aus dem ox_target-Format).

### Dispatch (Registry.execute)

`Registry.execute(src, payload)` ist der **einzige** Punkt, an dem Aktionen wirklich ausgefuehrt werden:

```lua
function Registry.execute(src, payload)
  local target  = payload.target           -- snapshot { type, entity, model, coords, npcId, zoneName, ... }
  local actId   = payload.actionId

  -- 1. Permission re-check (anti-cheat)
  if not Perms.hasAction(src, actId, target) then return false end

  -- 2. Cooldown re-check
  if not Perms.checkActionCooldown(src, actId, action.cooldown) then return false end

  -- 3. Bridge oder Store?
  local bridgeAct = Bridge.findAction(actId, target)
  if bridgeAct then
      return dispatchBridgeAction(src, target, bridgeAct, payload)   -- serverEvent/clientEvent/...
  end

  -- 4. Store-Action: lokal registrierte Job-Handler
  local handler = Registry.handlers[actId]
  if handler then return handler(src, target, payload) end

  return false
end
```

### Bridge-Dispatch-Typen

`dispatchBridgeAction(src, target, action, payload)` versteht:

| Action-Feld         | Wirkung                                                         |
|---------------------|------------------------------------------------------------------|
| `action.serverEvent`| `TriggerEvent(serverEvent, src, target, payload)`                |
| `action.clientEvent`| `TriggerClientEvent(clientEvent, src, target, payload)`          |
| `action.command`    | `ExecuteCommand((command):format(src))` — restriktiv             |
| `action.notify`     | `TriggerClientEvent('clp_gmenu:notify', src, action.notify)`     |
| `action.ui`         | `TriggerClientEvent('clp_gmenu:bridge:ui', src, action.ui)`      |
| `action.handler`    | Server triggert `'clp_gmenu:bridge:execute'` zurueck zum Client  |
|                     | (Client ruft das ehemalige `onSelect`-Lambda auf)               |

### Re-Register bei Resource-Restart

Wenn ein Drittanbieter-Resource (z.B. ein Job-Skript) `clp_gmenu:registerNpcAction` aufruft und dann gestoppt wird:

- `onResourceStop` purged alle Actions, die mit `_resource = <stoppedRes>` getaggt sind
- Beim `onResourceStart` werden die im Bridge-Hooks-Array registrierten Callbacks nach 2s aufgerufen, sodass das Skript seine Actions wieder pushen kann
- Alternative: Drittanbieter kann selbst `AddEventHandler('onResourceStart', function(r) if r==GetCurrentResourceName() then ... end end)` benutzen

## clp_target API (Client-Exports)

```lua
-- Globale (alle Entities eines Typs)
exports.clp_gmenu:addGlobalPed     ({ options = {...} })
exports.clp_gmenu:addGlobalVehicle ({ options = {...} })
exports.clp_gmenu:addGlobalObject  ({ options = {...} })
exports.clp_gmenu:addGlobalPlayer  ({ options = {...} })
exports.clp_gmenu:addGlobalOption  ({ options = {...} })   -- alle Targets

-- Per-Model
exports.clp_gmenu:addModel(`a_m_y_business_01`, { options = {...} })

-- Per-NetID (networked)
exports.clp_gmenu:addEntity(netId, { options = {...} })

-- Per-Local-Handle (nur dieser Client)
exports.clp_gmenu:addLocalEntity(handle, { options = {...} })

-- Zonen
exports.clp_gmenu:addBoxZone({
    name='store_door', coords=vec3(...), size=vec3(2,2,3), rotation=0.0,
    options = {...}
})
exports.clp_gmenu:addSphereZone({
    name='atm', coords=vec3(...), radius=2.0, options = {...}
})
exports.clp_gmenu:addPolyZone({
    name='loading_dock', points = { vec3(...), vec3(...), vec3(...), vec3(...) },
    minZ=20.0, maxZ=24.0, options = {...}
})
exports.clp_gmenu:removeZone('store_door')
```

### Action-Format (ox_target-kompatibel)

```lua
{
    label    = 'Tueren oeffnen',
    icon     = 'fa-solid fa-door-open',
    distance = 2.5,
    groups   = { 'admin' },                          -- ESX-Gruppen
    items    = { 'lockpick' },                       -- erforderliche Items
    canInteract = function(entity, distance, coords, name, bone)
        return GetVehicleEngineHealth(entity) > 0
    end,

    -- Eines davon waehlen:
    onSelect    = function(data) ... end,            -- Client-Lambda (vorzugsweise)
    serverEvent = 'myresource:openDoors',            -- Server-Event
    clientEvent = 'myresource:openDoorsClient',
    command     = 'me oeffnet die Tuer',
    notify      = { type='inform', description='Geoeffnet.' },

    -- Cooldown (server-clamped auf [0.1, 300] sec)
    cooldown    = 3.0,
}
```

## Impound API

Server-Exports:

```lua
exports.clp_gmenu:impoundVehicle({
    plate = 'ABC123',
    fee   = 5000,
    lotId = 'los_santos',          -- optional
    source = src,                  -- optional (wer impoundiert)
    reason = 'illegal parking',    -- optional
    ownerIdentifier = '...',       -- optional
})

exports.clp_gmenu:isVehicleImpounded(plate)        -- bool
exports.clp_gmenu:getImpoundedVehicle(plate)       -- entry|nil
exports.clp_gmenu:releaseVehicle(plate)            -- bool, ohne Bezahlung
exports.clp_gmenu:listImpoundedAtLot(lotId)        -- table
exports.clp_gmenu:getImpoundLots()                 -- Config.Impound.Lots
```

Server-Events (zum Reagieren):

```lua
AddEventHandler('clp_gmenu:impound:added',    function(plate, lotId, fee) end)
AddEventHandler('clp_gmenu:impound:released', function(plate, lotId, paid) end)
```

## Business Card

Server-Export:

```lua
exports.clp_gmenu:giveBusinessCard(srcGiver, srcReceiver)
```

ox_inventory item registry (in eurer items.lua):

```lua
['business_card'] = {
    label = 'Visitenkarte',
    weight = 1,
    stack = true,
    close = true,
    description = 'Eine personalisierte Visitenkarte',
},
```

## Konfiguration: Wichtige Felder

```lua
Config.SelfMenuKey       = 'J'                  -- Self-Menu Hotkey
Config.OpenKey           = 'G'                  -- Target-Menu Hotkey
Config.DefaultSoundPreset= 'soft'               -- soft|crisp|retro|sci_fi|off
Config.Locale            = 'de'                 -- de|en
Config.ActionCooldownMin = 0.1                  -- min Cooldown (sec)
Config.ActionCooldownMax = 300.0                -- max Cooldown (sec)
Config.AvailableThemes   = { 'glass', 'dark', 'neon', ..., 'matrix' }
Config.Impound = { Enabled=true, DefaultFee=5000, Lots={...} }
```

## Einfache Beispiele

### Einen NPC mit Custom-Aktion registrieren

```lua
-- in deiner resource (kein clp_gmenu modifizieren!)
exports.clp_gmenu:registerNpcAction('mein_dealer', {
    id          = 'dealer_buy',
    label       = 'Kaufen',
    icon        = 'fa-solid fa-bag-shopping',
    serverEvent = 'meinshop:openBuy',
    cooldown    = 1.0,
    requiredJob = nil,                        -- alle duerfen
})
```

### Eine Zone ueber den Admin-Editor erstellen

1. `/gmenuadmin` → Tab "Zones" → "+ Neue Zone"
2. Name: `tankstelle_idlewood`, Typ: `Sphere`, Coords + Radius eingeben
3. RequiredJob optional setzen
4. Per Zone-Action-Chip die Aktion `refuel` zuweisen (vorher unter "Actions" definiert)

### Fahrzeug impoundieren (z.B. aus Police-Job)

```lua
-- in eurer police-resource
RegisterCommand('beschlagnahmen', function(src, args)
    local plate = args[1]
    local ok, lot = exports.clp_gmenu:impoundVehicle({
        plate  = plate,
        fee    = 7500,
        source = src,
        reason = 'verkehrsverstoss',
    })
    -- ok=true wenn klappt
end, false)
```

## Live-Reload

Aenderungen ueber `/gmenuadmin` werden **sofort** an alle Clients gepusht via:

```lua
-- server/store.lua
function Store.patch(path, value, src)
    -- ... persist ...
    TriggerClientEvent('clp_gmenu:store:patch', -1, path, value)
end
```

Es ist **keinem `/gmenuadmin restart` noetig**. Wenn der Cache hartnaeckig ist, kann der Spieler `/gmenusettings` schliessen und neu oeffnen — Settings-Snapshot wird dann vom Server neu geladen.

## Themes

12 Themes verfuegbar: `glass, dark, neon, redcircle, minimal, custom, cyberpunk, midnight, sunset, royal, hologram, matrix`.

Jedes Theme definiert:
- `--m-accent`: Akzentfarbe
- `--m-bg`: Hintergrund (rgba)
- `--m-fg`: Vordergrund-Text

Custom-Theme nutzt die Werte aus `/gmenusettings` (UI/Outline/Marker). Andere Themes sind statisch.

Die Theme-Karten im Settings-Panel zeigen Mini-Mockups (Bars + Dots) mit den jeweiligen Farben.

## Sound-Presets

5 Presets in `html/script.js` `SOUND_PRESETS`:

- **soft**: Weiche Sinus-Toene (default)
- **crisp**: Stacked square waves, knackig
- **retro**: Sawtooth Toene, 8-bit Style
- **sci_fi**: Lange Pitch-Sweeps
- **off**: Komplett stumm

Preview-Button in den Settings spielt jedes Preset einmal kurz an.

## Localization

`html/script.js` `I18N_STRINGS` enthaelt `de` und `en`. Strings sind ueber `I18n.t('key', fallback)` abrufbar.
Der Locale wird beim Menue-Open via Payload mitgesendet (`Config.Locale`).

Erweiterbar fuer weitere Locales: einfach den Block kopieren und Code in `I18n.setLocale()` ergaenzen.
