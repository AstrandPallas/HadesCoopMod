--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--
-- Charon shop fix + diagnostic.
--
-- Bug: on first entry to a Charon shop, only 1-2 items spawn in the world
-- instead of the full 3-6. On exiting and re-entering the same shop, the
-- missing items appear. Save-reload also "fixes" it.
--
-- Cause: vanilla `SpawnStoreItemsInWorld` (StoreScripts.lua:396) iterates
-- `StoreOptions` and only spawns when there's a matching `LootPoint`
-- obstacle at that index. The check `if kitIds[index] ~= nil then ...`
-- silent-skips otherwise. On first entry the call fires before all
-- `LootPoint` obstacles have registered, so most items get skipped. On
-- re-entry the room is fully loaded and the call finds every LootPoint.
--
-- Fix: poll `#kitIds` against `#StoreOptions` and defer the spawn call
-- until they match (or until a 2s timeout, just in case). If they already
-- match when the engine first calls in, vanilla runs synchronously — no
-- delay in the common case where the bug doesn't apply.
--
-- The diagnostic DebugPrints would tell us the exact counts to confirm,
-- but on this build DebugPrint output isn't reaching Hades.log. Kept the
-- prints anyway in case logging works on a future Hades build.
--

---@type HookUtils
local HookUtils = ModRequire "../HookUtils.lua"

---@class ShopDiagnostic
local ShopDiagnostic = {}

---@private
local function countTable(t)
    if t == nil then return 0 end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

---@private
---Wait up to maxWait seconds for the room to have at least optionsCount
---LootPoint obstacles registered. Returns the final kitIds list.
local function waitForLootPoints(optionsCount, maxWait)
    local checkInterval = 0.05
    local elapsed = 0
    local kitIds = GetIdsByType({ Name = "LootPoint" })
    while #kitIds < optionsCount and elapsed < maxWait do
        wait(checkInterval)
        elapsed = elapsed + checkInterval
        kitIds = GetIdsByType({ Name = "LootPoint" })
    end
    return kitIds, elapsed
end

function ShopDiagnostic.InitHooks()
    -- RunShopGeneration / FillInShopOptions: pure diagnostic. If
    -- DebugPrint output ever surfaces, these reveal which stage of the
    -- store-options pipeline produced the count we observe in the spawn
    -- wrapper. They run synchronously and don't affect behavior.
    HookUtils.wrap("RunShopGeneration", function(baseFun, roomData)
        DebugPrint { Text = "TN_Coop ShopDiag RunShopGeneration entry"
            .. " roomName=" .. tostring(roomData and roomData.Name)
            .. " ChosenRewardType=" .. tostring(roomData and roomData.ChosenRewardType)
        }
        baseFun(roomData)
        DebugPrint { Text = "TN_Coop ShopDiag RunShopGeneration exit"
            .. " optionsCount=" .. tostring(countTable(roomData and roomData.Store and roomData.Store.StoreOptions))
        }
    end)

    HookUtils.wrap("FillInShopOptions", function(baseFun, args)
        local result = baseFun(args)
        DebugPrint { Text = "TN_Coop ShopDiag FillInShopOptions exit"
            .. " roomName=" .. tostring(args and args.RoomName)
            .. " optionsCount=" .. tostring(countTable(result and result.StoreOptions))
        }
        return result
    end)

    -- SpawnStoreItemsInWorld: fix + diagnostic. If kitIds already matches
    -- #StoreOptions when the engine calls in (normal case once LootPoints
    -- are all registered), defer to vanilla synchronously. Otherwise
    -- spawn a thread that polls until kitIds catches up, then runs
    -- vanilla — this is what fixes the "first entry shows 1-2 items" bug.
    HookUtils.wrap("SpawnStoreItemsInWorld", function(baseFun)
        local store = CurrentRun and CurrentRun.CurrentRoom and CurrentRun.CurrentRoom.Store
        local optionsCount = countTable(store and store.StoreOptions)
        local kitIds = GetIdsByType({ Name = "LootPoint" })

        DebugPrint { Text = "TN_Coop ShopDiag SpawnStoreItemsInWorld entry"
            .. " kitIdsCount=" .. tostring(#kitIds)
            .. " optionsCount=" .. tostring(optionsCount)
        }

        if #kitIds >= optionsCount or optionsCount == 0 then
            -- Common case: room is ready, no deferral needed.
            baseFun()
            DebugPrint { Text = "TN_Coop ShopDiag SpawnStoreItemsInWorld done sync"
                .. " spawnedCount=" .. tostring(countTable(store and store.SpawnedStoreItems))
            }
            return
        end

        -- Defer until LootPoints catch up. The thread captures the
        -- closure scope; on resume it re-checks kitIds, calls vanilla
        -- once it's ready (or after a 2s safety timeout).
        thread(function()
            local finalKitIds, elapsed = waitForLootPoints(optionsCount, 2.0)
            DebugPrint { Text = "TN_Coop ShopDiag SpawnStoreItemsInWorld deferred run"
                .. " elapsed=" .. tostring(elapsed)
                .. " kitIdsCount=" .. tostring(#finalKitIds)
                .. " optionsCount=" .. tostring(optionsCount)
            }
            baseFun()
            DebugPrint { Text = "TN_Coop ShopDiag SpawnStoreItemsInWorld done deferred"
                .. " spawnedCount=" .. tostring(countTable(store and store.SpawnedStoreItems))
            }
        end)
    end)
end

return ShopDiagnostic
