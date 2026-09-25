-- uosc menu integration for mpv-getsub-lua.
--
-- When uosc (https://github.com/tomasklaen/uosc) is loaded we render the
-- result list as a native uosc menu instead of the ASS-overlay picker. uosc
-- announces itself with a `uosc-version` script message at startup; we track
-- that to know whether the integration is available.

local utils = require("mp.utils")
local msg = require("mp.msg")

local M = { available = false }

mp.register_script_message("uosc-version", function()
    M.available = true
end)

--- Show `results` as a uosc command menu. `on_pick(i)` runs for selection i.
-- Falls back to nothing (returns false) when uosc isn't present so the
-- caller can use its own UI.
function M.show(results, on_pick)
    if not M.available then
        return false
    end

    -- register one-shot pick handler
    local handler_name = "mpv-getsub-lua-pick"
    mp.register_script_message(handler_name, function(idx)
        local i = tonumber(idx)
        if i and results[i] then
            on_pick(i)
        end
    end)

    local items = {}
    for i, r in ipairs(results) do
        local se = (r.season and r.episode)
            and string.format(" S%02dE%02d", r.season, r.episode) or ""
        local title = (r.title ~= "" and r.title or r.release)
        local hint = string.format("%s%s  •  %s dl%s%s",
            r.language or "?", se, tostring(r.downloads or 0),
            r.hearing_impaired and " • HI" or "", r.from_trusted and " • ★" or "")
        table.insert(items, {
            title = title .. se,
            hint = hint,
            value = string.format("script-message mpv-getsub-lua-pick %d", i),
        })
    end

    local menu = utils.format_json({
        type = "mpv-getsub-lua",
        title = "Subtitles",
        items = items,
    })
    mp.commandv("script-message-to", "uosc", "open-menu", menu)
    return true
end

return M
