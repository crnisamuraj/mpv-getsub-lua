-- In-player result picker rendered as an ASS OSD overlay (no dependencies).
-- Keyboard: ↑/↓ or k/j move, PgUp/PgDn page, Enter select, Esc cancel.
-- When uosc is loaded the caller prefers modules/uosc.lua instead; this is
-- the always-available fallback.

local mp = require("mp")

local Picker = {}
Picker.__index = Picker

local PAGE = 8
local MAXLEN = 78

local function ellipsize(s, n)
    if #s <= n then return s end
    return s:sub(1, n - 1) .. "…"
end

local function fmt_item(r, sel)
    local hi = r.hearing_impaired and " HI" or ""
    local trusted = r.from_trusted and " ★" or ""
    local se = (r.season and r.episode)
        and string.format(" S%02dE%02d", r.season, r.episode) or ""
    local left = ellipsize((r.title ~= "" and r.title or r.release) .. se, MAXLEN)
    local right = string.format("%s %s dl%s%s", r.language or "?", tostring(r.downloads or 0), hi, trusted)
    if sel then
        -- highlighted row: yellow text + leading marker
        return string.format("{\\c&H00FFFF&\\b1}▶ %s{\\b0\\c&HFFFFFF&}  %s", left, right)
    end
    return string.format("  %s  %s", left, right)
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
    mp.add_forced_key_binding("up", "vlsub_up", function() self:move(-1) end)
    mp.add_forced_key_binding("k", "vlsub_k", function() self:move(-1) end)
    mp.add_forced_key_binding("down", "vlsub_down", function() self:move(1) end)
    mp.add_forced_key_binding("j", "vlsub_j", function() self:move(1) end)
    mp.add_forced_key_binding("PGUP", "vlsub_pgup", function() self:move(-PAGE) end)
    mp.add_forced_key_binding("PGDWN", "vlsub_pgdwn", function() self:move(PAGE) end)
    mp.add_forced_key_binding("HOME", "vlsub_home", function() self:jump(1) end)
    mp.add_forced_key_binding("END", "vlsub_end", function() self:jump(#self.results) end)
    mp.add_forced_key_binding("ENTER", "vlsub_enter", function() self:pick() end)
    mp.add_forced_key_binding("ESC", "vlsub_esc", function() self:cancel() end)
end

function Picker:unbind()
    for _, n in ipairs({ "vlsub_up", "vlsub_k", "vlsub_down", "vlsub_j",
        "vlsub_pgup", "vlsub_pgdwn", "vlsub_home", "vlsub_end",
        "vlsub_enter", "vlsub_esc" }) do
        mp.remove_key_binding(n)
    end
end

function Picker:bump()
    self.timer:kill()
    self:render()
    self.timer:resume()
end

function Picker:move(d)
    self.sel = ((self.sel - 1 + d) % #self.results) + 1
    self:bump()
end

function Picker:jump(i)
    self.sel = math.max(1, math.min(i, #self.results))
    self:bump()
end

function Picker:render()
    local header = string.format(
        "{\\an2\\fs15\\b1}Subtitles (%d/%d){\\b0}  {\\fs12\\c&HAAAAAA&}↑/↓ PgUp/PgDn • Enter select • Esc cancel{\\c&HFFFFFF&}",
        self.sel, #self.results)
    local lines = { header }
    local start = math.max(1, math.min(self.sel - 3, #self.results - PAGE + 1))
    for i = start, math.min(#self.results, start + PAGE - 1) do
        table.insert(lines, "{\\fs14}" .. fmt_item(self.results[i], i == self.sel))
    end
    if start + PAGE - 1 < #self.results then
        table.insert(lines, string.format("{\\fs12\\c&HAAAAAA&}  … %d more{\\c&HFFFFFF&}",
            #self.results - (start + PAGE - 1)))
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
