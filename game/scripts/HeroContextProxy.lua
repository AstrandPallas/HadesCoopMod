--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type HeroContext
local HeroContext = ModRequire "HeroContext.lua"
---@type CoopPlayers
local CoopPlayers = ModRequire "CoopPlayers.lua"
---@type TableUtils
local TableUtils = ModRequire "TableUtils.lua"

---@class HeroContextProxy
---@field private separatedData table[]
---@field private target table
local HeroContextProxy = {}

---@param owner table
---@param keyInOwner string
---@return HeroContextProxy
function HeroContextProxy.New(owner, keyInOwner)
    local target = owner[keyInOwner]

    local handler = {
        separatedData = {};
        target = target;
        owner = owner;
        keyInOwner = keyInOwner;
    }
    setmetatable(handler, { __index = HeroContextProxy })

    -- Seed slots for the players known at construction time, but rely on
    -- ensurePlayerData for any slot that appears later (e.g. when a 3rd/4th
    -- player joins mid-session). Without this, every accessor below would
    -- index a nil entry and crash with "table expected, got nil".
    for playerId = 1, CoopPlayers.GetPlayersCount() do
        handler:ensurePlayerData(playerId)
    end

    handler:MoveDataToContext(1)

    local separatedData = handler.separatedData

    local function getTableForCurrentHero()
        local hero = HeroContext.GetCurrentHeroContext()
        local playerId = CoopPlayers.GetPlayerByHero(hero) or 1
        return handler:ensurePlayerData(playerId)
    end

    local contextMt = {
        __index = function(self, key)
            return getTableForCurrentHero()[key]
        end,

        __newindex = function(self, key, value)
            getTableForCurrentHero()[key] = value
        end,

        __pairs = function()
            return pairs(getTableForCurrentHero())
        end,

        __ipairs = function()
            return ipairs(getTableForCurrentHero())
        end,

        __len = function()
            return #getTableForCurrentHero()
        end
    }

    setmetatable(target, contextMt)

    return handler
end

---@private
-- Lazily allocate the data slot for a player and mirror it into `owner` so
-- save/load still picks it up via the existing per-player key convention.
---@param playerId integer
---@return table
function HeroContextProxy:ensurePlayerData(playerId)
    local data = self.separatedData[playerId]
    if data == nil then
        local playerKey = self.keyInOwner .. "CoopPlayer" .. playerId
        data = self.owner[playerKey] or {}
        self.separatedData[playerId] = data
        self.owner[playerKey] = data
    end
    return data
end

---@private
---@param playerId integer
function HeroContextProxy:MoveDataToContext(playerId)
    local dataInContext = self:ensurePlayerData(playerId)

    TableUtils.copyTo(dataInContext, self.target)
    TableUtils.clean(self.target)
end

---@param playerId number
function HeroContextProxy:MovePlayerDataToProxy(playerId)
    local dataFrom = self.separatedData[playerId]

    if not dataFrom then
        return
    end

    TableUtils.rawCopyTo(self.target, dataFrom)
end

---@param playerId integer
function HeroContextProxy:GetPlayerData(playerId)
    return self:ensurePlayerData(playerId)
end

function HeroContextProxy:CleanProxyTable()
    TableUtils.clean(self.target)
end

function HeroContextProxy:Reset()
    for playerId = 1, CoopPlayers.GetPlayersCount() do
        TableUtils.clean(self:ensurePlayerData(playerId))
    end

    TableUtils.clean(self.target)
end

return HeroContextProxy
