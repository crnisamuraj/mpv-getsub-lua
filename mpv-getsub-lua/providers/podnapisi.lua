-- Podnapisi provider (https://www.podnapisi.net) — web XML interface.
--
-- No key required. Endpoint shape confirmed against the long-lived Kodi
-- addon (amet/service.subtitles.podnapisi) and subliminal:
--   search:   /ppodnapisi/search?sK=<title>&sJ=<iso639-2,...>&sY=<year>
--                                &sTS=<season>&sTE=<episode>&sMH=<osdb_hash>&sXML=1
--   download: /subtitles/<pid>/download   (serves a .zip)
--
-- NOTE: podnapisi.net did not resolve from the development machine during
-- implementation, so this provider is shipped WITHOUT a live end-to-end
-- test. Set provider=podnapisi and press `n` to try it; failures surface
-- as a clean OSD error.

local http = require("modules.http")
local msg = require("mp.msg")
local utils = require("mp.utils")

local SEARCH = "https://www.podnapisi.net/ppodnapisi/search"
local DOWNLOAD = "https://www.podnapisi.net/subtitles/%s/download"

local M = {}
M.name = "podnapisi"

-- ISO-639-1 -> ISO-639-2 for the languages podnapisi indexes.
local LANG_MAP = {
    en = "eng", sr = "srp", hr = "hrv", bs = "bos", sl = "slv",
    mk = "mkd", de = "ger", fr = "fre", es = "spa", it = "ita",
    pt = "por", ru = "rus", pl = "pol", cs = "cze", sk = "slo",
    hu = "hun", ro = "rum", bg = "bul", tr = "tur", ar = "ara",
}

local function url_encode(s)
    return (tostring(s):gsub("[^%w%-%._~ ]", function(c)
        return string.format("%%%02X", string.byte(c))
    end):gsub(" ", "+"))
end

-- Minimal XML helpers for podnapisi's flat <subtitle> documents.
local function tag(xml, name)
    local v = xml:match("<" .. name .. ">(.-)</" .. name .. ">")
    if not v then return "" end
    return (v:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")
             :gsub("&quot;", '"'):gsub("&apos;", "'"))
end

local function each_subtitle(xml)
    return xml:gmatch("<subtitle>(.-)</subtitle>")
end

--- Search by title (+ optional OSDb hash, year, season/episode).
-- @param q { title, hash, languages = {...} }
function M.search(conf, q)
    local langs = {}
    for _, l in ipairs(q.languages or {}) do
        table.insert(langs, LANG_MAP[l:lower()] or l)
    end
    local params = {
        "sK=" .. url_encode(q.title or ""),
        "sJ=" .. table.concat(langs, ","),
        "sXML=1",
    }
    if q.hash then
        table.insert(params, "sMH=" .. q.hash)
    end
    local season, episode = (q.title or ""):lower():match("s(%d%d?)e(%d%d?)")
    if season then
        table.insert(params, "sTS=" .. season)
        table.insert(params, "sTE=" .. episode)
    end

    local ok, status, body, err = http.request({
        method = "GET", url = SEARCH .. "?" .. table.concat(params, "&"),
        headers = { "User-Agent: mpv-getsub-lua v0.1" },
    })
    if not ok then
        return nil, ("podnapisi search failed status=%d %s"):format(status, tostring(err))
    end

    local results = {}
    for sub in each_subtitle(body) do
        local pid = tag(sub, "pid")
        local flags = tag(sub, "flags")
        local release = tag(sub, "release")
        if release == "" then release = tag(sub, "title") end
        local se, ep = tonumber(tag(sub, "tvSeason")), tonumber(tag(sub, "tvEpisode"))
        local hash_hit = q.hash and tag(sub, "exactHashes"):find(q.hash, 1, true) ~= nil
        if pid ~= "" then
            table.insert(results, {
                id = pid,
                release = release,
                title = tag(sub, "title"),
                language = tag(sub, "languageName"),
                downloads = tonumber(tag(sub, "downloads")) or 0,
                rating = tonumber(tag(sub, "rating")) or 0,
                hearing_impaired = flags:find("n", 1, true) ~= nil,
                season = se, episode = ep,
                from_trusted = hash_hit or false, -- hash match == exact sync
                pid = pid,
                -- no format: downloads arrive as zip; the extracted file is
                -- moved onto the (srt-suffixed) dest and mpv content-detects
                provider = M.name,
            })
        end
    end
    return results, nil
end

--- Download a result. Podnapisi serves a zip; extract the first subtitle file.
function M.download(conf, result, dest)
    if not result.pid then return false, "no pid" end
    local tmp = dest .. ".podnapisi.zip"
    local ok, err = http.download(DOWNLOAD:format(result.pid), tmp,
        { "User-Agent: mpv-getsub-lua v0.1" })
    if not ok then
        return false, err
    end

    -- extract into a temp dir next to the destination
    local dir = dest .. ".podnapisi.d"
    local r = utils.subprocess({ args = { "mkdir", "-p", dir }, capture_stdout = true })
    r = utils.subprocess({
        args = { "unzip", "-o", "-j", tmp, "-d", dir },
        capture_stdout = true, capture_stderr = true, playback_only = false,
    })
    os.remove(tmp)
    if r.status ~= 0 then
        return false, "unzip failed: " .. (r.stderr or "")
    end

    -- pick the first subtitle-looking file
    local picked
    for _, name in ipairs(utils.readdir(dir, "files") or {}) do
        if name:match("%.[sS][rR][tT]$") or name:match("%.[aA][sS][sS]$")
            or name:match("%.[sS][sS][aA]$") or name:match("%.[vV][tT][tT]$") then
            picked = name
            break
        end
    end
    if not picked then
        return false, "no subtitle file inside archive"
    end

    local mv = utils.subprocess({
        args = { "mv", utils.join_path(dir, picked), dest },
        capture_stdout = true, playback_only = false,
    })
    utils.subprocess({ args = { "rm", "-rf", dir }, capture_stdout = true, playback_only = false })
    if mv.status ~= 0 then
        return false, "could not move extracted subtitle"
    end
    return true, nil
end

return M
