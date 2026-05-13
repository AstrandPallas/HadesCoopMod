--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type HookUtils
local HookUtils = ModRequire "HookUtils.lua"
---@type CoopPlayers
local CoopPlayers = ModRequire "CoopPlayers.lua"
---@type SecondPlayerUi
local SecondPlayerUi = ModRequire "SecondPlayerUI.lua"
---@type CoopPlayerUi
local CoopPlayerUi = ModRequire "CoopPlayerUi.lua"
---@type CoopPlayerLabels
local CoopPlayerLabels = ModRequire "CoopPlayerLabels.lua"
---@type PlayerVisibilityHelper
local PlayerVisibilityHelper = ModRequire "PlayerVisibilityHelper.lua"
---@type HeroContext
local HeroContext = ModRequire "HeroContext.lua"
---@type CoopCamera
local CoopCamera = ModRequire "CoopCamera.lua"
---@type FreezeHooks
local FreezeHooks = ModRequire "hooks/FreezeHooks.lua"
---@type RunHooks
local RunHooks = ModRequire "hooks/RunHooks.lua"
---@type MenuHooks
local MenuHooks = ModRequire "hooks/MenuHooks.lua"
---@type SaveHooks
local SaveHooks = ModRequire "hooks/SaveHooks.lua"
---@type EnemyAiHooks
local EnemyAiHooks = ModRequire "hooks/EnemyAiHooks.lua"
---@type LootHooks
local LootHooks = ModRequire "hooks/LootHooks.lua"
---@type UIHooks
local UIHooks = ModRequire "hooks/UIHooks.lua"
---@type VulnerabilityHooks
local VulnerabilityHooks = ModRequire "hooks/VulnerabilityHooks.lua"
---@type ResourceLoadingHooks
local ResourceLoadingHooks = ModRequire "hooks/ResourceLoadingHooks.lua"
---@type TroveHooks
local TroveHooks = ModRequire "hooks/TroveHooks.lua"
---@type FoodHooks
local FoodHooks = ModRequire "hooks/FoodHooks.lua"
---@type NPCRewardHooks
local NPCRewardHooks = ModRequire "hooks/NPCRewardHooks.lua"
---@type ShopDiagnostic
local ShopDiagnostic = ModRequire "hooks/ShopDiagnostic.lua"  -- TEMP diagnostic; remove after Charon shop bug resolved
---@type ILootDelivery
local LootDelivery = ModRequire "loot/LootInterface.lua"

ModRequire "hooks/DamageHooks.lua"
ModRequire "hooks/UseHooks.lua"
ModRequire "hooks/ControlHooks.lua"
ModRequire "hooks/WeaponHooks.lua"
ModRequire "hooks/FountainHooks.lua"

local hooksInited = false
local function TryInstalBasicHooks()
    if hooksInited then
        return
    end

    hooksInited = true

    -- Fixes crash on loading when the game truing add last stand to a second player
    ScreenAnchors = {}

    EnemyAiHooks.InitHooks()
    SaveHooks.InitHooks()
    CoopCamera.InitHooks()
    FreezeHooks.InitHooks()
    RunHooks.InitHooks()
    MenuHooks.InitHooks()
    --PactDoorFix.InitHooks()
    UIHooks.InitHooks()
    CoopPlayers.CoopInit()
    LootHooks.InitHooks()
    NPCRewardHooks.InitHooks()
    ShopDiagnostic.InitHooks()  -- TEMP diagnostic; remove after Charon shop bug resolved
    VulnerabilityHooks.InitHooks()
    ResourceLoadingHooks.InitHooks()
    TroveHooks.InitHooks()
    FoodHooks.InitHooks()
    LootDelivery.InitHooks()
    CoopPlayerLabels.InitHooks()
end

OnPreThingCreation
{
    TryInstalBasicHooks
}

OnAnyLoad {
    function(triggerArgs)
        local mapName = triggerArgs.name

        if mapName == "RoomPreRun" then
            HookUtils.onPostFunctionOnce("DeathAreaRoomTransition", function()
                if not HeroContext.GetDefaultHero() then
                    HeroContext.InitRunHook()
                end
                CoopPlayers.SetMainHero(HeroContext.GetDefaultHero())
                CoopPlayers.UpdateMainHero()

                -- P1's outline isn't applied by InitCoopUnit (that only runs
                -- for additional slots). Wire P1 through the same marker
                -- helper as P2-P4 so all four players share the same outline
                -- system and config-driven colors.
                local mainHero = CoopPlayers.GetMainHero()
                if mainHero and mainHero.ObjectId then
                    PlayerVisibilityHelper.AddPlayerMarkers(1, mainHero.ObjectId)
                end

                -- Spawn a hero unit and UI for every co-op slot that exists in
                -- the engine. CoopInit/InitCoopPlayer already allocated those
                -- based on the menu's captured controller count, so this loop
                -- naturally scales from 2 to 4. P2 keeps its bottom-right UI
                -- via the SecondPlayerUi shim (constructed lazily on first
                -- access); P3+ get the corner layouts from CoopPlayerUi.
                -- P2 stays at vanilla bottom-right (handled by SecondPlayerUI's
                -- LayoutForCorner("BR")). P3/P4 fill the gap between P1's
                -- vanilla bottom-left HUD and P2's bottom-right HUD, evenly
                -- spaced. On-screen left-to-right: P1, P3, P4, P2.
                for playerId = 2, CoopPlayers.GetPlayersCount() do
                    CoopPlayers.InitCoopUnit(playerId)
                    if playerId >= 3 and not CoopPlayerUi.Get(playerId) then
                        local ui = CoopPlayerUi.Create(playerId, CoopPlayerUi.LayoutForBottomSlot(playerId))
                        -- Vanilla ShowHealthUI / ShowAmmoUI / ShowSuperMeter
                        -- fire once early in the run, before this instance
                        -- exists, so the UIHooks dispatchers miss P3+. Show
                        -- them now explicitly, under the slot's hero context
                        -- so trait lookups inside the Show* methods resolve
                        -- against the right hero.
                        local hero = CoopPlayers.GetHero(playerId)
                        if hero then
                            HeroContext.RunWithHeroContext(hero, function()
                                ui:ShowHealthUI()
                                ui:ShowAmmoUI()
                                ui:ShowSuperMeter()
                                if hero.Weapons and hero.Weapons.GunWeapon then
                                    ui:ShowGunUI()
                                end
                            end)
                        end
                    end
                end
                CoopPlayerUi.RefreshAll()

                -- Spawn floating "P#" labels above each player's character.
                -- ShowFor itself no-ops in solo play, so this is safe to call
                -- unconditionally. RefreshAll on subsequent room loads re-spawns
                -- labels that the engine destroyed across transitions.
                CoopPlayerLabels.RefreshAll()
            end)
        end
    end
}

OnMenuOpened {
    "MainMenuScreen",
    function(triggerArgs)
        SetConfigOption { Name = "AllowControlHotSwap", Value = true }
        EnableGamepadInput()
        EnableKeyboardMenuInput()
    end
}
