--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type CoopPlayers
local CoopPlayers = ModRequire "../CoopPlayers.lua"
---@type HookUtils
local HookUtils = ModRequire "../HookUtils.lua"
---@type HeroContext
local HeroContext = ModRequire "../HeroContext.lua"

---@class FoodHooks
local FoodHooks = {}

function FoodHooks.InitHooks()
    HookUtils.onPostFunction("PurchaseConsumableItem", FoodHooks.OnConsumableUsed)
end

-- Post-hook on PurchaseConsumableItem. Vanilla heals only CurrentRun.Hero from
-- food consumables (Centaur Hearts, room Health drops, breakable-drop hearts,
-- pomegranates, etc.). Mirror the same heal to every other alive player, each
-- computing CalculateHealingMultiplier in its own HeroContext so per-player
-- traits (FountainHealFractionBonus, MaxHealthMultiplier, etc.) still apply.
---@param currentRun table?
---@param consumableItem table?
---@param args table?
function FoodHooks.OnConsumableUsed(currentRun, consumableItem, args)
    if consumableItem == nil then
        return
    end
    if consumableItem.HealFraction == nil and consumableItem.HealFixed == nil then
        return
    end

    local userId = CurrentRun.Hero and CurrentRun.Hero.ObjectId
    local sourceName = consumableItem.Name or "Item"

    for _, hero in CoopPlayers.PlayersIterator() do
        if hero and not hero.IsDead and hero.ObjectId and hero.ObjectId ~= userId then
            HeroContext.RunWithHeroContext(hero, function()
                if consumableItem.HealFraction ~= nil then
                    local frac = consumableItem.HealFraction * CalculateHealingMultiplier()
                    Heal(hero, { HealFraction = frac, SourceName = sourceName })
                end
                if consumableItem.HealFixed ~= nil then
                    local amount = consumableItem.HealFixed * CalculateHealingMultiplier()
                    amount = round(amount * GetTotalHeroTraitValue("MaxHealthMultiplier", { IsMultiplier = true }))
                    Heal(hero, { HealAmount = amount, SourceName = sourceName })
                end
            end)
        end
    end
end

return FoodHooks
