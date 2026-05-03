/* ============================================================
   clp_gmenu - Admin Editor (Logic)
   Laeuft in einem iframe. Kommuniziert mit Parent (script.js)
   ueber postMessage. Parent leitet an Lua weiter.
============================================================ */

const $ = (id) => document.getElementById(id);
const qs = (sel) => document.querySelector(sel);
const qsa = (sel) => Array.from(document.querySelectorAll(sel));

const State = {
    snapshot: null,
    knownPermissions: [],
    allowedCustomEvents: [],
    allowedCustomCommands: [],
    selectedJob: null,
    expandedRanks: new Set(),    // 'jobName:rankKey'
    filters: { actions: 'all', jobs: '', actionsSearch: '' },
    saving: false,
};

// ============================================================
//  COMMUNICATION (zu Lua via Parent)
// ============================================================

function sendToLua(cb, payload) {
    window.parent.postMessage({ __adminToLua: true, cb, payload: payload || {} }, '*');
}

// Pfade, die wir gerade selbst geschickt haben - der Server-Echo soll
// dann KEIN volles Re-Render mehr triggern (sonst springen Klicks zurueck).
const recentlySent = new Map();   // path -> expiresAt (ms)
function markSent(path) {
    if (!path) return;
    recentlySent.set(path, Date.now() + 1500);
}
function isOwnEcho(path) {
    if (!path) return false;
    const exp = recentlySent.get(path);
    if (!exp) return false;
    if (exp < Date.now()) { recentlySent.delete(path); return false; }
    return true;
}

function patchPath(path, value)  { markSent(path); sendToLua('patch',   { path, value }); }
function deletePath(path)         { markSent(path); sendToLua('patch',   { path, value: null }); }
function replaceAll(data)         { sendToLua('replace', data); }
function resetStore()             { sendToLua('reset',   {}); }
function closeAdmin()             { sendToLua('close',   {}); }

function exportJson() {
    sendToLua('export', {});
    // Antwort kommt nicht via postMessage zurueck; der Parent macht ein cb(snapshot)
    // Hilfsweise: wir downloaden direkt aus aktueller State.snapshot.
    setTimeout(() => downloadJson('clp_gmenu-store-v' + (State.snapshot._version || 0) + '.json', State.snapshot), 50);
}

function downloadJson(filename, obj) {
    const blob = new Blob([JSON.stringify(obj, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url; a.download = filename; a.click();
    setTimeout(() => URL.revokeObjectURL(url), 500);
}

// ============================================================
//  INCOMING (vom Parent)
// ============================================================

window.addEventListener('message', (event) => {
    const d = event.data || {};
    if (d.event === 'init') {
        State.snapshot = d.snapshot || null;
        State.knownPermissions    = d.knownPermissions    || [];
        State.allowedCustomEvents = d.allowedCustomEvents || [];
        State.allowedCustomCommands = d.allowedCustomCommands || [];
        renderAll();
    } else if (d.event === 'snapshot') {
        // Voller Snapshot-Reload (z.B. bei Replace/Reset).
        State.snapshot = d.payload || State.snapshot;
        renderAll();
        flashSaved();
    } else if (d.event === 'patch') {
        applyPatchInPlace(State.snapshot, d.payload);
        flashSaved();

        // Echo unserer eigenen Aenderung -> NICHT komplett re-rendern,
        // sonst verlieren wir Fokus, Scroll und der Klick "springt zurueck".
        if (isOwnEcho(d.payload && d.payload.path)) {
            // Optional: nur die Versionsnummer im Header updaten.
            if ($('status-version') && State.snapshot._version) {
                $('status-version').textContent = 'v' + State.snapshot._version;
            }
            return;
        }

        // Aenderung kam von einem ANDEREN Admin -> volles Re-Render.
        renderAll();
    }
});

function applyPatchInPlace(target, patch) {
    if (!target || !patch || typeof patch.path !== 'string') return;
    const parts = patch.path.split('.');
    let cur = target;
    for (let i = 0; i < parts.length - 1; i++) {
        if (typeof cur[parts[i]] !== 'object' || cur[parts[i]] === null) cur[parts[i]] = {};
        cur = cur[parts[i]];
    }
    if (patch.value === null || patch.value === undefined) {
        delete cur[parts[parts.length - 1]];
    } else {
        cur[parts[parts.length - 1]] = patch.value;
    }
    if (patch.version) target._version = patch.version;
}

function flashSaved() {
    const el = $('status-saved');
    if (!el) return;
    el.classList.remove('warn');
    el.classList.add('ok');
    el.innerHTML = '<i class="fa-solid fa-cloud-check"></i> Gespeichert';
    setTimeout(() => {
        el.innerHTML = '<i class="fa-solid fa-cloud-check"></i> Sync OK';
    }, 1500);
}

// ============================================================
//  RENDER MASTER
// ============================================================

function renderAll() {
    if (!State.snapshot) return;
    $('status-version').textContent = 'v' + (State.snapshot._version || 0);
    renderJobsList();
    renderJobDetail();
    renderActions();
    renderCustomActions();
    renderItems();
    renderGlobals();
    renderNpcs();
    renderZones();
    renderIdentity();
}

// ============================================================
//  TABS
// ============================================================

document.addEventListener('DOMContentLoaded', () => {
    qsa('.tab').forEach(t => {
        t.addEventListener('click', () => {
            qsa('.tab').forEach(x => x.classList.remove('active'));
            t.classList.add('active');
            const target = t.dataset.tab;
            qsa('.tab-pane').forEach(p => p.classList.toggle('active', p.dataset.pane === target));
            if (target === 'audit')   refreshAudit();
            if (target === 'bridges') refreshBridges();
            if (target === 'storage') refreshStorage();
            if (target === 'identity') renderIdentity();
            if (target === 'impound') refreshImpound();
            if (target === 'themes')  renderThemes();
        });
    });

    // Header buttons
    $('btn-close-admin').addEventListener('click', closeAdmin);
    $('btn-export').addEventListener('click', exportJson);
    $('btn-import').addEventListener('click', () => $('import-file').click());
    $('import-file').addEventListener('change', handleImport);
    $('btn-reset').addEventListener('click', () => {
        if (confirm('Wirklich auf Default-Seed zuruecksetzen? Alle Aenderungen gehen verloren.')) {
            resetStore();
        }
    });

    // Jobs tab
    $('btn-add-job').addEventListener('click', addNewJob);
    $('jobs-search').addEventListener('input', (e) => {
        State.filters.jobs = e.target.value.toLowerCase();
        renderJobsList();
    });

    // Actions tab
    $('actions-search').addEventListener('input', (e) => {
        State.filters.actionsSearch = e.target.value.toLowerCase();
        renderActions();
    });
    qsa('.filter[data-filter]').forEach(b => {
        b.addEventListener('click', () => {
            qsa('.filter[data-filter]').forEach(x => x.classList.remove('active'));
            b.classList.add('active');
            State.filters.actions = b.dataset.filter;
            renderActions();
        });
    });

    // Custom Actions
    $('btn-add-custom').addEventListener('click', () => openCustomModal());
    $('custom-modal-close').addEventListener('click', closeCustomModal);
    $('custom-cancel').addEventListener('click', closeCustomModal);
    $('custom-save').addEventListener('click', saveCustomAction);
    $('custom-type').addEventListener('change', updateCustomHint);

    // Items tab
    $('btn-add-item').addEventListener('click', addNewItem);

    // Audit refresh + filter
    $('btn-refresh-audit').addEventListener('click', refreshAudit);
    $('btn-apply-audit-filter') && $('btn-apply-audit-filter').addEventListener('click', refreshAudit);
    $('btn-clear-audit-filter') && $('btn-clear-audit-filter').addEventListener('click', clearAuditFilter);

    // NPCs / Zones / Bridges / Storage
    $('btn-add-npc') && $('btn-add-npc').addEventListener('click', addNewNpc);
    $('npcs-search') && $('npcs-search').addEventListener('input', e => {
        State.filters.npcs = (e.target.value || '').toLowerCase();
        renderNpcs();
    });
    $('btn-add-zone') && $('btn-add-zone').addEventListener('click', addNewZone);
    $('zones-search') && $('zones-search').addEventListener('input', e => {
        State.filters.zones = (e.target.value || '').toLowerCase();
        renderZones();
    });
    $('btn-refresh-bridges') && $('btn-refresh-bridges').addEventListener('click', refreshBridges);
    $('btn-refresh-storage') && $('btn-refresh-storage').addEventListener('click', refreshStorage);
    $('btn-refresh-impound') && $('btn-refresh-impound').addEventListener('click', refreshImpound);
    $('btn-add-lot')         && $('btn-add-lot').addEventListener('click', addNewLot);
    $('btn-add-theme')       && $('btn-add-theme').addEventListener('click', addNewTheme);

    // ESC schliesst Editor
    document.addEventListener('keyup', (e) => {
        if (e.key === 'Escape') {
            if (!$('custom-modal').classList.contains('hidden')) {
                closeCustomModal();
            } else {
                closeAdmin();
            }
        }
    });
});

// ============================================================
//  IMPORT
// ============================================================

function handleImport(e) {
    const file = e.target.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
        try {
            const obj = JSON.parse(reader.result);
            if (confirm('Datei wird den kompletten Store ersetzen. Fortfahren?')) {
                replaceAll(obj);
            }
        } catch (err) {
            alert('Ungueltige JSON: ' + err.message);
        }
    };
    reader.readAsText(file);
    e.target.value = '';
}

// ============================================================
//  JOBS LIST
// ============================================================

function renderJobsList() {
    const wrap = $('job-list');
    if (!wrap || !State.snapshot) return;
    wrap.innerHTML = '';

    const jobs = State.snapshot.jobs || {};
    const search = State.filters.jobs || '';
    const names = Object.keys(jobs).sort();

    let count = 0;
    names.forEach(name => {
        if (search && !name.toLowerCase().includes(search) && !(jobs[name].label || '').toLowerCase().includes(search)) return;
        count++;
        const j = jobs[name];
        const card = document.createElement('div');
        card.className = 'job-card' + (State.selectedJob === name ? ' active' : '') + (j.enabled === false ? ' job-disabled' : '');
        card.style.setProperty('--job-color', j.color || '#00FFB4');
        const rankCount = Object.keys(j.ranks || {}).length;
        card.innerHTML = `
            <div class="job-icon"><i class="fa-solid ${j.icon || 'fa-briefcase'}"></i></div>
            <div class="job-meta">
                <div class="job-name">${escapeHtml(j.label || name)}</div>
                <div class="job-sub">${escapeHtml(name)}</div>
            </div>
            <span class="badge">${rankCount} R&auml;nge</span>
        `;
        card.addEventListener('click', () => {
            State.selectedJob = name;
            renderJobsList();
            renderJobDetail();
        });
        wrap.appendChild(card);
    });

    if (count === 0) {
        wrap.innerHTML = '<div class="empty-state" style="padding:16px;"><p>Keine Treffer.</p></div>';
    }
}

function addNewJob() {
    const name = prompt('Job-Name (klein, alphanumerisch + _, max 30):');
    if (!name) return;
    if (!/^[a-z0-9_]{1,30}$/.test(name)) { alert('Ungueltiger Name.'); return; }
    if (State.snapshot.jobs[name]) { alert('Job existiert bereits.'); return; }

    const newJob = {
        label: name.charAt(0).toUpperCase() + name.slice(1),
        icon: 'fa-briefcase',
        color: '#00FFB4',
        enabled: true,
        inherits: null,
        ranks: {
            '0': { label: 'Mitarbeiter', permissions: {}, actions: { player: [], vehicle: [] } },
        },
    };

    patchPath('jobs.' + name, newJob);
    State.selectedJob = name;
    // Optimistisch lokal anwenden, damit UI sofort reagiert
    State.snapshot.jobs[name] = newJob;
    renderJobsList();
    renderJobDetail();
}

// ============================================================
//  JOB DETAIL
// ============================================================

function renderJobDetail() {
    const wrap = $('job-detail');
    if (!wrap) return;
    const name = State.selectedJob;
    if (!name || !State.snapshot.jobs[name]) {
        wrap.innerHTML = `
            <div class="empty-state">
                <i class="fa-solid fa-arrow-left"></i>
                <h3>Job ausw&auml;hlen</h3>
                <p>W&auml;hle links einen Job zur Bearbeitung oder erstelle einen neuen.</p>
            </div>`;
        return;
    }
    const j = State.snapshot.jobs[name];

    const otherJobs = Object.keys(State.snapshot.jobs).filter(n => n !== name);
    const inheritsOpts = ['<option value="">-- keine Vererbung --</option>']
        .concat(otherJobs.map(n => `<option value="${escapeHtml(n)}" ${j.inherits === n ? 'selected' : ''}>${escapeHtml(n)}</option>`))
        .join('');

    wrap.innerHTML = `
        <div class="detail-header">
            <div class="job-icon" style="width:48px;height:48px;border-radius:10px;background:${j.color || '#00FFB4'};color:#0a0c10;display:flex;align-items:center;justify-content:center;font-size:18px;flex-shrink:0;">
                <i class="fa-solid ${j.icon || 'fa-briefcase'}"></i>
            </div>
            <div class="detail-meta">
                <h2>${escapeHtml(name)}</h2>
                <p style="color:var(--text-dim);font-size:12px;">${Object.keys(j.ranks || {}).length} R&auml;nge</p>
            </div>
            <div class="detail-actions">
                <button class="btn-danger" id="btn-delete-job"><i class="fa-solid fa-trash"></i> L&ouml;schen</button>
            </div>
        </div>

        <div class="detail-form">
            <div class="form-row">
                <label>Anzeige-Label</label>
                <input type="text" id="job-label" value="${escapeAttr(j.label || '')}">
            </div>
            <div class="form-row">
                <label>FontAwesome-Icon (z.B. fa-briefcase)</label>
                <input type="text" id="job-icon" value="${escapeAttr(j.icon || '')}">
            </div>
            <div class="form-row">
                <label>Akzent-Farbe</label>
                <div class="row-with-color">
                    <input type="color" id="job-color" value="${escapeAttr(j.color || '#00FFB4')}">
                    <input type="text" id="job-color-hex" value="${escapeAttr(j.color || '#00FFB4')}">
                </div>
            </div>
            <div class="form-row">
                <label>Erbt von (optional)</label>
                <select id="job-inherits">${inheritsOpts}</select>
                <small class="hint">Permissions+Actions des Eltern-Jobs werden mit gleichem Rang gemerged.</small>
            </div>
            <div class="form-row">
                <label>Aktiv</label>
                <label class="toggle-mini">
                    <input type="checkbox" id="job-enabled" ${j.enabled !== false ? 'checked' : ''}>
                    <span class="slider"></span>
                </label>
            </div>
        </div>

        <div class="ranks-section">
            <h3>
                <i class="fa-solid fa-sitemap"></i>
                R&auml;nge
                <button class="btn-primary" id="btn-add-rank"><i class="fa-solid fa-plus"></i> Rang hinzuf&uuml;gen</button>
            </h3>
            <div id="ranks-container"></div>
        </div>
    `;

    // Wiring
    $('btn-delete-job').addEventListener('click', () => {
        if (confirm(`Job "${name}" wirklich l&ouml;schen?`)) {
            deletePath('jobs.' + name);
            delete State.snapshot.jobs[name];
            State.selectedJob = null;
            renderJobsList();
            renderJobDetail();
        }
    });

    $('job-label').addEventListener('change', e => {
        patchPath('jobs.' + name + '.label', e.target.value);
        j.label = e.target.value;
        renderJobsList();
    });
    $('job-icon').addEventListener('change', e => {
        patchPath('jobs.' + name + '.icon', e.target.value);
        j.icon = e.target.value;
        renderJobsList();
    });
    $('job-color').addEventListener('input', e => {
        $('job-color-hex').value = e.target.value.toUpperCase();
    });
    $('job-color').addEventListener('change', e => {
        patchPath('jobs.' + name + '.color', e.target.value);
        j.color = e.target.value;
        renderJobsList();
    });
    $('job-color-hex').addEventListener('change', e => {
        const v = e.target.value;
        if (/^#[0-9A-Fa-f]{6}$/.test(v)) {
            patchPath('jobs.' + name + '.color', v);
            j.color = v;
            $('job-color').value = v;
            renderJobsList();
        }
    });
    $('job-inherits').addEventListener('change', e => {
        const v = e.target.value || null;
        patchPath('jobs.' + name + '.inherits', v);
        j.inherits = v;
    });
    $('job-enabled').addEventListener('change', e => {
        patchPath('jobs.' + name + '.enabled', e.target.checked);
        j.enabled = e.target.checked;
        renderJobsList();
    });
    $('btn-add-rank').addEventListener('click', () => addRank(name));

    renderRanks(name);
}

// ============================================================
//  RANKS
// ============================================================

function renderRanks(jobName) {
    const wrap = $('ranks-container');
    if (!wrap) return;
    const j = State.snapshot.jobs[jobName];
    if (!j) return;

    wrap.innerHTML = '';

    const keys = Object.keys(j.ranks || {}).sort((a, b) => parseInt(a) - parseInt(b));
    keys.forEach(rk => {
        const rank = j.ranks[rk];
        const expandKey = jobName + ':' + rk;
        const card = document.createElement('div');
        card.className = 'rank-card' + (State.expandedRanks.has(expandKey) ? ' expanded' : '');

        const permCount = Object.keys(rank.permissions || {}).filter(k => rank.permissions[k] === true).length;
        const actionCount = (rank.actions && rank.actions.player ? rank.actions.player.length : 0)
                          + (rank.actions && rank.actions.vehicle ? rank.actions.vehicle.length : 0);

        card.innerHTML = `
            <div class="rank-header">
                <i class="fa-solid fa-chevron-right rank-toggle"></i>
                <div class="rank-num">${rk}</div>
                <div class="rank-label">${escapeHtml(rank.label || '')}</div>
                <div class="rank-counts">
                    <span><i class="fa-solid fa-key"></i> ${permCount}</span>
                    <span><i class="fa-solid fa-bolt"></i> ${actionCount}</span>
                </div>
            </div>
            <div class="rank-body"></div>
        `;
        card.querySelector('.rank-header').addEventListener('click', () => {
            if (State.expandedRanks.has(expandKey)) State.expandedRanks.delete(expandKey);
            else State.expandedRanks.add(expandKey);
            card.classList.toggle('expanded');
            if (card.classList.contains('expanded')) {
                // Card ist bereits im DOM (per appendChild oben).
                renderRankBody(card.querySelector('.rank-body'), jobName, rk);
            }
        });

        // WICHTIG: Card MUSS zuerst ins DOM, sonst findet getElementById die
        // Inputs/Buttons in renderRankBody nicht und addEventListener crasht.
        wrap.appendChild(card);

        if (State.expandedRanks.has(expandKey)) {
            renderRankBody(card.querySelector('.rank-body'), jobName, rk);
        }
    });
}

function renderRankBody(wrap, jobName, rk) {
    const rank = State.snapshot.jobs[jobName].ranks[rk];

    // Permissions: alle Keys aus knownPermissions + alle, die in rank.permissions vorhanden sind
    const allPerms = new Set([...(State.knownPermissions || []), ...Object.keys(rank.permissions || {})]);

    const permRows = [...allPerms].sort().map(p => {
        const checked = rank.permissions && rank.permissions[p] === true;
        return `
            <label class="check">
                <input type="checkbox" data-perm="${escapeAttr(p)}" ${checked ? 'checked' : ''}>
                <span class="box"></span>
                <span class="label">${escapeHtml(p)}</span>
            </label>`;
    }).join('');

    // Actions: gefiltert nach Target
    const allActions = { ...(State.snapshot.actions || {}), ...(State.snapshot.customActions || {}) };
    const playerActions = Object.entries(allActions).filter(([id, a]) => a.target === 'player' || a.target === 'both');
    const vehicleActions = Object.entries(allActions).filter(([id, a]) => a.target === 'vehicle' || a.target === 'both');

    const playerSet = new Set(rank.actions && rank.actions.player || []);
    const vehicleSet = new Set(rank.actions && rank.actions.vehicle || []);

    const renderActionList = (entries, set, target) => entries.sort((a, b) => a[0].localeCompare(b[0])).map(([id, a]) => `
        <label class="check action">
            <input type="checkbox" data-action="${escapeAttr(id)}" data-target="${target}" ${set.has(id) ? 'checked' : ''}>
            <span class="box"></span>
            <i class="fa-solid ${escapeAttr(a.icon || 'fa-circle')}"></i>
            <span class="label" title="${escapeAttr(a.label || id)}">${escapeHtml(a.label || id)}</span>
        </label>`).join('');

    wrap.innerHTML = `
        <div class="form-row" style="margin-bottom:12px;">
            <label>Rang-Bezeichnung</label>
            <input type="text" id="rank-label-${rk}" value="${escapeAttr(rank.label || '')}">
        </div>

        <h4><i class="fa-solid fa-key"></i> Berechtigungen</h4>
        <div class="checkbox-grid" id="perm-grid-${rk}">${permRows || '<small class="hint">Keine Permissions definiert. F&uuml;ge eigene unten hinzu.</small>'}</div>
        <div style="margin-top:8px;display:flex;gap:6px;">
            <input type="text" placeholder="Neuer Permission-Key (z.B. canMyAction)" id="new-perm-${rk}" style="flex:1;">
            <button class="btn-ghost" id="add-perm-${rk}"><i class="fa-solid fa-plus"></i></button>
        </div>

        <h4><i class="fa-solid fa-user"></i> Personen-Aktionen</h4>
        <div class="checkbox-grid">${renderActionList(playerActions, playerSet, 'player') || '<small class="hint">Keine.</small>'}</div>

        <h4><i class="fa-solid fa-car"></i> Fahrzeug-Aktionen</h4>
        <div class="checkbox-grid">${renderActionList(vehicleActions, vehicleSet, 'vehicle') || '<small class="hint">Keine.</small>'}</div>

        <div class="rank-actions">
            <button class="btn-icon danger" id="del-rank-${rk}" title="Rang l&ouml;schen"><i class="fa-solid fa-trash"></i></button>
        </div>
    `;

    // Wiring: Label
    $('rank-label-' + rk).addEventListener('change', e => {
        patchPath(`jobs.${jobName}.ranks.${rk}.label`, e.target.value);
        rank.label = e.target.value;
        renderRanks(jobName);    // Counts neu anzeigen
        // Re-expand:
        State.expandedRanks.add(jobName + ':' + rk);
    });

    // Permissions
    wrap.querySelectorAll('input[data-perm]').forEach(inp => {
        inp.addEventListener('change', () => {
            const k = inp.dataset.perm;
            if (!rank.permissions) rank.permissions = {};
            if (inp.checked) rank.permissions[k] = true;
            else delete rank.permissions[k];
            patchPath(`jobs.${jobName}.ranks.${rk}.permissions`, rank.permissions);
        });
    });
    $('add-perm-' + rk).addEventListener('click', () => {
        const v = $('new-perm-' + rk).value.trim();
        if (!/^[A-Za-z][A-Za-z0-9_]{0,39}$/.test(v)) { alert('Ungueltiger Permission-Key.'); return; }
        if (!rank.permissions) rank.permissions = {};
        rank.permissions[v] = true;
        patchPath(`jobs.${jobName}.ranks.${rk}.permissions`, rank.permissions);
        renderRanks(jobName);
        State.expandedRanks.add(jobName + ':' + rk);
    });

    // Actions
    wrap.querySelectorAll('input[data-action]').forEach(inp => {
        inp.addEventListener('change', () => {
            const id = inp.dataset.action;
            const target = inp.dataset.target;
            if (!rank.actions) rank.actions = { player: [], vehicle: [] };
            if (!rank.actions[target]) rank.actions[target] = [];
            const arr = rank.actions[target];
            const idx = arr.indexOf(id);
            if (inp.checked && idx === -1) arr.push(id);
            else if (!inp.checked && idx !== -1) arr.splice(idx, 1);
            patchPath(`jobs.${jobName}.ranks.${rk}.actions.${target}`, arr);
        });
    });

    // Delete rank
    $('del-rank-' + rk).addEventListener('click', () => {
        if (confirm(`Rang ${rk} (${rank.label}) wirklich l&ouml;schen?`)) {
            delete State.snapshot.jobs[jobName].ranks[rk];
            patchPath(`jobs.${jobName}.ranks`, State.snapshot.jobs[jobName].ranks);
            State.expandedRanks.delete(jobName + ':' + rk);
            renderRanks(jobName);
        }
    });
}

function addRank(jobName) {
    const j = State.snapshot.jobs[jobName];
    const existing = Object.keys(j.ranks || {}).map(n => parseInt(n));
    const next = existing.length ? Math.max(...existing) + 1 : 0;
    const k = String(next);
    j.ranks = j.ranks || {};
    j.ranks[k] = { label: 'Rang ' + k, permissions: {}, actions: { player: [], vehicle: [] } };
    patchPath(`jobs.${jobName}.ranks`, j.ranks);
    State.expandedRanks.add(jobName + ':' + k);
    renderRanks(jobName);
}

// ============================================================
//  ACTIONS TAB
// ============================================================

function renderActions() {
    const grid = $('actions-grid');
    if (!grid || !State.snapshot) return;
    grid.innerHTML = '';

    const all = State.snapshot.actions || {};
    const filter = State.filters.actions;
    const search = State.filters.actionsSearch;

    const entries = Object.entries(all).filter(([id, a]) => {
        if (filter !== 'all' && a.target !== filter) return false;
        if (search && !id.toLowerCase().includes(search) && !(a.label || '').toLowerCase().includes(search)) return false;
        return true;
    }).sort((a, b) => a[0].localeCompare(b[0]));

    entries.forEach(([id, a]) => {
        const card = document.createElement('div');
        card.className = 'action-card';
        card.innerHTML = `
            <div class="card-icon"><i class="fa-solid ${escapeAttr(a.icon || 'fa-circle')}"></i></div>
            <div class="card-meta">
                <div class="card-id">${escapeHtml(id)}</div>
                <div class="card-label">${escapeHtml(a.label || id)}</div>
                <div class="card-tags">
                    <span class="tag target-${a.target || 'both'}">${a.target || 'both'}</span>
                    ${a.permission ? `<span class="tag perm">${escapeHtml(a.permission)}</span>` : ''}
                    ${a.handler ? `<span class="tag">handler:${escapeHtml(a.handler)}</span>` : ''}
                </div>
            </div>
        `;
        grid.appendChild(card);
    });

    if (entries.length === 0) {
        grid.innerHTML = '<div class="empty-state"><p>Keine Aktionen passen zum Filter.</p></div>';
    }
}

// ============================================================
//  CUSTOM ACTIONS
// ============================================================

let customEditing = null;

function renderCustomActions() {
    const grid = $('custom-list');
    if (!grid || !State.snapshot) return;
    grid.innerHTML = '';

    const all = State.snapshot.customActions || {};
    const entries = Object.entries(all).sort((a, b) => a[0].localeCompare(b[0]));

    if (entries.length === 0) {
        grid.innerHTML = '<div class="empty-state" style="padding:40px;"><i class="fa-solid fa-wand-magic-sparkles"></i><h3>Noch keine Custom-Actions</h3><p>Erstelle eine eigene Action, ohne Lua schreiben zu m&uuml;ssen.</p></div>';
        return;
    }

    entries.forEach(([id, a]) => {
        const card = document.createElement('div');
        card.className = 'action-card';
        card.innerHTML = `
            <div class="card-icon"><i class="fa-solid ${escapeAttr(a.icon || 'fa-bolt')}"></i></div>
            <div class="card-meta">
                <div class="card-id">${escapeHtml(id)}</div>
                <div class="card-label">${escapeHtml(a.label || id)}</div>
                <div class="card-tags">
                    <span class="tag target-${a.target || 'both'}">${a.target || 'both'}</span>
                    <span class="tag">${escapeHtml(a.type)}</span>
                </div>
            </div>
            <div class="card-actions">
                <button class="btn-icon" data-edit="${escapeAttr(id)}" title="Bearbeiten"><i class="fa-solid fa-pen"></i></button>
                <button class="btn-icon danger" data-del="${escapeAttr(id)}" title="L&ouml;schen"><i class="fa-solid fa-trash"></i></button>
            </div>
        `;
        card.querySelector('[data-edit]').addEventListener('click', () => openCustomModal(id));
        card.querySelector('[data-del]').addEventListener('click', () => {
            if (confirm(`Custom-Action "${id}" l&ouml;schen?`)) {
                deletePath('customActions.' + id);
                delete State.snapshot.customActions[id];
                renderCustomActions();
            }
        });
        grid.appendChild(card);
    });
}

function openCustomModal(editId) {
    customEditing = editId || null;
    $('custom-modal-title').textContent = editId ? 'Custom-Action bearbeiten' : 'Neue Custom-Action';

    if (editId && State.snapshot.customActions && State.snapshot.customActions[editId]) {
        const a = State.snapshot.customActions[editId];
        $('custom-id').value = editId;
        $('custom-id').disabled = true;
        $('custom-label').value = a.label || '';
        $('custom-icon').value = a.icon || 'fa-bolt';
        $('custom-target').value = a.target || 'player';
        $('custom-type').value = a.type || 'notify';
        $('custom-payload').value = typeof a.payload === 'string' ? a.payload : JSON.stringify(a.payload || '');
    } else {
        $('custom-id').value = '';
        $('custom-id').disabled = false;
        $('custom-label').value = '';
        $('custom-icon').value = 'fa-bolt';
        $('custom-target').value = 'player';
        $('custom-type').value = 'notify';
        $('custom-payload').value = '';
    }

    updateCustomHint();
    $('custom-modal').classList.remove('hidden');
}

function closeCustomModal() {
    $('custom-modal').classList.add('hidden');
    $('custom-id').disabled = false;
    customEditing = null;
}

function updateCustomHint() {
    const t = $('custom-type').value;
    const hint = $('custom-hint');
    let txt = '';
    if (t === 'notify') txt = 'Payload = Text der dem Spieler angezeigt wird.';
    else if (t === 'event') txt = 'Payload = Client-Event-Name. Whitelist: ' + (State.allowedCustomEvents.join(', ') || '(leer)');
    else if (t === 'serverEvent') txt = 'Payload = Server-Event-Name. Whitelist: ' + (State.allowedCustomEvents.join(', ') || '(leer)');
    else if (t === 'command') txt = 'Payload = Server-Command. Whitelist: ' + (State.allowedCustomCommands.join(', ') || '(leer)');
    hint.textContent = txt;
}

function saveCustomAction() {
    const id = ($('custom-id').value || '').trim();
    if (!/^[a-z][a-z0-9_]{0,49}$/.test(id)) { alert('Ungueltige ID (snake_case).'); return; }

    const def = {
        label: ($('custom-label').value || '').trim() || id,
        icon:  ($('custom-icon').value  || 'fa-bolt').trim(),
        target: $('custom-target').value,
        type:   $('custom-type').value,
        payload: ($('custom-payload').value || '').trim(),
    };

    if (!def.label) { alert('Label fehlt.'); return; }

    patchPath('customActions.' + id, def);
    State.snapshot.customActions = State.snapshot.customActions || {};
    State.snapshot.customActions[id] = def;
    closeCustomModal();
    renderCustomActions();
}

// ============================================================
//  ITEMS TAB
// ============================================================

function renderItems() {
    const wrap = $('items-list');
    if (!wrap || !State.snapshot) return;
    wrap.innerHTML = '';

    const items = State.snapshot.items || {};
    const keys = Object.keys(items).sort();

    if (keys.length === 0) {
        wrap.innerHTML = '<div class="empty-state" style="padding:40px;"><p>Keine Items konfiguriert.</p></div>';
        return;
    }

    keys.forEach(k => {
        const row = document.createElement('div');
        row.className = 'item-row';
        row.innerHTML = `
            <div class="item-key">${escapeHtml(k)}</div>
            <i class="fa-solid fa-arrow-right arrow"></i>
            <input type="text" data-item="${escapeAttr(k)}" value="${escapeAttr(items[k] || '')}">
            <button class="btn-icon danger" data-delitem="${escapeAttr(k)}" title="L&ouml;schen"><i class="fa-solid fa-trash"></i></button>
        `;
        row.querySelector('input').addEventListener('change', e => {
            patchPath('items.' + k, e.target.value);
            items[k] = e.target.value;
        });
        row.querySelector('[data-delitem]').addEventListener('click', () => {
            if (confirm(`Item-Mapping "${k}" l&ouml;schen?`)) {
                deletePath('items.' + k);
                delete items[k];
                renderItems();
            }
        });
        wrap.appendChild(row);
    });
}

function addNewItem() {
    const key = prompt('Item-Schluessel (z.B. lockpick):');
    if (!key) return;
    if (!/^[a-z][a-z0-9_]{0,40}$/.test(key)) { alert('Ungueltiger Schluessel.'); return; }
    if (State.snapshot.items[key] !== undefined) { alert('Schluessel existiert bereits.'); return; }
    const value = prompt('ox_inventory Item-Name:', key);
    if (!value) return;
    patchPath('items.' + key, value);
    State.snapshot.items[key] = value;
    renderItems();
}

// ============================================================
//  GLOBALS TAB
// ============================================================

function renderGlobals() {
    const wrap = $('globals-form');
    if (!wrap || !State.snapshot) return;
    const g = State.snapshot.globals || {};
    const om = g.objectMarkers || {};

    wrap.innerHTML = `
        <div class="form-row">
            <label>UI-Akzent</label>
            <div class="row-with-color">
                <input type="color" id="g-uiColor" value="${escapeAttr(g.uiColor || '#00FFB4')}">
                <input type="text" id="g-uiColor-hex" value="${escapeAttr(g.uiColor || '#00FFB4')}">
            </div>
        </div>
        <div class="form-row">
            <label>Outline-Farbe</label>
            <div class="row-with-color">
                <input type="color" id="g-outlineColor" value="${escapeAttr(g.outlineColor || '#FF3232')}">
                <input type="text" id="g-outlineColor-hex" value="${escapeAttr(g.outlineColor || '#FF3232')}">
            </div>
        </div>
        <div class="form-row">
            <label>Marker-Farbe</label>
            <div class="row-with-color">
                <input type="color" id="g-markerColor" value="${escapeAttr(g.markerColor || '#3296FF')}">
                <input type="text" id="g-markerColor-hex" value="${escapeAttr(g.markerColor || '#3296FF')}">
            </div>
        </div>
        <div class="form-row">
            <label>Default-Theme</label>
            <select id="g-theme">
                ${['glass','dark','neon','redcircle','minimal','custom','cyberpunk','midnight','sunset','royal','hologram','matrix'].map(t => `<option value="${t}" ${g.defaultTheme === t ? 'selected' : ''}>${t}</option>`).join('')}
            </select>
        </div>
        <div class="form-row">
            <label>Menue-Anker</label>
            <select id="g-anchor">
                ${['right','center','bottom'].map(a => `<option value="${a}" ${g.menuAnchor === a ? 'selected' : ''}>${a}</option>`).join('')}
            </select>
        </div>
        <div class="form-row">
            <label>Max-Distanz: <span id="g-dist-val">${g.maxDistance || 9}</span> m</label>
            <input type="range" id="g-distance" min="5" max="12" step="0.5" value="${g.maxDistance || 9}">
        </div>
        <div class="form-row">
            <label>Outline pulsiert</label>
            <label class="toggle-mini"><input type="checkbox" id="g-pulse" ${g.outlinePulse !== false ? 'checked' : ''}><span class="slider"></span></label>
        </div>
        <div class="form-row">
            <label>Pfeil wippt</label>
            <label class="toggle-mini"><input type="checkbox" id="g-bobbing" ${g.markerArrowBobbing !== false ? 'checked' : ''}><span class="slider"></span></label>
        </div>
        <div class="form-row">
            <label>Marker dreht sich</label>
            <label class="toggle-mini"><input type="checkbox" id="g-spin" ${g.markerCircleSpin !== false ? 'checked' : ''}><span class="slider"></span></label>
        </div>
        <div class="form-row">
            <label>Sounds default an</label>
            <label class="toggle-mini"><input type="checkbox" id="g-sounds" ${g.enableSounds !== false ? 'checked' : ''}><span class="slider"></span></label>
        </div>
        <div class="form-row">
            <label>Vehicle-Stats default an</label>
            <label class="toggle-mini"><input type="checkbox" id="g-stats" ${g.showVehicleStats !== false ? 'checked' : ''}><span class="slider"></span></label>
        </div>
        <div class="form-row">
            <label>Default Sound-Preset (Server)</label>
            <select id="g-sound-preset">
                ${['soft','crisp','retro','sci_fi','off'].map(p => `<option value="${p}" ${(g.defaultSoundPreset || 'soft') === p ? 'selected' : ''}>${p}</option>`).join('')}
            </select>
        </div>
        <div class="form-row">
            <label>Default Locale (Server)</label>
            <select id="g-locale">
                ${['de','en'].map(l => `<option value="${l}" ${(g.defaultLocale || 'de') === l ? 'selected' : ''}>${l}</option>`).join('')}
            </select>
        </div>

        <div class="form-section-title">Object-Marker (Props)</div>
        <div class="form-row">
            <label>Aktiviert</label>
            <label class="toggle-mini"><input type="checkbox" id="g-om-enabled" ${(om.enabled !== false) ? 'checked' : ''}><span class="slider"></span></label>
        </div>
        <div class="form-row">
            <label>Marker-Typ</label>
            <select id="g-om-type">
                ${[
                    {v:1,  l:'1 - Boden-Kreis'},
                    {v:2,  l:'2 - Pfeil (Standard)'},
                    {v:20, l:'20 - Chevron-Up'},
                    {v:25, l:'25 - Ring-Flat'},
                    {v:27, l:'27 - Ring-Hoch'},
                    {v:6,  l:'6 - Auswahl-Stern'},
                ].map(o => `<option value="${o.v}" ${Number(om.markerType || 2) === o.v ? 'selected' : ''}>${o.l}</option>`).join('')}
            </select>
        </div>
        <div class="form-row">
            <label>Marker-Skala: <span id="g-om-scale-val">${(om.markerScale || 0.35).toFixed(2)}</span></label>
            <input type="range" id="g-om-scale" min="0.10" max="1.50" step="0.05" value="${om.markerScale || 0.35}">
        </div>
        <div class="form-row">
            <label>Hoehe ueber Prop (yOffset): <span id="g-om-yoff-val">${(om.yOffset || 1.1).toFixed(2)}</span> m</label>
            <input type="range" id="g-om-yoff" min="0.0" max="3.0" step="0.05" value="${om.yOffset || 1.1}">
        </div>
        <div class="form-row">
            <label>Marker-Sicht-Distanz: <span id="g-om-draw-val">${(om.drawDistance || 8).toFixed(1)}</span> m</label>
            <input type="range" id="g-om-draw" min="2" max="20" step="0.5" value="${om.drawDistance || 8}">
        </div>
        <div class="form-row">
            <label>Aktivierungs-Distanz: <span id="g-om-act-val">${(om.activationDistance || 1.8).toFixed(2)}</span> m</label>
            <input type="range" id="g-om-act" min="0.5" max="5.0" step="0.1" value="${om.activationDistance || 1.8}">
        </div>
        <div class="form-row">
            <label>Scan-Radius: <span id="g-om-scan-val">${(om.scanRadius || 12).toFixed(1)}</span> m</label>
            <input type="range" id="g-om-scan" min="4" max="30" step="1" value="${om.scanRadius || 12}">
        </div>
        <div class="form-row">
            <label>Wippen (Bobbing)</label>
            <label class="toggle-mini"><input type="checkbox" id="g-om-bob" ${om.bobbing !== false ? 'checked' : ''}><span class="slider"></span></label>
        </div>
    `;

    const wireColor = (id, key) => {
        const c = $(`g-${id}`);
        const hex = $(`g-${id}-hex`);
        c.addEventListener('input', () => hex.value = c.value.toUpperCase());
        c.addEventListener('change', () => {
            patchPath('globals.' + key, c.value);
            g[key] = c.value;
        });
        hex.addEventListener('change', () => {
            if (/^#[0-9A-Fa-f]{6}$/.test(hex.value)) {
                c.value = hex.value;
                patchPath('globals.' + key, hex.value);
                g[key] = hex.value;
            }
        });
    };
    wireColor('uiColor',      'uiColor');
    wireColor('outlineColor', 'outlineColor');
    wireColor('markerColor',  'markerColor');

    $('g-theme').addEventListener('change',  e => { patchPath('globals.defaultTheme', e.target.value); g.defaultTheme = e.target.value; });
    $('g-anchor').addEventListener('change', e => { patchPath('globals.menuAnchor',   e.target.value); g.menuAnchor   = e.target.value; });
    $('g-distance').addEventListener('input', e => $('g-dist-val').textContent = e.target.value);
    $('g-distance').addEventListener('change',e => { patchPath('globals.maxDistance', parseFloat(e.target.value)); g.maxDistance = parseFloat(e.target.value); });
    $('g-pulse').addEventListener('change',   e => { patchPath('globals.outlinePulse',       e.target.checked); g.outlinePulse = e.target.checked; });
    $('g-bobbing').addEventListener('change', e => { patchPath('globals.markerArrowBobbing', e.target.checked); g.markerArrowBobbing = e.target.checked; });
    $('g-spin').addEventListener('change',    e => { patchPath('globals.markerCircleSpin',   e.target.checked); g.markerCircleSpin = e.target.checked; });
    $('g-sounds').addEventListener('change',  e => { patchPath('globals.enableSounds',       e.target.checked); g.enableSounds = e.target.checked; });
    $('g-stats').addEventListener('change',   e => { patchPath('globals.showVehicleStats',   e.target.checked); g.showVehicleStats = e.target.checked; });
    $('g-sound-preset') && $('g-sound-preset').addEventListener('change', e => { patchPath('globals.defaultSoundPreset', e.target.value); g.defaultSoundPreset = e.target.value; });
    $('g-locale')       && $('g-locale').addEventListener('change',       e => { patchPath('globals.defaultLocale',      e.target.value); g.defaultLocale      = e.target.value; });

    // ---- Object-Marker (Props) ----
    const wireOm = (id, key, parser, formatter) => {
        const el = $(`g-om-${id}`);
        if (!el) return;
        const valEl = $(`g-om-${id}-val`);
        if (valEl) {
            el.addEventListener('input', e => {
                valEl.textContent = formatter ? formatter(e.target.value) : e.target.value;
            });
        }
        el.addEventListener('change', e => {
            const raw = parser ? parser(e.target.value) : e.target.value;
            patchPath('globals.objectMarkers.' + key, raw);
            g.objectMarkers = g.objectMarkers || {};
            g.objectMarkers[key] = raw;
        });
    };
    const wireOmCheck = (id, key) => {
        const el = $(`g-om-${id}`);
        if (!el) return;
        el.addEventListener('change', e => {
            patchPath('globals.objectMarkers.' + key, e.target.checked);
            g.objectMarkers = g.objectMarkers || {};
            g.objectMarkers[key] = e.target.checked;
        });
    };
    const fmt2 = v => Number(v).toFixed(2);
    const fmt1 = v => Number(v).toFixed(1);

    wireOmCheck('enabled', 'enabled');
    wireOm('type',  'markerType',          v => parseInt(v, 10));
    wireOm('scale', 'markerScale',         v => parseFloat(v), fmt2);
    wireOm('yoff',  'yOffset',             v => parseFloat(v), fmt2);
    wireOm('draw',  'drawDistance',        v => parseFloat(v), fmt1);
    wireOm('act',   'activationDistance',  v => parseFloat(v), fmt2);
    wireOm('scan',  'scanRadius',          v => parseFloat(v), fmt1);
    wireOmCheck('bob', 'bobbing');
}

// ============================================================
//  AUDIT TAB
// ============================================================

function getAuditFilter() {
    const actor  = ($('audit-filter-actor')  && $('audit-filter-actor').value  || '').trim();
    const action = ($('audit-filter-action') && $('audit-filter-action').value || '').trim();
    let limit = parseInt(($('audit-filter-limit') && $('audit-filter-limit').value) || '200', 10);
    if (!isFinite(limit) || limit < 10) limit = 200;
    if (limit > 500) limit = 500;
    const opts = { limit };
    if (actor)  opts.actor  = actor;
    if (action) opts.action = action;
    return opts;
}

function refreshAudit() {
    sendToLua('audit', getAuditFilter());
    $('audit-list').innerHTML = '<div class="empty-state"><p>L&auml;dt...</p></div>';
}

function clearAuditFilter() {
    if ($('audit-filter-actor'))  $('audit-filter-actor').value  = '';
    if ($('audit-filter-action')) $('audit-filter-action').value = '';
    if ($('audit-filter-limit'))  $('audit-filter-limit').value  = '200';
    refreshAudit();
}

window.addEventListener('message', (event) => {
    const d = event.data || {};
    if (d.event === 'auditList' && Array.isArray(d.payload)) {
        renderAudit(d.payload);
    } else if (d.event === 'bridgesList' && d.payload) {
        renderBridges(d.payload);
    } else if (d.event === 'bridgeStats' && d.payload) {
        renderBridgeStats(d.payload);
    } else if (d.event === 'storageStatus' && d.payload) {
        renderStorage(d.payload);
    } else if (d.event === 'impoundStatus' && d.payload) {
        renderImpound(d.payload);
    }
});

function renderAudit(list) {
    const wrap = $('audit-list');
    wrap.innerHTML = '';
    if (!list || list.length === 0) {
        wrap.innerHTML = '<div class="empty-state" style="padding:40px;"><p>Noch keine Eintraege.</p></div>';
        return;
    }
    list.slice().reverse().forEach(e => {
        const row = document.createElement('div');
        row.className = 'audit-row';
        const danger = (e.action || '').includes('denied') || (e.action || '').includes('reset');
        row.innerHTML = `
            <div class="ts">${escapeHtml(e.ts || '')}</div>
            <div class="who">${escapeHtml(e.name || 'unknown')}</div>
            <div class="action ${danger ? 'danger' : ''}">${escapeHtml(e.action || '')}</div>
            <div class="details">${escapeHtml(JSON.stringify(e.details || {}))}</div>
        `;
        wrap.appendChild(row);
    });
}

// ============================================================
//  NPCs TAB
// ============================================================

function renderNpcs() {
    const wrap = $('npcs-list');
    if (!wrap || !State.snapshot) return;
    const npcs  = State.snapshot.npcs || {};
    const allActions = collectAllActions();
    const search = State.filters.npcs || '';
    wrap.innerHTML = '';

    const ids = Object.keys(npcs).sort();
    let count = 0;
    ids.forEach(id => {
        const n = npcs[id] || {};
        const blob = (id + ' ' + (n.label||'') + ' ' + (n.model||'')).toLowerCase();
        if (search && !blob.includes(search)) return;
        count++;
        const card = document.createElement('div');
        card.className = 'npc-card';
        const coords = n.coords || {};
        card.innerHTML = `
            <div class="npc-head">
                <div class="npc-title">
                    <i class="fa-solid fa-user-tie"></i>
                    <strong>${escapeHtml(n.label || id)}</strong>
                    <span class="badge">${escapeHtml(id)}</span>
                </div>
                <div class="npc-actions-bar">
                    <button class="btn-ghost" data-act="del-npc" data-id="${escapeAttr(id)}"><i class="fa-solid fa-trash"></i></button>
                </div>
            </div>
            <div class="npc-grid">
                <label>Label<input type="text" data-field="label" value="${escapeAttr(n.label || '')}"></label>
                <label>Modell<input type="text" data-field="model" value="${escapeAttr(n.model || 'a_m_y_business_01')}"></label>
                <label>X<input type="number" step="0.01" data-field="x" value="${coords.x || 0}"></label>
                <label>Y<input type="number" step="0.01" data-field="y" value="${coords.y || 0}"></label>
                <label>Z<input type="number" step="0.01" data-field="z" value="${coords.z || 0}"></label>
                <label>Heading<input type="number" step="1" data-field="heading" value="${n.heading || 0}"></label>
                <label>Job-Filter (optional)<input type="text" data-field="requiredJob" value="${escapeAttr(n.requiredJob || '')}" placeholder="leer = alle"></label>
                <label>Frozen<input type="checkbox" data-field="frozen" ${n.frozen !== false ? 'checked' : ''}></label>
                <label>Invincible<input type="checkbox" data-field="invincible" ${n.invincible !== false ? 'checked' : ''}></label>
            </div>
            <div class="npc-actions">
                <h4>Aktionen</h4>
                <div class="chip-list">
                    ${(n.actions || []).map(a => `
                        <span class="chip">
                            ${escapeHtml(a)}
                            <button data-act="del-npc-action" data-id="${escapeAttr(id)}" data-action="${escapeAttr(a)}"><i class="fa-solid fa-xmark"></i></button>
                        </span>
                    `).join('')}
                    <select data-act="add-npc-action" data-id="${escapeAttr(id)}">
                        <option value="">+ Aktion zuweisen…</option>
                        ${allActions.filter(a => !(n.actions||[]).includes(a.id))
                                    .map(a => `<option value="${escapeAttr(a.id)}">${escapeHtml(a.label)} (${escapeHtml(a.id)})</option>`).join('')}
                    </select>
                </div>
            </div>
        `;
        // Wire field changes
        card.querySelectorAll('input[data-field], select[data-field]').forEach(el => {
            el.addEventListener('change', () => updateNpcField(id, el));
        });
        // Delete NPC
        card.querySelector('[data-act="del-npc"]').addEventListener('click', () => {
            if (confirm('NPC "' + id + '" loeschen?')) {
                deletePath('npcs.' + id);
                delete State.snapshot.npcs[id];
                renderNpcs();
            }
        });
        // Add action
        const addSel = card.querySelector('[data-act="add-npc-action"]');
        addSel && addSel.addEventListener('change', () => {
            if (!addSel.value) return;
            const cur = State.snapshot.npcs[id].actions || [];
            cur.push(addSel.value);
            State.snapshot.npcs[id].actions = cur;
            patchPath('npcs.' + id + '.actions', cur);
            renderNpcs();
        });
        // Remove action
        card.querySelectorAll('[data-act="del-npc-action"]').forEach(btn => {
            btn.addEventListener('click', () => {
                const aid = btn.dataset.action;
                const cur = (State.snapshot.npcs[id].actions || []).filter(x => x !== aid);
                State.snapshot.npcs[id].actions = cur;
                patchPath('npcs.' + id + '.actions', cur);
                renderNpcs();
            });
        });
        wrap.appendChild(card);
    });
    if (count === 0) {
        wrap.innerHTML = '<div class="empty-state" style="padding:40px;"><p>Keine NPCs definiert. Klick oben rechts auf <strong>NPC hinzufuegen</strong>.</p></div>';
    }
}

function updateNpcField(id, el) {
    const f = el.dataset.field;
    const cur = State.snapshot.npcs[id] || {};
    if (f === 'x' || f === 'y' || f === 'z') {
        cur.coords = cur.coords || { x:0, y:0, z:0 };
        cur.coords[f] = parseFloat(el.value) || 0;
        patchPath('npcs.' + id + '.coords', cur.coords);
    } else if (f === 'heading') {
        cur.heading = parseFloat(el.value) || 0;
        patchPath('npcs.' + id + '.heading', cur.heading);
    } else if (el.type === 'checkbox') {
        cur[f] = el.checked;
        patchPath('npcs.' + id + '.' + f, el.checked);
    } else {
        const v = el.value;
        cur[f] = v === '' ? null : v;
        if (v === '') deletePath('npcs.' + id + '.' + f);
        else patchPath('npcs.' + id + '.' + f, v);
    }
    State.snapshot.npcs[id] = cur;
}

function addNewNpc() {
    const id = (prompt('Neue NPC-ID (snake_case, eindeutig):') || '').trim();
    if (!id) return;
    if (!/^[a-z][a-z0-9_]*$/.test(id)) {
        alert('Ungueltige ID. Erlaubt: a-z, 0-9, _');
        return;
    }
    if ((State.snapshot.npcs || {})[id]) {
        alert('NPC-ID existiert bereits.');
        return;
    }
    const def = {
        label: id,
        model: 'a_m_y_business_01',
        coords: { x: 0, y: 0, z: 30.0 },
        heading: 0,
        frozen: true,
        invincible: true,
        actions: [],
    };
    State.snapshot.npcs = State.snapshot.npcs || {};
    State.snapshot.npcs[id] = def;
    patchPath('npcs.' + id, def);
    renderNpcs();
}

// ============================================================
//  ZONES TAB
// ============================================================

function renderZones() {
    const wrap = $('zones-list');
    if (!wrap || !State.snapshot) return;
    const zones = State.snapshot.zones || {};
    const allActions = collectAllActions();
    const search = State.filters.zones || '';
    wrap.innerHTML = '';

    const names = Object.keys(zones).sort();
    let count = 0;
    names.forEach(name => {
        const z = zones[name] || {};
        const blob = (name + ' ' + (z.label||'') + ' ' + (z.type||'')).toLowerCase();
        if (search && !blob.includes(search)) return;
        count++;
        const c = z.coords || {};
        const s = z.size   || {};
        const card = document.createElement('div');
        card.className = 'zone-card';
        card.innerHTML = `
            <div class="npc-head">
                <div class="npc-title">
                    <i class="fa-solid fa-draw-polygon"></i>
                    <strong>${escapeHtml(z.label || name)}</strong>
                    <span class="badge">${escapeHtml(name)}</span>
                    <span class="badge">${escapeHtml(z.type || 'box')}</span>
                </div>
                <div class="npc-actions-bar">
                    <button class="btn-ghost" data-act="del-zone" data-id="${escapeAttr(name)}"><i class="fa-solid fa-trash"></i></button>
                </div>
            </div>
            <div class="npc-grid">
                <label>Label<input type="text" data-field="label" value="${escapeAttr(z.label || '')}"></label>
                <label>Typ
                    <select data-field="type">
                        <option value="box"    ${z.type === 'box'    ? 'selected' : ''}>Box</option>
                        <option value="sphere" ${z.type === 'sphere' ? 'selected' : ''}>Sphere</option>
                    </select>
                </label>
                <label>X<input type="number" step="0.01" data-field="x" value="${c.x || 0}"></label>
                <label>Y<input type="number" step="0.01" data-field="y" value="${c.y || 0}"></label>
                <label>Z<input type="number" step="0.01" data-field="z" value="${c.z || 0}"></label>
                <label>Size X / Radius<input type="number" step="0.1" data-field="sx" value="${s.x || z.radius || 2}"></label>
                <label>Size Y<input type="number" step="0.1" data-field="sy" value="${s.y || 2}"></label>
                <label>Size Z<input type="number" step="0.1" data-field="sz" value="${s.z || 2}"></label>
                <label>Required Job (optional)<input type="text" data-field="requiredJob" value="${escapeAttr(z.requiredJob || '')}" placeholder="leer = alle"></label>
                <label>Required Duty<input type="checkbox" data-field="requiredDuty" ${z.requiredDuty ? 'checked' : ''}></label>
            </div>
            <div class="npc-actions">
                <h4>Aktionen</h4>
                <div class="chip-list">
                    ${(z.actions || []).map(a => `
                        <span class="chip">
                            ${escapeHtml(a)}
                            <button data-act="del-zone-action" data-id="${escapeAttr(name)}" data-action="${escapeAttr(a)}"><i class="fa-solid fa-xmark"></i></button>
                        </span>
                    `).join('')}
                    <select data-act="add-zone-action" data-id="${escapeAttr(name)}">
                        <option value="">+ Aktion zuweisen…</option>
                        ${allActions.filter(a => !(z.actions||[]).includes(a.id))
                                    .map(a => `<option value="${escapeAttr(a.id)}">${escapeHtml(a.label)} (${escapeHtml(a.id)})</option>`).join('')}
                    </select>
                </div>
            </div>
        `;
        card.querySelectorAll('input[data-field], select[data-field]').forEach(el => {
            el.addEventListener('change', () => updateZoneField(name, el));
        });
        card.querySelector('[data-act="del-zone"]').addEventListener('click', () => {
            if (confirm('Zone "' + name + '" loeschen?')) {
                deletePath('zones.' + name);
                delete State.snapshot.zones[name];
                renderZones();
            }
        });
        const addSel = card.querySelector('[data-act="add-zone-action"]');
        addSel && addSel.addEventListener('change', () => {
            if (!addSel.value) return;
            const cur = State.snapshot.zones[name].actions || [];
            cur.push(addSel.value);
            State.snapshot.zones[name].actions = cur;
            patchPath('zones.' + name + '.actions', cur);
            renderZones();
        });
        card.querySelectorAll('[data-act="del-zone-action"]').forEach(btn => {
            btn.addEventListener('click', () => {
                const aid = btn.dataset.action;
                const cur = (State.snapshot.zones[name].actions || []).filter(x => x !== aid);
                State.snapshot.zones[name].actions = cur;
                patchPath('zones.' + name + '.actions', cur);
                renderZones();
            });
        });
        wrap.appendChild(card);
    });
    if (count === 0) {
        wrap.innerHTML = '<div class="empty-state" style="padding:40px;"><p>Keine Zonen definiert. Klick oben rechts auf <strong>Zone hinzufuegen</strong>.</p></div>';
    }
}

function updateZoneField(name, el) {
    const f = el.dataset.field;
    const cur = State.snapshot.zones[name] || {};
    if (f === 'x' || f === 'y' || f === 'z') {
        cur.coords = cur.coords || { x:0, y:0, z:0 };
        cur.coords[f] = parseFloat(el.value) || 0;
        patchPath('zones.' + name + '.coords', cur.coords);
    } else if (f === 'sx' || f === 'sy' || f === 'sz') {
        if (cur.type === 'sphere' && f === 'sx') {
            cur.radius = parseFloat(el.value) || 0;
            patchPath('zones.' + name + '.radius', cur.radius);
        } else {
            cur.size = cur.size || { x:2, y:2, z:2 };
            cur.size[f.slice(1)] = parseFloat(el.value) || 0;
            patchPath('zones.' + name + '.size', cur.size);
        }
    } else if (el.type === 'checkbox') {
        cur[f] = el.checked;
        patchPath('zones.' + name + '.' + f, el.checked);
    } else {
        const v = el.value;
        cur[f] = v === '' ? null : v;
        if (v === '') deletePath('zones.' + name + '.' + f);
        else patchPath('zones.' + name + '.' + f, v);
    }
    State.snapshot.zones[name] = cur;
}

function addNewZone() {
    const name = (prompt('Neuer Zonen-Name (snake_case, eindeutig):') || '').trim();
    if (!name) return;
    if (!/^[a-z][a-z0-9_]*$/.test(name)) {
        alert('Ungueltiger Name. Erlaubt: a-z, 0-9, _');
        return;
    }
    if ((State.snapshot.zones || {})[name]) {
        alert('Zonen-Name existiert bereits.');
        return;
    }
    const def = {
        label: name,
        type: 'box',
        coords: { x: 0, y: 0, z: 30.0 },
        size:   { x: 2, y: 2, z: 2 },
        actions: [],
    };
    State.snapshot.zones = State.snapshot.zones || {};
    State.snapshot.zones[name] = def;
    patchPath('zones.' + name, def);
    renderZones();
}

// ============================================================
//  BRIDGES TAB (read-only)
// ============================================================

function refreshBridges() {
    sendToLua('bridges', {});
    sendToLua('bridgeStats', {});
    $('bridges-list').innerHTML = '<div class="empty-state"><p>L&auml;dt...</p></div>';
    if ($('bridge-stats')) {
        $('bridge-stats').innerHTML = '<div class="empty-state"><p>Lade Stats...</p></div>';
    }
}

function renderBridgeStats(stats) {
    const wrap = $('bridge-stats');
    if (!wrap) return;
    const t = stats.totals || {};
    const r = stats.resources || {};
    const resKeys = Object.keys(r).sort();
    let resHtml = '';
    if (resKeys.length === 0) {
        resHtml = '<p style="opacity:.7;">Keine Drittanbieter-Resourcen registriert.</p>';
    } else {
        resHtml = '<table class="bridge-stats-table">'
            + '<thead><tr><th>Resource</th><th style="text-align:right;">Aktionen</th></tr></thead><tbody>';
        resKeys.forEach(k => {
            resHtml += `<tr><td><code>${escapeHtml(k)}</code></td><td style="text-align:right;">${r[k]}</td></tr>`;
        });
        resHtml += '</tbody></table>';
    }
    wrap.innerHTML = `
        <div class="kpi-row">
            <div class="kpi"><div class="kpi-num">${t.total || 0}</div><div class="kpi-lbl">Total</div></div>
            <div class="kpi"><div class="kpi-num">${t.byTarget || 0}</div><div class="kpi-lbl">Target</div></div>
            <div class="kpi"><div class="kpi-num">${t.byNpc || 0}</div><div class="kpi-lbl">NPC</div></div>
            <div class="kpi"><div class="kpi-num">${t.byZone || 0}</div><div class="kpi-lbl">Zone</div></div>
            <div class="kpi"><div class="kpi-num">${t.byModel || 0}</div><div class="kpi-lbl">Modell</div></div>
        </div>
        ${resHtml}
    `;
}

function renderBridges(data) {
    const wrap = $('bridges-list');
    if (!wrap) return;
    wrap.innerHTML = '';
    const sections = [
        { key: 'byTarget', title: 'Per Target-Type' },
        { key: 'byNpc',    title: 'Per NPC-ID' },
        { key: 'byZone',   title: 'Per Zonen-Name' },
        { key: 'byModel',  title: 'Per Modell-Hash' },
    ];
    let total = 0;
    sections.forEach(sec => {
        const map = data[sec.key] || {};
        const keys = Object.keys(map).sort();
        if (keys.length === 0) return;
        const sect = document.createElement('div');
        sect.className = 'bridge-section';
        sect.innerHTML = `<h3>${escapeHtml(sec.title)}</h3>`;
        keys.forEach(k => {
            const list = map[k] || [];
            if (!list.length) return;
            total += list.length;
            const block = document.createElement('div');
            block.className = 'bridge-block';
            block.innerHTML = `
                <div class="bridge-block-head"><strong>${escapeHtml(k)}</strong><span class="badge">${list.length}</span></div>
                <div class="bridge-actions">
                    ${list.map(a => `
                        <div class="bridge-row">
                            <i class="fa-solid ${escapeAttr(a.icon || 'fa-circle')}"></i>
                            <div class="bridge-meta">
                                <strong>${escapeHtml(a.label || a.id || '?')}</strong>
                                <small>${escapeHtml(a.id || '')} ${a.event ? '· event: ' + escapeHtml(a.event) : ''} ${a.source ? '· src: ' + escapeHtml(a.source) : ''}</small>
                            </div>
                        </div>
                    `).join('')}
                </div>
            `;
            sect.appendChild(block);
        });
        wrap.appendChild(sect);
    });
    if (total === 0) {
        wrap.innerHTML = '<div class="empty-state" style="padding:40px;"><p>Keine Bridge-Aktionen registriert.</p></div>';
    }
}

// ============================================================
//  IDENTITY TAB
// ============================================================

function renderIdentity() {
    const wrap = $('identity-form');
    if (!wrap || !State.snapshot) return;
    const i = State.snapshot.identity || {};
    wrap.innerHTML = `
        <div class="form-row">
            <label>Label fuer unbekannten maennlichen Spieler</label>
            <input type="text" id="i-male"   value="${escapeAttr(i.strangerMale   || 'Fremder')}">
        </div>
        <div class="form-row">
            <label>Label fuer unbekannte weibliche Spielerin</label>
            <input type="text" id="i-female" value="${escapeAttr(i.strangerFemale || 'Fremde')}">
        </div>
        <div class="form-row">
            <label>Fallback (kein Geschlecht bekannt)</label>
            <input type="text" id="i-unknown" value="${escapeAttr(i.strangerUnknown || 'Unbekannte Person')}">
        </div>
        <div class="form-row">
            <label>Hand geben aktiviert</label>
            <label class="toggle-mini"><input type="checkbox" id="i-handshake" ${i.allowHandshake !== false ? 'checked' : ''}><span class="slider"></span></label>
        </div>
        <div class="form-row">
            <label>Visitenkarte aktiviert</label>
            <label class="toggle-mini"><input type="checkbox" id="i-card" ${i.allowCard !== false ? 'checked' : ''}><span class="slider"></span></label>
        </div>
        <div class="form-row">
            <label>Beim Handschlag dauerhaft lernen</label>
            <label class="toggle-mini"><input type="checkbox" id="i-learn" ${i.learnOnHandshake !== false ? 'checked' : ''}><span class="slider"></span></label>
        </div>
        <div class="form-row">
            <label>Handschlag Timeout (ms)</label>
            <input type="number" id="i-timeout" min="2000" max="60000" step="500" value="${i.handshakeTimeoutMs || 10000}">
        </div>
        <div class="form-row">
            <label>Maximale Distanz (Meter)</label>
            <input type="number" id="i-distance" min="1" max="10" step="0.1" value="${i.maxDistance || 3.5}">
        </div>
    `;
    const wireText = (id, key) => $(id).addEventListener('change', e => {
        const v = e.target.value;
        State.snapshot.identity = State.snapshot.identity || {};
        State.snapshot.identity[key] = v;
        patchPath('identity.' + key, v);
    });
    const wireBool = (id, key) => $(id).addEventListener('change', e => {
        State.snapshot.identity = State.snapshot.identity || {};
        State.snapshot.identity[key] = e.target.checked;
        patchPath('identity.' + key, e.target.checked);
    });
    const wireNum = (id, key) => $(id).addEventListener('change', e => {
        const v = parseFloat(e.target.value) || 0;
        State.snapshot.identity = State.snapshot.identity || {};
        State.snapshot.identity[key] = v;
        patchPath('identity.' + key, v);
    });
    wireText('i-male',     'strangerMale');
    wireText('i-female',   'strangerFemale');
    wireText('i-unknown',  'strangerUnknown');
    wireBool('i-handshake','allowHandshake');
    wireBool('i-card',     'allowCard');
    wireBool('i-learn',    'learnOnHandshake');
    wireNum ('i-timeout',  'handshakeTimeoutMs');
    wireNum ('i-distance', 'maxDistance');
}

// ============================================================
//  STORAGE TAB (read-only)
// ============================================================

function refreshStorage() {
    sendToLua('storage', {});
    $('storage-info').innerHTML = '<div class="empty-state"><p>L&auml;dt...</p></div>';
}

function renderStorage(data) {
    const wrap = $('storage-info');
    if (!wrap) return;
    const stat = (label, value, icon) => `
        <div class="storage-stat">
            <i class="fa-solid ${icon || 'fa-circle-check'}"></i>
            <div>
                <strong>${escapeHtml(String(value))}</strong>
                <small>${escapeHtml(label)}</small>
            </div>
        </div>
    `;
    wrap.innerHTML = `
        <div class="storage-grid">
            ${stat('Store-Version', 'v' + (data.version || 0), 'fa-code-commit')}
            ${stat('SQL aktiv',     data.sql ? 'JA' : 'NEIN', data.sql ? 'fa-database' : 'fa-floppy-disk')}
            ${stat('Jobs',          data.jobs || 0, 'fa-briefcase')}
            ${stat('Aktionen',      data.actions || 0, 'fa-bolt')}
            ${stat('Custom-Aktionen',data.customActions || 0, 'fa-wand-magic-sparkles')}
            ${stat('NPCs',          data.npcs || 0, 'fa-user-tie')}
            ${stat('Zonen',         data.zones || 0, 'fa-draw-polygon')}
            ${stat('Bekannte (SQL)',data.knownPlayers || 0, 'fa-id-card')}
            ${stat('Letztes Save',  data.lastSave || '—', 'fa-clock')}
        </div>
    `;
}

// ============================================================
//  HELPER: alle bekannten Aktions-IDs sammeln (Standard + Custom)
// ============================================================

function collectAllActions() {
    const out = [];
    const seen = {};
    const push = a => {
        if (!a || !a.id || seen[a.id]) return;
        seen[a.id] = true;
        out.push({ id: a.id, label: a.label || a.id });
    };
    const acts = (State.snapshot && State.snapshot.actions) || {};
    Object.keys(acts).forEach(k => push({ id: k, label: acts[k].label || k }));
    const custom = (State.snapshot && State.snapshot.customActions) || {};
    Object.keys(custom).forEach(k => push({ id: k, label: custom[k].label || k }));
    out.sort((a,b) => a.label.localeCompare(b.label));
    return out;
}

// ============================================================
//  HELPERS
// ============================================================

function escapeHtml(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
    }[c]));
}
function escapeAttr(s) { return escapeHtml(s); }

// ============================================================
//  IMPOUND TAB (A1 + C12)
// ============================================================

let _impoundCache = null;

function refreshImpound() {
    sendToLua('impound', {});
    if ($('impound-defaults')) $('impound-defaults').innerHTML = '<div class="empty-state"><p>L&auml;dt...</p></div>';
}

function impoundCfg() {
    State.snapshot.impound = State.snapshot.impound || {};
    return State.snapshot.impound;
}

function patchImpound(key, value) {
    const imp = impoundCfg();
    imp[key] = value;
    patchPath('impound.' + key, value);
}

function renderImpound(data) {
    _impoundCache = data || _impoundCache;
    const imp = impoundCfg();
    const def = (data && data.defaults) || {};

    const dWrap = $('impound-defaults');
    if (dWrap) {
        dWrap.innerHTML = `
            <div class="form-row"><label>Default Fee ($)</label><input type="number" id="imp-def-fee"  min="0" step="50"  value="${imp.defaultFee   != null ? imp.defaultFee   : (def.DefaultFee || 5000)}"></div>
            <div class="form-row"><label>Min Fee ($)</label>    <input type="number" id="imp-min-fee"  min="0" step="10"  value="${imp.minFee       != null ? imp.minFee       : (def.MinFee     || 100)}"></div>
            <div class="form-row"><label>Max Fee ($)</label>    <input type="number" id="imp-max-fee"  min="0" step="100" value="${imp.maxFee       != null ? imp.maxFee       : (def.MaxFee     || 100000)}"></div>
            <div class="form-row"><label>Default Lot</label>    <input type="text"   id="imp-def-lot"  value="${escapeAttr(imp.defaultLot || def.DefaultLot || 'los_santos')}"></div>
            <div class="form-row"><label>Payment-Account</label><input type="text"   id="imp-pay-acct" value="${escapeAttr(imp.paymentAccount || def.PaymentAccount || 'bank')}"></div>
            <div class="form-row"><label>Release-Timeout (s)</label><input type="number" id="imp-rel-to" min="60" step="60" value="${imp.releaseTimeoutSec || 600}"></div>
            <div class="form-row"><label>Interaktions-Distanz (m)</label><input type="number" id="imp-int-dist" min="1" max="10" step="0.5" value="${imp.interactDistance || 3.5}"></div>
        `;
        $('imp-def-fee')  && $('imp-def-fee').addEventListener('change',  e => patchImpound('defaultFee',  parseInt(e.target.value, 10) || 0));
        $('imp-min-fee')  && $('imp-min-fee').addEventListener('change',  e => patchImpound('minFee',      parseInt(e.target.value, 10) || 0));
        $('imp-max-fee')  && $('imp-max-fee').addEventListener('change',  e => patchImpound('maxFee',      parseInt(e.target.value, 10) || 0));
        $('imp-def-lot')  && $('imp-def-lot').addEventListener('change',  e => patchImpound('defaultLot',  e.target.value.trim() || 'los_santos'));
        $('imp-pay-acct') && $('imp-pay-acct').addEventListener('change', e => patchImpound('paymentAccount', e.target.value.trim() || 'bank'));
        $('imp-rel-to')   && $('imp-rel-to').addEventListener('change',   e => patchImpound('releaseTimeoutSec', parseInt(e.target.value, 10) || 600));
        $('imp-int-dist') && $('imp-int-dist').addEventListener('change', e => patchImpound('interactDistance',  parseFloat(e.target.value) || 3.5));
    }

    const sWrap = $('impound-stats');
    if (sWrap) {
        const total = (data && data.total) || 0;
        const totalFee = (data && data.totalFee) || 0;
        const perLot = (data && data.perLot) || {};
        let perLotHtml = '';
        Object.keys(perLot).sort().forEach(k => {
            perLotHtml += `<span class="kpi mini"><strong>${perLot[k]}</strong> <small>${escapeHtml(k)}</small></span>`;
        });
        sWrap.innerHTML = `
            <div class="kpi-row">
                <div class="kpi"><div class="kpi-num">${total}</div><div class="kpi-lbl">Beschlagnahmt aktuell</div></div>
                <div class="kpi"><div class="kpi-num">$${totalFee.toLocaleString()}</div><div class="kpi-lbl">Offene Gebuehren</div></div>
            </div>
            <div class="kpi-row">${perLotHtml || '<small style="opacity:.6;">Keine Eintraege.</small>'}</div>
        `;
    }

    renderImpoundLots(data);
    renderImpoundOwners(data);
}

function renderImpoundLots(data) {
    const wrap = $('impound-lots');
    if (!wrap) return;
    const lotsCfg = (impoundCfg().lots) || {};
    const live = (data && data.lots) || [];
    const liveById = {};
    live.forEach(l => { liveById[l.id] = l; });

    const allIds = {};
    Object.keys(lotsCfg).forEach(k => allIds[k] = true);
    live.forEach(l => allIds[l.id] = true);
    const ids = Object.keys(allIds).sort();

    if (ids.length === 0) {
        wrap.innerHTML = '<div class="empty-state" style="padding:30px;"><p>Noch keine Hoefe konfiguriert. Klick <strong>Hof anlegen</strong>.</p></div>';
        return;
    }

    wrap.innerHTML = `<h3 style="margin:18px 0 8px;">Hoefe</h3>` + ids.map(id => {
        const ovr  = lotsCfg[id] || null;
        const liveLot = liveById[id] || { label: id, slots: 0 };
        const label = (ovr && ovr.label) || liveLot.label || id;
        const slotsCount = (ovr && ovr.slots && ovr.slots.length) || liveLot.slots || 0;
        const pay  = (ovr && ovr.payCoords) || {};
        const cam  = (ovr && ovr.releaseCam) || {};
        const liveCount = (data && data.perLot && data.perLot[id]) || 0;
        return `
            <div class="lot-card" data-lot="${escapeAttr(id)}">
                <div class="lot-head">
                    <div>
                        <strong>${escapeHtml(label)}</strong>
                        <code style="margin-left:8px; opacity:.6;">${escapeHtml(id)}</code>
                    </div>
                    <div class="lot-meta">
                        <span>${slotsCount} Slots</span>
                        <span>${liveCount} aktiv</span>
                        <button class="btn-ghost btn-mini" data-act="del" data-lot="${escapeAttr(id)}"><i class="fa-solid fa-trash"></i></button>
                    </div>
                </div>
                <div class="lot-body">
                    <div class="form-row"><label>Label</label><input type="text" data-key="label"  value="${escapeAttr(label)}"></div>
                    <div class="form-row"><label>Pay-Coords (x y z)</label>
                        <input type="text" data-key="payCoords" value="${pay.x != null ? pay.x : ''} ${pay.y != null ? pay.y : ''} ${pay.z != null ? pay.z : ''}" placeholder="409.6 -1622.3 29.3">
                    </div>
                    <div class="form-row"><label>Release-Cam (x y z heading)</label>
                        <input type="text" data-key="releaseCam" value="${cam.x != null ? cam.x : ''} ${cam.y != null ? cam.y : ''} ${cam.z != null ? cam.z : ''} ${cam.h != null ? cam.h : (cam.w != null ? cam.w : '')}" placeholder="445.886 -1622.327 37.313 82.253">
                    </div>
                    <div class="form-row"><label>Slots (eine Zeile pro Slot: x y z heading)</label>
                        <textarea data-key="slots" rows="4" placeholder="409.5 -1623.4 28.3 320">${(ovr && ovr.slots ? ovr.slots.map(s => `${s.x} ${s.y} ${s.z} ${s.h || 0}`).join('\n') : '')}</textarea>
                    </div>
                    <div style="text-align:right;">
                        <button class="btn-primary btn-mini" data-act="save" data-lot="${escapeAttr(id)}"><i class="fa-solid fa-floppy-disk"></i> Speichern</button>
                    </div>
                </div>
            </div>
        `;
    }).join('');

    wrap.querySelectorAll('button[data-act="del"]').forEach(b => {
        b.addEventListener('click', () => {
            const id = b.dataset.lot;
            if (!confirm('Hof "' + id + '" wirklich loeschen?')) return;
            const lots = impoundCfg().lots || {};
            // false-Marker entfernt Default-Hof aus Config.Impound.Lots (siehe server/impound.lua)
            lots[id] = false;
            patchPath('impound.lots.' + id, false);
            impoundCfg().lots = lots;
            refreshImpound();
        });
    });
    wrap.querySelectorAll('button[data-act="save"]').forEach(b => {
        b.addEventListener('click', () => {
            const id = b.dataset.lot;
            const card = wrap.querySelector(`.lot-card[data-lot="${cssEscape(id)}"]`);
            if (!card) return;
            const get = k => card.querySelector(`[data-key="${k}"]`).value.trim();
            const parseVec = s => {
                const parts = s.split(/\s+/).map(parseFloat).filter(n => !isNaN(n));
                return parts;
            };
            const slotsTxt = get('slots');
            const slots = slotsTxt.split(/\n/).map(parseVec).filter(p => p.length >= 3).map(p => ({ x: p[0], y: p[1], z: p[2], h: p[3] || 0 }));
            const pay = parseVec(get('payCoords'));
            const cam = parseVec(get('releaseCam'));
            const lot = {
                label: get('label') || id,
                slots: slots,
            };
            if (pay.length >= 3) lot.payCoords  = { x: pay[0], y: pay[1], z: pay[2] };
            if (cam.length >= 3) lot.releaseCam = { x: cam[0], y: cam[1], z: cam[2], h: cam[3] || 0 };
            const lots = impoundCfg().lots || {};
            lots[id] = lot;
            impoundCfg().lots = lots;
            patchPath('impound.lots.' + id, lot);
        });
    });
}

function cssEscape(s) {
    return String(s).replace(/["\\]/g, '\\$&');
}

function addNewLot() {
    const id = (prompt('Neue Hof-ID (kein Whitespace, z.B. del_perro):') || '').trim().toLowerCase().replace(/\s+/g, '_');
    if (!id) return;
    if (!/^[a-z0-9_]+$/.test(id)) { alert('Nur Kleinbuchstaben/Ziffern/Underscore.'); return; }
    const lots = impoundCfg().lots || {};
    if (lots[id]) { alert('Existiert bereits.'); return; }
    lots[id] = {
        label: id,
        slots: [],
        payCoords:  { x: 0, y: 0, z: 0 },
        releaseCam: { x: 0, y: 0, z: 0, h: 0 },
    };
    impoundCfg().lots = lots;
    patchPath('impound.lots.' + id, lots[id]);
    refreshImpound();
}

function renderImpoundOwners(data) {
    const wrap = $('impound-owners');
    if (!wrap) return;
    const owners = (data && data.owners) || {};
    const ids = Object.keys(owners);
    if (ids.length === 0) {
        wrap.innerHTML = '<h3 style="margin:18px 0 8px;">Per-Spieler</h3><p style="opacity:.7;">Keine Eintraege.</p>';
        return;
    }
    let html = '<h3 style="margin:18px 0 8px;">Per-Spieler</h3>';
    html += '<table class="bridge-stats-table"><thead><tr><th>Spieler-ID</th><th style="text-align:right;">Fahrzeuge</th><th style="text-align:right;">Gesamt-Fee</th><th>Hoefe</th></tr></thead><tbody>';
    ids.sort().forEach(id => {
        const o = owners[id];
        const lots = Object.keys(o.lots || {}).map(k => `${k}:${o.lots[k]}`).join(', ');
        html += `<tr><td><code>${escapeHtml(id)}</code></td><td style="text-align:right;">${o.count || 0}</td><td style="text-align:right;">$${(o.totalFee || 0).toLocaleString()}</td><td>${escapeHtml(lots)}</td></tr>`;
    });
    html += '</tbody></table>';
    wrap.innerHTML = html;
}

// ============================================================
//  THEMES TAB (A2)
// ============================================================

const BUILTIN_THEMES = ['glass','dark','neon','redcircle','minimal','custom','cyberpunk','midnight','sunset','royal','hologram','matrix'];

function themesCfg() {
    State.snapshot.themes = State.snapshot.themes || {};
    return State.snapshot.themes;
}

function renderThemes() {
    const fWrap = $('themes-form');
    const lWrap = $('themes-list');
    if (!fWrap || !lWrap || !State.snapshot) return;
    const g = State.snapshot.globals || {};

    fWrap.innerHTML = `
        <div class="form-row">
            <label>Server-Default-Theme</label>
            <select id="th-default">
                ${BUILTIN_THEMES.map(t => `<option value="${t}" ${(g.defaultTheme || 'glass') === t ? 'selected' : ''}>${t}</option>`).join('')}
            </select>
        </div>
    `;
    $('th-default') && $('th-default').addEventListener('change', e => {
        patchPath('globals.defaultTheme', e.target.value);
        g.defaultTheme = e.target.value;
    });

    const themes = themesCfg();
    const ids = Object.keys(themes).sort();
    if (ids.length === 0) {
        lWrap.innerHTML = '<div class="empty-state" style="padding:30px;"><p>Keine custom Themes. Klick <strong>Theme hinzufuegen</strong> fuer ein neues.</p></div>';
        return;
    }
    lWrap.innerHTML = `<h3 style="margin:18px 0 8px;">Custom Themes</h3>` + ids.map(id => {
        const t = themes[id] || {};
        return `
            <div class="theme-card" data-theme="${escapeAttr(id)}" style="--accent:${escapeAttr(t.accent || '#00ffb4')}; --outline:${escapeAttr(t.outline || '#ff3232')};">
                <div class="theme-card-head">
                    <strong>${escapeHtml(t.label || id)}</strong>
                    <code style="opacity:.6;">${escapeHtml(id)}</code>
                    <button class="btn-ghost btn-mini" data-act="del-theme" data-theme="${escapeAttr(id)}"><i class="fa-solid fa-trash"></i></button>
                </div>
                <div class="theme-preview">
                    <div class="tp-bg"></div>
                    <div class="tp-accent"></div>
                    <div class="tp-outline"></div>
                </div>
                <div class="form-row"><label>Label</label><input type="text" data-key="label" value="${escapeAttr(t.label || id)}"></div>
                <div class="form-row"><label>Akzent (HEX)</label><input type="color" data-key="accent" value="${escapeAttr(t.accent || '#00FFB4')}"></div>
                <div class="form-row"><label>Outline (HEX)</label><input type="color" data-key="outline" value="${escapeAttr(t.outline || '#FF3232')}"></div>
                <div style="text-align:right;"><button class="btn-primary btn-mini" data-act="save-theme" data-theme="${escapeAttr(id)}"><i class="fa-solid fa-floppy-disk"></i> Speichern</button></div>
            </div>
        `;
    }).join('');

    lWrap.querySelectorAll('button[data-act="del-theme"]').forEach(b => {
        b.addEventListener('click', () => {
            const id = b.dataset.theme;
            if (!confirm('Theme "' + id + '" loeschen?')) return;
            delete themes[id];
            deletePath('themes.' + id);
            renderThemes();
        });
    });
    lWrap.querySelectorAll('button[data-act="save-theme"]').forEach(b => {
        b.addEventListener('click', () => {
            const id = b.dataset.theme;
            const card = lWrap.querySelector(`.theme-card[data-theme="${cssEscape(id)}"]`);
            if (!card) return;
            const t = {
                label:   card.querySelector('[data-key="label"]').value.trim() || id,
                accent:  card.querySelector('[data-key="accent"]').value,
                outline: card.querySelector('[data-key="outline"]').value,
            };
            themes[id] = t;
            patchPath('themes.' + id, t);
        });
    });
}

function addNewTheme() {
    const id = (prompt('Theme-ID (z.B. neon_pink):') || '').trim().toLowerCase().replace(/\s+/g, '_');
    if (!id) return;
    if (!/^[a-z0-9_]+$/.test(id)) { alert('Nur Kleinbuchstaben/Ziffern/Underscore.'); return; }
    const themes = themesCfg();
    if (themes[id]) { alert('Existiert bereits.'); return; }
    themes[id] = { label: id, accent: '#00FFB4', outline: '#FF3232' };
    patchPath('themes.' + id, themes[id]);
    renderThemes();
}
