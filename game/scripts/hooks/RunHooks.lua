--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type CoopPlayers
local CoopPlayers = ModRequire "../CoopPlayers.lua"
---@type HeroContext
local HeroContext = ModRequire "../HeroContext.lua"
---@type HookUtils
local HookUtils = ModRequire "../HookUtils.lua"
---@type CoopCamera
local CoopCamera = ModRequire "../CoopCamera.lua"
---@type EnemyAiHooks
local EnemyAiHooks = ModRequire "EnemyAiHooks.lua"
---@type LootHooks
local LootHooks = ModRequire "LootHooks.lua"
---@type ILootDelivery
local LootDelivery = ModRequire "../loot/LootInterface.lua"
---@type SecondPlayerUi
local SecondPlayerUi = ModRequire "../SecondPlayerUI.lua"
---@type RunEx
local RunEx = ModRequire "../RunEx.lua"
---@type PlayerVisibilityHelper
local PlayerVisibilityHelper = ModRequire "../PlayerVisibilityHelper.lua"
---@type CoopPlayerLabels
local CoopPlayerLabels = ModRequire "../CoopPlayerLabels.lua"
---@type CoopPlayerUi
local CoopPlayerUi = ModRequire "../CoopPlayerUi.lua"
---@type HeroEx
local HeroEx = ModRequire "../HeroEx.lua"
---@type CoopControl
local CoopControl = ModRequire "../CoopControl.lua"
---@type GameFlags
local GameFlags = ModRequire "../GameFlags.lua"

---@class RunHooks
local RunHooks = {}

function RunHooks.InitHooks()
    HookUtils.onPreFunction("LeaveRoom", RunHooks.LeaveRoomHook)
    HookUtils.onPreFunction("DeathAreaRoomTransition", RunHooks.DeathAreaRoomTransitionPreHook)
    HookUtils.wrap("EndEarlyAccessPresentation", RunHooks.EndEarlyAccessPresentationWrapHook)
    HookUtils.wrap("StartNewRun", RunHooks.StartNewRunWrapHook)
    HookUtils.wrap("StartRoom", RunHooks.StartRoomWrapHook)
    HookUtils.wrap("KillHero", RunHooks.KillHeroHook)
    HookUtils.wrap("CheckRoomExitsReady", RunHooks.CheckRoomExitsReadyHook)
    HookUtils.wrap("SetupHeroObject", RunHooks.SetupHeroObjectHook)
    HookUtils.wrap("CheckDistanceTrigger", RunHooks.CheckDistanceTriggerWrapHook)
    HookUtils.wrap("EndEncounterEffects", RunHooks.EndEncounterEffectsWrapHook)
    HookUtils.wrap("StartEncounterEffects", RunHooks.StartEncounterEffectsWrapHook)
    HookUtils.wrap("RestoreUnlockRoomExits", RunHooks.RestoreUnlockRoomExitsWrapHook)
    HookUtils.onPostFunction("StartNewGame", RunHooks.StartNewGameHook)
    HookUtils.onPostFunction("CheckForAllEnemiesDead", RunHooks.CheckForAllEnemiesDeadPostHook)
end

---@private
function RunHooks.DeathAreaRoomTransitionPreHook()
    if not HeroContext.GetDefaultHero() then
        HeroContext.InitRunHook()
    end
end

---@private
function RunHooks.CheckDistanceTriggerWrapHook(CheckDistanceTriggerFun, ...)
    -- TODO
    -- This hack fixes crashes like #21 when the player 1 is dead.
    -- The crash is caused by invalid reference to the second player.
    -- The game cannot find a player unit and triggers NotifyWithinDistance instantly without result
    HeroContext.RunWithHeroContext(CoopPlayers.GetMainHero(), CheckDistanceTriggerFun, ...)
end

---@private
function RunHooks.SetupHeroObjectHook(SetupHeroObjectFun, ...)
    local mainHero = CoopPlayers.GetMainHero()

    HeroContext.RunWithHeroContext(mainHero, SetupHeroObjectFun, ...)
    -- Fix unit -> hero table here
    CoopPlayers.UpdateMainHero()

    PlayerVisibilityHelper.AddPlayerMarkers(1, mainHero.ObjectId)

    if mainHero.IsDead and not RunEx.IsRunEnded() then
        HeroEx.HideHero(mainHero)
    end
end

---@private
function RunHooks.StartRoomWrapHook(StartRoomFun, run, currentRoom)
    -- Fixes mouse disappearing after level transiction
    CoopControl.ResetAllPlayers("Current")

    -- Initialization after save loading when encounter is active
    if not HeroContext.GetDefaultHero() then
        HeroContext.InitRunHook()
        CoopPlayers.SetMainHero(HeroContext.GetDefaultHero())
    end

    if currentRoom.RoomSetName == "Surface" then
        RunHooks.HandleSurfaceRoom(StartRoomFun, run, currentRoom)
    else
        RunHooks.HandleGenericRoom(StartRoomFun, run, currentRoom)
    end
end

---@private
function RunHooks.HandleGenericRoom(StartRoomFun, run, currentRoom)
    local overrides = currentRoom.EncounterSpecificDataOverwrites and
    currentRoom.EncounterSpecificDataOverwrites[currentRoom.Encounter.Name]

    local prevRoom = GetPreviousRoom(CurrentRun)
    local roomEntranceFunctionName = (overrides and overrides.EntranceFunctionName)
        or currentRoom.EntranceFunctionName
        or "RoomEntranceStandard"

    if prevRoom ~= nil and prevRoom.NextRoomEntranceFunctionName ~= nil then
        roomEntranceFunctionName = prevRoom.NextRoomEntranceFunctionName
    end
    local args = currentRoom.EntranceFunctionArgs

    HookUtils.onPostFunctionOnce(roomEntranceFunctionName, function()
        local entranceFunction = _G[roomEntranceFunctionName]
        --entranceFunction(currentRun, currentRoom, args)
        -- TODO ADD ENTER Animation

        -- Post-boss revive: if the room we just left was any boss-tier
        -- encounter (biome boss = Furies / Hydra / Theseus, or any
        -- mini-boss room flagged IsMiniBossRoom in RoomData), revive
        -- every dead hero to full HP before the InitCoopUnit loop runs.
        -- The loop only spawns world units for not-dead heroes, so
        -- flipping IsDead first is what makes the revived players
        -- physically appear in the next room.
        --
        -- Capture an "anchor" hero BEFORE flipping IsDead so the post-
        -- positioning teleport has a valid living target. Can't just
        -- use P1 — if P1 was the one who died (and the run is carrying
        -- on with P3 as the active hero), P1's unit doesn't exist.
        -- Any pre-revive alive hero is a safe teleport target since
        -- they walked through the door themselves.
        local roomHistory = CurrentRun and CurrentRun.RoomHistory
        local prevRoom = roomHistory and roomHistory[#roomHistory]
        local revivedPlayerIds = {}
        local anchorHero = nil
        if RunEx.IsAnyBossRoom(prevRoom) then
            anchorHero = CoopPlayers.GetFirstAliveHero()
            for playerId, hero in CoopPlayers.PlayersIterator() do
                if hero and hero.IsDead then
                    hero.IsDead = false
                    if hero.MaxHealth and hero.MaxHealth > 0 then
                        hero.Health = hero.MaxHealth
                    else
                        hero.MaxHealth = 50
                        hero.Health = 50
                    end
                    table.insert(revivedPlayerIds, playerId)
                end
            end
        end

        for playerId = 2, CoopPlayers.GetPlayersCount() do
            local hero = CoopPlayers.GetHero(playerId)
            if not hero or (hero and not hero.IsDead) then
                CoopCamera.ForceFocus(true)
                CoopPlayers.InitCoopUnit(playerId)
            end
        end
        SecondPlayerUi.Refresh()

        CoopPlayers.UpdateMainHero()

        -- Re-spawn floating P# labels now that each player's hero.ObjectId
        -- points at the new room's freshly-spawned unit. Our StartRoom
        -- hook fires earlier than this and would attach to the previous
        -- room's destroyed unit IDs (leaving the labels as invisible
        -- orphans for P2-P4), so refresh here too.
        CoopPlayerLabels.RefreshAll()

        local mainHero = CoopPlayers.GetMainHero()
        local isMainPlayerDead = mainHero and mainHero.IsDead
        if not isMainPlayerDead then
            -- For some strange reason RoomEntrancePortal keeps the main player invisible
            SetAlpha{ Id = mainHero.ObjectId, Fraction = 1.0, Duration = 1.0 }
        end

        if currentRoom.HeroEndPoint then
            for playerId = 2, CoopPlayers.GetPlayersCount() do
                local hero = CoopPlayers.GetHero(playerId)
                if not hero.IsDead then
                    Teleport({ Id = hero.ObjectId, DestinationId = currentRoom.HeroEndPoint })
                    if isMainPlayerDead then
                        RemoveInputBlock{ PlayerIndex = playerId, Name = "MoveHeroToRoomPosition" }
                    end
                end
            end
        end

        -- Revived heroes need extra handholding the regular room-entry
        -- flow doesn't cover:
        --   1. CoopCreatePlayerUnit places the new world unit at the
        --      slot's last known position — which was wherever the hero
        --      died in the previous room. Teleport them to anchorHero
        --      (any pre-revive alive hero — captured above before we
        --      flipped IsDead so we don't accidentally teleport a
        --      revived hero to themselves).
        --   2. The HUD dispatcher (UIHooks.ShowHealthUI) already ran
        --      with these heroes flagged IsDead, so their bar/ammo/
        --      super UI was skipped. Call the per-instance Show*
        --      methods now under each revived hero's context to fill
        --      in the placeholder text and re-create their HUD elements.
        if #revivedPlayerIds > 0 and anchorHero and anchorHero.ObjectId then
            for _, playerId in ipairs(revivedPlayerIds) do
                local hero = CoopPlayers.GetHero(playerId)
                if hero and hero.ObjectId then
                    -- Teleport synchronously — needs to happen before the
                    -- player sees the revived hero anywhere.
                    Teleport({ Id = hero.ObjectId, DestinationId = anchorHero.ObjectId })

                    -- Defer the HUD revive in a thread. The engine's
                    -- weapon-equip path is partially threaded — by the
                    -- time the synchronous part of InitCoopUnit returns,
                    -- GetWeaponProperty { WeaponName = "RangedWeapon" }
                    -- still returns nil for a few ticks. Show*UI's built-in
                    -- threaded Update fires next tick, which is too early.
                    -- Poll for the cast ammo to become queryable, then run
                    -- the full destroy+show cycle so the text-box rebinds
                    -- its LuaValue against real data.
                    thread(function()
                        local maxWait = 3.0
                        local elapsed = 0
                        while elapsed < maxWait do
                            local ammo = GetWeaponProperty {
                                Id = hero.ObjectId,
                                WeaponName = "RangedWeapon",
                                Property = "Ammo",
                            }
                            if ammo ~= nil then break end
                            wait(0.05)
                            elapsed = elapsed + 0.05
                        end

                        if elapsed >= maxWait then
                            -- Engine equip never completed within the budget.
                            -- Force the equip ourselves so the HUD has data
                            -- to bind against and the player can actually use
                            -- their cast in this room.
                            EquipWeapon { Name = "RangedWeapon", DestinationId = hero.ObjectId }
                        end

                        HeroContext.RunWithHeroContext(hero, function()
                            -- Destroy before Show: the HUD obstacles often
                            -- survive death (HideAmmoUI's dispatcher doesn't
                            -- cover P3+). With the obstacle intact, Show*UI
                            -- early-returns and the placeholder LuaValue
                            -- persists. Destroying first forces the full
                            -- create path.
                            if playerId == 2 then
                                SecondPlayerUi.DestroyHealthUI()
                                SecondPlayerUi.ShowHealthUI()
                                SecondPlayerUi.DestroyAmmoUI()
                                SecondPlayerUi.ShowAmmoUI()
                                SecondPlayerUi.ShowSuperMeter()
                                if hero.Weapons and hero.Weapons.GunWeapon then
                                    SecondPlayerUi.DestroyGunUI()
                                    SecondPlayerUi.ShowGunUI()
                                end
                            else
                                local ui = CoopPlayerUi.Get(playerId)
                                if ui then
                                    ui:DestroyHealthUI()
                                    ui:ShowHealthUI()
                                    ui:DestroyAmmoUI()
                                    ui:ShowAmmoUI()
                                    ui:ShowSuperMeter()
                                    if hero.Weapons and hero.Weapons.GunWeapon then
                                        ui:DestroyGunUI()
                                        ui:ShowGunUI()
                                    end
                                end
                            end
                        end)
                    end)
                end
            end
        end
    end)

    HookUtils.onPostFunctionOnce("SwitchActiveUnit", function()
        SwitchActiveUnit { PlayerIndex = 1, Id = CoopPlayers.GetMainHero().ObjectId }
    end)

    if RunEx.IsRunEnded() then
        HeroContext.RunWithHeroContext(CoopPlayers.GetMainHero(), StartRoomFun, run, currentRoom)
    else
        local hero = CoopPlayers.GetAliveHeroes()[1] or CoopPlayers.GetMainHero()
        HeroContext.RunWithHeroContext(hero, StartRoomFun, run, currentRoom)
    end
end

---@private
function RunHooks.HandleSurfaceRoom(StartRoomFun, run, currentRoom)
    local mainHero = CoopPlayers.GetMainHero()
    mainHero.IsDead = false
    HeroContext.SetDefaultHero(mainHero)

    if mainHero.Health == 0 then
        mainHero.Health = mainHero.MaxHealth
    end

    for playerId, hero in CoopPlayers.AdditionalHeroesIterator() do
        hero.IsDead = true
    end

    HeroContext.RunWithHeroContext(mainHero, StartRoomFun, run, currentRoom)
end

---@private
function RunHooks.StartNewRunWrapHook(StartNewRunFun, prevRun, args)
    local isNewGame = RunEx.WasTheFirstRunStarted()
    local newRun = StartNewRunFun(prevRun, args)
    HeroContext.InitRunHook()
    LootHooks.InitRunHooks()
    LootDelivery.Reset(CoopPlayers.GetPlayersCount())
    CoopPlayers.SetMainHero(HeroContext.GetDefaultHero())

    if not isNewGame then
        CoopPlayers.RecreateAllAdditionalPlayers()
    end

    return newRun
end

--- Bypass IsAlive check with this hook
---@private
function RunHooks.CheckRoomExitsReadyHook(baseFun, ...)
    local aliveHero = CoopPlayers.GetAliveHeroes()[1]
    if aliveHero then
        local result = false
        HeroContext.RunWithHeroContext(aliveHero, function(...)
            result = baseFun(...)
        end, ...)

        return result
    else
        return baseFun(...)
    end
end

---@private
function RunHooks.EndEarlyAccessPresentationWrapHook(baseFun)
    local mainHero = CoopPlayers.GetMainHero()
    mainHero.IsDead = false
    for playerId, hero in CoopPlayers.AdditionalHeroesIterator() do
        hero.IsDead = true
    end
    HeroContext.RunWithHeroContext(mainHero, baseFun)
end

---@private
function RunHooks.KillHeroHook(baseFun, ...)
    CurrentRun.Hero.IsDead = true
    if not CoopPlayers.HasAlivePlayers() then
        -- Handle death for player 1 only
        local mainHero = CoopPlayers.GetMainHero()
        HeroEx.ShowHero(mainHero, CurrentRun.Hero.ObjectId)
        RemoveOutline({ Id = mainHero.ObjectId })
        HeroContext.RunWithHeroContext(mainHero, baseFun, ...)
        CoopPlayers.OnAllPlayersDead()
        return
    end
    local aliveHero = CoopPlayers.GetAliveHeroes()[1]

    if CurrentRun.Hero == CoopPlayers.GetMainHero() then
        HeroEx.HideHero(CurrentRun.Hero)

        HeroContext.SetDefaultHero(aliveHero)
    else
        local playerId = CoopPlayers.GetPlayerByHero(CurrentRun.Hero)
        if playerId then
            CoopRemovePlayerUnit(playerId)
        end
    end
    -- Unstuck AI
    HeroContext.RunWithHeroContext(aliveHero, EnemyAiHooks.RefreshAI)
end

---@private
function RunHooks.LeaveRoomHook(currentRun, door)
    -- Disables an extit door after use
    door.ReadyToUse = false

    if not GameFlags.LeaveRoomHandlesOnce then
        return
    end

    -- Updates traits and health
    local nextRoom = door.Room
    local currentHero = CurrentRun.Hero
    for _, hero in CoopPlayers.PlayersIterator() do
        if hero ~= currentHero and not hero.IsDead then
            ClearEffect({ Id = hero.ObjectId, All = true, BlockAll = true, })
            StopCurrentStatusAnimation(hero)
            hero.BlockStatusAnimations = true

            if not nextRoom.BlockDoorHealFromPrevious then
                HeroContext.RunWithHeroContext(hero, CheckDoorHealTrait, currentRun)
            end

            local removedTraits = {}
            for _, trait in pairs(hero.Traits) do
                if trait.RemainingUses ~= nil and trait.UsesAsRooms ~= nil and trait.UsesAsRooms then
                    UseTraitData(hero, trait)
                    if trait.RemainingUses ~= nil and trait.RemainingUses <= 0 then
                        table.insert(removedTraits, trait)
                    end
                end
            end
            for _, trait in pairs(removedTraits) do
                RemoveTraitData(hero, trait)
            end
        end
    end
end

-- Clrears poison effects
---@private
function RunHooks.CheckForAllEnemiesDeadPostHook()
    for playerID = 2, CoopPlayers.GetPlayersCount() do
        local hero = CoopPlayers.GetHero(playerID)
        if hero and not hero.IsDead and hero.ObjectId then
            ClearEffect({ Id = hero.ObjectId, Name = "StyxPoison" })
            ClearEffect({ Id = hero.ObjectId, Name = "DamageOverTime" })
        end
    end
end

---@private
function RunHooks.StartNewGameHook()
    if not HeroContext.GetDefaultHero() then
        HeroContext.InitRunHook()
    end
    CoopPlayers.SetMainHero(HeroContext.GetDefaultHero())
end

---@private
function RunHooks.RestoreUnlockRoomExitsWrapHook(baseFun, run, room)
    local mainHero = CurrentRun.Hero
    local isMainPlayerShoudlBeHidden = not RunEx.IsRunEnded() and mainHero.IsDead
    local activeHero = isMainPlayerShoudlBeHidden and CoopPlayers.GetFirstAliveHero() or mainHero

    CoopPlayers.SetMainHero(mainHero)

    if not HeroContext.GetDefaultHero() then
        HeroContext.InitRunHook()
    end

    if isMainPlayerShoudlBeHidden then
        HeroContext.SetDefaultHero(activeHero)
    end

    HeroContext.RunWithHeroContext(mainHero, baseFun, run, room)

    if isMainPlayerShoudlBeHidden then
        HeroEx.HideHero(mainHero)
        CoopCamera.ForceFocus(true)
    end

    local spawnPoint = CurrentRun.CurrentRoom.HeroEndPoint or CoopPlayers.GetMainHero().ObjectId
    for playerId = 2, CoopPlayers.GetPlayersCount() do
        CoopPlayers.RestoreSavedHero(playerId)
        local hero = CoopPlayers.GetHero(playerId)
        if hero and not hero.IsDead then
            Teleport { Id = hero.ObjectId, DestinationId = spawnPoint }
        end
    end

    SecondPlayerUi.Refresh()
end

---@private
function RunHooks.EndEncounterEffectsWrapHook(baseFun, currentRun, currentRoom, currentEncounter)
    for _, hero in ipairs(CoopPlayers.GetAliveHeroes()) do
        HeroContext.RunWithHeroContextAwait(hero, baseFun, currentRun, currentRoom, currentEncounter)
        currentRoom.CodexUpdates = nil
        currentRoom.PendingCodexUpdate = nil
    end
end

---@private
function RunHooks.StartEncounterEffectsWrapHook(baseFun, run)
    for _, hero in ipairs(CoopPlayers.GetAliveHeroes()) do
        HeroContext.RunWithHeroContextAwait(hero, baseFun, run)
    end
end

return RunHooks
