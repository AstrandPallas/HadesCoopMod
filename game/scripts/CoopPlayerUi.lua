--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--
-- Per-player UI factory: health, ammo, super, gun, life pips. Each instance owns
-- its own ScreenAnchors table and computes element positions from a position
-- config so the four players can each occupy a different screen corner.
--
-- P2 still goes through SecondPlayerUI.lua which is now a thin shim around a
-- bottom-right CoopPlayerUi instance. P3 (top-left) and P4 (top-right) are
-- created from GamemodeInit when their slot exists.
--

---@type CoopPlayers
local CoopPlayers = ModRequire "CoopPlayers.lua"

---@class CoopPlayerUi
local CoopPlayerUi = {}
CoopPlayerUi.__index = CoopPlayerUi

---@class CoopPlayerUiPosition
---@field healthBarX number
---@field healthBarY number
---@field lifePipBaseX number      X of the rightmost pip (pips grow leftward by 32 each)
---@field lifePipY number
---@field ammoIndicatorX number
---@field ammoIndicatorY number
---@field ammoReloadX number
---@field ammoReloadY number
---@field ammoReloadMultiYOffset number   Y offset added for 2nd+ concurrent reload bar
---@field ammoReloadFinishTargetYOffset number  Y offset for the final destroy-target during reload-end animation
---@field superMeterX number
---@field superMeterY number
---@field superPipY number
---@field gunUiX number
---@field gunUiY number
---@field shadowX number
---@field shadowY number
---@field shadowFlipX boolean
---@field shadowFlipY boolean
---@field selfStoredAmmoBaseOffsetX number
---@field selfStoredAmmoBaseOffsetY number
---@field healthTextOffsetX number   X offset for the "current/max" health text relative to the bar anchor
---@field barColor number[]          RGBA tuple for the health-bar fill tint (also used by the floating P# label)

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

-- Build a default position config anchored at a corner. Returns the existing
-- bottom-right (P2) layout when corner == "BR", and mirrored layouts for the
-- other three corners. P2's layout values are byte-identical to the constants
-- in the original SecondPlayerUI to preserve current visuals exactly.
---@param corner "BR" | "BL" | "TR" | "TL"
---@return CoopPlayerUiPosition
function CoopPlayerUi.LayoutForCorner(corner)
    if corner == "BR" then
        -- Original SecondPlayerUI P2 position. Do not change.
        return {
            healthBarX = ScreenWidth - 500,
            healthBarY = ScreenHeight - 50,
            lifePipBaseX = ScreenWidth - 80,
            lifePipY = ScreenHeight - 95,
            ammoIndicatorX = ScreenWidth - 512 - 150,
            ammoIndicatorY = ScreenHeight - 62,
            ammoReloadX = ScreenWidth - 494 - 150,
            ammoReloadY = ScreenHeight - 70,
            ammoReloadMultiYOffset = 35,
            ammoReloadFinishTargetYOffset = 40,
            superMeterX = ScreenWidth - 500 + 20,
            superMeterY = ScreenHeight - 10,
            superPipY = SuperUI.PipY,
            gunUiX = ScreenWidth - GunUI.StartX - 64 - 100,
            gunUiY = GunUI.StartY,
            shadowX = ScreenWidth,
            shadowY = ScreenHeight,
            shadowFlipX = true,
            shadowFlipY = false,
            selfStoredAmmoBaseOffsetX = 600 + 380,
            selfStoredAmmoBaseOffsetY = -50,
            healthTextOffsetX = -90,
            -- SetAnimation Color is 0-255 RGBA (matches Color.Black = {0,0,0,255}).
            -- Bar tint values are pre-saturated to compensate for the texture's
            -- pastel-ifying multiply blend — the outline+label use brighter RGBs
            -- (89/217/242 etc.) but the bar needs darker dominant-channel input
            -- to render at the same apparent vividness.
            barColor = { 0, 180, 220, 255 },  -- P2 cyan
        }
    elseif corner == "TL" then
        return {
            healthBarX = 10,
            healthBarY = 50,
            lifePipBaseX = 80 + 12 * 32,    -- pips grow leftward from base; put base far right of bar
            lifePipY = 95,
            ammoIndicatorX = 512,
            ammoIndicatorY = 62,
            ammoReloadX = 494,
            ammoReloadY = 70,
            ammoReloadMultiYOffset = 35,
            ammoReloadFinishTargetYOffset = 40,
            superMeterX = 10 + 20,
            superMeterY = 10 + 40,           -- nudge down to keep below health bar
            superPipY = 80,                  -- below the health bar at TL
            gunUiX = 10 + GunUI.StartX + 64 + 100,
            gunUiY = 50 + 80,
            shadowX = 0,
            shadowY = 0,
            shadowFlipX = false,
            shadowFlipY = true,
            selfStoredAmmoBaseOffsetX = 10,
            selfStoredAmmoBaseOffsetY = 50,
            healthTextOffsetX = 0,
            barColor = { 60, 200, 40, 255 },  -- placeholder green; TL is unused in current 4P layout
        }
    elseif corner == "TR" then
        return {
            healthBarX = ScreenWidth - 500,
            healthBarY = 50,
            lifePipBaseX = ScreenWidth - 80,
            lifePipY = 95,
            ammoIndicatorX = ScreenWidth - 512 - 150,
            ammoIndicatorY = 62,
            ammoReloadX = ScreenWidth - 494 - 150,
            ammoReloadY = 70,
            ammoReloadMultiYOffset = 35,
            ammoReloadFinishTargetYOffset = 40,
            superMeterX = ScreenWidth - 500 + 20,
            superMeterY = 50,
            superPipY = 80,
            gunUiX = ScreenWidth - GunUI.StartX - 64 - 100,
            gunUiY = 50 + 80,
            shadowX = ScreenWidth,
            shadowY = 0,
            shadowFlipX = true,
            shadowFlipY = true,
            selfStoredAmmoBaseOffsetX = 600 + 380,
            selfStoredAmmoBaseOffsetY = 50,
            healthTextOffsetX = -90,
            barColor = { 150, 40, 220, 255 },  -- placeholder purple; TR is unused in current 4P layout
        }
    else -- "BL"
        return {
            healthBarX = 10,
            healthBarY = ScreenHeight - 50,
            lifePipBaseX = 80 + 12 * 32,
            lifePipY = ScreenHeight - 95,
            ammoIndicatorX = 512,
            ammoIndicatorY = ScreenHeight - 62,
            ammoReloadX = 494,
            ammoReloadY = ScreenHeight - 70,
            ammoReloadMultiYOffset = 35,
            ammoReloadFinishTargetYOffset = 40,
            superMeterX = 10 + 20,
            superMeterY = ScreenHeight - 10,
            superPipY = SuperUI.PipY,
            gunUiX = 10 + GunUI.StartX + 64 + 100,
            gunUiY = GunUI.StartY,
            shadowX = 0,
            shadowY = ScreenHeight,
            shadowFlipX = false,
            shadowFlipY = false,
            selfStoredAmmoBaseOffsetX = 10,
            selfStoredAmmoBaseOffsetY = -50,
            healthTextOffsetX = 0,
            barColor = { 150, 40, 220, 255 },  -- placeholder purple; BL is unused in current 4P layout
        }
    end
end

-- Build a position config for a bottom-row slot. slotIndex is the player ID
-- (P2/P3/P4) since bottom-row players occupy slots in player-ID order;
-- totalSlots is the number of active players so positions can be spaced
-- evenly between P1's vanilla bottom-left HUD and the bottom-right corner.
--
-- N=2 collapses to a single right-anchored slot (slot 2 sits at the legacy
-- BR position byte-identical). N=3 puts P2 in the middle, P3 at BR. N=4
-- spreads P2/P3/P4 across the gap with P4 at BR.
--
-- Rightmost slot (slotIndex == totalSlots) keeps the BR-style decorative
-- corner shadow and right-aligned pip cluster. Middle slots use an
-- offscreen shadow target and a center-clustered pip set since they have
-- no screen edge to anchor against.
---@param slotIndex 2 | 3 | 4
---@param totalSlots 2 | 3 | 4
---@return CoopPlayerUiPosition
function CoopPlayerUi.LayoutForBottomSlot(slotIndex, totalSlots)
    -- SetAnimation Color is 0-255 RGBA (see Color.lua: Black = {0,0,0,255}).
    -- Bar tints are pre-saturated to compensate for the texture's
    -- pastel-ifying multiply blend — outline+label use the brighter on-
    -- screen palette (89/217/242 etc.) but the bar needs darker dominant-
    -- channel input to render at the same apparent vividness.
    local barColors = {
        [2] = { 0,   180, 220, 255 },   -- P2 cyan
        [3] = { 60,  200, 40,  255 },   -- P3 green
        [4] = { 150, 40,  220, 255 },   -- P4 purple
    }

    local leftAnchor  = 50
    local rightAnchor = ScreenWidth - 500
    local step = (rightAnchor - leftAnchor) / (totalSlots - 1)
    local barX = leftAnchor + (slotIndex - 1) * step

    local isRightmost = slotIndex == totalSlots

    return {
        healthBarX = barX,
        healthBarY = ScreenHeight - 50,
        -- Rightmost slot keeps BR-vanilla's right-aligned pip cluster
        -- (rightmost pip flush with the bar's right edge, reading against
        -- the corner shadow). Middle slots center the cluster on the bar's
        -- visual midpoint (~barX + 210) since they have no corner shadow
        -- to anchor against.
        lifePipBaseX = isRightmost and (barX + 340) or (barX + 242),
        lifePipY = ScreenHeight - 95,
        ammoIndicatorX = barX - 162,
        ammoIndicatorY = ScreenHeight - 62,
        ammoReloadX = barX - 144,
        ammoReloadY = ScreenHeight - 70,
        ammoReloadMultiYOffset = 35,
        ammoReloadFinishTargetYOffset = 40,
        superMeterX = barX + 20,
        superMeterY = ScreenHeight - 10,
        superPipY = SuperUI.PipY,
        gunUiX = barX + 336 - GunUI.StartX,
        gunUiY = GunUI.StartY,
        -- Decorative corner shadow only reads at the screen edge — anchor
        -- it on-screen for the rightmost slot, offscreen for middle slots
        -- (SetAnimation still needs a target obstacle).
        shadowX = isRightmost and ScreenWidth or (barX + 250),
        shadowY = isRightmost and ScreenHeight or (ScreenHeight + 100),
        shadowFlipX = isRightmost,
        shadowFlipY = false,
        selfStoredAmmoBaseOffsetX = 980,
        selfStoredAmmoBaseOffsetY = -50,
        healthTextOffsetX = -90,
        barColor = barColors[slotIndex] or { 200, 200, 200, 255 },
    }
end

-- --------------------------------------------------------------------------
-- Health bar
-- --------------------------------------------------------------------------

function CoopPlayerUi:ShowHealthUI()
    DebugPrint { Text = "TN_Coop ShowHealthUI entered playerId=" .. tostring(self.playerId)
        .. " ShowUIAnimations=" .. tostring(ConfigOptionCache.ShowUIAnimations)
        .. " HealthBack=" .. tostring(self.ScreenAnchors.HealthBack)
        .. " healthBarX=" .. tostring(self.position and self.position.healthBarX)
        .. " barColor=" .. tostring(self.position and self.position.barColor and self.position.barColor[1])
    }
    if not ConfigOptionCache.ShowUIAnimations then return end
    if self.ScreenAnchors.HealthBack ~= nil then return end

    local hero = CoopPlayers.GetHero(self.playerId)
    if hero == nil then
        DebugPrint { Text = "TN_Coop ShowHealthUI hero nil for playerId=" .. tostring(self.playerId) }
        return
    end

    local p = self.position
    local barX = p.healthBarX - (10 - CombatUI.FadeDistance.Health)
    local barY = p.healthBarY

    if self.ScreenAnchors.Shadow == nil then
        self.ScreenAnchors.Shadow = CreateScreenObstacle({
            Name = "BlankObstacle", Group = "Combat_UI_Backing",
            X = p.shadowX, Y = p.shadowY,
        })
        SetAnimation({ Name = "BarShadow", DestinationId = self.ScreenAnchors.Shadow })
        if p.shadowFlipX then
            SetScaleX({ Ids = { self.ScreenAnchors.Shadow }, Fraction = -1 })
        end
        if p.shadowFlipY then
            SetScaleY({ Ids = { self.ScreenAnchors.Shadow }, Fraction = -1 })
        end
    end

    self.ScreenAnchors.HealthBack  = CreateScreenObstacle({ Name = "BlankObstacle", Group = "Combat_UI", X = barX, Y = barY })
    self.ScreenAnchors.HealthRally = CreateScreenObstacle({ Name = "BlankObstacle", Group = "Combat_UI", X = barX, Y = barY })
    self.ScreenAnchors.HealthFill  = CreateScreenObstacle({ Name = "BlankObstacle", Group = "Combat_UI", X = barX, Y = barY })
    self.ScreenAnchors.HealthFlash = CreateScreenObstacle({ Name = "BlankObstacle", Group = "Combat_UI", X = barX, Y = barY })

    self.ScreenAnchors.StoredAmmo = self.ScreenAnchors.StoredAmmo or {}
    self.ScreenAnchors.SelfStoredAmmo = self.ScreenAnchors.SelfStoredAmmo or {}

    self:RecreateLifePips()

    CreateTextBox(MergeTables({
        Id = self.ScreenAnchors.HealthBack,
        OffsetX = p.healthTextOffsetX, OffsetY = -13,
        Font = "AlegreyaSansSCBold", FontSize = 24,
        ShadowRed = 0.1, ShadowBlue = 0.1, ShadowGreen = 0.1,
        OutlineColor = { 0.113, 0.113, 0.113, 1 }, OutlineThickness = 1,
        ShadowAlpha = 1.0, ShadowBlur = 0, ShadowOffsetY = 2, ShadowOffsetX = 0,
        Justification = "Left",
    }, LocalizationData.UIScripts.HealthUI))

    SetAnimation({ Name = "HealthBar", DestinationId = self.ScreenAnchors.HealthBack })

    local frameTarget = 1 - (hero.Health / hero.MaxHealth)
    SetAnimation({ Name = "HealthBarFill",      DestinationId = self.ScreenAnchors.HealthFill,  FrameTarget = frameTarget, Instant = true, Color = p.barColor })
    SetAnimation({ Name = "HealthBarFillWhite", DestinationId = self.ScreenAnchors.HealthRally, FrameTarget = frameTarget, Instant = true, Color = Color.RallyHealth })

    self:UpdateHealthUI()

    if CurrentRun.CurrentRoom.LoadedAmmo then
        for i = 1, CurrentRun.CurrentRoom.LoadedAmmo do
            local offsetX = p.selfStoredAmmoBaseOffsetX + (#self.ScreenAnchors.SelfStoredAmmo * 22)
            local offsetY = p.selfStoredAmmoBaseOffsetY
            local screenId = CreateScreenObstacle({
                Name = "BlankObstacle", Group = "Combat_UI",
                DestinationId = self.ScreenAnchors.HealthBack,
                X = 10 + offsetX, Y = p.healthBarY + offsetY,
            })
            SetThingProperty({ Property = "SortMode", Value = "Id", DestinationId = screenId })
            table.insert(self.ScreenAnchors.SelfStoredAmmo, screenId)
            SetAnimation({ Name = "AmmoEmbeddedInEnemyIcon", DestinationId = screenId })
        end
    end

    FadeObstacleIn({ Id = self.ScreenAnchors.HealthBack,  Duration = CombatUI.FadeInDuration, IncludeText = true,  Distance = CombatUI.FadeDistance.Health, Direction = 0 })
    FadeObstacleIn({ Id = self.ScreenAnchors.HealthRally, Duration = CombatUI.FadeInDuration, IncludeText = false, Distance = CombatUI.FadeDistance.Health, Direction = 0 })
    FadeObstacleIn({ Id = self.ScreenAnchors.HealthFill,  Duration = CombatUI.FadeInDuration, IncludeText = false, Distance = CombatUI.FadeDistance.Health, Direction = 0 })
    FadeObstacleIn({ Id = self.ScreenAnchors.HealthFlash, Duration = CombatUI.FadeInDuration, IncludeText = false, Distance = CombatUI.FadeDistance.Health, Direction = 0 })
    if self.ScreenAnchors.BadgeId ~= nil then
        FadeObstacleIn({ Id = self.ScreenAnchors.BadgeId, Duration = CombatUI.FadeInDuration, IncludeText = false, Distance = CombatUI.FadeDistance.Health, Direction = 0 })
    end
end

function CoopPlayerUi:UpdateHealthUI()
    local hero = CoopPlayers.GetHero(self.playerId)
    if hero == nil then return end

    local currentHealth = hero.Health
    local maxHealth = hero.MaxHealth
    if currentHealth == nil or maxHealth == nil then return end

    local rallyHealth = hero.RallyHealth and hero.RallyHealth.Store or 0
    if self.ScreenAnchors.HealthBack ~= nil then
        ModifyTextBox({
            Id = self.ScreenAnchors.HealthBack,
            Text = "UI_PlayerHealth",
            LuaKey = "TempTextData",
            LuaValue = { Current = math.ceil(currentHealth), Maximum = math.ceil(maxHealth) },
            AutoSetDataProperties = false,
        })
    end

    if self.ScreenAnchors.HealthFill ~= nil then
        SetAnimationFrameTarget({
            Name = "HealthBarFill",
            Fraction = 1 - (currentHealth / maxHealth),
            DestinationId = self.ScreenAnchors.HealthFill,
        })
    end
    if self.ScreenAnchors.HealthRally ~= nil then
        SetAnimationFrameTarget({
            Name = "HealthBarFillWhite",
            Fraction = 1 - (currentHealth + rallyHealth) / maxHealth,
            DestinationId = self.ScreenAnchors.HealthRally,
        })
    end
    if hero.RallyHealth then
        hero.RallyHealth.Cache = { CurrentHealth = currentHealth, MaxHealth = maxHealth }
    end
end

function CoopPlayerUi:UpdateRallyHealthUI()
    local hero = CoopPlayers.GetHero(self.playerId)
    if hero == nil then return end
    if self.ScreenAnchors.HealthRally == nil then return end

    local rallyHealth = hero.RallyHealth and hero.RallyHealth.Store or 0
    local currentHealth = hero.Health
    local maxHealth = hero.MaxHealth
    if hero.RallyHealth and hero.RallyHealth.Cache then
        currentHealth = hero.RallyHealth.Cache.CurrentHealth
        maxHealth = hero.RallyHealth.Cache.MaxHealth
    end
    if currentHealth == nil or maxHealth == nil then return end

    SetAnimationFrameTarget({
        Name = "HealthBarFillWhite",
        Fraction = 1 - (currentHealth + rallyHealth) / maxHealth,
        DestinationId = self.ScreenAnchors.HealthRally,
    })
end

function CoopPlayerUi:HideHealthUI()
    if self.ScreenAnchors.HealthBack == nil then return end

    local healthIds = { "HealthBack", "HealthFill", "HealthFlash", "HealthRally", "BadgeId" }
    local healthAnchorIds = {}
    for _, key in pairs(healthIds) do
        if self.ScreenAnchors[key] ~= nil then
            table.insert(healthAnchorIds, self.ScreenAnchors[key])
        end
    end
    if self.ScreenAnchors.LifePipIds then
        for _, id in pairs(self.ScreenAnchors.LifePipIds) do
            table.insert(healthAnchorIds, id)
        end
    end
    if self.ScreenAnchors.SelfStoredAmmo then
        for _, id in pairs(self.ScreenAnchors.SelfStoredAmmo) do
            table.insert(healthAnchorIds, id)
        end
    end

    self.ScreenAnchors.HealthBack = nil
    self.ScreenAnchors.HealthFill = nil
    self.ScreenAnchors.HealthFlash = nil
    self.ScreenAnchors.HealthRally = nil
    self.ScreenAnchors.LifePipIds = nil
    self.ScreenAnchors.SelfStoredAmmo = nil
    self.ScreenAnchors.BadgeId = nil

    HideObstacle({
        Ids = healthAnchorIds, IncludeText = true, FadeTarget = 0,
        Duration = CombatUI.FadeDuration, Angle = 180, Distance = CombatUI.FadeDistance.Health,
    })

    wait(CombatUI.FadeDuration, RoomThreadName)
    Destroy({ Ids = healthAnchorIds })
end

function CoopPlayerUi:DestroyHealthUI()
    local ids = CombineTables({
        self.ScreenAnchors.HealthBack,
        self.ScreenAnchors.HealthFill,
        self.ScreenAnchors.HealthFlash,
    }, self.ScreenAnchors.LifePipIds)

    if not IsEmpty(ids) then
        Destroy({ Ids = ids })
    end
    self.ScreenAnchors.HealthBack = nil
    self.ScreenAnchors.HealthFill = nil
    self.ScreenAnchors.HealthFlash = nil
    self.ScreenAnchors.HealthRally = nil
    self.ScreenAnchors.LifePipIds = nil
    self.ScreenAnchors.BadgeId = nil
end

-- --------------------------------------------------------------------------
-- Life pips (death insurance)
-- --------------------------------------------------------------------------

function CoopPlayerUi:UpdateLifePips()
    local hero = CoopPlayers.GetHero(self.playerId)
    if not hero or not self.ScreenAnchors.LifePipIds or not hero.LastStands then return end

    for i, lifePipId in pairs(self.ScreenAnchors.LifePipIds) do
        local lastStandData = hero.LastStands[i]
        if lastStandData then
            SetAnimation({ Name = lastStandData.Icon, DestinationId = lifePipId })
        else
            if hero.IsDead then
                if IsMetaUpgradeActive("ExtraChanceReplenishMetaUpgrade") then
                    SetAnimation({ Name = "ExtraLifeReplenish", DestinationId = lifePipId })
                else
                    SetAnimation({ Name = "ExtraLifeZag", DestinationId = lifePipId })
                end
            else
                SetAnimation({ Name = "ExtraLifeEmpty", DestinationId = lifePipId })
            end
        end
    end
end

function CoopPlayerUi:RecreateLifePips()
    if self.ScreenAnchors.LifePipIds then
        Destroy { Ids = self.ScreenAnchors.LifePipIds }
    end
    self.ScreenAnchors.LifePipIds = {}

    local hero = CoopPlayers.GetHero(self.playerId)
    if hero == nil then return end

    local numLastStands = 0
    if hero.IsDead then
        numLastStands = TableLength(hero.LastStands) + GetNumMetaUpgradeLastStands()
    elseif hero.MaxLastStands then
        numLastStands = hero.MaxLastStands
    end

    local p = self.position
    for i = 1, numLastStands do
        local obstacleId = CreateScreenObstacle({
            Name = "BlankObstacle", Group = "Combat_UI",
            X = p.lifePipBaseX - i * 32, Y = p.lifePipY,
        })
        SetAnimation({ Name = "ExtraLifeEmpty", DestinationId = obstacleId })
        table.insert(self.ScreenAnchors.LifePipIds, obstacleId)
    end
    self:UpdateLifePips()
end

-- --------------------------------------------------------------------------
-- Ammo (cast)
-- --------------------------------------------------------------------------

function CoopPlayerUi:ShowAmmoUI()
    if self.ScreenAnchors.AmmoIndicatorUI ~= nil then return end
    local p = self.position
    self.ScreenAnchors.AmmoIndicatorUI = CreateScreenObstacle({
        Name = "BlankObstacle", Group = "Combat_UI",
        X = p.ammoIndicatorX, Y = p.ammoIndicatorY,
    })
    SetAnimation({ Name = "AmmoIndicatorIcon", DestinationId = self.ScreenAnchors.AmmoIndicatorUI })
    CreateTextBox(MergeTables({
        Id = self.ScreenAnchors.AmmoIndicatorUI,
        OffsetX = 24, OffsetY = -2,
        Font = "AlegreyaSansSCBold", FontSize = 24,
        ShadowRed = 0.1, ShadowBlue = 0.1, ShadowGreen = 0.1,
        OutlineColor = { 0.113, 0.113, 0.113, 1 }, OutlineThickness = 1,
        ShadowAlpha = 1.0, ShadowBlur = 0, ShadowOffsetY = 2, ShadowOffsetX = 0,
        Justification = "Left",
    }, LocalizationData.UIScripts.AmmoUI))
    local instance = self
    thread(function() instance:UpdateAmmoUI() end)

    FadeObstacleIn({
        Id = self.ScreenAnchors.AmmoIndicatorUI,
        Duration = CombatUI.FadeInDuration, IncludeText = true,
        Distance = CombatUI.FadeDistance.Ammo, Direction = 0,
    })
end

function CoopPlayerUi:UpdateAmmoUI()
    local hero = CoopPlayers.GetHero(self.playerId)
    if self.ScreenAnchors.AmmoIndicatorUI == nil or not hero then return end

    local ammoData = {
        Current = GetWeaponProperty { Id = hero.ObjectId, WeaponName = "RangedWeapon", Property = "Ammo" },
        Maximum = GetWeaponMaxAmmo  { Id = hero.ObjectId, WeaponName = "RangedWeapon" },
    }
    if ammoData.Current == nil then return end

    PulseText({
        Id = self.ScreenAnchors.AmmoIndicatorUI,
        ScaleTarget = 1.04, ScaleDuration = 0.05, HoldDuration = 0.05, PulseBias = 0.02,
    })
    ModifyTextBox({
        Id = self.ScreenAnchors.AmmoIndicatorUI,
        Text = "UI_AmmoText", OffsetY = -2,
        LuaKey = "TempTextData", LuaValue = ammoData,
        AutoSetDataProperties = false,
    })
end

function CoopPlayerUi:HideAmmoUI()
    if self.ScreenAnchors.AmmoIndicatorUI == nil then return end
    self.ScreenAnchors.AmmoIndicatorUIReloads = self.ScreenAnchors.AmmoIndicatorUIReloads or {}

    local ids = CombineTables({ self.ScreenAnchors.AmmoIndicatorUI }, self.ScreenAnchors.AmmoIndicatorUIReloads)
    for _, reloadId in pairs(ids) do
        HideObstacle({
            Id = reloadId, IncludeText = true,
            Distance = CombatUI.FadeDistance.Ammo, Angle = 180,
            Duration = CombatUI.FadeDuration, SmoothStep = true,
        })
    end
    self.ScreenAnchors.AmmoIndicatorUI = nil
    self.ScreenAnchors.AmmoIndicatorUIReloads = nil

    wait(CombatUI.FadeDuration, RoomThreadName)
    Destroy({ Ids = ids })
end

function CoopPlayerUi:StartAmmoReloadPresentation(delay)
    self.ScreenAnchors.AmmoIndicatorUIReloads = self.ScreenAnchors.AmmoIndicatorUIReloads or {}
    local reloadTimer = delay
    local p = self.position

    if IsEmpty(self.ScreenAnchors.AmmoIndicatorUIReloads) then
        local id = CreateScreenObstacle({
            Name = "BlankObstacle", Group = "Combat_Menu",
            X = p.ammoReloadX + 40 * #self.ScreenAnchors.AmmoIndicatorUIReloads,
            Y = p.ammoReloadY,
        })
        SetAnimation({ Name = "AmmoReloadTimer", DestinationId = id, PlaySpeed = 100 / reloadTimer })
        SetColor({ Id = self.ScreenAnchors.AmmoIndicatorUI, Color = { 0.5, 0.5, 0.5, 1.0 } })
        table.insert(self.ScreenAnchors.AmmoIndicatorUIReloads, id)
    else
        local id = CreateScreenObstacle({
            Name = "BlankObstacle", Group = "Combat_Menu",
            X = p.ammoReloadX + 40 * #self.ScreenAnchors.AmmoIndicatorUIReloads,
            Y = p.ammoIndicatorY + p.ammoReloadMultiYOffset,
        })
        SetAnimation({ Name = "AmmoMultipleReloadTimer", DestinationId = id, PlaySpeed = 100 / reloadTimer })
        SetColor({ Id = self.ScreenAnchors.AmmoIndicatorUI, Color = { 0.5, 0.5, 0.5, 1.0 } })
        table.insert(self.ScreenAnchors.AmmoIndicatorUIReloads, id)
    end
end

function CoopPlayerUi:EndAmmoReloadPresentation()
    if IsEmpty(self.ScreenAnchors.AmmoIndicatorUIReloads) then return end

    SetColor({ Id = self.ScreenAnchors.AmmoIndicatorUI, Color = { 1.0, 1.0, 1.0, 1.0 } })
    CreateAnimation({ DestinationId = self.ScreenAnchors.AmmoIndicatorUI, Name = "AmmoReloadFinishedFlare" })
    table.remove(self.ScreenAnchors.AmmoIndicatorUIReloads, 1)

    local p = self.position
    local destroyIds = {}
    for i, id in pairs(self.ScreenAnchors.AmmoIndicatorUIReloads) do
        local targetId = SpawnObstacle({
            Name = "InvisibleTarget",
            OffsetX = ScreenWidth + 40 * (i - 1),
            OffsetY = p.ammoIndicatorY + p.ammoReloadFinishTargetYOffset,
            Group = "Standing",
        })
        Move({ Id = id, DestinationId = targetId, Duration = 0.25 })
        table.insert(destroyIds, targetId)
    end
    local hero = CoopPlayers.GetHero(self.playerId)
    if hero and hero.ObjectId then
        PlaySound({ Name = "/SFX/BloodstoneAmmoRecharged", Id = hero.ObjectId })
    end
    Destroy({ Ids = destroyIds })
end

function CoopPlayerUi:DestroyAmmoUI()
    if self.ScreenAnchors.AmmoIndicatorUI == nil then return end
    Destroy({ Id = self.ScreenAnchors.AmmoIndicatorUI })
    if self.ScreenAnchors.AmmoIndicatorUIReloads then
        Destroy({ Ids = self.ScreenAnchors.AmmoIndicatorUIReloads })
    end
    self.ScreenAnchors.AmmoIndicatorUI = nil
    self.ScreenAnchors.AmmoIndicatorUIReloads = nil
end

-- --------------------------------------------------------------------------
-- Gun UI
-- --------------------------------------------------------------------------

function CoopPlayerUi:ShowGunUI()
    local hero = CoopPlayers.GetHero(self.playerId)
    if not hero or not hero.Weapons or not hero.Weapons.GunWeapon then return end
    if self.ScreenAnchors.GunUI ~= nil then return end

    if self.ScreenAnchors.Shadow ~= nil and self.position.shadowFlipX then
        SetScaleX({ Id = self.ScreenAnchors.Shadow, Fraction = -1.3 })
    end

    self.ScreenAnchors.GunUI = CreateScreenObstacle({
        Name = "BlankObstacle", Group = "Combat_UI",
        X = self.position.gunUiX, Y = self.position.gunUiY,
    })

    if HeroHasTrait("GunLoadedGrenadeTrait") then
        SetAnimation({ Name = "GunLaserIndicatorIcon", DestinationId = self.ScreenAnchors.GunUI })
    else
        SetAnimation({ Name = "GunAmmoIndicatorIcon", DestinationId = self.ScreenAnchors.GunUI })
    end

    CreateTextBox(MergeTables({
        Id = self.ScreenAnchors.GunUI,
        OffsetX = 20, OffsetY = -2,
        Font = "AlegreyaSansSCBold", FontSize = 24,
        ShadowRed = 0.1, ShadowBlue = 0.1, ShadowGreen = 0.1,
        OutlineColor = { 0.113, 0.113, 0.113, 1 }, OutlineThickness = 1,
        ShadowAlpha = 1.0, ShadowBlur = 0, ShadowOffsetY = 2, ShadowOffsetX = 0,
        Justification = "Left",
    }, LocalizationData.UIScripts.GunUI))

    local instance = self
    thread(function() instance:UpdateGunUI() end)

    FadeObstacleIn({
        Id = self.ScreenAnchors.GunUI,
        Duration = CombatUI.FadeInDuration, IncludeText = true,
        Distance = CombatUI.FadeDistance.Ammo, Direction = 0,
    })
end

function CoopPlayerUi:UpdateGunUI(triggerArgs)
    triggerArgs = triggerArgs or {}
    local hero = CoopPlayers.GetHero(self.playerId)
    if self.ScreenAnchors.GunUI == nil or not hero or not hero.ObjectId then return end

    local ammoData = {
        Current = triggerArgs.Ammo or GetWeaponProperty({ Id = hero.ObjectId, WeaponName = "GunWeapon", Property = "Ammo" }),
        Maximum = triggerArgs.MaxAmmo or GetWeaponMaxAmmo({ Id = hero.ObjectId, WeaponName = "GunWeapon" }),
    }
    if ammoData.Current == nil then return end

    PulseText({ Id = self.ScreenAnchors.GunUI, ScaleTarget = 1.04, ScaleDuration = 0.05, HoldDuration = 0.05, PulseBias = 0.02 })
    if ammoData.Current > 0 then
        ModifyTextBox({ Id = self.ScreenAnchors.GunUI, Text = "UI_GunText", Color = Color.White, ColorDuration = 0.04 })
    else
        ModifyTextBox({ Id = self.ScreenAnchors.GunUI, Text = "UI_GunText", Color = Color.Red,   ColorDuration = 0.04 })
    end
    ModifyTextBox({ Id = self.ScreenAnchors.GunUI, Text = "UI_GunText", FadeTarget = 1 })

    if HeroHasTrait("GunInfiniteAmmoTrait") or HeroHasTrait("GunLoadedGrenadeInfiniteAmmoTrait") then
        ModifyTextBox({
            Id = self.ScreenAnchors.GunUI, Text = "UI_Gun_Text_Infinity", OffsetY = -2,
            LuaKey = "TempTextData", LuaValue = ammoData, AutoSetDataProperties = false,
        })
    else
        ModifyTextBox({
            Id = self.ScreenAnchors.GunUI, Text = "UI_GunText", OffsetY = -2,
            LuaKey = "TempTextData", LuaValue = ammoData, AutoSetDataProperties = false,
        })
    end

    if HeroHasTrait("GunLoadedGrenadeTrait") then
        SetAnimation({ Name = "GunLaserIndicatorIcon", DestinationId = self.ScreenAnchors.GunUI })
    else
        SetAnimation({ Name = "GunAmmoIndicatorIcon", DestinationId = self.ScreenAnchors.GunUI })
    end
end

function CoopPlayerUi:HideGunUI()
    if self.ScreenAnchors.GunUI == nil then return end

    local id = self.ScreenAnchors.GunUI
    HideObstacle({
        Id = id, IncludeText = true,
        Distance = CombatUI.FadeDistance.Ammo, Angle = 180,
        Duration = CombatUI.FadeDuration, SmoothStep = true,
    })
    self.ScreenAnchors.GunUI = nil

    wait(CombatUI.FadeDuration, RoomThreadName)
    Destroy({ Id = id })
    ModifyTextBox({ Id = id, FadeTarget = 0, FadeDuration = 0, AutoSetDataProperties = false })
end

function CoopPlayerUi:DestroyGunUI()
    if self.ScreenAnchors.GunUI == nil then return end
    Destroy({ Id = self.ScreenAnchors.GunUI })
    self.ScreenAnchors.GunUI = nil
end

-- --------------------------------------------------------------------------
-- Super meter (Wrath)
-- --------------------------------------------------------------------------

function CoopPlayerUi:ShowSuperMeter()
    if not IsSuperValid() then return end
    if self.ScreenAnchors.SuperMeterIcon ~= nil then return end

    local hero = CoopPlayers.GetHero(self.playerId)
    if not hero then return end

    local p = self.position
    local posX = p.superMeterX

    self.ScreenAnchors.SuperMeterIcon = CreateScreenObstacle({
        Name = "BlankObstacle", Group = "Combat_UI",
        X = posX - (10 - CombatUI.FadeDistance.Super), Y = p.superMeterY,
    })
    self.ScreenAnchors.SuperMeterCap = CreateScreenObstacle({
        Name = "BlankObstacle", Group = "Combat_Menu",
        X = posX - (10 - CombatUI.FadeDistance.Super), Y = p.superMeterY,
    })
    self.ScreenAnchors.SuperMeterHint = CreateScreenObstacle({
        Name = "BlankObstacle", Group = "Combat_Menu_Additive",
        X = posX - 10, Y = p.superMeterY,
    })

    SetAnimation({ Name = "WrathBar", DestinationId = self.ScreenAnchors.SuperMeterIcon })

    if HasHeroTraitValue("SuperMeterCap") then
        SetAnimation({ Name = "WrathBarRegenCap", DestinationId = self.ScreenAnchors.SuperMeterCap })
    end

    local superMeterPoints = hero.SuperMeter or 0
    if hero.SuperMeter == hero.SuperMeterLimit and IsSuperAvailable(hero) and CanCommenceSuper() then
        SetAnimation({ Name = "WrathBarFullFx", DestinationId = self.ScreenAnchors.SuperMeterHint })
    end

    self.ScreenAnchors.SuperPipBackingIds = {}
    self.ScreenAnchors.SuperPipIds = {}
    local pipXSize = SuperUI.PipXWidth * hero.SuperCost / SuperUI.BaseMoveThreshold
    for i = 1, math.ceil(hero.SuperMeterLimit / hero.SuperCost) do
        table.insert(self.ScreenAnchors.SuperPipBackingIds, CreateScreenObstacle({
            Name = "BlankObstacle", Group = "Combat_UI",
            X = posX + SuperUI.PipXStart + (i - 1) * pipXSize - CombatUI.FadeDistance.Super + 20,
            Y = p.superPipY,
        }))
        table.insert(self.ScreenAnchors.SuperPipIds, CreateScreenObstacle({
            Name = "BlankObstacle", Group = "Combat_Menu_Additive",
            X = posX + SuperUI.PipXStart + (i - 1) * pipXSize - CombatUI.FadeDistance.Super + 20,
            Y = p.superPipY,
        }))
        local fillPercent = 0
        if superMeterPoints > (i - 1) * hero.SuperCost then
            if hero.SuperMeterLimit < hero.SuperCost * i and i == math.ceil(hero.SuperMeterLimit / hero.SuperCost) then
                fillPercent = math.min(1, (superMeterPoints - (i - 1) * hero.SuperCost) / (hero.SuperMeterLimit % hero.SuperCost))
            else
                fillPercent = math.min(1, (superMeterPoints - (i - 1) * hero.SuperCost) / hero.SuperCost)
            end
        end
        self:UpdateSuperUIComponent(i, fillPercent)
    end

    self:UpdateSuperMeterUIReal()

    FadeObstacleIn({ Id = self.ScreenAnchors.SuperMeterIcon, Duration = CombatUI.FadeInDuration, IncludeText = true,  Distance = CombatUI.FadeDistance.Super, Direction = 0 })
    FadeObstacleIn({ Id = self.ScreenAnchors.SuperMeterCap,  Duration = CombatUI.FadeInDuration, IncludeText = true,  Distance = CombatUI.FadeDistance.Super, Direction = 0 })
    for _, pipId in pairs(self.ScreenAnchors.SuperPipIds) do
        FadeObstacleIn({ Id = pipId, Duration = CombatUI.FadeInDuration, IncludeText = false, Distance = CombatUI.FadeDistance.Super, Direction = 0 })
    end
    for _, pipId in pairs(self.ScreenAnchors.SuperPipBackingIds) do
        FadeObstacleIn({ Id = pipId, Duration = CombatUI.FadeInDuration, IncludeText = false, Distance = CombatUI.FadeDistance.Super, Direction = 0 })
    end
end

function CoopPlayerUi:HideSuperMeter()
    if self.ScreenAnchors.SuperMeterIcon == nil then return end

    HideObstacle({ Id = self.ScreenAnchors.SuperMeterIcon, IncludeText = true, Distance = CombatUI.FadeDistance.Super, Angle = 180, Duration = CombatUI.FadeDuration, SmoothStep = true })
    HideObstacle({ Id = self.ScreenAnchors.SuperMeterCap,  IncludeText = true, Distance = CombatUI.FadeDistance.Super, Angle = 180, Duration = CombatUI.FadeDuration, SmoothStep = true })

    for _, pipId in pairs(self.ScreenAnchors.SuperPipIds or {}) do
        Move({ Id = pipId, Distance = CombatUI.FadeDistance.Super, Angle = 180, Duration = CombatUI.FadeDuration, SmoothStep = true })
        SetAlpha({ Id = pipId, Fraction = 0, Duration = CombatUI.FadeDuration })
    end
    for _, pipId in pairs(self.ScreenAnchors.SuperPipBackingIds or {}) do
        Move({ Id = pipId, Distance = CombatUI.FadeDistance.Super, Angle = 180, Duration = CombatUI.FadeDuration, SmoothStep = true })
        SetAlpha({ Id = pipId, Fraction = 0, Duration = CombatUI.FadeDuration })
    end

    local ids = CombineTables(self.ScreenAnchors.SuperPipIds, self.ScreenAnchors.SuperPipBackingIds) or {}
    table.insert(ids, self.ScreenAnchors.SuperMeterIcon)
    table.insert(ids, self.ScreenAnchors.SuperMeterCap)
    table.insert(ids, self.ScreenAnchors.SuperMeterHint)

    self.ScreenAnchors.SuperMeterIcon = nil
    self.ScreenAnchors.SuperMeterCap = nil
    self.ScreenAnchors.SuperMeterHint = nil
    self.ScreenAnchors.SuperPipIds = nil
    self.ScreenAnchors.SuperPipBackingIds = nil

    wait(CombatUI.FadeDuration, RoomThreadName)
    Destroy({ Ids = ids })
end

function CoopPlayerUi:DestroySuperMeter()
    local ids = CombineTables(self.ScreenAnchors.SuperPipIds, self.ScreenAnchors.SuperPipBackingIds) or {}
    table.insert(ids, self.ScreenAnchors.SuperMeterIcon)
    table.insert(ids, self.ScreenAnchors.SuperMeterCap)
    table.insert(ids, self.ScreenAnchors.SuperMeterHint)
    if not IsEmpty(ids) then
        Destroy({ Ids = ids })
    end
    self.ScreenAnchors.SuperMeterIcon = nil
    self.ScreenAnchors.SuperMeterCap = nil
    self.ScreenAnchors.SuperMeterHint = nil
    self.ScreenAnchors.SuperPipIds = nil
    self.ScreenAnchors.SuperPipBackingIds = nil
end

function CoopPlayerUi:UpdateSuperUIComponent(index, filled)
    local hero = CoopPlayers.GetHero(self.playerId)
    if not hero or not hero.SuperCost then return end
    if self.ScreenAnchors.SuperPipBackingIds == nil or self.ScreenAnchors.SuperPipIds == nil then return end

    local animationName = "WrathPipEmpty"
    if filled >= 1 then
        animationName = "WrathPipFull"
    elseif filled > 0 then
        animationName = "WrathPipPartial"
    end

    SetAnimation({ Name = "WrathPipEmpty",   DestinationId = self.ScreenAnchors.SuperPipBackingIds[index] })
    SetAnimation({ Name = animationName,     DestinationId = self.ScreenAnchors.SuperPipIds[index] })
    local baseFraction = hero.SuperCost / SuperUI.BaseMoveThreshold * 1.0
    if hero.SuperMeterLimit < hero.SuperCost * index then
        baseFraction = (hero.SuperMeterLimit % hero.SuperCost) / SuperUI.BaseMoveThreshold * 1.0
    end
    SetScaleX({ Id = self.ScreenAnchors.SuperPipBackingIds[index], Fraction = baseFraction, Duration = 0 })
    SetScaleX({ Id = self.ScreenAnchors.SuperPipIds[index],        Fraction = baseFraction * filled, Duration = 0 })
end

function CoopPlayerUi:UpdateSuperMeterUIReal()
    local hero = CoopPlayers.GetHero(self.playerId)
    if not hero or not hero.SuperCost then return end
    if self.ScreenAnchors.SuperMeterIcon == nil then return end

    local superMeterPoints = hero.SuperMeter or 0
    for i = 1, TableLength(self.ScreenAnchors.SuperPipBackingIds) do
        local fillPercent = 0
        if superMeterPoints > (i - 1) * hero.SuperCost then
            if hero.SuperMeterLimit < hero.SuperCost * i and i == math.ceil(hero.SuperMeterLimit / hero.SuperCost) then
                fillPercent = math.min(1, (superMeterPoints - (i - 1) * hero.SuperCost) / (hero.SuperMeterLimit % hero.SuperCost))
            else
                fillPercent = math.min(1, (superMeterPoints - (i - 1) * hero.SuperCost) / hero.SuperCost)
            end
        end
        self:UpdateSuperUIComponent(i, fillPercent)
    end
    ModifyTextBox({
        Id = self.ScreenAnchors.SuperMeterIcon,
        Text = "UI_SuperText",
        LuaKey = "TempTextData",
        LuaValue = { Current = math.floor(superMeterPoints), Maximum = hero.SuperMeterLimit },
    })
end

-- --------------------------------------------------------------------------
-- Composite refresh
-- --------------------------------------------------------------------------

function CoopPlayerUi:Refresh()
    self:UpdateHealthUI()
    self:RecreateLifePips()
    self:UpdateAmmoUI()
end

function CoopPlayerUi.RefreshAll()
    for _, instance in pairs(CoopPlayerUi.Instances) do
        instance:Refresh()
    end
end

return CoopPlayerUi
