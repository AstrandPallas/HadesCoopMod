--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type CoopPlayers
local CoopPlayers = ModRequire "../CoopPlayers.lua"
---@type HeroContext
local HeroContext = ModRequire "../HeroContext.lua"

-- Vanilla heals only the player who interacted with the fountain. Heal every
-- other alive player with the same source, each using their own trait bonuses.
-- The vanilla handler still drives the spent animation, BlockExitUntilUsed
-- clearing, and FountainDamageBonus accumulation for the user.
OnUsed { "HealthFountain HealthFountainAsphodel HealthFountainElysium HealthFountainStyx",
    function(triggerArgs)
        local used = triggerArgs.AttachedTable
        if used == nil or used.HealFraction == nil then
            return
        end

        local userId = triggerArgs.UserId
        for _, hero in CoopPlayers.PlayersIterator() do
            if hero and not hero.IsDead and hero.ObjectId and hero.ObjectId ~= userId then
                HeroContext.RunWithHeroContext(hero, function()
                    local healFraction = used.HealFraction + GetTotalHeroTraitValue("FountainHealFractionBonus")
                    local healFractionOverride = GetTotalHeroTraitValue("FountainHealFractionOverride")
                    if healFractionOverride > 0 then
                        healFraction = healFractionOverride
                    end
                    healFraction = healFraction * CalculateHealingMultiplier()
                    Heal(hero, { HealFraction = healFraction, SourceName = "HealthFountain" })
                end)
            end
        end
    end
}
