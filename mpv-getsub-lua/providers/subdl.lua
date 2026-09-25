-- Subdl provider (https://subdl.com), API v2.
--
-- Auth:  Authorization: *** <api_key>   for api.subdl.com
--        X-API-Key: <api_key>          for dl.subdl.com downloads
-- The response of /files/search already embeds a `subtitles` array; passing
-- unpack=1 makes downloads serve the raw subtitle file (no zip handling).
-- Shape confirmed against ocsh/mpv-subhanallah.

local http = require("modules.http")
local msg = require("mp.msg")

local FILE_SEARCH = "https://api.subdl.com/api/v2/files/search"
local API_BASE = "https://api.subdl.com"
local DOWNLOAD_BASE = "https://dl.subdl.com"

local M = {}
M.name = "subdl"

local function url_encode(s)
    return (tostring(s):gsub("[^%w%-%._~ ]", function(c)
        return string.format("%%%02X", string.byte(c))
    end):gsub(" ", "+"))
end

local function api_headers(conf)
    return { "Authorization: Bearer " .. (conf.subdl_api_key or "") }
end

--- Search Subdl by filename/title.
-- @param conf config
-- @param q    { title, languages = {...} }
function M.search(conf, q)
    if (conf.subdl_api_key or "") == "" then
        return nil, "subdl_api_key not set in mpv-getsub-lua.conf"
    end
    local langs = table.concat(q.languages or {}, ",")
    local url = FILE_SEARCH
        .. "?filename=" .. url_encode(q.title or "")
        .. "&languages=" .. url_encode(langs)
        .. "&episode_scope=exact&subs_per_page=30&unpack=1"

    local ok, status, data, _, err = http.request_json({
        method = "GET", url = url, headers = api_headers(conf),
    })
    if not ok or not data then
        return nil, ("subdl search failed status=%d %s"):format(status, tostring(err))
    end
    if data.status == false then
        return nil, "subdl: " .. tostring(data.error or data.message or "search error")
    end

    local results = {}
    for _, item in ipairs(data.subtitles or {}) do
        table.insert(results, {
            id = item.sd_id,
            release = item.release_name or item.name or "?",
            language = (item.language or ""):lower(),
            downloads = item.downloads or 0,
            hearing_impaired = item.hi == true or item.hi == 1,
            title = item.name or "",
            season = item.season,
            episode = item.episode,
            from_trusted = item.author == "admin",
            format = item.format,
            url = item.url,
            provider = M.name,
        })
    end
    return results, nil
end

--- Download a result. Subdl serves raw subtitle files when unpack=1.
function M.download(conf, result, dest)
    if not result.url or result.url == "" then
        return false, "no download url"
    end
    local url = result.url
    if url:match("^/subtitle/") then
        url = DOWNLOAD_BASE .. url
    elseif url:sub(1, 1) == "/" then
        url = API_BASE .. url
    end
    return http.download(url, dest, {
        "X-API-Key: " .. (conf.subdl_api_key or ""),
    })
end

return M
