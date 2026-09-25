-- Thin curl wrapper over mpv's utils.subprocess.
-- No luasocket / no external Lua deps. Returns parsed JSON tables.

local utils = require("mp.utils")
local msg = require("mp.msg")

local M = {}

--- Perform an HTTP request via curl.
-- @param opts table:
--   method  "GET" | "POST"  (default GET)
--   url     string
--   headers array of "Key: value" strings
--   body    string (for POST; sent as JSON)
-- @return ok(bool), status(number), body(string), err(string)
function M.request(opts)
    local args = { "curl", "-sSL", "-m", "30", "-w", "\n%{http_code}" }
    if opts.method and opts.method ~= "GET" then
        table.insert(args, "-X"); table.insert(args, opts.method)
    end
    for _, h in ipairs(opts.headers or {}) do
        table.insert(args, "-H"); table.insert(args, h)
    end
    if opts.body then
        table.insert(args, "--data-binary"); table.insert(args, opts.body)
    end
    table.insert(args, opts.url)

    local r = utils.subprocess({
        args = args, capture_stdout = true, capture_stderr = true, playback_only = false,
    })
    if r.status ~= 0 then
        return false, 0, "", "curl exit " .. tostring(r.status) .. ": " .. (r.stderr or "")
    end
    -- split trailing status line
    local body, code = (r.stdout or ""):match("^(.*)\n(%d+)%s*$")
    code = tonumber(code) or 0
    if not body then
        return false, code, r.stdout or "", "no status line"
    end
    return code >= 200 and code < 300, code, body, nil
end

--- Convenience: request + JSON parse.
-- @return ok(bool), status(number), data(table|nil), raw(string), err(string)
function M.request_json(opts)
    opts = opts or {}
    opts.headers = opts.headers or {}
    table.insert(opts.headers, "Accept: application/json")
    if opts.body then
        table.insert(opts.headers, "Content-Type: application/json")
    end
    local ok, status, body, err = M.request(opts)
    if not ok then
        return false, status, nil, body, err
    end
    local data = utils.parse_json(body)
    if not data then
        return false, status, nil, body, "invalid JSON"
    end
    return true, status, data, body, nil
end

--- Download a URL to a file on disk.
-- @return ok(bool), err(string)
function M.download(url, dest, headers)
    local args = { "curl", "-sSL", "-m", "60", "-o", dest }
    for _, h in ipairs(headers or {}) do
        table.insert(args, "-H"); table.insert(args, h)
    end
    table.insert(args, url)
    local r = utils.subprocess({
        args = args, capture_stdout = true, capture_stderr = true, playback_only = false,
    })
    if r.status ~= 0 then
        return false, "curl download exit " .. tostring(r.status)
    end
    local info = utils.file_info(dest)
    if not info or (info.size or 0) == 0 then
        return false, "empty download"
    end
    return true, nil
end

return M
