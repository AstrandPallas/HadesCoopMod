--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--
-- TEMPORARY diagnostic for the Charon shop "only 1-2 items" bug. Wraps
-- the three vanilla shop functions and logs counts at each stage so we
-- can tell whether the cut happens during generation (RunShopGeneration /
-- FillInShopOptions producing few options) or during spawning
-- (SpawnStoreItemsInWorld silent-skipping due to missing LootPoints).
--
-- Remove the ModRequire in GamemodeInit.lua and delete this file once
-- the bug is diagnosed.
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

function ShopDiagnostic.InitHooks()
    -- RunShopGeneration: called once per room transition at RoomManager.lua:5089.
    -- After it returns, roomData.Store.StoreOptions should be populated.
    HookUtils.wrap("RunShopGeneration", function(baseFun, roomData)
        DebugPrint { Text = "TN_Coop ShopDiag RunShopGeneration entry"
            .. " roomName=" .. tostring(roomData and roomData.Name)
            .. " ChosenRewardType=" .. tostring(roomData and roomData.ChosenRewardType)
            .. " storeNil=" .. tostring(roomData and roomData.Store == nil)
        }
        baseFun(roomData)
        local store = roomData and roomData.Store
        local options = store and store.StoreOptions
        DebugPrint { Text = "TN_Coop ShopDiag RunShopGeneration exit"
            .. " roomName=" .. tostring(roomData and roomData.Name)
            .. " storeNil=" .. tostring(store == nil)
            .. " optionsCount=" .. tostring(countTable(options))
        }
    end)

    -- FillInShopOptions: called by RunShopGeneration. The actual filter
    -- pipeline (Traits, Consumables, Cosmetic, Healing). Log its result.
    HookUtils.wrap("FillInShopOptions", function(baseFun, args)
        local result = baseFun(args)
        DebugPrint { Text = "TN_Coop ShopDiag FillInShopOptions exit"
            .. " roomName=" .. tostring(args and args.RoomName)
            .. " storeDataKind=" .. tostring(args and args.StoreData and args.StoreData.RewardType or "n/a")
            .. " optionsCount=" .. tostring(countTable(result and result.StoreOptions))
        }
        return result
    end)

    -- SpawnStoreItemsInWorld: called when the shop event fires after the
    -- room is fully entered. Compares #kitIds (LootPoints registered) to
    -- #StoreOptions (items to spawn). The silent-skip lives here at
    -- StoreScripts.lua:412 - "if kitIds[index] ~= nil then spawn else skip".
    HookUtils.wrap("SpawnStoreItemsInWorld", function(baseFun)
        local kitIds = GetIdsByType({ Name = "LootPoint" })
        local store = CurrentRun and CurrentRun.CurrentRoom and CurrentRun.CurrentRoom.Store
        local options = store and store.StoreOptions
        DebugPrint { Text = "TN_Coop ShopDiag SpawnStoreItemsInWorld entry"
            .. " kitIdsCount=" .. tostring(#(kitIds or {}))
            .. " optionsCount=" .. tostring(countTable(options))
        }
        baseFun()
        local spawnedAfter = store and store.SpawnedStoreItems
        DebugPrint { Text = "TN_Coop ShopDiag SpawnStoreItemsInWorld exit"
            .. " spawnedCount=" .. tostring(countTable(spawnedAfter))
        }
    end)
end

return ShopDiagnostic
