--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type CoopPlayers
local CoopPlayers = ModRequire "../CoopPlayers.lua"
---@type HeroContext
local HeroContext = ModRequire "../HeroContext.lua"
---@type SecondPlayerUi
local SecondPlayerUi = ModRequire "../SecondPlayerUI.lua"
---@type CoopPlayerUi
local CoopPlayerUi = ModRequire "../CoopPlayerUi.lua"
---@type HeroContextWrapper
local HeroContextWrapper = ModRequire "../HeroContextWrapper.lua"
---@type HookUtils
local HookUtils = ModRequire "../HookUtils.lua"
---@type CoopModConfig
local Config = ModRequire "../config.lua"
---@type PerfCounters
local PerfCounters = ModRequire "../PerfCounters.lua"

local _OnHit = OnHit
function OnHit(args)
    -- Only one usage
    local fun = args[1]
    _OnHit { function(triggerArgs)
        PerfCounters.Tick("OnHit")
        local attacker = triggerArgs.AttackerTable
        local victim = triggerArgs.TriggeredByTable

        local isAttackerPlayer = attacker and CoopPlayers.IsPlayerHero(attacker)
        local isVictimPlayer = CoopPlayers.IsPlayerHero(victim)

        -- Disable PvP
        if isAttackerPlayer and isVictimPlayer then
            return
        end

        if Config.Debug.P1GodMode and isVictimPlayer and victim == CoopPlayers.GetHero(1) then
            return
        end

        if Config.Debug.P2GodMode and isVictimPlayer and victim == CoopPlayers.GetHero(2) then
            return
        end

        if Config.Debug.OneHit then
            triggerArgs.DamageAmount = 10000
        end

        if isAttackerPlayer then
            -- Save last attacker to run OnEffectApply with the right hero context
            victim.CoopLastAttackerId = attacker.ObjectId
        end

        if isAttackerPlayer then
            HeroContext.RunWithHeroContext(attacker, fun, triggerArgs)
        elseif isVictimPlayer then
            HeroContext.RunWithHeroContext(victim, fun, triggerArgs)
        else
            fun(triggerArgs)
        end

        if isVictimPlayer then
            if victim == CoopPlayers.GetMainHero() then
                UpdateHealthUI()
            elseif victim == CoopPlayers.GetHero(2) then
                SecondPlayerUi.UpdateHealthUI()
            else
                -- Player 3 / 4 — find which slot and update its UI instance.
                local victimPlayerId = CoopPlayers.GetPlayerByHero(victim)
                if victimPlayerId then
                    local ui = CoopPlayerUi.Get(victimPlayerId)
                    if ui then
                        ui:UpdateHealthUI()
                    end
                end
            end
        end
    end }
end

local _OnProjectileDeath = OnProjectileDeath
function OnProjectileDeath(args)
    local originalHandler = args[1]

    _OnProjectileDeath { function(triggerArgs)
        PerfCounters.Tick("OnProjectileDeath")
        local attacker = triggerArgs.AttackerTable
        local isAttackerPlayer = attacker and CoopPlayers.IsPlayerHero(attacker)
        local victim = triggerArgs.TriggeredByTable
        local isVictimPlayer = victim and CoopPlayers.IsPlayerHero(victim)

        if triggerArgs.name == "RangedWeapon" then
            -- This hack disables PvP for red crystals
            if isAttackerPlayer and isVictimPlayer then
                triggerArgs.TriggeredByTable = nil
            end
        end

        -- Vanilla Combat.lua:2848 dereferences attacker.ObjectId without a nil check.
        -- AttackerTable goes nil when a player dies while their projectile is still
        -- in flight (co-op-specific). The dead player has nowhere to store ammo, so
        -- short-circuiting the handler is functionally equivalent and avoids the crash.
        if attacker == nil then
            return
        end

        if isAttackerPlayer then
            HeroContext.RunWithHeroContext(attacker, originalHandler, triggerArgs)
        elseif isVictimPlayer then
            HeroContext.RunWithHeroContext(victim, originalHandler, triggerArgs)
        else
            originalHandler(triggerArgs)
        end
    end }
end

HeroContextWrapper.WrapTriggerHero("OnWeaponFired", "OwnerTable")
HeroContextWrapper.WrapTriggerHero("OnWeaponTriggerRelease", "OwnerTable")
HeroContextWrapper.WrapTriggerHero("OnWeaponFailedToFire", "TriggeredByTable")
HeroContextWrapper.WrapTriggerHero("OnWeaponCharging", "OwnerTable")
HeroContextWrapper.WrapTriggerHero("OnWeaponChargeCanceled", "OwnerTable")
HeroContextWrapper.WrapTriggerHero("OnPerfectChargeWindowEntered", "OwnerTable")

HookUtils.wrap("OnEffectApply", function(baseFunc, args)
    local originalHandler = args[1]

    baseFunc{
        function(triggerArgs)
            PerfCounters.Tick("OnEffectApply")

            local target = triggerArgs.TriggeredByTable
            local attacker = triggerArgs.AttackerTable

            -- Friendly-fire status effect block. Vanilla's
            -- ApplyEffectFromWeapon/Projectile is engine-side and lands
            -- the effect on the victim BEFORE Damage() runs (and entirely
            -- separately from it when the effect is a pure status — Chill,
            -- Doom, Hangover, Weak, Jolted, Charm). The Damage() wrap
            -- can't see those. This is the first Lua-visible hook after
            -- the engine application: ClearEffect the just-applied stack
            -- and short-circuit so any OnApply callback / scheduled DoT
            -- tick doesn't run.
            if target and attacker
                and CoopPlayers.IsPlayerHero(target)
                and CoopPlayers.IsPlayerHero(attacker)
                and attacker ~= target
            then
                if triggerArgs.EffectName and target.ObjectId then
                    ClearEffect({ Id = target.ObjectId, Name = triggerArgs.EffectName })
                end
                return
            end

            if CoopPlayers.IsPlayerHero(target) then
                HeroContext.RunWithHeroContext(target, originalHandler, triggerArgs)
            elseif target and target.CoopLastAttackerId then
                local hero = CoopPlayers.GetHeroByUnit(target.CoopLastAttackerId)
                if hero then
                    HeroContext.RunWithHeroContext(hero, originalHandler, triggerArgs)
                else
                    originalHandler(triggerArgs)
                end
            else
                originalHandler(triggerArgs)
            end
        end
    }
end)

-- Charm: vanilla CharmApply is wired as the OnApplyFunctionName for
-- Aphrodite's charm weapon data (WeaponData.lua:17054). When the function
-- IS resolvable as a Lua global at mod-load time, wrap it so a player
-- charming a teammate can't toggle .Charmed / outgoing-damage multiplier.
-- On builds where CharmApply isn't in _G at load (engine-resolved
-- OnApplyFunctionName, or load-order quirk), the OnEffectApply
-- ClearEffect above is the only defense — which is fine, that's the
-- primary mechanism. Skip silently rather than abort mod load.
if _G.CharmApply then
    HookUtils.wrap("CharmApply", function(baseFun, triggerArgs)
        local victim = triggerArgs and triggerArgs.TriggeredByTable
        local attacker = triggerArgs and triggerArgs.AttackerTable
        if victim and attacker
            and CoopPlayers.IsPlayerHero(victim)
            and CoopPlayers.IsPlayerHero(attacker)
            and attacker ~= victim
        then
            return
        end
        return baseFun(triggerArgs)
    end)
end

-- Freeze: vanilla HitByFreezeWeapon(victim) sets victim.Frozen = true and
-- spawns FreezeEscape, which only listens for control input when
-- `victim == CurrentRun.Hero` (Combat.lua:3827). Any other player who
-- gets frozen relies on the enemy-style 0.5s auto-attempt timer, which
-- feels broken next to P1's mash-to-escape behavior. Drop the call for
-- any non-main player hero so freeze stays a P1-only mechanic. Same
-- _G existence check as CharmApply in case this function isn't
-- resolvable at load on a given build.
if _G.HitByFreezeWeapon then
    HookUtils.wrap("HitByFreezeWeapon", function(baseFun, victim)
        if victim and CoopPlayers.IsPlayerHero(victim)
            and victim ~= CoopPlayers.GetMainHero()
        then
            return
        end
        return baseFun(victim)
    end)
end

HeroContextWrapper.WrapTriggerHero("OnEffectCleared", "TriggeredByTable")
HeroContextWrapper.WrapTriggerHero("OnEffectStackDecrease", "TriggeredByTable")
HeroContextWrapper.WrapTriggerHero("OnEffectDelayedKnockbackForce", "TriggeredByTable")

-- Vanilla Combat.lua:Damage() branches on `victim == CurrentRun.Hero`,
-- routing anyone NOT equal to the default hero (i.e., P2/P3/P4) through
-- DamageEnemy as if they were a hostile. The existing OnHit / OnProjectileDeath
-- PvP guards short-circuit most code paths upstream, but a few weapon
-- damage paths (notably the shield throw observed in the training room)
-- reach Damage() directly without firing those triggers. Wrap Damage()
-- as a last line of defense: if both attacker and victim are players —
-- and they aren't the same hero (self-damage from Doom DoTs etc. must
-- still apply) — drop the call entirely.
HookUtils.wrap("Damage", function(baseFun, victim, triggerArgs)
    if victim and triggerArgs and triggerArgs.AttackerTable
        and triggerArgs.AttackerTable ~= victim
        and CoopPlayers.IsPlayerHero(triggerArgs.AttackerTable)
        and CoopPlayers.IsPlayerHero(victim)
    then
        return
    end
    return baseFun(victim, triggerArgs)
end)
