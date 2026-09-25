-- OpenSubtitles (OSDb) movie hash for mpv, with no external Lua dependencies.
--
-- The hash is the file's byte size plus the 64-bit little-endian word sums of
-- the first and last 64 KiB of the file. Implemented over `utils.subprocess`
-- + `dd` so it works in a stock mpv Lua environment (no luafilesystem).
-- Reference: osdb-mpv, opensubtitles HashSourceCodes.
--
-- Lua numbers are IEEE doubles (53-bit mantissa), so a full 64-bit integer
-- can't be held exactly. We track the low 32 bits, the high 32 bits, and any
-- overflow carry separately and fold them together at the end.

local utils = require("mp.utils")
local msg = require("mp.msg")

local CHUNK = 64 * 1024
local M = {}

local function read_chunk(path, offset, count)
    local args = { "dd", "if=" .. path, "bs=1", "count=" .. tostring(count), "status=none" }
    if offset and offset > 0 then
        table.insert(args, "skip=" .. tostring(offset))
    end
    local r = utils.subprocess({
        args = args, capture_stdout = true, capture_stderr = true, playback_only = false,
    })
    if r.status ~= 0 or not r.stdout then
        msg.warn("hash: dd failed status=" .. tostring(r.status))
        return nil
    end
    return r.stdout
end

-- Accumulate 64-bit LE words into three 32-bit lanes: lo, hi, and the carry
-- that overflows the high lane. Keeping lanes under 2^32 keeps doubles exact.
local function sum_words_le64(data, st)
    local n = #data - (#data % 8)
    local i = 1
    while i <= n do
        local b1, b2, b3, b4, b5, b6, b7, b8 = data:byte(i, i + 7)
        st.lo = st.lo + b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
        st.hi = st.hi + b5 + b6 * 256 + b7 * 65536 + b8 * 16777216
        -- renormalize, propagating carries up the lanes
        st.hi = st.hi + math.floor(st.lo / 4294967296); st.lo = st.lo % 4294967296
        st.carry = st.carry + math.floor(st.hi / 4294967296); st.hi = st.hi % 4294967296
        i = i + 8
    end
end

--- Compute the OSDb movie hash and byte size of `path`.
-- @return hash (16-hex-char string), size (number)  OR  nil, nil on failure
function M.hash(path)
    if not path or path == "" then return nil, nil end
    if path:match("^%a+://") then
        msg.info("hash: skipping remote url")
        return nil, nil
    end

    local info = utils.file_info(path)
    if not info or not info.size or info.size < CHUNK then
        msg.warn("hash: file too small or unreadable")
        return nil, nil
    end
    local size = info.size

    local head = read_chunk(path, 0, CHUNK)
    local tail = read_chunk(path, size - CHUNK, CHUNK)
    if not head or not tail then return nil, nil end

    local st = { lo = 0, hi = 0, carry = 0 }
    -- file size, split into 32-bit halves (exact while size < 2^53)
    st.lo = st.lo + (size % 4294967296)
    st.hi = st.hi + math.floor(size / 4294967296)
    sum_words_le64(head, st)
    sum_words_le64(tail, st)

    -- final normalization (a stray carry out of lo after size was added)
    st.hi = st.hi + math.floor(st.lo / 4294967296); st.lo = st.lo % 4294967296
    st.carry = st.carry + math.floor(st.hi / 4294967296); st.hi = st.hi % 4294967296
    st.carry = st.carry % 4294967296

    -- 64-bit value is carry:hi:lo truncated to 64 bits => hi:lo (carry is bit 64+)
    return string.format("%08x%08x", st.hi % 4294967296, st.lo), size
end

return M
