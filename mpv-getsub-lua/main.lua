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
local uosc = require("modules.uosc")
local rank = require("modules.rank")

local PROVIDERS = {
    opensubtitles = require("providers.opensubtitles"),
    subdl = require("providers.subdl"),
    podnapisi = require("providers.podnapisi"),
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

local function save_path_for(video, result, index)
    local dir
    if conf.save_to == "video" then
        dir = video:match("^(.*)[/\\]") or "."
    else
        dir = conf.save_to
    end
    local base = (video:match("([^/\\]+)$") or "subtitle"):gsub("%.%w+$", "")
    local lang = result.language or "und"
    -- honor the provider-reported format when present (ass/ssa/vtt…)
    local ext = (result.format and result.format ~= "")
        and result.format:lower() or "srt"
    if index then
        return string.format("%s/%s.%d.%s.%s", dir, base, index, lang, ext)
    end
    return string.format("%s/%s.%s.%s", dir, base, lang, ext)
end

-- Shared pipeline: locate provider, hash the file, search, rank, filter.
-- Returns provider, ranked_results  OR  nil, error-message
local function search_and_rank()
    local video = current_file()
    if not video then
        return nil, "no file loaded"
    end
    local provider = PROVIDERS[conf.provider]
    if not provider then
        return nil, "unknown provider " .. tostring(conf.provider)
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
        return nil, err
    end

    local ctx = {
        title = q.title,
        year = tonumber((q.title or ""):match("(%d%d%d%d)")),
        fps = mp.get_property_number("container-fps")
            or mp.get_property_number("estimated-vf-fps"),
        hash = q.hash,
        filename = video:match("([^/\\]+)$") or q.title,
    }
    results = rank.filter_and_score(results, ctx)
    msg.info("results: " .. #results .. " (after rank/filter)")
    if #results > 0 then
        msg.info(("top: score=%.1f fps=%s rel=%s"):format(
            results[1].score, tostring(results[1].fps), tostring(results[1].release)))
    end
    if #results == 0 then
        return nil, "no subtitles found for " .. (q.title or "this file")
    end
    return provider, results, video
end

local function do_search()
    local provider, results, video = search_and_rank()
    if not provider then
        mp.osd_message(results or "Search failed", 4)
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
    elseif uosc.show(results, function(i) use(results[i]) end) then
        -- rendered by uosc
    else
        Picker.new(results, use, conf.osd_duration_ms)
    end
end

-- Batch mode: `script-message batch [N]` downloads the top-N ranked results
-- as numbered files next to the video and loads them all, so you can cycle
-- tracks (v / j) to find the one that syncs. N defaults to 3.
local function do_batch(n_arg)
    local n = tonumber(n_arg) or 3
    local provider, results, video = search_and_rank()
    if not provider then
        mp.osd_message(results or "Search failed", 4)
        return
    end

    n = math.min(n, #results)
    local loaded = 0
    for i = 1, n do
        local r = results[i]
        local dest = save_path_for(video, r, i)
        local ok, derr = provider.download(conf, r, dest)
        if ok then
            -- first result gets selected, the rest are just added
            mp.commandv("sub-add", dest, i == 1 and "select" or "auto",
                string.format("#%d %s", i, r.release), r.language)
            loaded = loaded + 1
            msg.info(("batch #%d saved: %s (score %.1f)"):format(i, dest, r.score))
        else
            msg.warn(("batch #%d failed: %s"):format(i, tostring(derr)))
        end
    end
    mp.osd_message(string.format(
        "Batch: %d/%d subtitles loaded — cycle tracks with v/j to test", loaded, n), 5)
end

mp.add_key_binding("n", "mpv-getsub-lua", do_search)
mp.register_script_message("search", do_search)
mp.register_script_message("batch", do_batch)
msg.info("mpv-getsub-lua loaded (n = search/pick, script-message batch N = grab top-N)")
