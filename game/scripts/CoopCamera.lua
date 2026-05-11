--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type CoopPlayers
local CoopPlayers = ModRequire "CoopPlayers.lua"
---@type HookUtils
local HookUtils = ModRequire "HookUtils.lua"
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
CoopCamera.FarDistance         = 1200  -- at/above this → co-op wide zoom
CoopCamera.CloseZoomScale      = 0.9   -- close-zoom = vanilla * this (slightly wider than vanilla)
-- Lerp duration must stay much LONGER than update interval, so each FocusCamera
-- call lands while the previous ease is still in flight. That's how we get a
-- continuous low-pass-filter feel instead of step-and-stop jerks.
CoopCamera.ZoomLerpDuration    = 0.35  -- seconds FocusCamera takes to ease to target
CoopCamera.ZoomUpdateInterval  = 0.05  -- minimum seconds between FocusCamera calls
CoopCamera.MinZoomDelta        = 0.003 -- skip update if target zoom barely changed

---@private
CoopCamera.LastZoomFraction = nil
---@private
CoopCamera.LastZoomTime     = -math.huge

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
function CoopCamera.Update()
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

    UnlockCamera()
    CoopCamera.LockCameraOrig { Ids = units, Duration = 0.0 }
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
    if dist == nil then
        -- Only one player alive → use the wide room default.
        desiredZoom = room.ZoomFraction
    else
        local closeZoom = (room.CoopVanillaZoomFraction or 1.0) * CoopCamera.CloseZoomScale
        local wideZoom  = room.ZoomFraction
        desiredZoom = CoopCamera.ComputeZoomFraction(dist, closeZoom, wideZoom)
    end

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
-- cluster) and the co-op wide view (when players spread out).
---@param distance number  distance between the two furthest-apart alive players
---@param closeZoom number  zoom when players are close (room's vanilla ZoomFraction)
---@param wideZoom number   zoom when players are far (room's co-op ZoomFraction)
---@return number
function CoopCamera.ComputeZoomFraction(distance, closeZoom, wideZoom)
    if distance <= CoopCamera.CloseDistance then
        return closeZoom
    elseif distance >= CoopCamera.FarDistance then
        return wideZoom
    end
    local t = (distance - CoopCamera.CloseDistance) / (CoopCamera.FarDistance - CoopCamera.CloseDistance)
    local s = t * t * (3 - 2 * t)
    return closeZoom + (wideZoom - closeZoom) * s
end

---@private
function CoopCamera.CreateRoomWrapHook(baseFunc, ...)
    local room = baseFunc(...)
    -- Stash the vanilla single-player zoom; dynamic-zoom uses it as the close-target.
    room.CoopVanillaZoomFraction = room.ZoomFraction or 1.0
    if not room.ZoomFraction then
        room.ZoomFraction = 0.6
    elseif room.ZoomFraction > 0.5 then
        room.ZoomFraction = room.ZoomFraction * 0.6
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
