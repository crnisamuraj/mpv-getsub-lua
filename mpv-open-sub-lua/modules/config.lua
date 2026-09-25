-- Configuration for mpv-open-sub-lua.
--
-- Options are read from  <script-opts>/mpv-open-sub-lua.conf
-- (i.e. ~/.config/mpv/script-opts/mpv-open-sub-lua.conf) via mpv's mp.options
-- module, so they also work when injected into Haruna.

local options = require("mp.options")

local defaults = {
    -- Provider to use. Currently only "opensubtitles" is implemented.
    provider = "opensubtitles",

    -- Preferred subtitle languages, comma-separated ISO-639 codes.
    -- e.g. "en,sr,hr"
    languages = "en",

    -- OpenSubtitles REST API key identifying THIS app (the "consumer").
    -- Leave empty to be prompted / use only the login flow.
    api_key = "",

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

local conf = {}
options.read_options(conf, "mpv-open-sub-lua")

-- Merge over defaults so missing keys still have sane values.
for k, v in pairs(defaults) do
    if conf[k] == nil then
        conf[k] = v
    end
end

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
