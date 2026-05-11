--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--
-- Per-player health bar UI factory for players 3 and 4. SecondPlayerUI.lua
-- still owns player 2's full UI (health + ammo + super + gun); this module
-- handles just the health bar for additional slots so 3- and 4-player runs
-- can render at all. Future commits should fold the ammo/super/gun UIs in
-- here too and retire SecondPlayerUI as a parameterized instance.
--

---@type CoopPlayers
local CoopPlayers = ModRequire "CoopPlayers.lua"

---@class CoopPlayerUi
local CoopPlayerUi = {}
CoopPlayerUi.__index = CoopPlayerUi

---@class CoopPlayerUiPosition
---@field anchorX number   Screen-space X anchor (e.g. 10 for left, ScreenWidth - 500 for right)
---@field anchorY number   Screen-space Y anchor (e.g. ScreenHeight - 50 for bottom, 50 for top)
---@field shadowFlipX boolean  True to mirror the bar shadow horizontally (right-side anchored bars)
---@field shadowFlipY boolean  True to mirror the bar shadow vertically (top-anchored bars)

---@type table<number, CoopPlayerUi>
CoopPlayerUi.Instances = {}

---@param playerId number
---@param position CoopPlayerUiPosition
---@return CoopPlayerUi
function CoopPlayerUi.Create(playerId, position)
    local self = setmetatable({}, CoopPlayerUi)
    self.playerId = playerId
    self.position = position
    self.ScreenAnchors = {}
    CoopPlayerUi.Instances[playerId] = self
    return self
end

---@param playerId number
---@return CoopPlayerUi?
function CoopPlayerUi.Get(playerId)
    return CoopPlayerUi.Instances[playerId]
end

function CoopPlayerUi:ShowHealthUI()
    if not ConfigOptionCache.ShowUIAnimations then return end
    if self.ScreenAnchors.HealthBack ~= nil then return end

    local hero = CoopPlayers.GetHero(self.playerId)
    if hero == nil then return end

    local anchorX = self.position.anchorX
    local anchorY = self.position.anchorY

    if self.ScreenAnchors.Shadow == nil then
        self.ScreenAnchors.Shadow = CreateScreenObstacle({
            Name = "BlankObstacle",
            Group = "Combat_UI_Backing",
            X = anchorX,
            Y = anchorY,
        })
        SetAnimation({ Name = "BarShadow", DestinationId = self.ScreenAnchors.Shadow })
        if self.position.shadowFlipX then
            SetScaleX({ Ids = { self.ScreenAnchors.Shadow }, Fraction = -1 })
        end
        if self.position.shadowFlipY then
            SetScaleY({ Ids = { self.ScreenAnchors.Shadow }, Fraction = -1 })
        end
    end

    local barX = anchorX - (10 - CombatUI.FadeDistance.Health)
    local barY = anchorY

    self.ScreenAnchors.HealthBack = CreateScreenObstacle({
        Name = "BlankObstacle", Group = "Combat_UI", X = barX, Y = barY,
    })
    self.ScreenAnchors.HealthRally = CreateScreenObstacle({
        Name = "BlankObstacle", Group = "Combat_UI", X = barX, Y = barY,
    })
    self.ScreenAnchors.HealthFill = CreateScreenObstacle({
        Name = "BlankObstacle", Group = "Combat_UI", X = barX, Y = barY,
    })
    self.ScreenAnchors.HealthFlash = CreateScreenObstacle({
        Name = "BlankObstacle", Group = "Combat_UI", X = barX, Y = barY,
    })

    CreateTextBox(MergeTables({
        Id = self.ScreenAnchors.HealthBack,
        OffsetX = -90,
        OffsetY = -13,
        Font = "AlegreyaSansSCBold",
        FontSize = 24,
        ShadowRed = 0.1,
        ShadowBlue = 0.1,
        ShadowGreen = 0.1,
        OutlineColor = { 0.113, 0.113, 0.113, 1 },
        OutlineThickness = 1,
        ShadowAlpha = 1.0,
        ShadowBlur = 0,
        ShadowOffsetY = 2,
        ShadowOffsetX = 0,
        Justification = "Left",
    }, LocalizationData.UIScripts.HealthUI))

    SetAnimation({ Name = "HealthBar", DestinationId = self.ScreenAnchors.HealthBack })

    local frameTarget = 1 - (hero.Health / hero.MaxHealth)
    SetAnimation({
        Name = "HealthBarFill",
        DestinationId = self.ScreenAnchors.HealthFill,
        FrameTarget = frameTarget,
        Instant = true,
        Color = Color.Black,
    })
    SetAnimation({
        Name = "HealthBarFillWhite",
        DestinationId = self.ScreenAnchors.HealthRally,
        FrameTarget = frameTarget,
        Instant = true,
        Color = Color.RallyHealth,
    })

    self:UpdateHealthUI()

    FadeObstacleIn({ Id = self.ScreenAnchors.HealthBack,  Duration = CombatUI.FadeInDuration, IncludeText = true,  Distance = CombatUI.FadeDistance.Health, Direction = 0 })
    FadeObstacleIn({ Id = self.ScreenAnchors.HealthRally, Duration = CombatUI.FadeInDuration, IncludeText = false, Distance = CombatUI.FadeDistance.Health, Direction = 0 })
    FadeObstacleIn({ Id = self.ScreenAnchors.HealthFill,  Duration = CombatUI.FadeInDuration, IncludeText = false, Distance = CombatUI.FadeDistance.Health, Direction = 0 })
    FadeObstacleIn({ Id = self.ScreenAnchors.HealthFlash, Duration = CombatUI.FadeInDuration, IncludeText = false, Distance = CombatUI.FadeDistance.Health, Direction = 0 })
end

function CoopPlayerUi:UpdateHealthUI()
    local hero = CoopPlayers.GetHero(self.playerId)
    if hero == nil then return end
    if self.ScreenAnchors.HealthFill == nil then return end

    local currentHealth = hero.Health
    local maxHealth = hero.MaxHealth
    if maxHealth == nil or maxHealth <= 0 then return end

    local healthFraction = 1 - (currentHealth / maxHealth)
    SetAnimationFrameTarget({
        Name = "HealthBarFill",
        DestinationId = self.ScreenAnchors.HealthFill,
        FrameTarget = healthFraction,
    })

    ModifyTextBox({
        Id = self.ScreenAnchors.HealthBack,
        Text = string.format("%d / %d", round(currentHealth), round(maxHealth)),
    })
end

function CoopPlayerUi:HideHealthUI()
    if self.ScreenAnchors.HealthBack == nil then return end
    FadeObstacleIn({ Id = self.ScreenAnchors.HealthBack,  Duration = CombatUI.FadeDuration, FadeTarget = 0, IncludeText = true,  Distance = CombatUI.FadeDistance.Health, Angle = 180 })
    FadeObstacleIn({ Id = self.ScreenAnchors.HealthRally, Duration = CombatUI.FadeDuration, FadeTarget = 0, IncludeText = false, Distance = CombatUI.FadeDistance.Health, Angle = 180 })
    FadeObstacleIn({ Id = self.ScreenAnchors.HealthFill,  Duration = CombatUI.FadeDuration, FadeTarget = 0, IncludeText = false, Distance = CombatUI.FadeDistance.Health, Angle = 180 })
    FadeObstacleIn({ Id = self.ScreenAnchors.HealthFlash, Duration = CombatUI.FadeDuration, FadeTarget = 0, IncludeText = false, Distance = CombatUI.FadeDistance.Health, Angle = 180 })
end

function CoopPlayerUi:DestroyHealthUI()
    for _, key in ipairs({ "HealthBack", "HealthRally", "HealthFill", "HealthFlash", "Shadow" }) do
        if self.ScreenAnchors[key] ~= nil then
            Destroy({ Id = self.ScreenAnchors[key] })
            self.ScreenAnchors[key] = nil
        end
    end
end

function CoopPlayerUi:Refresh()
    self:DestroyHealthUI()
    self:ShowHealthUI()
end

-- Refresh every per-player UI instance (P3+ at minimum); used at room/run init.
function CoopPlayerUi.RefreshAll()
    for _, instance in pairs(CoopPlayerUi.Instances) do
        instance:Refresh()
    end
end

return CoopPlayerUi
