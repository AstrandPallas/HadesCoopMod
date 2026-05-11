--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

local SelectedGuiControl = {}

local function GetCurrentControl()
    local isMouseVisible = GetConfigOptionValue { Name = "UseMouse" } or
        not GetConfigOptionValue { Name = "UseGamepadGlyphs" }

    if isMouseVisible then
        return
        {
            Device = "Keyboard",
            ControllerId = -1,
        }
    else
        return
        {
            Device = "Gamepad",
            ControllerId = CoopGetPlayerGamepad(1),
        }
    end
end

local function TostringPlayerConfiguration(playerId)
    if SelectedGuiControl[playerId].Device == "Keyboard" then
        return GetDisplayName { Text = "CoopMenu_KbAndMouse" }
    else
        local index = SelectedGuiControl[playerId].ControllerId
        --return "Gamepad " .. index .. " - " .. CoopGetGamepadName(index)
        return GetDisplayName { Text = "CoopMenu_Gamepad", Param =  index }
    end
end

-- Hard cap matches MAX_PLAYERS in the C++ DLL. Bump both together.
local MAX_COOP_PLAYERS = 4

local MENU_STATE = {
    START = 0,
    PLAYER_ONE_SELECTED = 1,
    PLAYER_TWO_SELECTED = 2,
    PLAYER_THREE_SELECTED = 3,
    PLAYER_FOUR_SELECTED = 4,
    INVALID_STATE_SECOND_KEYBOARD = 10,
    INVALID_STATE_SAME_DEVICE = 11,
}

-- Map "n players selected" -> the state that represents that selection set.
-- States PLAYER_TWO_SELECTED..PLAYER_FOUR_SELECTED are numerically contiguous
-- so SelectedStateFor(n) = PLAYER_TWO_SELECTED + (n - 2) for n in 2..4.
local function SelectedStateFor(n)
    if n == 0 then return MENU_STATE.START end
    if n == 1 then return MENU_STATE.PLAYER_ONE_SELECTED end
    return MENU_STATE.PLAYER_TWO_SELECTED + (n - 2)
end

local CURRENT_MENU_STATE

local START_BUTTON_MESSAGES = {
    "Let's play",
    "Go, go, go",
    "Start",
    "Let the Carnage Begin!",
    "Next",
    "Let's Roll!",
    "Game On!",
    "Adventure Awaits",
    "Initiate Chaos!",
    "Begin the Hunt!",
    "It's Time to Kick Gum and Chew Ass",
    "Fus Ro Dah!",
    "Let's Cause Trouble",
    "Press Start to Change Everything"
}

MainMenuAPIAddGamemode("Coop", function(name)
    SelectedGuiControl = {}

    local menu = CreateMenuScreen()
    menu:CreateBack(0.8)
    menu:CreateBackground("")
    menu:CreateTitleText()
    menu:SetLowerInputBlock(true)

    menu:CreateCancelButton(function()
        SetTempRuntimeData("Gamemode", nil)
        menu:ExitScreen()
    end)

    local message = CreateGUIComponentTextBox(menu)

    menu:AddReflection("mMessageText", message)

    local btn = CreateGUIComponentButton(menu)
    local startBtn = CreateGUIComponentButton(menu)

    -- Build the per-state message text. For states P2..P4 selected, the body
    -- lists each player's controller and (if more can join) a hint that the
    -- "Press to add" button accepts another device.
    local function MessageForSelected(n)
        local template = GetDisplayName { Text = "CoopMenu_PlayerController" }
        local lines = {}
        for i = 1, n do
            table.insert(lines, string.gsub(template, "%$(%w+)", {
                PlayerIndex = i,
                Controller = TostringPlayerConfiguration(i),
            }))
        end
        return table.concat(lines, "\n")
    end

    local function SetStage(state)
        CURRENT_MENU_STATE = state
        local n = #SelectedGuiControl

        if state == MENU_STATE.START then
            message:SetTextLocalizationKey("CoopMenu_StartMessage")
            btn:SetTextLocalizationKey("CoopMenu_P1Press")
            startBtn:SetText("")
        elseif state == MENU_STATE.PLAYER_ONE_SELECTED then
            message:SetText(MessageForSelected(1))
            btn:SetTextLocalizationKey("CoopMenu_P2Press")
            startBtn:SetText("")
        elseif state == MENU_STATE.PLAYER_TWO_SELECTED
            or state == MENU_STATE.PLAYER_THREE_SELECTED
            or state == MENU_STATE.PLAYER_FOUR_SELECTED then
            message:SetText(MessageForSelected(n))
            if n < MAX_COOP_PLAYERS then
                btn:SetText("Press a controller to add Player " .. (n + 1))
            else
                btn:SetText("")
            end
            startBtn:SetText(START_BUTTON_MESSAGES[math.random(1, #START_BUTTON_MESSAGES)])
        elseif state == MENU_STATE.INVALID_STATE_SECOND_KEYBOARD then
            message:SetTextLocalizationKey("CoopMenu_ErrP1KBOnly")
            btn:SetTextLocalizationKey("CoopMenu_Again")
            startBtn:SetText("")
        elseif state == MENU_STATE.INVALID_STATE_SAME_DEVICE then
            message:SetTextLocalizationKey("CoopMenu_ErrDeviceCollision")
            btn:SetTextLocalizationKey("CoopMenu_Again")
            startBtn:SetText("")
        else
            message:SetText("Error description is missing :D")
            btn:SetTextLocalizationKey("CoopMenu_Again")
            startBtn:SetText("")
        end
    end

    SetStage(MENU_STATE.START)

    local function StartGameNow()
        SetTempRuntimeData("Gamemode", name)
        SetTempRuntimeData("TN_Coop:control", SelectedGuiControl)
        MainMenuOpenProfiles()
    end

    -- True if `device` matches any already-selected player's device.
    local function MatchesExistingDevice(device)
        for _, existing in ipairs(SelectedGuiControl) do
            if existing.Device == device.Device
                and existing.ControllerId == device.ControllerId then
                return true
            end
        end
        return false
    end

    btn:AddActivationHandler(function()
        local n = #SelectedGuiControl

        -- Error-recovery: just go back to the appropriate "ready" state without
        -- discarding earlier selections.
        if CURRENT_MENU_STATE == MENU_STATE.INVALID_STATE_SECOND_KEYBOARD
            or CURRENT_MENU_STATE == MENU_STATE.INVALID_STATE_SAME_DEVICE then
            SetStage(SelectedStateFor(n))
            return
        end

        if n >= MAX_COOP_PLAYERS then
            return
        end

        local device = GetCurrentControl()

        -- Keyboard is allowed only for P1.
        if device.Device == "Keyboard" and n >= 1 then
            SetStage(MENU_STATE.INVALID_STATE_SECOND_KEYBOARD)
            return
        end

        -- A new player must use a device not already claimed.
        if n >= 1 and MatchesExistingDevice(device) then
            SetStage(MENU_STATE.INVALID_STATE_SAME_DEVICE)
            return
        end

        SelectedGuiControl[n + 1] = device
        SetStage(SelectedStateFor(n + 1))
    end)

    startBtn:AddActivationHandler(function()
        -- Only valid once at least 2 players are configured.
        if #SelectedGuiControl >= 2 then
            StartGameNow()
        end
    end)

    menu:AddReflection("mControllerPress", btn)
    menu:AddReflection("mStartGame", startBtn)

    menu:LoadDefenitions("../Mods/TN_CoopMod/ControllerSelectionMenuScreen.sjson")
end)
