-- Entry point for mpv-getsub-lua.
--
-- Loaded by mpv from ~/.config/mpv/scripts/ (rename this folder's parent so
-- main.lua sits at the top level), or injected into Haruna via load-script.

-- Resolve the script's own directory so sibling modules can be required.
-- get_script_directory() is reliable when mpv loads us from scripts/, but can
-- be nil under some injection paths, so fall back to the script's own path.
local function script_dir()
    local d = mp.get_script_directory and mp.get_script_directory()
    if d and d ~= "" then return d end
    -- debug info: the source of this chunk, minus leading '@'
    local src = debug.getinfo(1, "S").source or ""
    src = src:gsub("^@", "")
    return src:match("^(.*)[/\\]") or "."
end

package.path = script_dir() .. "/?.lua;" .. package.path

local msg = require("mp.msg")
local utils = require("mp.utils")
local conf = require("modules.config")
local hash = require("modules.hash")
local Picker = require("modules.picker")

local PROVIDERS = {
    opensubtitles = require("providers.opensubtitles"),
}

local function current_file()
    local path = mp.get_property("path")
    if path and path ~= "" then return path end
    return nil
end

local function guess_title(path)
    if not path then return nil end
    local name = path:match("([^/\\]+)$") or path
    name = name:gsub("%.%w+$", "")            -- strip extension
    name = name:gsub("[._]", " ")             -- dots/underscores -> spaces
    name = name:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return name
end

local function save_path_for(video, result)
    local dir
    if conf.save_to == "video" then
        dir = video:match("^(.*)[/\\]") or "."
    else
        dir = conf.save_to
    end
    local base = (video:match("([^/\\]+)$") or "subtitle"):gsub("%.%w+$", "")
    local lang = result.language or "und"
    return string.format("%s/%s.%s.srt", dir, base, lang)
end

local function do_search()
    local video = current_file()
    if not video then
        mp.osd_message("mpv-getsub-lua: no file loaded", 3)
        return
    end
    local provider = PROVIDERS[conf.provider]
    if not provider then
        mp.osd_message("mpv-getsub-lua: unknown provider " .. tostring(conf.provider), 3)
        return
    end

    mp.osd_message("Searching subtitles…", 2)

    local h, size = hash.hash(video)
    local q = {
        hash = h,
        size = size,
        title = guess_title(video),
        languages = conf.language_list(),
    }
    msg.info("query title=" .. tostring(q.title) .. " hash=" .. tostring(q.hash))

    local results, err = provider.search(conf, q)
    if not results then
        msg.error("search error: " .. tostring(err))
        mp.osd_message("Search failed: " .. tostring(err), 4)
        return
    end
    msg.info("results: " .. #results)
    if #results == 0 then
        mp.osd_message("No subtitles found for " .. (q.title or "this file"), 3)
        return
    end

    local function use(result)
        if not result then
            mp.osd_message("Cancelled", 2)
            return
        end
        local dest = save_path_for(video, result)
        mp.osd_message("Downloading subtitle…", 2)
        local ok, derr = provider.download(conf, result, dest)
        if not ok then
            mp.osd_message("Download failed: " .. tostring(derr), 4)
            return
        end
        mp.commandv("sub-add", dest, "select")
        mp.osd_message("Subtitle loaded: " .. result.release, 4)
        msg.info("saved to " .. dest)
    end

    if conf.auto_select or #results == 1 then
        use(results[1])
    else
        Picker.new(results, use, conf.osd_duration_ms)
    end
end

mp.add_key_binding("n", "mpv-getsub-lua", do_search)
mp.register_script_message("search", do_search)
msg.info("mpv-getsub-lua loaded (press n, or script-message search)")
