--------------------------------------------------------
-- NoScript plugin for luakit                         --
-- (C) 2011 Mason Larobina <mason.larobina@gmail.com> --
--------------------------------------------------------

-- Get Lua environment
local os = require "os"
local tonumber = tonumber
local assert = assert
local table = table
local string = string

-- Get luakit environment
local webview = webview
local add_binds = add_binds
local lousy = require "lousy"
local sql_escape = lousy.util.sql_escape
local capi = { luakit = luakit, sqlite3 = sqlite3 }

module "noscript"

-- Default blocking values
enable_scripts = true
enable_plugins = true

create_table = [[
CREATE TABLE IF NOT EXISTS by_domain (
    id INTEGER PRIMARY KEY,
    domain TEXT,
    enable_scripts INTEGER,
    enable_plugins INTEGER
);]]

db = capi.sqlite3{ filename = capi.luakit.data_dir .. "/noscript.db" }
db:exec("PRAGMA synchronous = OFF; PRAGMA secure_delete = 1;")
db:exec(create_table)

local function btoi(bool) return bool and 1 or 0    end
local function itob(int)  return tonumber(int) ~= 0 end

local function get_domain(uri)
    uri = lousy.uri.parse(uri)
    -- uri parsing will fail on some URIs, e.g. "about:blank"
    return uri and string.lower(uri.host) or nil
end

local function match_domain(domain)
    local rows = db:exec(string.format("SELECT * FROM by_domain "
        .. "WHERE domain == %s;", sql_escape(domain)))
    if rows[1] then return rows[1] end
end

local function update(id, field, value)
    db:exec(string.format("UPDATE by_domain SET %s = %d WHERE id == %d;",
        field, btoi(value), id))
end

local function insert(domain, enable_scripts, enable_plugins)
    db:exec(string.format("INSERT INTO by_domain VALUES (NULL, %s, %d, %d);",
        sql_escape(domain), btoi(enable_scripts), btoi(enable_plugins)))
end

function webview.methods.toggle_scripts(view, w)
    local domain = get_domain(view.uri)
    local enable_scripts = _M.enable_scripts
    local row = match_domain(domain)

    if row then
        enable_scripts = itob(row.enable_scripts)
        update(row.id, "enable_scripts", not enable_scripts)
    else
        insert(domain, not enable_scripts, _M.enable_plugins)
    end

    w:notify(string.format("%sabled scripts for domain: %s",
        enable_scripts and "Dis" or "En", domain))
end

function webview.methods.toggle_plugins(view, w)
    local domain = get_domain(view.uri)
    local enable_plugins = _M.enable_plugins
    local row = match_domain(domain)

    if row then
        enable_plugins = itob(row.enable_plugins)
        update(row.id, "enable_plugins", not enable_plugins)
    else
        insert(domain, _M.enable_scripts, not enable_plugins)
    end

    w:notify(string.format("%sabled plugins for domain: %s",
        enable_plugins and "Dis" or "En", domain))
end

function webview.methods.toggle_remove(view, w)
    local domain = get_domain(view.uri)
    db:exec(string.format("DELETE FROM by_domain WHERE domain == %s;",
        sql_escape(domain)))
    w:notify("Removed rules for domain: " .. domain)
end

function string.starts(a, b)
    return string.sub(a, 1, string.len(b)) == b
end

local function lookup_domain(uri)
    local enable_scripts, enable_plugins = _M.enable_scripts, _M.enable_plugins
    local full_match = true
    local domain = get_domain(uri)

    -- Enable everything for chrome pages; without this, chrome pages which
    -- depend upon javascript will break
    if string.starts(uri, "luakit://") then return true, true, true end

    -- Look up this domain and all parent domains, returning the first match
    -- E.g. querying a.b.com will lookup a.b.com, then b.com, then com
    while domain do
        local row = match_domain(domain)
        if row then
            enable_scripts = itob(row.enable_scripts)
            enable_plugins = itob(row.enable_plugins)
            break
        end
        full_match = false
        domain = string.match(domain, "%.(.+)")
    end

    -- full_match is true if the domain of the matched record is equal to the
    -- full subdomain of the given URI
    -- E.g. a.b.com matched to b.com will return false, but will return true if
    -- matched to a.b.com; intended for use in indicators/widgets
    return enable_scripts, enable_plugins, full_match
end

function webview.methods.noscript_state(view, w)
    if view.uri then
        return lookup_domain(view.uri)
    end
end

webview.init_funcs.noscript_load = function (view)
    view:add_signal("load-status", function (v, status)
        if status == "provisional" then
            view.enable_scripts = enable_scripts
            view.enable_plugins = enable_plugins
            return
        end
        if status == "committed" and v.uri ~= "about:blank" then
            local enable_scripts, enable_plugins, _ = lookup_domain(v.uri)
            view.enable_scripts = enable_scripts
            view.enable_plugins = enable_plugins
        end
    end)
end

local buf = lousy.bind.buf
add_binds("normal", {
    buf("^,ts$", function (w) w:toggle_scripts() end),
    buf("^,tp$", function (w) w:toggle_plugins() end),
    buf("^,tr$", function (w) w:toggle_remove()  end),
})
