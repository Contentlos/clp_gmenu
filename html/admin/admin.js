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
            if (target === 'audit') refreshAudit();
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

    // Audit refresh
    $('btn-refresh-audit').addEventListener('click', refreshAudit);

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
                ${['glass','dark','neon','redcircle'].map(t => `<option value="${t}" ${g.defaultTheme === t ? 'selected' : ''}>${t}</option>`).join('')}
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
}

// ============================================================
//  AUDIT TAB
// ============================================================

function refreshAudit() {
    sendToLua('audit', { limit: 200 });
    // Antwort kommt nicht automatisch zurueck (der Parent muss cb-Antwort
    // wieder per postMessage forwarden). Wir setzen optimistisch ein
    // Lade-Zeichen.
    $('audit-list').innerHTML = '<div class="empty-state"><p>L&auml;dt...</p></div>';
}

window.addEventListener('message', (event) => {
    const d = event.data || {};
    if (d.event === 'auditList' && Array.isArray(d.payload)) {
        renderAudit(d.payload);
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
//  HELPERS
// ============================================================

function escapeHtml(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
    }[c]));
}
function escapeAttr(s) { return escapeHtml(s); }
