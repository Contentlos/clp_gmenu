/* ============================================================
   clp_gmenu - NUI-Skript v2 (Hexagon-Layout + Inline Farbverwaltung)

   Lua -> JS Nachrichten:
     { event:'open',          target, options, job, theme, colors, anchor, stats }
     { event:'close' }
     { event:'updateOptions', options }
     { event:'updateStats',   stats }
     { event:'updateTheme',   theme, colors, anchor }
     { event:'openSettings',  data }
     { event:'closeSettings' }
     { event:'openAdmin',     snapshot, knownPermissions, ... }
     { event:'closeAdmin' }
     { event:'adminToFrame',  subEvent, payload }

   JS -> Lua POST-Endpunkte:
     /select               { id }
     /close                {}
     /openSettings         {}
     /saveSettings         { theme?, uiColor?, outlineColor?, markerColor?, enableSounds?, showStats?, maxDistance? }
                           (Server speichert NUR die mitgegebenen Felder.)
     /resetSettings        {}
     /closeSettings        {}
     /cycleTheme           { theme }
     /admin:<callback>     (Vom iframe weitergeleitet via __adminToLua-Bruecke)
============================================================ */

const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'clp_gmenu';
const $   = (id) => document.getElementById(id);
const qs  = (sel) => document.querySelector(sel);
const qsa = (sel) => Array.from(document.querySelectorAll(sel));

const Menu = {
    visible: false,
    target:  null,
    options: [],
};

const Settings = {
    visible: false,
};

// ============================================================
//  LOKALISIERUNG (de/en/fallback)
// ============================================================
const I18N_STRINGS = {
    de: {
        'menu.empty':       'Keine Aktionen verfuegbar.',
        'menu.search':      'Suchen...',
        'menu.no_results':  'Keine passenden Aktionen.',
        'footer.rank':      'Rang',
        'settings.title':   'Einstellungen',
        'settings.theme':   'Theme',
        'settings.sound':   'Sound',
        'settings.distance':'Maximale Distanz',
    },
    en: {
        'menu.empty':       'No actions available.',
        'menu.search':      'Search...',
        'menu.no_results':  'No matching actions.',
        'footer.rank':      'Rank',
        'settings.title':   'Settings',
        'settings.theme':   'Theme',
        'settings.sound':   'Sound',
        'settings.distance':'Max distance',
    },
};

const I18n = {
    locale: 'de',
    setLocale(loc) {
        if (I18N_STRINGS[loc]) this.locale = loc;
    },
    t(key, fallback) {
        const dict = I18N_STRINGS[this.locale] || I18N_STRINGS.de;
        return dict[key] || fallback || key;
    },
};

// ============================================================
//  SUBTILE SOUNDS (WebAudio - keine Asset-Files noetig)
// ============================================================
// Preset-Definitionen: jedes Preset hat fuer jeden Trigger eine Liste von Toenen.
const SOUND_PRESETS = {
    soft: {
        open:   [{ f: 660, slideTo: 880, dur: 0.14, type: 'sine',     gain: 0.045 }],
        close:  [{ f: 660, slideTo: 330, dur: 0.12, type: 'sine',     gain: 0.04  }],
        hover:  [{ f: 1100,               dur: 0.05, type: 'triangle', gain: 0.018 }],
        select: [{ f: 880, slideTo: 1320, dur: 0.10, type: 'sine',     gain: 0.06  }],
        notify: [{ f: 740, slideTo: 980,  dur: 0.16, type: 'triangle', gain: 0.05  }],
    },
    crisp: {
        open:   [{ f: 1200, dur: 0.05, type: 'square',  gain: 0.04 }, { f: 1800, dur: 0.05, type: 'square', gain: 0.03, delay: 0.06 }],
        close:  [{ f: 800,  dur: 0.06, type: 'square',  gain: 0.04 }],
        hover:  [{ f: 1400, dur: 0.025, type: 'square', gain: 0.012 }],
        select: [{ f: 1600, slideTo: 2200, dur: 0.08, type: 'square', gain: 0.05 }],
        notify: [{ f: 1000, dur: 0.07, type: 'square', gain: 0.04 }, { f: 1500, dur: 0.07, type: 'square', gain: 0.04, delay: 0.08 }],
    },
    retro: {
        open:   [{ f: 440, slideTo: 660, dur: 0.18, type: 'sawtooth', gain: 0.05 }],
        close:  [{ f: 660, slideTo: 220, dur: 0.16, type: 'sawtooth', gain: 0.05 }],
        hover:  [{ f: 880, dur: 0.04, type: 'sawtooth', gain: 0.018 }],
        select: [{ f: 523, dur: 0.08, type: 'sawtooth', gain: 0.05 }, { f: 784, dur: 0.08, type: 'sawtooth', gain: 0.05, delay: 0.09 }],
        notify: [{ f: 660, slideTo: 990, dur: 0.2, type: 'sawtooth', gain: 0.05 }],
    },
    sci_fi: {
        open:   [{ f: 220, slideTo: 1760, dur: 0.22, type: 'sine', gain: 0.05 }],
        close:  [{ f: 1760, slideTo: 220, dur: 0.18, type: 'sine', gain: 0.045 }],
        hover:  [{ f: 1320, dur: 0.04, type: 'sine', gain: 0.015 }],
        select: [{ f: 440, slideTo: 1760, dur: 0.14, type: 'triangle', gain: 0.06 }],
        notify: [{ f: 880, slideTo: 1760, dur: 0.18, type: 'triangle', gain: 0.05 }, { f: 660, dur: 0.05, type: 'sine', gain: 0.04, delay: 0.2 }],
    },
    off: {
        open: [], close: [], hover: [], select: [], notify: [],
    },
};

const Sound = {
    enabled: true,
    preset: 'soft',
    ctx: null,
    _ensure() {
        if (!this.enabled) return null;
        if (!this.ctx) {
            try { this.ctx = new (window.AudioContext || window.webkitAudioContext)(); }
            catch (_) { return null; }
        }
        if (this.ctx.state === 'suspended') this.ctx.resume().catch(() => {});
        return this.ctx;
    },
    setPreset(name) {
        if (SOUND_PRESETS[name]) this.preset = name;
    },
    /**
     * @param {Object} o {f, dur, type, gain, slideTo, attack, delay}
     */
    play(o) {
        const ctx = this._ensure();
        if (!ctx) return;
        const t0 = ctx.currentTime + (o.delay || 0);
        const dur = o.dur || 0.08;
        const osc = ctx.createOscillator();
        const g   = ctx.createGain();
        osc.type = o.type || 'sine';
        osc.frequency.setValueAtTime(o.f, t0);
        if (o.slideTo) {
            osc.frequency.exponentialRampToValueAtTime(o.slideTo, t0 + dur);
        }
        const peak = (o.gain == null ? 0.05 : o.gain);
        g.gain.setValueAtTime(0.0001, t0);
        g.gain.exponentialRampToValueAtTime(peak, t0 + (o.attack || 0.005));
        g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
        osc.connect(g).connect(ctx.destination);
        osc.start(t0);
        osc.stop(t0 + dur + 0.02);
    },
    _trigger(name) {
        const preset = SOUND_PRESETS[this.preset] || SOUND_PRESETS.soft;
        const tones = preset[name] || [];
        for (const t of tones) this.play(t);
    },
    open()   { this._trigger('open'); },
    close()  { this._trigger('close'); },
    hover()  { this._trigger('hover'); },
    select() { this._trigger('select'); },
    notify() { this._trigger('notify'); },
    /** Preview-Funktion fuer das Settings-Panel: Spielt eine Demo-Sequenz */
    preview(presetName) {
        const old = this.preset;
        if (presetName) this.preset = presetName;
        const wasEnabled = this.enabled;
        this.enabled = true;
        this._trigger('open');
        setTimeout(() => this._trigger('hover'), 220);
        setTimeout(() => this._trigger('select'), 380);
        setTimeout(() => { this.preset = old; this.enabled = wasEnabled; }, 800);
    },
};

const Colors = {
    ui:      '#00FFB4',
    outline: '#FF3232',
    marker:  '#3296FF',
};

// ============================================================
//  DOM-CACHE (einmalig nach DOMContentLoaded befuellt)
// ============================================================
const DOM = {};
let domReady = false;

function cacheDOM() {
    DOM.menuRoot       = $('menu-root');
    DOM.settingsPanel  = $('settings-panel');
    DOM.settingsOverlay= $('settings-overlay');
    DOM.headerTitle    = $('header-title');
    DOM.headerSub      = $('header-sub');
    DOM.headerDist     = $('header-distance');
    DOM.headerIcon     = $('header-icon-i');
    DOM.menuOptions    = $('menu-options');
    DOM.vehicleStats   = $('vehicle-stats');
    DOM.playerStats    = $('player-stats');
    DOM.statEngine     = $('stat-engine');
    DOM.statEngineVal  = $('stat-engine-val');
    DOM.statBody       = $('stat-body');
    DOM.statBodyVal    = $('stat-body-val');
    DOM.statSpeedVal   = $('stat-speed-val');
    DOM.statPlateVal   = $('stat-plate-val');
    DOM.statHp         = $('stat-hp');
    DOM.statHpVal      = $('stat-hp-val');
    DOM.statDead       = $('stat-dead');
    DOM.footerJobLabel = $('footer-job-label');
    DOM.footerRankLabel= $('footer-rank-label');
    DOM.footerJobIcon  = $('footer-job-icon');
    DOM.themeGrid      = $('theme-grid');
    DOM.adminFrame     = $('admin-frame');
    domReady = true;
}

// ============================================================
//  HILFSFUNKTIONEN
// ============================================================

function escapeHtml(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({
        '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
    }[c]));
}

function hexToRgb(hex) {
    if (!hex || typeof hex !== 'string') return null;
    const h = hex.replace('#', '');
    if (h.length !== 6) return null;
    return {
        r: parseInt(h.slice(0, 2), 16),
        g: parseInt(h.slice(2, 4), 16),
        b: parseInt(h.slice(4, 6), 16),
    };
}

function hexToRgba(hex, a = 1) {
    const c = hexToRgb(hex);
    return c ? `rgba(${c.r},${c.g},${c.b},${a})` : `rgba(0,0,0,${a})`;
}

function postLua(endpoint, body) {
    return fetch(`https://${RES}/${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body || {}),
    }).catch(() => null);
}

// ============================================================
//  THEME / FARBEN
// ============================================================

function applyAccent(hex) {
    if (!hex) return;
    Colors.ui = hex.toUpperCase();

    const c = hexToRgb(hex);
    const rgb = c ? `${c.r}, ${c.g}, ${c.b}` : '0, 255, 180';
    const glow = `0 0 24px ${hexToRgba(hex, 0.55)}`;

    [$('menu-root'), $('settings-panel')].forEach(el => {
        if (!el) return;
        el.style.setProperty('--accent', hex);
        el.style.setProperty('--accent-rgb', rgb);
        el.style.setProperty('--accent-glow', glow);
    });

    // UI-Farbfeld im Footer aktualisieren
    const swUi = document.querySelector('.swatch-hex[data-color="ui"]');
    if (swUi) swUi.style.setProperty('--swatch', hex);
    const inpUi = document.querySelector('input[data-color-input="ui"]');
    if (inpUi) inpUi.value = hex.toLowerCase();
}

function applyOutline(hex) {
    if (!hex) return;
    Colors.outline = hex.toUpperCase();
    const sw = document.querySelector('.swatch-hex[data-color="outline"]');
    if (sw) sw.style.setProperty('--swatch', hex);
    const inp = document.querySelector('input[data-color-input="outline"]');
    if (inp) inp.value = hex.toLowerCase();
}

function applyMarker(hex) {
    if (!hex) return;
    Colors.marker = hex.toUpperCase();
    const sw = document.querySelector('.swatch-hex[data-color="marker"]');
    if (sw) sw.style.setProperty('--swatch', hex);
    const inp = document.querySelector('input[data-color-input="marker"]');
    if (inp) inp.value = hex.toLowerCase();
}

function setTheme(theme, colors, anchor) {
    const root  = DOM.menuRoot;
    const panel = DOM.settingsPanel;

    if (theme) {
        if (root)  root.dataset.theme  = theme;
        if (panel) panel.dataset.theme = theme;
    }

    if (colors) {
        if (colors.ui)      applyAccent(colors.ui);
        if (colors.outline) applyOutline(colors.outline);
        if (colors.marker)  applyMarker(colors.marker);
    }

    if (anchor && root) {
        root.classList.remove('anchor-right', 'anchor-center', 'anchor-bottom');
        root.classList.add('anchor-' + anchor);
    }
}

function setThemeSafe(theme, colors, anchor) {
    if (!domReady) return;
    setTheme(theme, colors, anchor);
}

// ============================================================
//  HAUPTMENUE: OEFFNEN / SCHLIESSEN
// ============================================================

function openMenu(payload) {
    Menu.target  = payload.target  || null;
    Menu.options = payload.options || [];

    if (typeof payload.sounds === 'boolean') Sound.enabled = payload.sounds;
    if (payload.soundPreset) Sound.setPreset(payload.soundPreset);
    if (payload.locale) I18n.setLocale(payload.locale);
    setTheme(payload.theme, payload.colors, payload.anchor);
    renderHeader(Menu.target);
    renderStats(payload.stats);
    renderOptions(Menu.options);
    renderFooter(payload.job);

    DOM.menuRoot.classList.remove('hidden');
    requestAnimationFrame(() => DOM.menuRoot.classList.add('visible'));
    Menu.visible = true;
    Sound.open();
}

function closeMenu() {
    if (!Menu.visible) return;
    DOM.menuRoot.classList.remove('visible');
    setTimeout(() => DOM.menuRoot.classList.add('hidden'), 220);
    Menu.visible = false;
    Sound.close();
}

// ============================================================
//  TARGET-CHIP (Header) - gecachte DOM-Referenzen
// ============================================================

function renderHeader(target) {
    if (!target) {
        DOM.headerTitle.textContent  = '--';
        DOM.headerSub.textContent    = '';
        DOM.headerDist.textContent   = '0m';
        return;
    }

    DOM.headerTitle.textContent  = target.label || '--';
    DOM.headerSub.textContent    = target.sub || (target.type === 'vehicle' ? (target.plate || '') : '');
    DOM.headerDist.textContent   = (target.distance || 0).toFixed(1) + 'm';

    if (target.type === 'self') {
        DOM.headerIcon.className = 'fa-solid fa-circle-user';
    } else if (target.type === 'vehicle') {
        DOM.headerIcon.className = 'fa-solid fa-car';
    } else if (target.type === 'ped') {
        DOM.headerIcon.className = 'fa-solid fa-person-walking';
    } else if (target.isPlayer) {
        DOM.headerIcon.className = 'fa-solid fa-user';
    } else {
        DOM.headerIcon.className = 'fa-solid fa-person';
    }
}

// ============================================================
//  STATS
// ============================================================

function tierClass(value) {
    if (value < 25) return 'crit';
    if (value < 60) return 'warn';
    return '';
}

// Entprellter Stats-Render via requestAnimationFrame
let _statsPending = null;
let _statsRafId   = 0;

function renderStats(stats) {
    // Bei null sofort verstecken
    if (!stats) {
        DOM.vehicleStats.classList.add('hidden');
        DOM.playerStats.classList.add('hidden');
        _statsPending = null;
        return;
    }
    // Nur letzten Stand puffern, einmal pro Frame rendern
    _statsPending = stats;
    if (!_statsRafId) {
        _statsRafId = requestAnimationFrame(_flushStats);
    }
}

function _flushStats() {
    _statsRafId = 0;
    const stats = _statsPending;
    if (!stats) return;

    if (stats.kind === 'vehicle') {
        DOM.vehicleStats.classList.remove('hidden');
        DOM.playerStats.classList.add('hidden');
        const e = Math.max(0, Math.min(100, stats.engine || 0));
        const b = Math.max(0, Math.min(100, stats.body   || 0));

        DOM.statEngine.style.width = e + '%';
        DOM.statEngine.className   = tierClass(e);
        DOM.statEngineVal.textContent = e + '%';

        DOM.statBody.style.width = b + '%';
        DOM.statBody.className   = tierClass(b);
        DOM.statBodyVal.textContent = b + '%';

        DOM.statSpeedVal.textContent = (stats.speed || 0);
        DOM.statPlateVal.textContent = stats.plate || '---';
    } else if (stats.kind === 'player') {
        DOM.playerStats.classList.remove('hidden');
        DOM.vehicleStats.classList.add('hidden');
        const hp = Math.max(0, Math.min(100, stats.hp || 0));
        DOM.statHp.style.width = hp + '%';
        DOM.statHp.className   = tierClass(hp);
        DOM.statHpVal.textContent = hp;
        DOM.statDead.classList.toggle('hidden', !stats.isDead);
    }
}

// ============================================================
//  HEX-OPTIONEN (rendert als Hexagon-Liste)
// ============================================================

// Options-Pool: Elemente wiederverwenden statt staendig neu erzeugen
const _optPool = [];

function _getOptionEl() {
    if (_optPool.length) return _optPool.pop();
    const hex = document.createElement('div');
    hex.className = 'hex-option';
    const inner = document.createElement('div');
    inner.className = 'hex-inner';
    const iconWrap = document.createElement('div');
    iconWrap.className = 'hex-icon';
    const icon = document.createElement('i');
    iconWrap.appendChild(icon);
    const label = document.createElement('div');
    label.className = 'hex-label';
    const key = document.createElement('div');
    key.className = 'hex-key';
    inner.appendChild(iconWrap);
    inner.appendChild(label);
    inner.appendChild(key);
    hex.appendChild(inner);
    // Referenzen am Element speichern fuer schnellen Zugriff
    hex._icon  = icon;
    hex._label = label;
    hex._key   = key;
    return hex;
}

// Search-Filter (case-insensitive, label match)
let _searchTerm = '';

function renderOptions(options) {
    const wrap = DOM.menuOptions;

    // Alte Elemente zurueck in den Pool
    while (wrap.firstChild) {
        const child = wrap.firstChild;
        wrap.removeChild(child);
        if (child._icon) _optPool.push(child);  // nur echte Option-Elemente
    }

    if (!options || options.length === 0) {
        const empty = document.createElement('div');
        empty.className = 'menu-empty';
        empty.textContent = I18n.t('menu.empty');
        wrap.appendChild(empty);
        return;
    }

    // Suchleiste nur einblenden wenn >8 Optionen vorhanden
    if (options.length > 8) {
        const sb = document.createElement('div');
        sb.className = 'menu-search';
        sb.innerHTML = `
            <i class="fa-solid fa-magnifying-glass"></i>
            <input type="text" id="menu-search-input"
                   placeholder="${I18n.t('menu.search')}"
                   autocomplete="off" spellcheck="false" value="${_searchTerm}" />
        `;
        wrap.appendChild(sb);
        // Async fokussieren damit der Layout-Pass durch ist
        setTimeout(() => {
            const inp = $('menu-search-input');
            if (inp) {
                inp.focus();
                inp.addEventListener('input', () => {
                    _searchTerm = inp.value || '';
                    renderOptions(options);
                });
            }
        }, 30);
    } else {
        _searchTerm = '';
    }

    // Filter
    const term = _searchTerm.toLowerCase().trim();
    const filtered = term
        ? options.filter(o => (o.label || o.id || '').toLowerCase().includes(term))
        : options;

    if (filtered.length === 0) {
        const empty = document.createElement('div');
        empty.className = 'menu-empty';
        empty.textContent = I18n.t('menu.no_results');
        wrap.appendChild(empty);
        Menu._visibleOptions = [];
        return;
    }

    // Sichtbare (gefilterte) Liste fuer Tasten-Shortcuts merken
    Menu._visibleOptions = filtered;

    const frag = document.createDocumentFragment();
    filtered.forEach((opt, idx) => {
        const hex = _getOptionEl();
        hex.style.setProperty('--i', idx);
        hex.dataset.id = opt.id;
        hex._icon.className  = 'fa-solid ' + (opt.icon || 'fa-circle');
        hex._label.textContent = opt.label || opt.id;
        hex._key.textContent = idx < 9 ? String(idx + 1) : '';
        hex._key.style.display = idx < 9 ? '' : 'none';
        // Event-Listener: einmal setzen via dataset (kein Lambda-Leak)
        hex.onclick = () => selectOption(opt.id);
        hex.onmouseenter = () => Sound.hover();
        frag.appendChild(hex);
    });
    wrap.appendChild(frag);  // Ein einziger Reflow
}

// ============================================================
//  FUSSZEILE (Job-Chip)
// ============================================================

function renderFooter(job) {
    if (!job) {
        DOM.footerJobLabel.textContent = '--';
        DOM.footerRankLabel.textContent = '';
        return;
    }
    DOM.footerJobLabel.textContent = job.label || job.name || '--';
    DOM.footerRankLabel.textContent = job.rankLabel || ('Rang ' + (job.grade || 0));
    if (job.icon) {
        DOM.footerJobIcon.className = 'fa-solid ' + job.icon;
    }
}

// ============================================================
//  AUSWAHL / SCHLIESSEN
// ============================================================

function selectOption(id) {
    Sound.select();
    postLua('select', { id });
}

function doClose() {
    postLua('close', {});
    closeMenu();
}

// ============================================================
//  INLINE FARBVERWALTUNG (Footer-Farbfelder, Live-Speichern)
// ============================================================

function wireColorQuick() {
    qsa('.swatch-hex input[data-color-input]').forEach(input => {
        const which = input.dataset.colorInput;          // 'ui' | 'outline' | 'marker'
        // Klick auf den Hex-Button -> nativen Farbwaehler oeffnen
        input.parentElement.addEventListener('click', (e) => {
            // Wenn der Klick direkt aufs <input> war, nichts tun (Browser oeffnet sowieso)
            if (e.target.tagName === 'INPUT') return;
            input.click();
        });

        // Live-Vorschau waehrend der Spieler durch Farben zieht
        input.addEventListener('input', () => {
            const hex = input.value;
            if (which === 'ui')      applyAccent(hex);
            else if (which === 'outline') applyOutline(hex);
            else if (which === 'marker')  applyMarker(hex);
        });

        // Beim Schliessen des Farbwaehlers -> teilweises Speichern
        input.addEventListener('change', () => {
            const hex = input.value;
            const payload = {};
            if (which === 'ui')      payload.uiColor      = hex;
            else if (which === 'outline') payload.outlineColor = hex;
            else if (which === 'marker')  payload.markerColor  = hex;
            postLua('saveSettings', payload);
        });
    });
}

// ============================================================
//  EINSTELLUNGEN (Vollansicht)
// ============================================================

const THEMES = [
    'glass', 'dark', 'neon', 'redcircle', 'minimal', 'custom',
    'cyberpunk', 'midnight', 'sunset', 'royal', 'hologram', 'matrix',
];

// Theme-Preview Akzent (fuer Mini-Mockups in den Theme-Karten)
const THEME_ACCENTS = {
    glass:     { accent: '#00FFB4', bg: '#101418' },
    dark:      { accent: '#00FFB4', bg: '#08090c' },
    neon:      { accent: '#00E5FF', bg: '#0c1224' },
    redcircle: { accent: '#FF2C2C', bg: '#1a0a0a' },
    minimal:   { accent: '#FFFFFF', bg: '#15151a' },
    custom:    { accent: '#00FFB4', bg: '#101418' },
    cyberpunk: { accent: '#FF2D87', bg: '#1a0a22' },
    midnight:  { accent: '#6E8BFF', bg: '#0a0e1c' },
    sunset:    { accent: '#FF8C42', bg: '#1c0d08' },
    royal:     { accent: '#C9A227', bg: '#16101e' },
    hologram:  { accent: '#80FFEA', bg: '#06141a' },
    matrix:    { accent: '#00FF7A', bg: '#020c06' },
};

const SOUND_PRESET_LIST = [
    { id: 'soft',   label: 'Soft' },
    { id: 'crisp',  label: 'Crisp' },
    { id: 'retro',  label: 'Retro' },
    { id: 'sci_fi', label: 'Sci-Fi' },
    { id: 'off',    label: 'Aus' },
];

function openSettings(data) {
    DOM.settingsOverlay.classList.remove('hidden');
    requestAnimationFrame(() => DOM.settingsOverlay.classList.add('visible'));
    Settings.visible = true;

    // Theme-Auswahl als Mini-Mockup-Karten
    DOM.themeGrid.innerHTML = '';
    THEMES.forEach(t => {
        const accents = THEME_ACCENTS[t] || THEME_ACCENTS.glass;
        const card = document.createElement('div');
        card.className = 'theme-card' + (t === data.theme ? ' active' : '');
        card.dataset.theme = t;
        card.innerHTML = `
            <div class="theme-mini" style="--m-accent:${accents.accent};--m-bg:${accents.bg};">
                <div class="theme-mini-bar"></div>
                <div class="theme-mini-row"><span class="dot"></span><span class="bar"></span></div>
                <div class="theme-mini-row"><span class="dot"></span><span class="bar short"></span></div>
            </div>
            <div class="theme-name">${t}</div>
        `;
        card.addEventListener('click', () => {
            qsa('.theme-card').forEach(c => c.classList.remove('active'));
            card.classList.add('active');
            applySettingsPreview();
        });
        DOM.themeGrid.appendChild(card);
    });

    // Sound-Preset Auswahl (mit Preview-Buttons)
    const soundGrid = $('sound-preset-grid');
    if (soundGrid) {
        const currentPreset = data.soundPreset || 'soft';
        Sound.setPreset(currentPreset);
        soundGrid.innerHTML = '';
        SOUND_PRESET_LIST.forEach(p => {
            const card = document.createElement('div');
            card.className = 'sound-card' + (p.id === currentPreset ? ' active' : '');
            card.dataset.preset = p.id;
            card.innerHTML = `
                <div class="sound-card-label">${p.label}</div>
                <button class="sound-preview-btn" data-preview="${p.id}" title="Preview"><i class="fa-solid fa-play"></i></button>
            `;
            // Klick auf die Karte (aber nicht den Preview-Button) -> auswaehlen
            card.addEventListener('click', (e) => {
                if (e.target.closest('.sound-preview-btn')) return;
                qsa('.sound-card').forEach(c => c.classList.remove('active'));
                card.classList.add('active');
                Sound.setPreset(p.id);
            });
            // Preview-Button: Tonsequenz abspielen
            card.querySelector('.sound-preview-btn').addEventListener('click', (e) => {
                e.stopPropagation();
                Sound.preview(p.id);
            });
            soundGrid.appendChild(card);
        });
    }

    // Aktuelle Werte setzen
    $('color-ui').value      = (data.uiColor      || Colors.ui).toLowerCase();
    $('color-outline').value = (data.outlineColor || Colors.outline).toLowerCase();
    $('color-marker').value  = (data.markerColor  || Colors.marker).toLowerCase();

    $('color-ui-hex').textContent      = (data.uiColor      || Colors.ui).toUpperCase();
    $('color-outline-hex').textContent = (data.outlineColor || Colors.outline).toUpperCase();
    $('color-marker-hex').textContent  = (data.markerColor  || Colors.marker).toUpperCase();

    $('opt-sounds').checked = data.enableSounds !== false;
    Sound.enabled           = data.enableSounds !== false;
    $('opt-stats').checked  = data.showVehicleStats !== false;

    $('slider-distance').value           = data.maxDistance || 9;
    $('slider-distance-val').textContent = data.maxDistance || 9;

    applySettingsPreview();
}

function closeSettings() {
    DOM.settingsOverlay.classList.remove('visible');
    setTimeout(() => DOM.settingsOverlay.classList.add('hidden'), 220);
    Settings.visible = false;
    postLua('closeSettings', {});
}

function applySettingsPreview() {
    const theme = qs('.theme-card.active')?.dataset.theme || 'glass';
    const ui    = $('color-ui').value;
    const panel = $('settings-panel');
    panel.dataset.theme = theme;

    // Akzent fuer die Vorschau im Einstellungs-Panel
    const c = hexToRgb(ui);
    if (c) {
        panel.style.setProperty('--accent', ui);
        panel.style.setProperty('--accent-rgb', `${c.r}, ${c.g}, ${c.b}`);
        panel.style.setProperty('--accent-glow', `0 0 24px ${hexToRgba(ui, 0.55)}`);
    }
}

function gatherSettings() {
    const activeSound = qs('.sound-card.active');
    return {
        theme:        qs('.theme-card.active')?.dataset.theme || 'glass',
        uiColor:      $('color-ui').value,
        outlineColor: $('color-outline').value,
        markerColor:  $('color-marker').value,
        enableSounds: $('opt-sounds').checked,
        showStats:    $('opt-stats').checked,
        maxDistance:  parseFloat($('slider-distance').value) || 9,
        soundPreset:  activeSound ? activeSound.dataset.preset : 'soft',
    };
}

function saveSettings() {
    const data = gatherSettings();
    Sound.enabled = !!data.enableSounds;
    Sound.setPreset(data.soundPreset);
    postLua('saveSettings', data);
    // Sofort lokal anwenden fuer schnelles Feedback
    applyAccent(data.uiColor);
    applyOutline(data.outlineColor);
    applyMarker(data.markerColor);
    setTheme(data.theme, null, null);
    closeSettings();
}

function resetSettings() {
    postLua('resetSettings', {});
    closeSettings();
}

// ============================================================
//  TASTATUR
// ============================================================

document.addEventListener('keyup', (e) => {
    if (e.key === 'Escape') {
        if (Settings.visible) return closeSettings();
        if (Menu.visible)     return doClose();
    }
    // Digit-Shortcuts deaktivieren wenn Spieler in der Suchleiste tippt
    const isTyping = document.activeElement && document.activeElement.tagName === 'INPUT';
    if (Menu.visible && !isTyping && e.key >= '1' && e.key <= '9') {
        const idx = parseInt(e.key, 10) - 1;
        // Auf die aktuell sichtbare (gefilterte) Liste mappen,
        // sonst stimmt die Tastenbeschriftung nicht mit der Aktion ueberein.
        const list = (Menu._visibleOptions && Menu._visibleOptions.length)
            ? Menu._visibleOptions
            : Menu.options;
        if (list[idx]) selectOption(list[idx].id);
    }
});

// ============================================================
//  EINGEHEND (Lua -> JS)
// ============================================================

window.addEventListener('message', (event) => {
    const d = event.data || {};
    switch (d.event) {
        case 'open':
            openMenu(d);
            break;
        case 'close':
            closeMenu();
            break;
        case 'updateOptions':
            Menu.options = d.options || [];
            renderOptions(Menu.options);
            break;
        case 'updateStats':
            renderStats(d.stats);
            break;
        case 'updateTheme':
            setTheme(d.theme, d.colors, d.anchor);
            break;
        case 'openSettings':
            openSettings(d.data || {});
            break;
        case 'closeSettings':
            closeSettings();
            break;
        case 'openAdmin': {
            // Iframe starten
            const frame = DOM.adminFrame;
            frame.classList.remove('hidden');
            const tryPost = () => {
                if (frame.contentWindow) {
                    frame.contentWindow.postMessage({
                        event: 'init',
                        snapshot: d.snapshot,
                        knownPermissions:    d.knownPermissions,
                        allowedCustomEvents: d.allowedCustomEvents,
                        allowedCustomCommands: d.allowedCustomCommands,
                        isAdmin: d.isAdmin,
                    }, '*');
                }
            };
            if (frame.contentDocument && frame.contentDocument.readyState === 'complete') tryPost();
            else frame.addEventListener('load', tryPost, { once: true });
            break;
        }
        case 'closeAdmin':
            DOM.adminFrame.classList.add('hidden');
            break;
        case 'adminToFrame': {
            const f = DOM.adminFrame;
            if (f && f.contentWindow) {
                f.contentWindow.postMessage({ event: d.subEvent, payload: d.payload }, '*');
            }
            break;
        }
    }
});

// ============================================================
//  IFRAME -> LUA (Bruecke fuer Admin-Editor)
//  Antworten der NUI-Callbacks werden bei Bedarf an das Iframe zurueckgegeben.
// ============================================================

window.addEventListener('message', (event) => {
    const d = event.data || {};
    if (!d.__adminToLua) return;

    fetch(`https://${RES}/admin:${d.cb}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(d.payload || {}),
    })
    .then(r => r.json().catch(() => null))
    .then(result => {
        if (result === null || result === undefined) return;
        const cbToEvent = {
            audit:   'auditList',
            export:  'exportData',
            bridges: 'bridgesList',
            storage: 'storageStatus',
        };
        const evt = cbToEvent[d.cb];
        if (!evt) return;
        const frame = DOM.adminFrame;
        if (frame && frame.contentWindow) {
            frame.contentWindow.postMessage({ event: evt, payload: result }, '*');
        }
    })
    .catch(() => {});
});

// ============================================================
//  VERDRAHTUNG (Buttons + Farb-Eingaben)
// ============================================================

document.addEventListener('DOMContentLoaded', () => {
    cacheDOM();  // DOM-Referenzen einmalig cachen

    $('btn-close').addEventListener('click',    doClose);
    $('btn-settings').addEventListener('click', () => postLua('openSettings', {}));

    $('btn-theme').addEventListener('click', () => {
        const root = DOM.menuRoot;
        const cur  = root.dataset.theme || 'glass';
        const next = THEMES[(THEMES.indexOf(cur) + 1) % THEMES.length];
        root.dataset.theme = next;
        postLua('cycleTheme', { theme: next });
    });

    $('settings-close-btn').addEventListener('click', closeSettings);
    $('settings-save-btn').addEventListener('click',  saveSettings);
    $('settings-reset-btn').addEventListener('click', resetSettings);

    // Farb-Eingaben in Einstellungen (Live-Vorschau im Panel)
    ['color-ui', 'color-outline', 'color-marker'].forEach(id => {
        const inp = $(id);
        if (!inp) return;
        inp.addEventListener('input', () => {
            $(id + '-hex').textContent = inp.value.toUpperCase();
            applySettingsPreview();
        });
    });

    // Distanz-Regler Live-Wert
    const sd = $('slider-distance');
    if (sd) {
        sd.addEventListener('input', () => {
            $('slider-distance-val').textContent = sd.value;
        });
    }

    // Inline Farbverwaltung im Hauptmenue (Footer-Farbfelder)
    wireColorQuick();
});
