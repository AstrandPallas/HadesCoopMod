--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--
-- Duplicate per-player NPC rewards (Eurydice / Sisyphus / Patroclus) across every alive player.
--
-- Shared-pool rewards (SisyphusMoney, SisyphusMetaPoints) are intentionally NOT wrapped:
-- those credit global buckets that already benefit every player, so duplicating
-- them would over-credit the bucket. See:
--   docs/superpowers/specs/2026-05-11-multi-player-npc-rewards-design.md
--

---@type HookUtils
local HookUtils = ModRequire "../HookUtils.lua"
---@type CoopPlayers
local CoopPlayers = ModRequire "../CoopPlayers.lua"
---@type HeroContext
local HeroContext = ModRequire "../HeroContext.lua"

---@class NPCRewardHooks
local NPCRewardHooks = {}

---@private
---Run baseFn once per alive player under that player's HeroContext.
---Vanilla reward functions operate on CurrentRun.Hero, which the HeroContext
---swap rebinds to each player in turn.
local function applyToAllAlivePlayers(baseFn, ...)
    for _, hero in CoopPlayers.PlayersIterator() do
        if hero and not hero.IsDead and hero.ObjectId then
            HeroContext.RunWithHeroContext(hero, baseFn, ...)
        end
    end
end

function NPCRewardHooks.InitHooks()
    -- Per-player rewards: duplicate to every alive player.
    HookUtils.wrap("EurydiceBuff", function(baseFn, ...)
        applyToAllAlivePlayers(baseFn, ...)
    end)
    HookUtils.wrap("PatroclusBuff", function(baseFn, ...)
        applyToAllAlivePlayers(baseFn, ...)
    end)
    HookUtils.wrap("SisyphusHealing", function(baseFn, ...)
        applyToAllAlivePlayers(baseFn, ...)
    end)

    -- SisyphusMoney and SisyphusMetaPoints are deliberately NOT wrapped — they
    -- credit shared pools that already benefit every player.
end

return NPCRewardHooks
