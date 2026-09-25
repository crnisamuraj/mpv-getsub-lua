-- Minimal in-player result picker rendered as an ASS OSD overlay.
-- Keyboard: up/down (or k/j) move, Enter select, Esc cancel.
-- If uosc is loaded we could delegate to its menu API later; this fallback
-- keeps the script dependency-free.

local mp = require("mp")
local msg = require("mp.msg")

local Picker = {}
Picker.__index = Picker

local function fmt_item(r, sel)
    local hi = r.hearing_impaired and " HI" or ""
    local trusted = r.from_trusted and " ★" or ""
    local se = ""
    if r.season and r.episode then
        se = string.format(" S%02dE%02d", r.season, r.episode)
    end
    local line = string.format("%s%s | %s | %s dl%s%s",
        r.title ~= "" and r.title or r.release, se, r.language, r.downloads, hi, trusted)
    if sel then
        return "{\\c&H00FFFF&\\b1}> " .. line .. "{\\b0}"
    end
    return "  " .. line
end

function Picker.new(results, on_done, duration_ms)
    local self = setmetatable({}, Picker)
    self.results = results
    self.on_done = on_done
    self.sel = 1
    self.ov = mp.create_osd_overlay("ass-events")
    self.timer = mp.add_timeout((duration_ms or 8000) / 1000, function() self:cancel() end)
    self:bind()
    self:render()
    return self
end

function Picker:bind()
    local function key(name)
        return function() self:move(name) end
    end
    mp.add_forced_key_binding("up", "vlsub_up", function() self:move(-1) end)
    mp.add_forced_key_binding("k", "vlsub_k", function() self:move(-1) end)
    mp.add_forced_key_binding("down", "vlsub_down", function() self:move(1) end)
    mp.add_forced_key_binding("j", "vlsub_j", function() self:move(1) end)
    mp.add_forced_key_binding("ENTER", "vlsub_enter", function() self:pick() end)
    mp.add_forced_key_binding("ESC", "vlsub_esc", function() self:cancel() end)
end

function Picker:unbind()
    for _, n in ipairs({ "vlsub_up", "vlsub_k", "vlsub_down", "vlsub_j", "vlsub_enter", "vlsub_esc" }) do
        mp.remove_key_binding(n)
    end
end

function Picker:move(d)
    self.timer:kill()
    self.sel = ((self.sel - 1 + d) % #self.results) + 1
    self:render()
    self.timer:resume()
end

function Picker:render()
    local lines = { "{\\an2\\fs16\\b1}Subtitles — ↑/↓ move, Enter select, Esc cancel{\\b0}" }
    local MAX = 8
    local start = math.max(1, math.min(self.sel - 3, #self.results - MAX + 1))
    for i = start, math.min(#self.results, start + MAX - 1) do
        table.insert(lines, fmt_item(self.results[i], i == self.sel))
    end
    self.ov.data = table.concat(lines, "\\N")
    self.ov:update()
end

function Picker:finish(result)
    self.timer:kill()
    self:unbind()
    self.ov:remove()
    if self.on_done then self.on_done(result) end
end

function Picker:pick() self:finish(self.results[self.sel]) end
function Picker:cancel() self:finish(nil) end

return Picker
