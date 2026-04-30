--[[
    clp_gmenu - JOB-SEED

    Diese Datei ist nur der INITIAL-SEED. Beim ersten Server-Start wird sie
    in data/jobs.json geschrieben. Danach wird die JSON-Datei zur Source-of-Truth.

    Aenderungen hier wirken nur:
      a) bei Server-Start wenn data/jobs.json fehlt
      b) bei "Reset to Default" im Admin-Editor (/gmenuadmin)

    Format ist intentional 1:1 zur JSON-Struktur, damit Migration trivial ist.

    Permission-Keys sind FREI WAEHLBAR - der Admin-Editor zeigt alle Keys an,
    die mindestens einmal in einem Rang vorkommen, plus eine vordefinierte
    Liste aus Config.KnownPermissions (siehe unten).
]]

-- Bekannte Permissions (nur fuer UI-Anzeige im Admin-Editor)
-- Admin kann jederzeit neue Keys per Custom-Permission hinzufuegen.
Config.KnownPermissions = {
    -- Police
    'canSearch', 'canCuff', 'canImpound', 'canCheckId', 'canDrag', 'canBreakLock',
    -- EMS / Ambulance
    'canRevive', 'canHeal', 'canCheckVitals', 'canTransport',
    -- Fire
    'canExtinguish', 'canRescue', 'canFirstAid',
    -- Mechanic
    'canRepair', 'canTune', 'canFixTires', 'canRefuel',
    -- Tow
    'canTow', 'canDetach',
    -- Taxi
    'canOfferRide',
    -- Red Circle
    'canEscort', 'canRequestRide', 'canServeDrink', 'canHire', 'canFire',
    'canPromote', 'canFinance', 'canDjControl',
    -- Generic
    'canRunCommand', 'canTrade', 'canLock',
}

-- ============================================================
--  SEED-DATEN: JOBS
-- ============================================================
Config.JobsSeed = {

    -- ===== POLIZEI =====================================================
    police = {
        label = 'Polizei',
        icon  = 'fa-shield',
        color = '#3B82F6',
        enabled = true,
        inherits = 'citizen',
        ranks = {
            ['0'] = {
                label = 'Anwaerter',
                permissions = { canCheckId = true },
                actions = {
                    player  = { 'pd_check_id' },
                    vehicle = { 'pd_check_plate' },
                    ped     = { 'pd_check_id' },  -- NPCs ebenfalls kontrollierbar
                },
            },
            ['1'] = {
                label = 'Officer',
                permissions = { canCheckId = true, canSearch = true, canCuff = true },
                actions = {
                    player  = { 'pd_check_id', 'pd_search', 'pd_cuff', 'pd_drag' },
                    vehicle = { 'pd_check_plate', 'pd_search_vehicle' },
                    ped     = { 'pd_check_id', 'pd_search' },
                },
            },
            ['2'] = {
                label = 'Sergeant',
                permissions = { canCheckId = true, canSearch = true, canCuff = true, canImpound = true },
                actions = {
                    player  = { 'pd_check_id', 'pd_search', 'pd_cuff', 'pd_drag' },
                    vehicle = { 'pd_check_plate', 'pd_search_vehicle', 'pd_impound', 'pd_break_lock' },
                },
            },
            ['3'] = {
                label = 'Lieutenant',
                permissions = { canCheckId = true, canSearch = true, canCuff = true, canImpound = true, canBreakLock = true },
                actions = {
                    player  = { 'pd_check_id', 'pd_search', 'pd_cuff', 'pd_drag' },
                    vehicle = { 'pd_check_plate', 'pd_search_vehicle', 'pd_impound', 'pd_break_lock' },
                },
            },
            ['4'] = {
                label = 'Chief',
                permissions = { canCheckId = true, canSearch = true, canCuff = true, canImpound = true, canBreakLock = true },
                actions = {
                    player  = { 'pd_check_id', 'pd_search', 'pd_cuff', 'pd_drag' },
                    vehicle = { 'pd_check_plate', 'pd_search_vehicle', 'pd_impound', 'pd_break_lock' },
                },
            },
        },
    },

    -- ===== RETTUNGSDIENST ==============================================
    ambulance = {
        label = 'Rettungsdienst',
        icon  = 'fa-heart-pulse',
        color = '#10B981',
        enabled = true,
        inherits = 'citizen',
        ranks = {
            ['0'] = {
                label = 'Sanitaeter',
                permissions = { canHeal = true, canCheckVitals = true },
                actions = {
                    player  = { 'ems_vitals', 'ems_heal' },
                    vehicle = {},
                },
            },
            ['1'] = {
                label = 'Notarzt',
                permissions = { canHeal = true, canCheckVitals = true, canRevive = true, canTransport = true },
                actions = {
                    player  = { 'ems_vitals', 'ems_heal', 'ems_revive', 'ems_transport' },
                    vehicle = {},
                },
            },
            ['2'] = {
                label = 'Chefarzt',
                permissions = { canHeal = true, canCheckVitals = true, canRevive = true, canTransport = true },
                actions = {
                    player  = { 'ems_vitals', 'ems_heal', 'ems_revive', 'ems_transport' },
                    vehicle = {},
                },
            },
        },
    },

    -- ===== FEUERWEHR ===================================================
    fire = {
        label = 'Feuerwehr',
        icon  = 'fa-fire-extinguisher',
        color = '#EF4444',
        enabled = true,
        inherits = 'citizen',
        ranks = {
            ['0'] = {
                label = 'Feuerwehrmann',
                permissions = { canExtinguish = true, canFirstAid = true },
                actions = {
                    player  = { 'fire_first_aid' },
                    vehicle = { 'fire_extinguish' },
                },
            },
            ['1'] = {
                label = 'Brandmeister',
                permissions = { canExtinguish = true, canFirstAid = true, canRescue = true },
                actions = {
                    player  = { 'fire_first_aid', 'fire_rescue_ped' },
                    vehicle = { 'fire_extinguish', 'fire_rescue' },
                },
            },
            ['2'] = {
                label = 'Kommandant',
                permissions = { canExtinguish = true, canFirstAid = true, canRescue = true },
                actions = {
                    player  = { 'fire_first_aid', 'fire_rescue_ped' },
                    vehicle = { 'fire_extinguish', 'fire_rescue' },
                },
            },
        },
    },

    -- ===== MECHANIKER ==================================================
    mechanic = {
        label = 'Mechaniker',
        icon  = 'fa-wrench',
        color = '#F59E0B',
        enabled = true,
        inherits = 'citizen',
        ranks = {
            ['0'] = {
                label = 'Lehrling',
                permissions = { canRepair = true, canFixTires = true },
                actions = {
                    player  = {},
                    vehicle = { 'mech_repair_light', 'mech_tires' },
                },
            },
            ['1'] = {
                label = 'Mechaniker',
                permissions = { canRepair = true, canFixTires = true, canTune = true },
                actions = {
                    player  = {},
                    vehicle = { 'mech_repair', 'mech_tires', 'mech_tune' },
                },
            },
            ['2'] = {
                label = 'Meister',
                permissions = { canRepair = true, canFixTires = true, canTune = true, canRefuel = true },
                actions = {
                    player  = {},
                    vehicle = { 'mech_repair', 'mech_tires', 'mech_tune', 'mech_refuel' },
                },
            },
        },
    },

    -- ===== ABSCHLEPPDIENST =============================================
    tow = {
        label = 'Abschleppdienst',
        icon  = 'fa-truck',
        color = '#EAB308',
        enabled = true,
        inherits = 'citizen',
        ranks = {
            ['0'] = {
                label = 'Fahrer',
                permissions = { canTow = true, canDetach = true },
                actions = {
                    player  = {},
                    vehicle = { 'tow_attach', 'tow_detach' },
                },
            },
        },
    },

    -- ===== TAXI ========================================================
    taxi = {
        label = 'Taxi',
        icon  = 'fa-taxi',
        color = '#FACC15',
        enabled = true,
        inherits = 'citizen',
        ranks = {
            ['0'] = {
                label = 'Taxifahrer',
                permissions = { canOfferRide = true },
                actions = {
                    player  = { 'taxi_offer' },
                    vehicle = {},
                },
            },
        },
    },

    -- ===== RED CIRCLE (Spezial: clp_redcircle Integration) =============
    redcircle = {
        label = 'Red Circle',
        icon  = 'fa-wine-glass',
        color = '#FF2C2C',
        enabled = true,
        inherits = 'citizen',
        ranks = {
            ['0'] = {
                label = 'Recruit',
                permissions = {},
                actions = { player = { 'civ_handshake' }, vehicle = {} },
            },
            ['1'] = {
                label = 'Security',
                permissions = { canSearch = true, canEscort = true },
                actions = {
                    player  = { 'rc_search', 'rc_escort' },
                    vehicle = {},
                },
            },
            ['2'] = {
                label = 'Chauffeur',
                permissions = { canRequestRide = true },
                actions = {
                    player  = {},
                    vehicle = { 'rc_request_ride' },
                },
            },
            ['3'] = {
                label = 'Barkeeper',
                permissions = { canSearch = true, canServeDrink = true },
                actions = {
                    player  = { 'rc_search', 'rc_serve_drink' },
                    vehicle = {},
                },
            },
            ['4'] = {
                label = 'Manager',
                permissions = { canSearch = true, canHire = true, canFire = true, canPromote = true },
                actions = {
                    player  = { 'rc_search', 'rc_hire', 'rc_fire', 'rc_promote' },
                    vehicle = {},
                },
            },
            ['5'] = {
                label = 'Owner',
                permissions = { canSearch = true, canHire = true, canFire = true, canPromote = true, canFinance = true },
                actions = {
                    player  = { 'rc_search', 'rc_hire', 'rc_fire', 'rc_promote', 'rc_finance' },
                    vehicle = {},
                },
            },
            ['6'] = {
                label = 'DJ',
                permissions = { canDjControl = true },
                actions = {
                    player  = {},
                    vehicle = {},
                },
            },
        },
    },

    -- ===== ZIVILIST (Fallback fuer alle Spieler) =======================
    citizen = {
        label = 'Zivilist',
        icon  = 'fa-user',
        color = '#9CA3AF',
        enabled = true,
        inherits = nil,
        ranks = {
            ['0'] = {
                label = 'Buerger',
                permissions = { canTrade = true },
                actions = {
                    player  = { 'civ_handshake', 'civ_trade', 'civ_help_up', 'civ_give_money', 'civ_point' },
                    vehicle = { 'civ_check_plate', 'civ_lock_vehicle' },
                    ped     = { 'npc_talk', 'npc_trade' },
                    self    = { 'self_job_info', 'self_gps', 'self_emote_sit', 'self_emote_wave', 'self_emote_surrender' },
                },
            },
        },
    },
}

-- ============================================================
--  SEED-DATEN: ACTIONS (komplette Library)
-- ============================================================
-- Format pro Action:
--   id          - eindeutiger Key
--   label       - Anzeigetext
--   icon        - FontAwesome (ohne 'fa-solid ')
--   target      - 'player' | 'vehicle' | 'ped' | 'both'
--   handler     - Server-Handler-Name (in action_registry.lua)
--   permission  - benoetigter Permission-Key (oder nil)
--   description - Hilfetext im Admin-Editor
--   canInteract - optionale clientseitige Vorab-Pruefung (Funktion-Name in registry)
Config.ActionsSeed = {

    -- ===== NPC (verfuegbar fuer alle) ==================================
    npc_talk         = { label = 'Ansprechen',       icon = 'fa-comments',      target = 'ped',     handler = 'npc_talk' },
    npc_trade        = { label = 'Handeln',           icon = 'fa-store',         target = 'ped',     handler = 'npc_trade',         permission = 'canTrade' },
    npc_rob          = { label = 'Ausrauben',         icon = 'fa-mask',          target = 'ped',     handler = 'npc_rob' },

    -- ===== POLICE ====================================================
    pd_check_id      = { label = 'Ausweis pruefen',  icon = 'fa-id-card',       target = 'player',  handler = 'pd_check_id',      permission = 'canCheckId' },
    pd_search        = { label = 'Durchsuchen',      icon = 'fa-magnifying-glass', target = 'player', handler = 'pd_search',     permission = 'canSearch' },
    pd_cuff          = { label = 'Festnehmen',       icon = 'fa-handcuffs',     target = 'player',  handler = 'pd_cuff',          permission = 'canCuff' },
    pd_drag          = { label = 'Mitnehmen',        icon = 'fa-people-pulling',target = 'player',  handler = 'pd_drag',          permission = 'canCuff' },
    pd_check_plate   = { label = 'Kennzeichen pruefen', icon = 'fa-clipboard-list', target = 'vehicle', handler = 'pd_check_plate', permission = 'canCheckId' },
    pd_search_vehicle= { label = 'Fahrzeug durchsuchen', icon = 'fa-magnifying-glass', target = 'vehicle', handler = 'pd_search_vehicle', permission = 'canSearch' },
    pd_impound       = { label = 'Beschlagnahmen',   icon = 'fa-truck-ramp-box',target = 'vehicle', handler = 'pd_impound',       permission = 'canImpound' },
    pd_break_lock    = { label = 'Schloss aufbrechen',icon = 'fa-unlock',        target = 'vehicle', handler = 'pd_break_lock',    permission = 'canBreakLock' },

    -- ===== AMBULANCE =================================================
    ems_vitals    = { label = 'Vitalwerte pruefen', icon = 'fa-heart-pulse',     target = 'player', handler = 'ems_vitals',    permission = 'canCheckVitals' },
    ems_heal      = { label = 'Behandeln',          icon = 'fa-kit-medical',     target = 'player', handler = 'ems_heal',      permission = 'canHeal' },
    ems_revive    = { label = 'Wiederbeleben',      icon = 'fa-heart-circle-bolt', target = 'player', handler = 'ems_revive',  permission = 'canRevive' },
    ems_transport = { label = 'Transport rufen',    icon = 'fa-truck-medical',   target = 'player', handler = 'ems_transport', permission = 'canTransport' },

    -- ===== FIRE ======================================================
    fire_extinguish   = { label = 'Loeschen',          icon = 'fa-fire-extinguisher', target = 'vehicle', handler = 'fire_extinguish', permission = 'canExtinguish' },
    fire_rescue       = { label = 'Aus Auto bergen',   icon = 'fa-person-falling-burst', target = 'vehicle', handler = 'fire_rescue', permission = 'canRescue' },
    fire_rescue_ped   = { label = 'Person bergen',     icon = 'fa-person-walking-arrow-right', target = 'player', handler = 'fire_rescue_ped', permission = 'canRescue' },
    fire_first_aid    = { label = 'Erste Hilfe',       icon = 'fa-hand-holding-medical', target = 'player', handler = 'fire_first_aid', permission = 'canFirstAid' },

    -- ===== MECHANIC ==================================================
    mech_repair_light = { label = 'Leichte Reparatur',icon = 'fa-screwdriver',   target = 'vehicle', handler = 'mech_repair_light', permission = 'canRepair' },
    mech_repair       = { label = 'Voll reparieren',  icon = 'fa-wrench',        target = 'vehicle', handler = 'mech_repair',       permission = 'canRepair' },
    mech_tires        = { label = 'Reifen flicken',   icon = 'fa-circle-notch',  target = 'vehicle', handler = 'mech_tires',        permission = 'canFixTires' },
    mech_tune         = { label = 'Tuning oeffnen',   icon = 'fa-sliders',       target = 'vehicle', handler = 'mech_tune',         permission = 'canTune' },
    mech_refuel       = { label = 'Auftanken',        icon = 'fa-gas-pump',      target = 'vehicle', handler = 'mech_refuel',       permission = 'canRefuel' },

    -- ===== TOW =======================================================
    tow_attach = { label = 'Aufladen', icon = 'fa-truck-arrow-right', target = 'vehicle', handler = 'tow_attach', permission = 'canTow' },
    tow_detach = { label = 'Abladen',  icon = 'fa-truck-fast',        target = 'vehicle', handler = 'tow_detach', permission = 'canDetach' },

    -- ===== TAXI ======================================================
    taxi_offer = { label = 'Taxi anbieten', icon = 'fa-taxi', target = 'player', handler = 'taxi_offer', permission = 'canOfferRide' },

    -- ===== RED CIRCLE ================================================
    rc_search        = { label = 'Person abtasten',  icon = 'fa-hand',          target = 'player',  handler = 'rc_search',        permission = 'canSearch' },
    rc_escort        = { label = 'Hinausbegleiten',  icon = 'fa-person-walking-arrow-right', target = 'player', handler = 'rc_escort', permission = 'canEscort' },
    rc_request_ride  = { label = 'Limo anfordern',   icon = 'fa-car',           target = 'vehicle', handler = 'rc_request_ride',  permission = 'canRequestRide' },
    rc_serve_drink   = { label = 'Drink servieren',  icon = 'fa-martini-glass', target = 'player',  handler = 'rc_serve_drink',   permission = 'canServeDrink' },
    rc_hire          = { label = 'Einstellen',       icon = 'fa-user-plus',     target = 'player',  handler = 'rc_hire',          permission = 'canHire' },
    rc_fire          = { label = 'Kuendigen',        icon = 'fa-user-minus',    target = 'player',  handler = 'rc_fire',          permission = 'canFire' },
    rc_promote       = { label = 'Befoerdern',       icon = 'fa-arrow-up',      target = 'player',  handler = 'rc_promote',       permission = 'canPromote' },
    rc_finance       = { label = 'Finanzen',         icon = 'fa-coins',         target = 'player',  handler = 'rc_finance',       permission = 'canFinance' },

    -- ===== CITIZEN / GENERIC =========================================
    civ_handshake    = { label = 'Hand schuetteln', icon = 'fa-handshake', target = 'player', handler = 'civ_handshake' },
    civ_trade        = { label = 'Handel anbieten', icon = 'fa-arrow-right-arrow-left', target = 'player', handler = 'civ_trade', permission = 'canTrade' },
    civ_help_up      = { label = 'Aufhelfen',       icon = 'fa-hands-holding', target = 'player', handler = 'civ_help_up' },
    civ_give_money   = { label = 'Geld geben',      icon = 'fa-money-bill-wave', target = 'player', handler = 'civ_give_money' },
    civ_point        = { label = 'Zeigen',           icon = 'fa-hand-point-right', target = 'player', handler = 'civ_point' },
    civ_check_plate  = { label = 'Kennzeichen lesen',icon = 'fa-eye',         target = 'vehicle', handler = 'civ_check_plate' },
    civ_lock_vehicle = { label = 'Ab-/Aufschliessen',icon = 'fa-lock',        target = 'vehicle', handler = 'civ_lock_vehicle' },

    -- ===== SELF (ohne Ziel, auf sich selbst) ========================
    self_job_info        = { label = 'Job-Info',         icon = 'fa-briefcase',      target = 'self', handler = 'self_job_info' },
    self_gps             = { label = 'GPS-Position',     icon = 'fa-location-dot',   target = 'self', handler = 'self_gps' },
    self_emote_sit       = { label = 'Hinsetzen',        icon = 'fa-chair',          target = 'self', handler = 'self_emote', extra = 'sit' },
    self_emote_wave      = { label = 'Winken',           icon = 'fa-hand',           target = 'self', handler = 'self_emote', extra = 'wave' },
    self_emote_surrender = { label = 'Haende hoch',      icon = 'fa-hands',          target = 'self', handler = 'self_emote', extra = 'surrender' },

    -- ===== GENERIC (frei verwendbar im Admin-Editor) =================
    generic_notify   = { label = 'Notify senden',  icon = 'fa-message',       target = 'both',   handler = 'generic_notify' },
    generic_command  = { label = 'Command',        icon = 'fa-terminal',      target = 'both',   handler = 'generic_command', permission = 'canRunCommand' },
    generic_event    = { label = 'Event Trigger',  icon = 'fa-bolt',          target = 'both',   handler = 'generic_event' },
}
