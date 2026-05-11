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
    VulnerabilityHooks.InitHooks()
    ResourceLoadingHooks.InitHooks()
    TroveHooks.InitHooks()
    FoodHooks.InitHooks()
    LootDelivery.InitHooks()
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

                -- Spawn a hero unit and UI for every co-op slot that exists in
                -- the engine. CoopInit/InitCoopPlayer already allocated those
                -- based on the menu's captured controller count, so this loop
                -- naturally scales from 2 to 4. P2 keeps its bottom-right UI
                -- via the SecondPlayerUi shim (constructed lazily on first
                -- access); P3+ get the corner layouts from CoopPlayerUi.
                local cornerForSlot = { [3] = "TL", [4] = "TR" }
                for playerId = 2, CoopPlayers.GetPlayersCount() do
                    CoopPlayers.InitCoopUnit(playerId)
                    if playerId >= 3 and not CoopPlayerUi.Get(playerId) then
                        CoopPlayerUi.Create(playerId, CoopPlayerUi.LayoutForCorner(cornerForSlot[playerId]))
                    end
                end
                CoopPlayerUi.RefreshAll()
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
