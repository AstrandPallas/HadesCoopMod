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
    end)

    local _AddLastStand = AddLastStand
    AddLastStand = function(args)
        local isSecondPlayer = CoopPlayers.GetMainHero() ~= HeroContext.GetCurrentHeroContext()
        local pipsBackup = ScreenAnchors.LifePipIds
        local _CreateScreenObstacle = CreateScreenObstacle
        if isSecondPlayer then
            ScreenAnchors.LifePipIds = SecondPlayerUi.ScreenAnchors.LifePipIds
            CreateScreenObstacle = function(args)
                args.X = (ScreenWidth - 80) - (args.X - 70)
            end
        end

        _AddLastStand(args)

        if isSecondPlayer then
            ScreenAnchors.LifePipIds = pipsBackup
            CreateScreenObstacle = _CreateScreenObstacle
        end
    end

    -- Ammo (red crystrals)
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
        if CurrentRun.Hero == CoopPlayers.GetHero(2) then
            thread(SecondPlayerUi.UpdateAmmoUI)

            CreateAnimation({ Name = "QuickFlashRedSmall", DestinationId = CurrentRun.Hero.ObjectId, OffsetZ = -90 })

            if SecondPlayerUi.ScreenAnchors.AmmoIndicatorUI ~= nil then
                ModifyTextBox({ Id = SecondPlayerUi.ScreenAnchors.AmmoIndicatorUI, ColorTarget = Color.White, ColorDuration = 0.5, AutoSetDataProperties = false, })
                thread(PulseText,
                    { ScreenAnchorReference = "AmmoIndicatorUI", ScaleTarget = 1.3, ScaleDuration = 0.125, HoldDuration = 0.1, PulseBias = 0.2 })
            end
        else
            baseFun(...);
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