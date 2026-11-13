-- Configuration for mpv-getsub-lua.
--
-- Primary source: mpv's script-opts machinery (works in plain mpv and in
-- players that enable config loading, e.g. Celluloid).
--
-- Fallback: libmpv embedders like Haruna initialize mpv with config=no, so
-- mp.options never sees any file. In that case we parse the conf ourselves
-- from the standard XDG locations. Values set by mpv take precedence; the
-- manual pass only fills keys still at their defaults.

local options = require("mp.options")
local msg = require("mp.msg")

local defaults = {
    -- Provider to use: "opensubtitles", "subdl" or "podnapisi".
    provider = "opensubtitles",

    -- Preferred subtitle languages, comma-separated ISO-639 codes.
    -- e.g. "en,sr,hr"
    languages = "en",

    -- OpenSubtitles REST API key identifying THIS app (the "consumer").
    -- Leave empty to be prompted / use only the login flow.
    api_key = "",

    -- Subdl API key (https://subdl.com), used when provider=subdl.
    subdl_api_key = "",

    -- Optional OpenSubtitles user credentials. When set, the script logs in
    -- and downloads against the USER's own quota instead of the app's
    -- anonymous/key-based limits. Password can be left empty and filled by a
    -- secret store later; it is NOT stored by this script.
    username = "",
    password = "",

    -- Where to save downloaded subtitles. Special values:
    --   "video"  -> next to the video file (default, same basename)
    --   any absolute path -> that directory
    save_to = "video",

    -- Automatically pick the single best match instead of showing the picker.
    auto_select = false,

    -- Key binding is registered separately; see main.lua.
    osd_duration_ms = 8000,

    -- Extra curl flags, e.g. for proxies. Kept as a single string.
    curl_extra = "",
}

-- read_options validates each key against the table passed in, so read
-- directly into the defaults table (which contains every valid key).
local conf = defaults
options.read_options(conf, "mpv-getsub-lua")

-- ---- fallback manual parse (for config=no embedders like Haruna) ----

local function candidate_paths()
    local home = os.getenv("HOME") or ""
    local xdg = os.getenv("XDG_CONFIG_HOME")
    if not xdg or xdg == "" then
        xdg = home .. "/.config"
    end
    return {
        xdg .. "/mpv/script-opts/mpv-getsub-lua.conf",
        xdg .. "/celluloid/script-opts/mpv-getsub-lua.conf",
        home .. "/.mpv/script-opts/mpv-getsub-lua.conf",
    }
end

local function coerce(key, raw)
    local d = defaults[key]
    if type(d) == "boolean" then
        return raw == "yes" or raw == "true" or raw == "1"
    end
    if type(d) == "number" then
        return tonumber(raw) or d
    end
    return raw
end

local function manual_fill()
    for _, path in ipairs(candidate_paths()) do
        local f = io.open(path, "r")
        if f then
            msg.info("config: reading fallback file " .. path)
            for line in f:lines() do
                local k, v = line:match("^%s*([%w_%-]+)%s*=%s*(.-)%s*$")
                if k and defaults[k] ~= nil
                    and (conf[k] == nil or conf[k] == defaults[k]) then
                    conf[k] = coerce(k, v)
                end
            end
            f:close()
            return
        end
    end
end

manual_fill()

function conf.language_list()
    local out = {}
    for lang in string.gmatch(conf.languages or "", "[^,%s]+") do
        table.insert(out, lang)
    end
    if #out == 0 then
        out = { "en" }
    end
    return out
end

return conf
