-- Result ranking and wrong-movie filtering for mpv-getsub-lua.
--
-- Motivation: provider queries return a grab-bag — different releases,
-- different frame rates, sometimes entirely different movies ("Battle for
-- Sevastopol" for a "Cloud Atlas" query). Ranking by fps match, release
-- name overlap with the actual file, and popularity puts the likely-sync
-- candidates on top; hard-dropping provably-wrong movies declutters the
-- picker.

local msg = require("mp.msg")

local M = {}

-- tokens that carry no release-identity signal
local NOISE = {
    ["1080p"] = true, ["720p"] = true, ["2160p"] = true, ["480p"] = true,
    ["bluray"] = true, ["brrip"] = true, ["bdrip"] = true, ["webrip"] = true,
    ["web"] = true, ["webdl"] = true, ["hdtv"] = true, ["dvdrip"] = true,
    ["x264"] = true, ["x265"] = true, ["h264"] = true, ["h265"] = true,
    ["hevc"] = true, ["avc"] = true, ["xvid"] = true, ["divx"] = true,
    ["aac"] = true, ["ac3"] = true, ["dts"] = true, ["dd5"] = true,
    ["mp3"] = true, ["flac"] = true, ["5"] = true, ["1"] = true,
    ["2"] = true, ["7"] = true, ["10bit"] = true, ["8bit"] = true,
    ["yify"] = true, ["rarbg"] = true, ["mkv"] = true, ["mp4"] = true,
    ["avi"] = true, ["srt"] = true,
}

local function tokenize(s)
    local out = {}
    for t in tostring(s or ""):lower():gmatch("[a-z0-9]+") do
        if not NOISE[t] and not t:match("^%d%d%d%d$") then
            out[t] = true
        end
    end
    return out
end

local function count_overlap(a, b)
    local n = 0
    for t in pairs(a) do
        if b[t] then n = n + 1 end
    end
    return n
end

--- Score and filter results for the current video.
-- @param results  array of provider results (mutated: .score set)
-- @param ctx      { title, year, fps, hash, filename }
-- @return filtered+sorted array
function M.filter_and_score(results, ctx)
    local title_tokens = tokenize(ctx.title)
    local file_tokens = tokenize(ctx.filename or ctx.title)
    -- signature tokens: in the filename but NOT in the plain title —
    -- e.g. "remastered", "bone", "extended", "repack" for a scene release
    local signature = {}
    for t in pairs(file_tokens) do
        if not title_tokens[t] then signature[t] = true end
    end

    local kept = {}
    for _, r in ipairs(results) do
        local rel_tokens = tokenize(r.release or "")
        local res_title_tokens = tokenize(r.title ~= "" and r.title or r.release)
        local ryear = tonumber(r.year)

        -- HARD DROP: positive evidence of a different movie — a known year
        -- that disagrees with the video's year.
        if ctx.year and ryear and math.abs(ryear - ctx.year) > 1 then
            msg.info(("rank: dropping wrong-year result (%s, %d)"):format(
                tostring(r.release), ryear))
            goto continue
        end

        local score = 0

        -- exact hash = guaranteed sync
        if ctx.hash and r.hash_match then
            score = score + 1000
        end

        -- fps match against the actual video
        if ctx.fps and r.fps and r.fps > 0 then
            if math.abs(r.fps - ctx.fps) < 0.5 then
                score = score + 50
                r.fps_ok = true
            elseif math.abs(r.fps - ctx.fps) > 2 then
                score = score - 40  -- PAL/film speed mismatch: will drift
                r.fps_ok = false
            end
        end

        -- release-signature overlap ("remastered", "bone", "extended"...)
        score = score + math.min(count_overlap(signature, rel_tokens), 3) * 10

        -- title agreement: result names the same movie
        local title_overlap = count_overlap(title_tokens, res_title_tokens)
        if next(title_tokens) and title_overlap == 0 then
            score = score - 100     -- names a different movie, demote hard
        else
            score = score + title_overlap * 5
        end

        if r.from_trusted then
            score = score + 15
        end

        -- popularity, log-scaled (25k dl ~= +21)
        local dl = tonumber(r.downloads) or 0
        score = score + math.log(dl + 1) / math.log(10) * 5

        r.score = score
        table.insert(kept, r)
        ::continue::
    end

    table.sort(kept, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return (a.downloads or 0) > (b.downloads or 0)
    end)
    return kept
end

return M
