--[[
    clp_gmenu - Gemeinsame Hilfsfunktionen

    Helfer fuer Client + Server (Farben, Tabellen, Validierung).
]]

GMenu = GMenu or {}
GMenu.Util = {}

local U = GMenu.Util

-- ============================================================
--  FARB-HELFER
-- ============================================================

--- RGB-Tabelle {r,g,b} zu Hex-String "#RRGGBB"
function U.rgbToHex(rgb)
    if type(rgb) ~= 'table' then return '#000000' end
    local r = math.max(0, math.min(255, math.floor(tonumber(rgb.r) or 0)))
    local g = math.max(0, math.min(255, math.floor(tonumber(rgb.g) or 0)))
    local b = math.max(0, math.min(255, math.floor(tonumber(rgb.b) or 0)))
    return string.format('#%02X%02X%02X', r, g, b)
end

--- Hex-String "#RRGGBB" oder "RRGGBB" zu {r,g,b}
function U.hexToRgb(hex)
    if type(hex) ~= 'string' then return { r = 0, g = 0, b = 0 } end
    hex = hex:gsub('#', '')
    if #hex ~= 6 then return { r = 0, g = 0, b = 0 } end
    return {
        r = tonumber(hex:sub(1, 2), 16) or 0,
        g = tonumber(hex:sub(3, 4), 16) or 0,
        b = tonumber(hex:sub(5, 6), 16) or 0,
    }
end

--- RGB-Tabelle zu CSS rgba()-String
function U.rgbToCss(rgb, alpha)
    if type(rgb) ~= 'table' then return 'rgba(0,0,0,1)' end
    return string.format('rgba(%d,%d,%d,%s)', rgb.r or 0, rgb.g or 0, rgb.b or 0, tostring(alpha or 1))
end

-- ============================================================
--  TABELLEN-HELFER
-- ============================================================

--- Tiefe Kopie einer Tabelle (sicher gegen Zyklen via seen-Set)
function U.deepCopy(orig, seen)
    seen = seen or {}
    if type(orig) ~= 'table' then return orig end
    if seen[orig] then return seen[orig] end
    local copy = {}
    seen[orig] = copy
    for k, v in pairs(orig) do
        copy[U.deepCopy(k, seen)] = U.deepCopy(v, seen)
    end
    return copy
end

--- Zusammenfuehren von src in dst (in-place). dst gewinnt nicht; src ueberschreibt.
function U.deepMerge(dst, src)
    if type(dst) ~= 'table' or type(src) ~= 'table' then return dst end
    for k, v in pairs(src) do
        if type(v) == 'table' and type(dst[k]) == 'table' then
            U.deepMerge(dst[k], v)
        else
            dst[k] = v
        end
    end
    return dst
end

--- Liefert true wenn beide Tabellen identisch sind (rekursiver Vergleich)
function U.deepEqual(a, b)
    if a == b then return true end
    if type(a) ~= 'table' or type(b) ~= 'table' then return false end
    for k, v in pairs(a) do
        if not U.deepEqual(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

--- Pfad-Zugriff: GetByPath({ a = { b = 1 }}, 'a.b') -> 1
function U.getByPath(tbl, path)
    if type(tbl) ~= 'table' or type(path) ~= 'string' or path == '' then return nil end
    local cur = tbl
    for part in path:gmatch('[^.]+') do
        if type(cur) ~= 'table' then return nil end
        cur = cur[part]
    end
    return cur
end

--- Pfad-Setzen: SetByPath({}, 'a.b', 1) -> { a = { b = 1 }}
function U.setByPath(tbl, path, value)
    if type(tbl) ~= 'table' or type(path) ~= 'string' or path == '' then return false end
    local parts = {}
    for part in path:gmatch('[^.]+') do parts[#parts + 1] = part end
    if #parts == 0 then return false end
    local cur = tbl
    for i = 1, #parts - 1 do
        local p = parts[i]
        if type(cur[p]) ~= 'table' then cur[p] = {} end
        cur = cur[p]
    end
    cur[parts[#parts]] = value
    return true
end

--- Pfad-Loeschen: DeleteByPath({ a = { b = 1 }}, 'a.b')
function U.deleteByPath(tbl, path)
    if type(tbl) ~= 'table' or type(path) ~= 'string' then return false end
    local parts = {}
    for part in path:gmatch('[^.]+') do parts[#parts + 1] = part end
    if #parts == 0 then return false end
    local cur = tbl
    for i = 1, #parts - 1 do
        if type(cur) ~= 'table' then return false end
        cur = cur[parts[i]]
    end
    if type(cur) ~= 'table' then return false end
    cur[parts[#parts]] = nil
    return true
end

--- Liefert die Anzahl der Eintraege (auch fuer Hash-Tabellen)
function U.tableCount(t)
    if type(t) ~= 'table' then return 0 end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

--- Liefert true wenn ein Wert in der Liste enthalten ist
function U.tableContains(list, value)
    if type(list) ~= 'table' then return false end
    for i = 1, #list do
        if list[i] == value then return true end
    end
    return false
end

-- ============================================================
--  TEXT / VALIDIERUNG
-- ============================================================

--- Entfernt Leerzeichen am Anfang und Ende
function U.trim(s)
    if type(s) ~= 'string' then return '' end
    return s:match('^%s*(.-)%s*$') or ''
end

--- ESX-Job-Namen: klein, alphanumerisch, _ erlaubt, max 30 Zeichen
function U.isValidJobName(name)
    if type(name) ~= 'string' then return false end
    if #name == 0 or #name > 30 then return false end
    return name:match('^[a-z0-9_]+$') ~= nil
end

--- Berechtigungs-Keys: alphanumerisch, max 40 Zeichen
function U.isValidPermissionKey(name)
    if type(name) ~= 'string' then return false end
    if #name == 0 or #name > 40 then return false end
    return name:match('^[A-Za-z][A-Za-z0-9_]*$') ~= nil
end

--- Aktions-IDs: snake_case, max 50 Zeichen
function U.isValidActionId(id)
    if type(id) ~= 'string' then return false end
    if #id == 0 or #id > 50 then return false end
    return id:match('^[a-z][a-z0-9_]*$') ~= nil
end

-- ============================================================
--  RANG-SORTIERUNG
-- ============================================================

--- Liefert Rang-Keys numerisch sortiert (1, 2, 10 statt "1", "10", "2")
function U.sortedRankKeys(ranks)
    if type(ranks) ~= 'table' then return {} end
    local keys = {}
    for k in pairs(ranks) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        return (tonumber(a) or 0) < (tonumber(b) or 0)
    end)
    return keys
end

-- ============================================================
--  SCHEMA-VALIDIERUNG
-- ============================================================

--- Validiert eine Job-Definition. Liefert true oder false + Fehlermeldung
function U.validateJob(job)
    if type(job) ~= 'table' then return false, 'Job muss eine Tabelle sein' end
    if type(job.label) ~= 'string' or #job.label == 0 then return false, 'job.label ist erforderlich' end
    if type(job.ranks) ~= 'table' or U.tableCount(job.ranks) == 0 then return false, 'job.ranks ist erforderlich' end
    for rankKey, rank in pairs(job.ranks) do
        if not tonumber(rankKey) then return false, ('Rang-Key "%s" muss numerisch sein'):format(tostring(rankKey)) end
        if type(rank) ~= 'table' then return false, 'Rang muss eine Tabelle sein' end
        if type(rank.label) ~= 'string' then return false, 'rank.label ist erforderlich' end
        if rank.permissions and type(rank.permissions) ~= 'table' then return false, 'rank.permissions muss eine Tabelle sein' end
        if rank.actions and type(rank.actions) ~= 'table' then return false, 'rank.actions muss eine Tabelle sein' end
        if rank.actions then
            if rank.actions.player and type(rank.actions.player) ~= 'table' then return false, 'rank.actions.player muss eine Tabelle sein' end
            if rank.actions.vehicle and type(rank.actions.vehicle) ~= 'table' then return false, 'rank.actions.vehicle muss eine Tabelle sein' end
        end
    end
    return true
end

--- Validiert eine Aktions-Definition.
function U.validateAction(action)
    if type(action) ~= 'table' then return false, 'Aktion muss eine Tabelle sein' end
    if type(action.label) ~= 'string' or #action.label == 0 then return false, 'action.label ist erforderlich' end
    if type(action.target) ~= 'string' then return false, 'action.target ist erforderlich' end
    if action.target ~= 'player' and action.target ~= 'vehicle' and action.target ~= 'both' then
        return false, 'action.target muss player|vehicle|both sein'
    end
    return true
end

--- Validiert eine Custom-Aktion.
function U.validateCustomAction(action)
    local ok, err = U.validateAction(action)
    if not ok then return false, err end
    if type(action.type) ~= 'string' then return false, 'customAction.type ist erforderlich' end
    local valid = action.type == 'event' or action.type == 'serverEvent'
        or action.type == 'command' or action.type == 'notify'
    if not valid then return false, 'customAction.type muss event|serverEvent|command|notify sein' end
    return true
end

-- ============================================================
--  DEBUG
-- ============================================================

function U.debug(...)
    if Config and Config.Debug then
        print('^5[clp_gmenu]^0', ...)
    end
end
