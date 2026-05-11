--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type CoopPlayers
local CoopPlayers = ModRequire "../CoopPlayers.lua"
---@type HookUtils
local HookUtils = ModRequire "../HookUtils.lua"

---@class TroveHooks
local TroveHooks = {}

function TroveHooks.InitHooks()
    HookUtils.onPostFunction("HandleChallengeLoot", TroveHooks.OnLootHandled)
end

-- Post-hook on the engine's trove reward dispenser. For Health-type Infernal
-- Troves the vanilla path heals only CurrentRun.Hero; mirror the same heal to
-- every other alive player so the reward benefits the whole co-op party.
---@param challengeSwitch table?
---@param challengeEncounter table?
function TroveHooks.OnLootHandled(challengeSwitch, challengeEncounter)
    if challengeSwitch == nil or challengeEncounter == nil then
        return
    end
    if challengeSwitch.RewardType ~= "Health" then
        return
    end
    -- Vanilla plays the "empty" voice line and skips healing when the user's
    -- healing multiplier is zero; do the same so we don't out-heal vanilla.
    if CalculateHealingMultiplier() == 0 then
        return
    end

    local healAmount = challengeSwitch.CurrentValue
    if healAmount == nil or healAmount <= 0 then
        return
    end

    local userId = CurrentRun.Hero and CurrentRun.Hero.ObjectId
    for _, hero in CoopPlayers.PlayersIterator() do
        if hero and not hero.IsDead and hero.ObjectId and hero.ObjectId ~= userId then
            Heal(hero, { HealAmount = healAmount, Name = "HealthChallengeSwitch" })
        end
    end
end

return TroveHooks
