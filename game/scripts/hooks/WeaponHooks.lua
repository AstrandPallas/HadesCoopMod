--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type CoopPlayers
local CoopPlayers = ModRequire "../CoopPlayers.lua"
---@type HookUtils
local HookUtils = ModRequire "../HookUtils.lua"

-- Fixes crashes when the game unload weapons that is currently equipped by another player
HookUtils.wrap("UnequipWeapon", function (baseFunc, args)
    if args.UnloadPackages == false then
        return baseFunc(args)
    end

    local toRemove = args.Names or { args.Name }

    local unit = args.DestinationId
    local hasAnotherPlayerThisWeapon = false

    for playerId, hero in CoopPlayers.PlayersIterator() do
        if hero.ObjectId == unit then
            goto continue
        end

        for _, name in ipairs(toRemove) do
            if hero.Weapons[name] then
                hasAnotherPlayerThisWeapon = true
                break
            end
        end

        ::continue::
    end

    args.UnloadPackages = not hasAnotherPlayerThisWeapon
    args.UnloadPackages = false

    return baseFunc(args)
end)

HookUtils.wrap("PreLoadBinks", function(baseFun, args)
    if args.Cache == "WeaponCache" then
        return baseFun {
            Names = args.Names
            -- Do not reset
        }
    else
        return baseFun(args)
    end
end)

-- Shield-recall routing for all players, including P1.
--
-- Vanilla Combat.lua:1972's OnWeaponFailedToFire handler issues the
-- recall via
--     RunWeaponMethod({ Id = CurrentRun.Hero.ObjectId,
--                       Weapon = weaponData.RecallOnFailToFire,
--                       Method = "RecallProjectiles" })
-- In the coop modded environment, that vanilla call is empirically a
-- no-op for every player -- nobody's thrown shield recalls without
-- this handler. The exact reason is engine-side (likely the
-- HadesCoopGame.dll's input-routing reshapes the call context away
-- from what the engine accepts for projectile recall), but the
-- observed behavior is consistent: even P1, whose CurrentRun.Hero
-- resolves to the correct defaultHero in vanilla's un-wrapped handler,
-- never gets their shield back.
--
-- We don't skip any player. This handler is registered via the
-- HeroContextWrapper installed at DamageHooks.lua:125, so it runs in
-- a coroutine tagged with triggerArgs.TriggeredByTable -- the actual
-- triggering player's hero context. From inside that context the
-- engine accepts RunWeaponMethod("RecallProjectiles") as a real
-- recall and the projectile returns.
--
-- An earlier version skipped when `attacker == CoopPlayers.GetMainHero()`
-- on the theory that vanilla already handled P1; an even earlier draft
-- used a more defensive ObjectId comparison against
-- HeroContext.GetDefaultHero(). Both were wrong: the premise that
-- vanilla recalls correctly for P1 in coop turned out to be false
-- (verified empirically). Always-run is the correct shape.
OnWeaponFailedToFire {
    function(triggerArgs)
        local attacker = triggerArgs.TriggeredByTable
        if not attacker or not CoopPlayers.IsPlayerHero(attacker) then
            return
        end
        local weaponData = GetWeaponData(attacker, triggerArgs.name)
        if weaponData and weaponData.RecallOnFailToFire then
            RunWeaponMethod({
                Id = attacker.ObjectId,
                Weapon = weaponData.RecallOnFailToFire,
                Method = "RecallProjectiles",
            })
        end
    end
}
