-- OpenSubtitles REST v1 provider.
-- Docs: https://opensubtitles.stoplight.io/docs/opensubtitles-api
--
-- Auth model:
--   * Every request sends  Api-Key: <app key>   (identifies the consumer app)
--   * If username+password are configured we POST /login once and reuse the
--     returned JWT as  Authorization: Bearer <token>, so downloads count
--     against the USER's quota instead of the app's shared/anonymous limits.

local http = require("modules.http")
local msg = require("mp.msg")
local utils = require("mp.utils")

local API = "https://api.opensubtitles.com/api/v1"
local UA = "mpv-getsub-lua v0.1"

local M = {}
M.name = "opensubtitles"

local function base_headers(conf)
    return {
        "User-Agent: " .. UA,
        "Api-Key: " .. (conf.api_key or ""),
    }
end

-- Lazily log in and cache the JWT on M._token.
local function ensure_token(conf)
    if M._token then return true end
    if (conf.username or "") == "" or (conf.password or "") == "" then
        return false -- run anonymously against the app key
    end
    local headers = base_headers(conf)
    local ok, status, data, _, err = http.request_json({
        method = "POST",
        url = API .. "/login",
        headers = headers,
        body = utils.format_json({ username = conf.username, password = conf.password }),
    })
    if not ok or not data or not data.token then
        msg.warn("opensubtitles login failed status=" .. tostring(status) .. " " .. tostring(err))
        return false
    end
    M._token = data.token
    msg.info("opensubtitles: logged in as " .. conf.username)
    return true
end

local function auth_headers(conf)
    local h = base_headers(conf)
    if ensure_token(conf) then
        table.insert(h, "Authorization: Bearer " .. M._token)
    end
    return h
end

--- Search for subtitles.
-- @param conf   config table
-- @param q      table: { hash, size, filename, title, languages = {...} }
-- @return results array, err
function M.search(conf, q)
    local params = {}
    if q.languages and #q.languages > 0 then
        table.insert(params, "languages=" .. table.concat(q.languages, ","))
    end
    if q.hash then
        table.insert(params, "moviehash=" .. q.hash)
    end
    if q.title and q.title ~= "" then
        table.insert(params, "query=" .. url_encode(q.title))
    end
    local url = API .. "/subtitles?" .. table.concat(params, "&")

    local ok, status, data, _, err = http.request_json({
        method = "GET", url = url, headers = auth_headers(conf),
    })
    if not ok or not data then
        return nil, ("search failed status=%d %s"):format(status, tostring(err))
    end

    local results = {}
    for _, item in ipairs(data.data or {}) do
        local a = item.attributes or {}
        local files = a.files or {}
        local f = files[1] or {}
        local feat = a.feature_details or {}
        table.insert(results, {
            id = item.id,
            file_id = f.file_id,
            release = a.release or f.file_name or "?",
            language = a.language,
            downloads = a.download_count or 0,
            hearing_impaired = a.hearing_impaired or false,
            fps = a.fps,
            title = feat.movie_name or feat.title or "",
            year = feat.year,
            season = feat.season_number,
            episode = feat.episode_number,
            from_trusted = a.from_trusted or false,
            provider = M.name,
        })
    end
    return results, nil
end

--- Resolve a download URL for a result's file_id, then download to dest.
-- OpenSubtitles requires POST /download with {file_id} to get a fresh link.
function M.download(conf, result, dest)
    if not result.file_id then
        return false, "no file_id"
    end
    local ok, status, data, raw, err = http.request_json({
        method = "POST",
        url = API .. "/download",
        headers = auth_headers(conf),
        body = utils.format_json({ file_id = result.file_id }),
    })
    if not ok or not data or not data.link then
        return false, ("download-link failed status=%d %s"):format(status, tostring(err or raw))
    end
    return http.download(data.link, dest, { "User-Agent: " .. UA })
end

function url_encode(s)
    return (s:gsub("[^%w%-%._~ ]", function(c)
        return string.format("%%%02X", string.byte(c))
    end):gsub(" ", "+"))
end

return M
