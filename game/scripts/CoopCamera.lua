--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type CoopPlayers
local CoopPlayers = ModRequire "CoopPlayers.lua"
---@type HookUtils
local HookUtils = ModRequire "HookUtils.lua"
---@type PerfCounters
local PerfCounters = ModRequire "PerfCounters.lua"
---@type RunEx
local RunEx = ModRequire "RunEx.lua"

---@class CoopCamera
local CoopCamera = {}

---@private
CoopCamera.isFocusEnabled = true

---@private
CoopCamera.IgnoreHeroes = {}

-- Dynamic-zoom tunables: distance is in game units (same units GetDistance returns).
-- Close-zoom target is the room's vanilla ZoomFraction (stashed in CreateRoomWrapHook).
CoopCamera.CloseDistance       = 400   -- at/below this → close-zoom target
CoopCamera.FarDistance         = 1200  -- at/above this → co-op wide zoom (with 2 players)
CoopCamera.CloseZoomScale      = 0.9   -- close-zoom = vanilla * this (slightly wider than vanilla)
-- With more players the cluster spreads naturally — a 3- or 4-player party often
-- crosses the 2-player FarDistance just standing around. Grow both thresholds by
-- this amount per extra player so the zoom curve still has headroom before maxing
-- out at the wide end.
CoopCamera.FarDistancePerPlayer   = 250
CoopCamera.CloseDistancePerPlayer = 100
-- Per-frame LockCamera updates with a small lerp Duration. The original
-- mod (pre-throttle) updated every draw tick; that's what kept the engine's
-- multi-Id averaging stable. Throttling let the engine "settle" between
-- calls and pick a single Id to favor, which manifested as the camera
-- jerking toward P1 at room edges. Going back to the working baseline.
CoopCamera.ZoomLerpDuration    = 0.35  -- seconds FocusCamera takes to ease to target
CoopCamera.ZoomUpdateInterval  = 0.05  -- inner FocusCamera throttle
-- Per-frame LockCamera needs Duration = 0 (instant snap to the new target).
-- Any non-zero value causes consecutive calls to start fresh lerps that fight
-- with the previous in-flight lerp, producing visible camera shake when
-- players walk (each frame the camera is told to lerp to a slightly-newer
-- target) or near room edges (where small target adjustments oscillate).
CoopCamera.LockLerpDuration    = 0.0
CoopCamera.MinZoomDelta        = 0.003 -- skip zoom update if target zoom barely changed

---@private
CoopCamera.LastZoomFraction = nil
---@private
CoopCamera.LastZoomTime     = -math.huge
---@private
CoopCamera.LastUpdateTime   = -math.huge
---@private
-- Cache of the most-recent units list. The unlock half of relocking is the
-- expensive engine op; if the alive set hasn't changed, we can skip it.
CoopCamera.LastUnitsKey     = nil
---@private
-- World-space anchor obstacle the camera locks onto. Lazy-spawned and
-- moved to the player-centroid each Update tick. Using a single-Id lock
-- instead of LockCamera { Ids = manyPlayers } eliminates the engine's
-- multi-Id framing oscillation at room edges (where the bounding box
-- exceeds the room's min-zoom capacity, the engine was alternating
-- priority between Ids and snapping the camera between them).
CoopCamera.AnchorObstacleId = nil

function CoopCamera.InitHooks()
    HookUtils.wrap("CreateRoom", CoopCamera.CreateRoomWrapHook)
    HookUtils.onPostFunction("draw", CoopCamera.Update)
    HookUtils.onPostFunction("ExitNPCPresentation", CoopCamera.OnExitNPCPresentation)
    HookUtils.onPostFunction("PanCamera", CoopCamera.PanCameraPostHook)
    CoopCamera.LockCameraOrig = LockCamera
    LockCamera = CoopCamera.LockCameraHook
end

---@param state boolean
function CoopCamera.ForceFocus(state)
    CoopCamera.isFocusEnabled = state
end

function CoopCamera.LockCameraHook(args)
    local mainPlayerId  = CoopPlayers.GetMainHero().ObjectId
    if mainPlayerId and args.Id == mainPlayerId then
        CoopCamera.ForceFocus(true)
        -- Force a fresh lock on the next Update tick. Clear the cached
        -- units key so the unit-set comparison reissues the unlock, and the
        -- per-tick throttle so the call runs immediately (vanilla LockCamera
        -- is typically called at deliberate transitions — we don't want to
        -- elide that intent waiting for the next 0.5s tick).
        CoopCamera.LastUnitsKey = nil
        CoopCamera.LastUpdateTime = -math.huge
        CoopCamera.Update()
    else
        CoopCamera.ForceFocus(false)
        CoopCamera.LockCameraOrig(args)
    end
end

---@private
function CoopCamera.OnExitNPCPresentation()
    -- Fixes wrong camera focus after some  NPC dialoges.
    -- E.g. after feeding the dog in the styx temple hub
    CoopCamera.LockCameraHook({ Id = CoopPlayers.GetMainHero().ObjectId })
end

---@private
---Spawn the world-anchor obstacle on demand. The lock target stays at the
---centroid of the alive players; the camera follows this single anchor
---instead of trying to frame multiple player Ids.
local function ensureAnchor()
    if CoopCamera.AnchorObstacleId then return end
    -- Vanilla's pattern for invisible-world targets (CombatPresentation.lua:3035)
    -- is "InvisibleTarget" in the Standing group. Same template here.
    CoopCamera.AnchorObstacleId = SpawnObstacle({
        Name = "InvisibleTarget",
        Group = "Standing",
    })
end

---@private
---Move the anchor obstacle to the centroid of the supplied alive units.
---Uses iterative averaging — after processing k players, the anchor sits
---at the centroid of those k. No absolute-coordinate read needed (Hades's
---Lua sandbox doesn't expose one) — Teleport + relative Move handles it.
---@param units number[]  player unit ObjectIds, length >= 1
local function moveAnchorToCentroid(units)
    -- Centroid of {p1} = p1.
    Teleport { Id = CoopCamera.AnchorObstacleId, DestinationId = units[1] }

    for k = 2, #units do
        local dist = GetDistance { Id = CoopCamera.AnchorObstacleId, DestinationId = units[k] }
        if dist and dist > 0 then
            -- After step k, the anchor sits at the centroid of the first k
            -- players: each new player gets a 1/k weight against the running
            -- (k-1)-player average.
            Move {
                Id = CoopCamera.AnchorObstacleId,
                DestinationId = units[k],
                Distance = dist / k,
                Duration = 0,
            }
        end
    end
end

---@private
function CoopCamera.Update()
    PerfCounters.Tick("CoopCamera.Update.entry")
    if not CoopCamera.isFocusEnabled then
        return
    end

    local units = {}

    -- It's bad
    -- Players are dead in prerun room
    local wasRunFinished = RunEx.IsRunEnded()

    for _, hero in CoopPlayers.PlayersIterator() do
        if hero and (wasRunFinished or not hero.IsDead) and not CoopCamera.IgnoreHeroes[hero] then
            table.insert(units, hero.ObjectId)
        end
    end

    if #units == 0 then
        return
    end

    -- Refresh the multi-Id lock every frame. The engine's averaging needs
    -- continuous re-receipt of the target list to stay stable; throttling
    -- this call let the engine pick a single Id and jerk toward it. The
    -- expensive op is the Unlock; we only do that when the unit set itself
    -- changes (someone dies/spawns), and let the per-tick LockCamera refresh
    -- be a cheap target update.
    local unitsKey = table.concat(units, ",")
    if unitsKey ~= CoopCamera.LastUnitsKey then
        PerfCounters.Tick("CoopCamera.Update.unitsChanged")
        UnlockCamera()
        CoopCamera.LastUnitsKey = unitsKey
    end
    CoopCamera.LockCameraOrig { Ids = units, Duration = CoopCamera.LockLerpDuration }
    CoopCamera.UpdateDynamicZoom(units)
end

---@private
---@param units number[] alive player unit IDs (>=1 entry guaranteed)
---@return number? max distance between any pair, or nil if only one player
function CoopCamera.GetMaxPairDistance(units)
    if #units < 2 then return nil end
    local maxDist = 0
    for i = 1, #units do
        for j = i + 1, #units do
            local d = GetDistance { Id = units[i], DestinationId = units[j] }
            if d and d > maxDist then
                maxDist = d
            end
        end
    end
    return maxDist
end

---@private
-- Lerp camera Fraction based on how spread out the players are.
-- Called every frame from Update(); throttled internally so FocusCamera's
-- easing isn't interrupted by a new call every tick.
---@param units number[]
function CoopCamera.UpdateDynamicZoom(units)
    local room = CurrentRun and CurrentRun.CurrentRoom
    if not room or not room.ZoomFraction then
        return
    end

    local dist = CoopCamera.GetMaxPairDistance(units)
    local desiredZoom
    local closeZoom = (room.CoopVanillaZoomFraction or 1.0) * CoopCamera.CloseZoomScale
    if dist == nil then
        -- Only one player in the camera's focus list (others dead, off-screen
        -- during a reward menu, or not yet spawned at a boss intro). Snap to the
        -- close vanilla-single-player zoom rather than the wide co-op zoom —
        -- otherwise the lone visible player ends up tiny in the middle of a
        -- camera framed for a party.
        desiredZoom = closeZoom
    else
        local wideZoom  = room.ZoomFraction
        -- Scale the close/far thresholds with the number of alive players so a
        -- 3- or 4-player party — which sits further apart at rest than a pair —
        -- doesn't max out the zoom curve just by existing in formation.
        local extraPlayers = math.max(0, #units - 2)
        local closeDist = CoopCamera.CloseDistance + extraPlayers * CoopCamera.CloseDistancePerPlayer
        local farDist   = CoopCamera.FarDistance   + extraPlayers * CoopCamera.FarDistancePerPlayer
        desiredZoom = CoopCamera.ComputeZoomFraction(dist, closeZoom, wideZoom, closeDist, farDist)
    end

    -- FocusCamera every Update tick would interrupt its own in-flight lerp,
    -- causing visible zoom stutter. Throttle inner-loop so we only re-target
    -- the zoom every ZoomUpdateInterval seconds OR when the target jumped
    -- enough to matter.
    local now = _worldTime or 0
    if CoopCamera.LastZoomFraction
        and math.abs(desiredZoom - CoopCamera.LastZoomFraction) < CoopCamera.MinZoomDelta
        and (now - CoopCamera.LastZoomTime) < CoopCamera.ZoomUpdateInterval then
        return
    end

    FocusCamera { Fraction = desiredZoom, Duration = CoopCamera.ZoomLerpDuration, ZoomType = "Ease" }
    CoopCamera.LastZoomFraction = desiredZoom
    CoopCamera.LastZoomTime = now
end

---@private
-- Smoothstep-lerp the camera zoom between vanilla single-player feel (when players
-- cluster) and the co-op wide view (when players spread out). Close/far thresholds
-- are passed in so the caller can scale them with the active player count.
---@param distance number  distance between the two furthest-apart alive players
---@param closeZoom number  zoom when players are close (room's vanilla ZoomFraction)
---@param wideZoom number   zoom when players are far (room's co-op ZoomFraction)
---@param closeDistance? number  optional override for CoopCamera.CloseDistance
---@param farDistance? number    optional override for CoopCamera.FarDistance
---@return number
function CoopCamera.ComputeZoomFraction(distance, closeZoom, wideZoom, closeDistance, farDistance)
    closeDistance = closeDistance or CoopCamera.CloseDistance
    farDistance   = farDistance   or CoopCamera.FarDistance
    if distance <= closeDistance then
        return closeZoom
    elseif distance >= farDistance then
        return wideZoom
    end
    local t = (distance - closeDistance) / (farDistance - closeDistance)
    local s = t * t * (3 - 2 * t)
    return closeZoom + (wideZoom - closeZoom) * s
end

---@private
function CoopCamera.CreateRoomWrapHook(baseFunc, ...)
    local room = baseFunc(...)

    -- New rooms destroy the previous anchor obstacle; clear our id so the
    -- next Update tick lazy-spawns a fresh one in the new room. Also clear
    -- the lock cache so we reissue LockCamera with the new anchor.
    CoopCamera.AnchorObstacleId = nil
    CoopCamera.LastUnitsKey = nil

    -- Stash the vanilla single-player zoom; dynamic-zoom uses it as the close-target.
    room.CoopVanillaZoomFraction = room.ZoomFraction or 1.0
    -- Co-op wide zoom is a fraction of vanilla. Lower = zoomed out further.
    if not room.ZoomFraction then
        room.ZoomFraction = 0.55
    elseif room.ZoomFraction > 0.5 then
        room.ZoomFraction = room.ZoomFraction * 0.55
    end
    return room
end

---@private
function CoopCamera.PanCameraPostHook(args)
    local id = args.Id or args.Ids
    if id then
        CoopCamera.ForceFocus(CoopPlayers.IsPlayerUnit(id))
    end
end

---@public
function CoopCamera.SetHeroIgnored(hero, state)
    if state then
        CoopCamera.IgnoreHeroes[hero] = state
    else
        CoopCamera.IgnoreHeroes[hero] = nil
    end
end

---@public
function CoopCamera.ResetIgnore()
    CoopCamera.IgnoreHeroes = {}
end

return CoopCamera
