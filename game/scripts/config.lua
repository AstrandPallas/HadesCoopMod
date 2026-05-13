--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@class CoopModConfig
local Config = {
    -- Choose loot delivery type here
    -- Possible values: "Shared", "RoomDuplicated"
    --
    -- Shared - rooms generate one reward. Only one player can pick it up.
    -- The game has a query that select a player context for a reward.
    -- E.g. Player 1 boon room, meta progress room, Player 2 boon room, Player 1 boon room...
    --
    -- RoomDuplicated - rooms generate two reward for each player.
    LootDelivery = "RoomDuplicated",

    -- This config is used for the "RoomDuplicated" loot delivery option
    RoomDuplicatedDelivery = {
        -- Enables duplication of the Chaos boons.
        DuplicateChaosBoon = true;
    },
    -- Outline RGB values match the HUD bar colors so each player's outline
    -- visually pairs with their health bar at the bottom of the screen.
    -- Bar colors are defined in CoopPlayerUi.LayoutForCorner/LayoutForBottomSlot
    -- as 0-1 floats; these are the 0-255 equivalents.
    Player1HasOutline = true;
    Player1Outline = {
        R = 230,
        G = 64,
        B = 64,
        Opacity = 0.6,
        Thickness = 2,
        Threshold = 0.6,
    };
    Player2HasOutline = true,
    Player2Outline = {
        R = 89,
        G = 217,
        B = 242,
        Opacity = 0.6,
        Thickness = 2,
        Threshold = 0.6,
    };
    Player3HasOutline = true,
    Player3Outline = {
        R = 140,
        G = 217,
        B = 115,
        Opacity = 0.6,
        Thickness = 2,
        Threshold = 0.6,
    };
    Player4HasOutline = true,
    Player4Outline = {
        R = 179,
        G = 115,
        B = 230,
        Opacity = 0.6,
        Thickness = 2,
        Threshold = 0.6,
    };
    TextAbovePlayersEnabled = false;
    TextAbovePlayersParams = {
        -- CreateTextBox params
        OffsetX = 0,
        OffsetY = -150,
        FontSize = 28,
        Color = { 255, 255, 255, 255 },
        ShadowColor = { 0, 0, 0, 240 },
        ShadowOffset = { 0, 2 },
        ShadowBlur = 0,
        OutlineThickness = 3,
        OutlineColor = { 0, 0, 0, 1 },
        Font = "AlegreyaSansSCRegular",
        Justification = "Center"
    },
    Debug = {
        OneHit = false,
        P1GodMode = false,
        P2GodMode = false,
    }
}

return Config
