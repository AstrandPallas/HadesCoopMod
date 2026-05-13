--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--
-- World-anchored "P1" / "P2" / "P3" / "P4" labels floating above each player's
-- character. Uses Hades's standard floating-text pattern (see vanilla
-- CombatPresentation.lua's prompt label + damage text):
--   SpawnObstacle({ Group = "Combat_UI_World", DestinationId = unitId, OffsetY = ... })
-- followed by CreateTextBox on that obstacle. The engine projects to screen
-- automatically as the camera moves; no per-frame updates required.
--
-- P1's label is hidden in solo play (when no additional players exist) so the
-- standard single-player experience is unchanged.
--

---@type HookUtils
local HookUtils = ModRequire "HookUtils.lua"
---@type CoopPlayers
local CoopPlayers = ModRequire "CoopPlayers.lua"

---@class CoopPlayerLabels
local CoopPlayerLabels = {}

---@private
---@type table<number, number>  playerId -> obstacle id (label anchor)
CoopPlayerLabels.LabelObstacles = {}

-- Match CoopPlayerUi's bar colors so a player's label visually pairs with
-- their HUD bar. P1 red; P2 cyan; P3 green; P4 purple.
-- CreateTextBox's Color is 0-255 RGBA (matches Color.White = {255,255,255,255}).
-- OutlineColor and ShadowColor use 0-1 floats in vanilla (inconsistent, but
-- that's the vanilla convention).
---@private
CoopPlayerLabels.LabelColors = {
    [1] = { 230, 64,  64,  255 },
    [2] = { 89,  217, 242, 255 },
    [3] = { 140, 217, 115, 255 },
    [4] = { 179, 115, 230, 255 },
}

-- Vertical offset above the hero's pivot. Zagreus's pivot is at his feet;
-- ~130 units up sits the label just above his head without floating into
-- ceiling geometry in low-ceiling rooms.
---@private
CoopPlayerLabels.LabelOffsetY = -130

---@private
---@return boolean
local function shouldShowLabels()
    return CoopPlayers.GetPlayersCount() > 1
end

---@public
---@param hero table  CoopPlayers hero proxy (must have .ObjectId)
---@param playerId number
function CoopPlayerLabels.ShowFor(hero, playerId)
    if not hero or not hero.ObjectId then return end
    if not shouldShowLabels() then return end

    -- Force-recreate: if there's an existing entry, it may be an orphan
    -- (attached to a destroyed unit from a previous room). Destroy and
    -- rebuild rather than trusting the "already shown" check — the previous
    -- early-return left orphaned obstacles in place when room transitions
    -- invalidated the attach target.
    if CoopPlayerLabels.LabelObstacles[playerId] then
        Destroy({ Id = CoopPlayerLabels.LabelObstacles[playerId] })
        CoopPlayerLabels.LabelObstacles[playerId] = nil
    end

    local color = CoopPlayerLabels.LabelColors[playerId] or { 1, 1, 1, 1 }

    local obstacleId = SpawnObstacle({
        Name = "BlankObstacle",
        Group = "Combat_UI_World",
        DestinationId = hero.ObjectId,
        OffsetY = CoopPlayerLabels.LabelOffsetY,
    })

    -- Attach() pins the obstacle to track the unit's world position
    -- continuously. SpawnObstacle's DestinationId only places the obstacle
    -- at the initial position — without this Attach call, the label sits
    -- where it spawned and doesn't follow the moving character.
    Attach({
        Id = obstacleId,
        DestinationId = hero.ObjectId,
        OffsetY = CoopPlayerLabels.LabelOffsetY,
    })

    CreateTextBox({
        Id = obstacleId,
        Text = "P" .. tostring(playerId),
        Font = "AlegreyaSansSCBold",
        FontSize = 22,
        Color = color,
        OutlineColor = { 0.05, 0.05, 0.05, 1 },
        OutlineThickness = 2,
        ShadowAlpha = 1.0,
        ShadowBlur = 0,
        ShadowOffsetY = 2,
        ShadowOffsetX = 0,
        Justification = "Center",
    })

    CoopPlayerLabels.LabelObstacles[playerId] = obstacleId
end

---@public
---@param playerId number
function CoopPlayerLabels.HideFor(playerId)
    local id = CoopPlayerLabels.LabelObstacles[playerId]
    if not id then return end
    Destroy({ Id = id })
    CoopPlayerLabels.LabelObstacles[playerId] = nil
end

---@public
-- Re-spawn labels for every alive player. Call on room load / major
-- transitions because the engine may destroy obstacle attachments across
-- room boundaries.
function CoopPlayerLabels.RefreshAll()
    -- Collect the existing playerIds before tearing down — iterating with
    -- `pairs` while HideFor mutates the table is undefined behavior in Lua
    -- (some entries get skipped), which left stale obstacle handles that
    -- made ShowFor's "already shown" early-return suppress the re-spawn.
    local stalePlayerIds = {}
    for playerId in pairs(CoopPlayerLabels.LabelObstacles) do
        table.insert(stalePlayerIds, playerId)
    end
    for _, playerId in ipairs(stalePlayerIds) do
        CoopPlayerLabels.HideFor(playerId)
    end

    if not shouldShowLabels() then return end
    for playerId, hero in CoopPlayers.PlayersIterator() do
        if hero and not hero.IsDead then
            CoopPlayerLabels.ShowFor(hero, playerId)
        end
    end
end

---@public
function CoopPlayerLabels.InitHooks()
    -- StartRoom fires on every chamber transition. The previous double-up
    -- with OnAnyLoad raced — OnAnyLoad fires for many events and each call
    -- would tear down and rebuild both labels, occasionally with stale hero
    -- state, leaving one player's label as an orphan (attached to a
    -- destroyed unit). One hook is enough.
    HookUtils.onPostFunction("StartRoom", function()
        CoopPlayerLabels.RefreshAll()
    end)
end

return CoopPlayerLabels
