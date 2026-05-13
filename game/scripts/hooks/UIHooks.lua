--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type SecondPlayerUi
local SecondPlayerUi = ModRequire "../SecondPlayerUI.lua"
---@type CoopPlayerUi
local CoopPlayerUi = ModRequire "../CoopPlayerUi.lua"
---@type CombinedTraitsUI
local CombinedTraitsUI = ModRequire "../CombinedTraitsUI.lua"
---@type CoopPlayers
local CoopPlayers = ModRequire "../CoopPlayers.lua"
---@type HeroContext
local HeroContext = ModRequire "../HeroContext.lua"
---@type HookUtils
local HookUtils = ModRequire "../HookUtils.lua"
---@type RunEx
local RunEx = ModRequire "../RunEx.lua"

---@class UIHooks
local UIHooks = {}

---@private
---@param hero table?
function UIHooks.ShouldBeUiVisibleFor(hero)
    return hero and (RunEx.IsRunEnded() or not hero.IsDead)
end

---@private
-- For P3+, dispatch to the matching CoopPlayerUi method when one exists.
-- P2 is handled separately via the SecondPlayerUi shim (which itself wraps a
-- P2 CoopPlayerUi instance), so we skip playerId == 2 here to avoid calling
-- P2's methods twice per event.
---@param funcName string
local function CallExtraPlayerUis(funcName)
    for playerId, ui in pairs(CoopPlayerUi.Instances) do
        if playerId ~= 2 then
            local hero = CoopPlayers.GetHero(playerId)
            if hero and ui[funcName] then
                HeroContext.RunWithHeroContext(hero, ui[funcName], ui)
            end
        end
    end
end

---@private
---@param funcName string
function UIHooks.CreateSimpleHook(funcName)
    local orig = _G[funcName]
    _G[funcName] = function(...)
        local mainHero = CoopPlayers.GetMainHero()
        local secondHero = CoopPlayers.GetHero(2)
        HeroContext.RunWithHeroContext(mainHero, orig, ...)
        if secondHero then
            HeroContext.RunWithHeroContext(secondHero, SecondPlayerUi[funcName], ...)
        end
        CallExtraPlayerUis(funcName)
    end
end

---@private
---@param funcName string
function UIHooks.SimpleHookWithVisibilityCheck(funcName)
    local orig = _G[funcName]
    _G[funcName] = function(...)
        local mainHero = CoopPlayers.GetMainHero()
        if UIHooks.ShouldBeUiVisibleFor(mainHero) then
            HeroContext.RunWithHeroContext(mainHero, orig, ...)
        end
        local secondHero = CoopPlayers.GetHero(2)
        if UIHooks.ShouldBeUiVisibleFor(secondHero) then
            HeroContext.RunWithHeroContext(secondHero, SecondPlayerUi[funcName], ...)
        end
        for playerId, ui in pairs(CoopPlayerUi.Instances) do
            if playerId ~= 2 then
                local hero = CoopPlayers.GetHero(playerId)
                if UIHooks.ShouldBeUiVisibleFor(hero) and ui[funcName] then
                    HeroContext.RunWithHeroContext(hero, ui[funcName], ui)
                end
            end
        end
    end
end

---@private
function UIHooks.SimpleCurrentTraitWrapper(funcName)
    HookUtils.wrap(funcName, function(baseFun, ...)
        HeroContext.RunWithHeroContext(CombinedTraitsUI.GetCurrentTraitHero(), baseFun, ...)
    end)
end

function UIHooks.InitHooks()
    -- Health
    -- Replace vanilla ShowHealthUI to center the "Current/Max" text on the
    -- bar instead of vanilla's right-anchored Left-justified placement
    -- (OffsetX=374, Justification="Left"). ModifyTextBox doesn't support
    -- updating OffsetX/Justification after CreateTextBox — those are set
    -- only at creation — so the post-hook approach that tried to recenter
    -- after the fact silently no-op'd. This pre-empts vanilla so the
    -- desired params are baked in from the first CreateTextBox call.
    --
    -- Body is verbatim UIScripts.lua:ShowHealthUI with two changes:
    --   - the CreateTextBox call uses OffsetX=210, Justification="Center"
    --   - everything else is identical, including the BadgeId/StoredAmmo
    --     setup and FadeObstacleIn dispatch, so vanilla-equivalent visuals.
    -- If vanilla updates this function in a future Hades patch, the
    -- override needs the same diff.
    ShowHealthUI = function()
        if not ConfigOptionCache.ShowUIAnimations then return end
        if ScreenAnchors.HealthBack ~= nil then return end

        if ScreenAnchors.Shadow == nil then
            ScreenAnchors.Shadow = CreateScreenObstacle({ Name = "BlankObstacle", Group = "Combat_UI_Backing", X = 0, Y = ScreenHeight })
            SetAnimation({ Name = "BarShadow", DestinationId = ScreenAnchors.Shadow })
        end

        ScreenAnchors.HealthBack  = CreateScreenObstacle({ Name = "BlankObstacle", Group = "Combat_UI", X = 10 - CombatUI.FadeDistance.Health, Y = ScreenHeight - 50 })
        ScreenAnchors.HealthRally = CreateScreenObstacle({ Name = "BlankObstacle", Group = "Combat_UI", X = 10 - CombatUI.FadeDistance.Health, Y = ScreenHeight - 50 })
        ScreenAnchors.HealthFill  = CreateScreenObstacle({ Name = "BlankObstacle", Group = "Combat_UI", X = 10 - CombatUI.FadeDistance.Health, Y = ScreenHeight - 50 })
        ScreenAnchors.HealthFlash = CreateScreenObstacle({ Name = "BlankObstacle", Group = "Combat_UI", X = 10 - CombatUI.FadeDistance.Health, Y = ScreenHeight - 50 })
        ScreenAnchors.StoredAmmo     = ScreenAnchors.StoredAmmo     or {}
        ScreenAnchors.SelfStoredAmmo = ScreenAnchors.SelfStoredAmmo or {}

        if GameState.BadgeRank ~= nil then
            local badgeData = GameData.BadgeData[GameData.BadgeOrderData[GameState.BadgeRank]]
            ScreenAnchors.BadgeId = CreateScreenObstacle({ Name = "BlankObstacle", Group = "Combat_UI", X = 44, Y = ScreenHeight - 60, Scale = 0.5 })
            SetAnimation({ Name = badgeData.Icon, DestinationId = ScreenAnchors.BadgeId })
        end

        RecreateLifePips()

        CreateTextBox(MergeTables({
            Id = ScreenAnchors.HealthBack,
            OffsetX = 210, OffsetY = -13,
            Font = "AlegreyaSansSCBold", FontSize = 24,
            ShadowRed = 0.1, ShadowBlue = 0.1, ShadowGreen = 0.1,
            OutlineColor = { 0.113, 0.113, 0.113, 1 }, OutlineThickness = 1,
            ShadowAlpha = 1.0, ShadowBlur = 0, ShadowOffsetY = 2, ShadowOffsetX = 0,
            Justification = "Center",
        }, LocalizationData.UIScripts.HealthUI))

        SetAnimation({ Name = "HealthBar", DestinationId = ScreenAnchors.HealthBack })

        local frameTarget = 1 - (CurrentRun.Hero.Health / CurrentRun.Hero.MaxHealth)
        SetAnimation({ Name = "HealthBarFill",      DestinationId = ScreenAnchors.HealthFill,  FrameTarget = frameTarget, Instant = true, Color = Color.Black })
        SetAnimation({ Name = "HealthBarFillWhite", DestinationId = ScreenAnchors.HealthRally, FrameTarget = frameTarget, Instant = true, Color = Color.RallyHealth })

        thread(UpdateHealthUI)

        if CurrentRun.CurrentRoom.LoadedAmmo then
            for i = 1, CurrentRun.CurrentRoom.LoadedAmmo do
                local offsetX = 380 + (#ScreenAnchors.SelfStoredAmmo * 22)
                local offsetY = -50
                local screenId = CreateScreenObstacle({ Name = "BlankObstacle", Group = "Combat_UI", DestinationId = ScreenAnchors.HealthBack, X = 10 + offsetX, Y = ScreenHeight - 50 + offsetY })
                SetThingProperty({ Property = "SortMode", Value = "Id", DestinationId = screenId })
                table.insert(ScreenAnchors.SelfStoredAmmo, screenId)
                SetAnimation({ Name = "AmmoEmbeddedInEnemyIcon", DestinationId = screenId })
            end
        end

        FadeObstacleIn({ Id = ScreenAnchors.HealthBack,  Duration = CombatUI.FadeInDuration, IncludeText = true,  Distance = CombatUI.FadeDistance.Health, Direction = 0 })
        FadeObstacleIn({ Id = ScreenAnchors.HealthRally, Duration = CombatUI.FadeInDuration, IncludeText = false, Distance = CombatUI.FadeDistance.Health, Direction = 0 })
        FadeObstacleIn({ Id = ScreenAnchors.HealthFill,  Duration = CombatUI.FadeInDuration, IncludeText = false, Distance = CombatUI.FadeDistance.Health, Direction = 0 })
        FadeObstacleIn({ Id = ScreenAnchors.HealthFlash, Duration = CombatUI.FadeInDuration, IncludeText = false, Distance = CombatUI.FadeDistance.Health, Direction = 0 })
        if ScreenAnchors.BadgeId ~= nil then
            FadeObstacleIn({ Id = ScreenAnchors.BadgeId, Duration = CombatUI.FadeInDuration, IncludeText = false, Distance = CombatUI.FadeDistance.Health, Direction = 0 })
        end
    end

    UIHooks.SimpleHookWithVisibilityCheck("ShowHealthUI")

    UIHooks.CreateSimpleHook("UpdateHealthUI")
    HookUtils.onPostFunction("DestroyHealthUI", function()
        SecondPlayerUi.DestroyHealthUI()
        for playerId, ui in pairs(CoopPlayerUi.Instances) do
            if playerId ~= 2 then
                ui:DestroyHealthUI()
            end
        end
    end)
    HookUtils.onPreFunction("HideHealthUI", function()
        thread(SecondPlayerUi.HideHealthUI)
        for playerId, ui in pairs(CoopPlayerUi.Instances) do
            if playerId ~= 2 then
                thread(function() ui:HideHealthUI() end)
            end
        end
    end)
    HookUtils.onPostFunction("UpdateRallyHealthUI", SecondPlayerUi.UpdateRallyHealthUI)

    -- LifePipIds
    UIHooks.CreateSimpleHook("RecreateLifePips")

    HookUtils.wrap("UpdateLifePips", function(basefun, unit)
        local mainHero = CoopPlayers.GetMainHero()
        if not mainHero or not unit or mainHero == unit then
            basefun(mainHero)
        end
        SecondPlayerUi.UpdateLifePips()
        for playerId, ui in pairs(CoopPlayerUi.Instances) do
            if playerId ~= 2 then
                ui:UpdateLifePips()
            end
        end
    end)

    local _AddLastStand = AddLastStand
    AddLastStand = function(args)
        local currentHero = HeroContext.GetCurrentHeroContext()
        local mainHero = CoopPlayers.GetMainHero()
        local playerId = currentHero and CoopPlayers.GetPlayerByHero(currentHero)

        if not playerId or currentHero == mainHero then
            _AddLastStand(args)
            return
        end

        -- Non-main player: redirect ScreenAnchors.LifePipIds to that player's
        -- anchors so vanilla code mutates the right pip set, and override
        -- CreateScreenObstacle to either reflect the X (P2's original hack
        -- for the BR layout) or be a no-op for P3/P4 (their visuals get
        -- rebuilt from hero state via UpdateLifePips below — the BR-specific
        -- X-flip math wouldn't make sense for TL/TR anyway).
        local pipsBackup = ScreenAnchors.LifePipIds
        local _CreateScreenObstacle = CreateScreenObstacle

        if playerId == 2 then
            ScreenAnchors.LifePipIds = SecondPlayerUi.ScreenAnchors.LifePipIds
            CreateScreenObstacle = function(args)
                args.X = (ScreenWidth - 80) - (args.X - 70)
            end
        else
            local ui = CoopPlayerUi.Get(playerId)
            if ui then
                ScreenAnchors.LifePipIds = ui.ScreenAnchors.LifePipIds
            end
            CreateScreenObstacle = function(args) end
        end

        _AddLastStand(args)

        ScreenAnchors.LifePipIds = pipsBackup
        CreateScreenObstacle = _CreateScreenObstacle

        if playerId >= 3 then
            local ui = CoopPlayerUi.Get(playerId)
            if ui then ui:UpdateLifePips() end
        end
    end

    -- Ammo (red crystrals)
    -- Replace vanilla ShowAmmoUI to position P1's bloodstone above the bar
    -- next to the lifepip row, matching how P2-P4's CoopPlayerUi positions
    -- the cast indicator. Done BEFORE SimpleHookWithVisibilityCheck so our
    -- version becomes the `orig` the per-player dispatcher invokes for P1.
    -- Body is verbatim vanilla UIScripts.lua:ShowAmmoUI with X/Y changed —
    -- if vanilla updates the obstacle setup, this needs the same diff.
    ShowAmmoUI = function()
        if not ConfigOptionCache.ShowUIAnimations then return end
        if ScreenAnchors.AmmoIndicatorUI ~= nil then return end

        -- X=216 puts the icon ~50px past the rightmost lifepip in the
        -- 3-pip default case (P1 pips grow rightward from X=102; 3 pips
        -- end at X=166). Vanilla maxes out at 3 Last Stands with all
        -- Death Defiance Mirror upgrades, so this gap stays consistent.
        -- Y is lifted 10px above the pip row to compensate for the icon
        -- art's lower-anchored baseline (matches CoopPlayerUi's offset).
        ScreenAnchors.AmmoIndicatorUI = CreateScreenObstacle({
            Name = "BlankObstacle", Group = "Combat_UI",
            X = 216, Y = ScreenHeight - 105,
        })
        SetAnimation({ Name = "AmmoIndicatorIcon", DestinationId = ScreenAnchors.AmmoIndicatorUI })
        CreateTextBox(MergeTables({
            Id = ScreenAnchors.AmmoIndicatorUI, OffsetX = 24, OffsetY = -2,
            Font = "AlegreyaSansSCBold", FontSize = 24,
            ShadowRed = 0.1, ShadowBlue = 0.1, ShadowGreen = 0.1,
            OutlineColor = { 0.113, 0.113, 0.113, 1 }, OutlineThickness = 1,
            ShadowAlpha = 1.0, ShadowBlur = 0, ShadowOffsetY = 2, ShadowOffsetX = 0,
            Justification = "Left",
        }, LocalizationData.UIScripts.AmmoUI))
        thread(UpdateAmmoUI)
        FadeObstacleIn({
            Id = ScreenAnchors.AmmoIndicatorUI,
            Duration = CombatUI.FadeInDuration, IncludeText = true,
            Distance = CombatUI.FadeDistance.Ammo, Direction = 0,
        })
    end

    UIHooks.SimpleHookWithVisibilityCheck("ShowAmmoUI")
    HookUtils.onPreFunction("HideAmmoUI", function() thread(SecondPlayerUi.HideAmmoUI) end)
    HookUtils.onPreFunction("DestroyAmmoUI", SecondPlayerUi.DestroyAmmoUI)

    HookUtils.wrap("StartAmmoReloadPresentation", function(baseFun, delay)
        if CoopPlayers.GetMainHero() == HeroContext.GetCurrentHeroContext() then
            baseFun(delay)
        else
            SecondPlayerUi.StartAmmoReloadPresentation(delay)
        end
    end)

    HookUtils.wrap("EndAmmoReloadPresentation", function(baseFun)
        if CoopPlayers.GetMainHero() == HeroContext.GetCurrentHeroContext() then
            baseFun()
        else
            SecondPlayerUi.EndAmmoReloadPresentation()
        end
    end)

    local _UpdateAmmoUI = UpdateAmmoUI
    UpdateAmmoUI = function()
        local mainHero = CoopPlayers.GetMainHero()
        if HeroContext.IsHeroContextExplicit() then
            local currentHero = HeroContext.GetCurrentHeroContext()
            if currentHero == mainHero then
                _UpdateAmmoUI()
            else
                local playerId = CoopPlayers.GetPlayerByHero(currentHero)
                if playerId == 2 then
                    SecondPlayerUi.UpdateAmmoUI()
                elseif playerId then
                    local ui = CoopPlayerUi.Get(playerId)
                    if ui then ui:UpdateAmmoUI() end
                end
            end
        else
            HeroContext.RunWithHeroContext(mainHero, function()
                _UpdateAmmoUI()
                SecondPlayerUi.UpdateAmmoUI()
            end)
            for playerId, ui in pairs(CoopPlayerUi.Instances) do
                if playerId ~= 2 then
                    local hero = CoopPlayers.GetHero(playerId)
                    if hero then
                        HeroContext.RunWithHeroContext(hero, function() ui:UpdateAmmoUI() end)
                    end
                end
            end
        end
    end

    HookUtils.wrap("AddAmmoPresentation", function(baseFun, ...)
        local hero = CurrentRun.Hero
        local playerId = hero and CoopPlayers.GetPlayerByHero(hero)

        if playerId == nil or playerId == 1 then
            -- Main hero (or no co-op context) — vanilla.
            baseFun(...)
            return
        end

        if playerId == 2 then
            thread(SecondPlayerUi.UpdateAmmoUI)
            CreateAnimation({ Name = "QuickFlashRedSmall", DestinationId = hero.ObjectId, OffsetZ = -90 })
            if SecondPlayerUi.ScreenAnchors.AmmoIndicatorUI ~= nil then
                ModifyTextBox({ Id = SecondPlayerUi.ScreenAnchors.AmmoIndicatorUI, ColorTarget = Color.White, ColorDuration = 0.5, AutoSetDataProperties = false })
                thread(PulseText,
                    { ScreenAnchorReference = "AmmoIndicatorUI", ScaleTarget = 1.3, ScaleDuration = 0.125, HoldDuration = 0.1, PulseBias = 0.2 })
            end
        else
            -- P3 / P4: same visual treatment but addressed by Id rather than
            -- the SecondPlayerUi-specific ScreenAnchorReference name.
            local ui = CoopPlayerUi.Get(playerId)
            if ui then
                thread(function() ui:UpdateAmmoUI() end)
                CreateAnimation({ Name = "QuickFlashRedSmall", DestinationId = hero.ObjectId, OffsetZ = -90 })
                if ui.ScreenAnchors.AmmoIndicatorUI ~= nil then
                    ModifyTextBox({ Id = ui.ScreenAnchors.AmmoIndicatorUI, ColorTarget = Color.White, ColorDuration = 0.5, AutoSetDataProperties = false })
                    thread(PulseText, { Id = ui.ScreenAnchors.AmmoIndicatorUI, ScaleTarget = 1.3, ScaleDuration = 0.125, HoldDuration = 0.1, PulseBias = 0.2 })
                end
            end
        end
    end)

    -- Gun
    UIHooks.SimpleHookWithVisibilityCheck("ShowGunUI")

    local _HideGunUI = HideGunUI
    HideGunUI = function()
        local mainHero = CoopPlayers.GetMainHero()
        HeroContext.RunWithHeroContext(mainHero, _HideGunUI)
        local secondHero = CoopPlayers.GetHero(2)
        if secondHero then
            HeroContext.RunWithHeroContext(secondHero, SecondPlayerUi.HideGunUI)
        end
        for playerId, ui in pairs(CoopPlayerUi.Instances) do
            if playerId ~= 2 then
                local hero = CoopPlayers.GetHero(playerId)
                if hero then
                    HeroContext.RunWithHeroContext(hero, function() ui:HideGunUI() end)
                end
            end
        end
    end

    local _UpdateGunUI = UpdateGunUI
    UpdateGunUI = function()
        local mainHero = CoopPlayers.GetMainHero()
        local secondHero = CoopPlayers.GetHero(2)

        if HeroContext.IsHeroContextExplicit() then
            local currentHero = HeroContext.GetCurrentHeroContext()
            if mainHero == currentHero then
                HeroContext.RunWithHeroContext(mainHero, _UpdateGunUI)
            elseif currentHero == secondHero then
                HeroContext.RunWithHeroContext(currentHero, SecondPlayerUi.UpdateGunUI)
            else
                local playerId = CoopPlayers.GetPlayerByHero(currentHero)
                if playerId then
                    local ui = CoopPlayerUi.Get(playerId)
                    if ui then
                        HeroContext.RunWithHeroContext(currentHero, function() ui:UpdateGunUI() end)
                    end
                end
            end
        else
            HeroContext.RunWithHeroContext(mainHero, _UpdateGunUI)
            if secondHero then
                HeroContext.RunWithHeroContext(secondHero, SecondPlayerUi.UpdateGunUI)
            end
            for playerId, ui in pairs(CoopPlayerUi.Instances) do
                if playerId ~= 2 then
                    local hero = CoopPlayers.GetHero(playerId)
                    if hero then
                        HeroContext.RunWithHeroContext(hero, function() ui:UpdateGunUI() end)
                    end
                end
            end
        end
    end

    EquipPlayerWeaponPresentation = function(weaponData, args)
        wait(0.02)
        -- TODO: Fix hero here, maybe
        PlaySound({ Name = "/SFX/Menu Sounds/WeaponEquipChunk", Id = CurrentRun.Hero.ObjectId })
        if not args.SkipEquipLines then
            thread(PlayVoiceLines, weaponData.EquipVoiceLines, false)
        end

        local function hasHeroWeaponWithIcon(hero)
            for weaponName in pairs(hero.Weapons) do
                if WeaponData[weaponName].ActiveReloadTime then
                    return true
                end
            end
            return false
        end

        local hero = CoopPlayers.GetMainHero()
        local execFun = hasHeroWeaponWithIcon(hero) and ShowGunUI or _HideGunUI
        thread(function()
            HeroContext.RunWithHeroContext(hero, execFun)
        end)

        hero = CoopPlayers.GetHero(2)
        if hero then
            execFun = hasHeroWeaponWithIcon(hero) and SecondPlayerUi.ShowGunUI or SecondPlayerUi.HideGunUI
            thread(function()
                HeroContext.RunWithHeroContext(hero, execFun)
            end)
        end

        for playerId, ui in pairs(CoopPlayerUi.Instances) do
            if playerId ~= 2 then
                local p = CoopPlayers.GetHero(playerId)
                if p then
                    local show = hasHeroWeaponWithIcon(p)
                    thread(function()
                        HeroContext.RunWithHeroContext(p, function()
                            if show then ui:ShowGunUI() else ui:HideGunUI() end
                        end)
                    end)
                end
            end
        end
    end

    HookUtils.onPostFunction("DestroyGunUI", SecondPlayerUi.DestroyGunUI)

    -- Super meter (God aid)
    UIHooks.SimpleHookWithVisibilityCheck("ShowSuperMeter")
    UIHooks.SimpleHookWithVisibilityCheck("UpdateSuperMeterUIReal")
    UIHooks.CreateSimpleHook("DestroySuperMeter")
    UIHooks.CreateSimpleHook("HideSuperMeter")

    local _UpdateSuperUIComponent = UpdateSuperUIComponent
    UpdateSuperUIComponent = function(...)
        local mainHero = CoopPlayers.GetMainHero()
        local secondHero = CoopPlayers.GetHero(2)
        if ScreenAnchors.SuperPipBackingIds then
            HeroContext.RunWithHeroContext(mainHero, _UpdateSuperUIComponent, ...)
        end
        if secondHero and SecondPlayerUi.ScreenAnchors.SuperPipBackingIds then
            HeroContext.RunWithHeroContext(secondHero, SecondPlayerUi.UpdateSuperUIComponent, ...)
        end
    end

    -- Traits
    HookUtils.onPreFunction("ShowAdvancedTooltip", CombinedTraitsUI.ChangeHeroInTraitsMenu)
    HookUtils.onPreFunction("TraitUIActivateTrait", CombinedTraitsUI.ChangeHeroInTraitsMenu)
    HookUtils.onPreFunction("TraitUIDeactivateTrait", CombinedTraitsUI.ChangeHeroInTraitsMenu)
    HookUtils.onPreFunction("TraitUICreateComponent", CombinedTraitsUI.ChangeHeroInTraitsMenu)
    HookUtils.onPreFunction("TraitUIUpdateText", CombinedTraitsUI.ChangeHeroInTraitsMenu)
    HookUtils.onPreFunction("TraitUIRemove", CombinedTraitsUI.ChangeHeroInTraitsMenu)
    HookUtils.onPreFunction("TraitUICreateText", CombinedTraitsUI.ChangeHeroInTraitsMenu)
    HookUtils.onPreFunction("UpdateTraitNumber", CombinedTraitsUI.ChangeHeroInTraitsMenu)
    HookUtils.onPreFunction("UpdateAdditionalTraitHint", CombinedTraitsUI.ChangeHeroInTraitsMenu)
    HookUtils.onPreFunction("TraitUIActivateTraits", CombinedTraitsUI.ChangeHeroInTraitsMenu)

    UIHooks.SimpleCurrentTraitWrapper("CloseAdvancedTooltipScreen")
    UIHooks.SimpleCurrentTraitWrapper("PinTraitDetails")

    -- Etc
    local _PulseText = PulseText
    PulseText = function(args)
        if args.ScreenAnchorReference and HeroContext.GetCurrentHeroContext() == CoopPlayers.GetHero(2) then
            local idOnSecond = SecondPlayerUi.ScreenAnchors[args.ScreenAnchorReference]
            if idOnSecond then
                args.Id = idOnSecond
            end
        end

        _PulseText(args)
    end

    HookUtils.onPostFunction("ShowUseButton", function(objectId, useTarget)
        if HeroContext.GetDefaultHero() ~= HeroContext.GetCurrentHeroContext() then
            Move({ Id = ScreenAnchors.UsePrompts[objectId], DestinationId = ScreenAnchors.UsePrompts[objectId], OffsetY = -50 })
        end
    end)
end

return UIHooks