-- Slash bars in the style of the PlainExt Rainmeter skin.
-- Each function fetches the value itself through conky_parse — simpler than passing it
-- as an argument.
local WIDTH = 18

local function bar(pct)
    local n = math.floor((tonumber(pct) or 0) * WIDTH / 100 + 0.5)
    if n > WIDTH then n = WIDTH end
    if n < 0 then n = 0 end
    return string.rep("/", n) .. string.rep(" ", WIDTH - n)
end

local SRC = {
    cpu  = "${cpu cpu0}",
    mem  = "${memperc}",
    root = "${fs_used_perc /}",
    sata = "${fs_used_perc /run/media/s1dd1/s1d}",
}

function conky_bar(what)
    if what == "gpu" then
        -- conky has ${nvidia gpuutil}, but it does not always return a number: query it directly
        local f = io.popen("nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null")
        if not f then return bar(0) end
        local v = f:read("*l"); f:close()
        return bar(v)
    end
    return bar(conky_parse(SRC[what] or "0"))
end

-- ── Per-socket load ──────────────────────────────────────────────────────────
-- Computed from /proc/stat instead of 72 ${cpu cpuN} calls: cheaper and more accurate.
-- The core-to-NUMA-node layout was read from lscpu on this machine:
--   node0 = 0-17,36-53   node1 = 18-35,54-71
local SOCK = { [0] = {}, [1] = {} }
for i = 0, 17  do SOCK[0][i] = true end
for i = 36, 53 do SOCK[0][i] = true end
for i = 18, 35 do SOCK[1][i] = true end
for i = 54, 71 do SOCK[1][i] = true end

local prev = {}

local function socket_pct(n)
    local busy, total = 0, 0
    local f = io.open("/proc/stat")
    if not f then return 0 end
    for line in f:lines() do
        local id, rest = line:match("^cpu(%d+)%s+(.*)$")
        if id and SOCK[n][tonumber(id)] then
            local i = 0
            for tok in rest:gmatch("%d+") do
                local v = tonumber(tok); i = i + 1; total = total + v
                if i ~= 4 and i ~= 5 then busy = busy + v end   -- 4=idle, 5=iowait
            end
        end
    end
    f:close()
    local p = prev[n]
    prev[n] = { busy = busy, total = total }
    if not p then return 0 end
    local dt = total - p.total
    if dt <= 0 then return 0 end
    return (busy - p.busy) * 100 / dt
end

function conky_sock(n)
    return string.format("%2.0f", socket_pct(tonumber(n)))
end

function conky_sockbar(n)
    local pct = socket_pct(tonumber(n))
    local W = 18
    local k = math.floor(pct * W / 100 + 0.5)
    if k > W then k = W end
    if k < 0 then k = 0 end
    return string.rep("/", k) .. string.rep(" ", W - k)
end
