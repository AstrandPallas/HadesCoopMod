--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--
-- Lightweight per-second-bucket counters for the mod's hot paths. Wraps the
-- noisy hooks (damage, draw, UI dispatch, HeroContext switches) and prints
-- aggregate counts every PerfCounters.ReportInterval seconds so we can spot
-- which one is firing 100+ times a frame in combat.
--
-- Strictly diagnostic — meant to be enabled when investigating a perf issue
-- and disabled again afterward. Set PerfCounters.Enabled = false to stub.
--

---@class PerfCounters
local PerfCounters = {}

PerfCounters.Enabled = true
PerfCounters.ReportInterval = 5  -- seconds between log dumps

---@private
PerfCounters.Counts = {}
---@private
PerfCounters.LastReportTime = -1

---@private
---@return number  current game world time, or 0 if not yet set
local function now()
    return _worldTime or 0
end

---@public
---@param name string  Counter name (free-form, used as the log label)
function PerfCounters.Tick(name)
    if not PerfCounters.Enabled then return end
    PerfCounters.Counts[name] = (PerfCounters.Counts[name] or 0) + 1
    PerfCounters.MaybeReport()
end

---@private
function PerfCounters.MaybeReport()
    local t = now()
    if PerfCounters.LastReportTime < 0 then
        PerfCounters.LastReportTime = t
        return
    end
    if (t - PerfCounters.LastReportTime) < PerfCounters.ReportInterval then return end

    local interval = t - PerfCounters.LastReportTime
    if interval <= 0 then return end

    local parts = { string.format("TN_Coop Perf (per %.1fs):", interval) }
    -- Sort names so the log is consistent run-to-run.
    local names = {}
    for name in pairs(PerfCounters.Counts) do table.insert(names, name) end
    table.sort(names)
    for _, name in ipairs(names) do
        local count = PerfCounters.Counts[name]
        local rate = count / interval
        table.insert(parts, string.format("  %s: %d (%.1f/s)", name, count, rate))
    end
    DebugPrint { Text = table.concat(parts, "\n") }

    PerfCounters.Counts = {}
    PerfCounters.LastReportTime = t
end

return PerfCounters
