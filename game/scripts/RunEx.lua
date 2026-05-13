--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@class RunEx
local RunEx = {}

---@return boolean
function RunEx.IsRunEnded()
    -- The game sets EndingMoney in state after death
    -- So we can use this value to check if the run was finished
    return CurrentRun.EndingMoney and true
end

---@return boolean
function RunEx.WasTheFirstRunStarted()
    return not GameState or (not CurrentRun and IsEmpty(GameState.RunHistory))
end

---@return boolean
function RunEx.IsStyxTempleHubRoom(room)
    return room.Name == "D_Hub"
end

---@return boolean
function RunEx.IsSecretRoom(room)
    return room.LocationText == "Location_Secret"
end

---@return boolean
function RunEx.IsShopRoomName(name)
    return name == "A_Shop01" or name == "B_Shop01" or name == "C_Shop01"
end

---@return boolean
function RunEx.IsStoryRoomName(name)
    return name == "A_Story01" or name == "B_Story01" or name == "C_Story01"
end

---@return boolean
function RunEx.IsPrebossRoomName(name)
    return name == "A_PreBoss01" or name == "B_PreBoss01" or name == "C_PreBoss01"
end

---@return boolean
---True for biome boss rooms (Tartarus A_Boss01-03 = Furies, Asphodel
---B_Boss01-02 = Hydra variants, Elysium C_Boss01 = Theseus + Asterius).
---Final-boss D_Boss01 is excluded — the run ends there, no "next room"
---to revive in.
function RunEx.IsBossRoomName(name)
    return name == "A_Boss01" or name == "A_Boss02" or name == "A_Boss03"
        or name == "B_Boss01" or name == "B_Boss02"
        or name == "C_Boss01"
end

---@return boolean
---True for any boss-equivalent room — biome bosses above, plus any room
---flagged `IsMiniBossRoom` in RoomData (rare-spawn mini-boss encounters
---scattered through Tartarus / Asphodel / Elysium / Styx).
function RunEx.IsAnyBossRoom(room)
    if not room then return false end
    if room.IsMiniBossRoom then return true end
    return RunEx.IsBossRoomName(room.Name)
end

function RunEx.IsDoorSpecial(door)
    -- chaos door or chall aenge room
    return door.OnUsedPresentationFunctionName == "SecretDoorUsedPresentation" or
        door.OnUsedPresentationFunctionName == "ShrinePointDoorUsedPresentation"
end

---@return boolean
function RunEx.IsFinalBossDoor(door)
    return door.ForceRoomName == "D_Boss01"
end

---@return boolean
function RunEx.IsDefaultDoorsLeadToRunProgress()
    for _, door in pairs(OfferedExitDoors) do
        local room = door.Room
        if room
            and not RunEx.IsShopRoomName(room.Name)
            and not RunEx.IsStoryRoomName(room.Name)
            and not RunEx.IsDoorSpecial(door)
            and room.RewardStoreName == "RunProgress"
            then
            return true
        end
    end
    return false
end

function RunEx.RemoveDoorReward(door)
    if door.DoorIconId ~= nil then
        Destroy { Id = door.DoorIconBackingId }
        Destroy { Id = door.DoorIconId }
        Destroy { Id = door.DoorIconFront }
        Destroy { Ids = door.AdditionalIcons }
        Destroy { Ids = door.AdditionalAttractIds }

        door.DoorIconBackingId = nil
        door.DoorIconId = nil
        door.DoorIconFront = nil
        door.AdditionalIcons = {}
        door.AdditionalAttractIds = {}
    end

    local room = door.Room
    room.ForceLootName = nil
    room.RewardOverrides = nil
end

function RunEx.RemoveRewardFromAllDefaultDoors()
    for _, door in pairs(OfferedExitDoors) do
        if door.IsDefaultDoor then
            RunEx.RemoveDoorReward(door)
        end
    end
end

return RunEx
