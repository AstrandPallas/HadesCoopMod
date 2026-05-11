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

    -- Diagnostic helper: prefer Hades's DebugPrint, but the Lua sandbox at
    -- main-menu time may filter it; we keep the calls minimal and only run
    -- those paths if DebugPrint is available, so we never crash the menu.
    local function ProbeLog(msg)
        if DebugPrint then
            DebugPrint { Text = "[CoopMenu] " .. msg }
        end
    end

    -- Build the per-state message text — list each selected player's controller
    -- on its own line, plus (when 2+ are selected and more can join) a hint that
    -- pressing an already-bound device will start the game.
    local function MessageForSelected(n)
        local template = GetDisplayName { Text = "CoopMenu_PlayerController" }
        local lines = {}
        for i = 1, n do
            -- string.gsub returns (string, count) — wrap in parens so only
            -- the string makes it into table.insert. Without this, the
            -- replacement count is passed as table.insert's third arg and
            -- the call errors at runtime, silently aborting SetStage.
            local replaced = (string.gsub(template, "%$(%w+)", {
                PlayerIndex = i,
                Controller = TostringPlayerConfiguration(i),
            }))
            table.insert(lines, replaced)
        end
        return table.concat(lines, "\n")
    end

    local function SetStage(state)
        ProbeLog("SetStage -> " .. tostring(state) .. " (n=" .. tostring(#SelectedGuiControl) .. ")")
        CURRENT_MENU_STATE = state
        local n = #SelectedGuiControl

        if state == MENU_STATE.START then
            message:SetTextLocalizationKey("CoopMenu_StartMessage")
            btn:SetTextLocalizationKey("CoopMenu_P1Press")
        elseif state == MENU_STATE.PLAYER_ONE_SELECTED then
            message:SetText(MessageForSelected(1))
            btn:SetTextLocalizationKey("CoopMenu_P2Press")
        elseif state == MENU_STATE.PLAYER_TWO_SELECTED
            or state == MENU_STATE.PLAYER_THREE_SELECTED
            or state == MENU_STATE.PLAYER_FOUR_SELECTED then
            local body = MessageForSelected(n)
            if n < MAX_COOP_PLAYERS then
                body = body .. "\n\nPress a new controller to add Player " .. (n + 1)
                    .. ",\nor press any selected controller to begin."
                btn:SetText(START_BUTTON_MESSAGES[math.random(1, #START_BUTTON_MESSAGES)])
            else
                body = body .. "\n\nPress any controller to begin."
                btn:SetText(START_BUTTON_MESSAGES[math.random(1, #START_BUTTON_MESSAGES)])
            end
            message:SetText(body)
        elseif state == MENU_STATE.INVALID_STATE_SECOND_KEYBOARD then
            message:SetTextLocalizationKey("CoopMenu_ErrP1KBOnly")
            btn:SetTextLocalizationKey("CoopMenu_Again")
        elseif state == MENU_STATE.INVALID_STATE_SAME_DEVICE then
            message:SetTextLocalizationKey("CoopMenu_ErrDeviceCollision")
            btn:SetTextLocalizationKey("CoopMenu_Again")
        else
            message:SetText("Error description is missing :D")
            btn:SetTextLocalizationKey("CoopMenu_Again")
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
        ProbeLog("btn activated. state=" .. tostring(CURRENT_MENU_STATE) .. " n=" .. tostring(n))

        -- Error-recovery: return to the appropriate "ready" state without
        -- discarding earlier selections; user retries with a fresh press.
        if CURRENT_MENU_STATE == MENU_STATE.INVALID_STATE_SECOND_KEYBOARD
            or CURRENT_MENU_STATE == MENU_STATE.INVALID_STATE_SAME_DEVICE then
            ProbeLog("  recovery from error state")
            SetStage(SelectedStateFor(n))
            return
        end

        local device = GetCurrentControl()
        ProbeLog("  GetCurrentControl: Device=" .. tostring(device.Device) .. " ControllerId=" .. tostring(device.ControllerId))
        ProbeLog("    UseMouse=" .. tostring(GetConfigOptionValue { Name = "UseMouse" }) ..
                 " UseGamepadGlyphs=" .. tostring(GetConfigOptionValue { Name = "UseGamepadGlyphs" }) ..
                 " CoopGetPlayerGamepad(1)=" .. tostring(CoopGetPlayerGamepad(1)))

        -- Once at the max, any press starts the game.
        if n >= MAX_COOP_PLAYERS then
            ProbeLog("  at max, starting game")
            StartGameNow()
            return
        end

        -- At 2+ players, pressing an already-selected device starts the game.
        if n >= 2 and MatchesExistingDevice(device) then
            ProbeLog("  existing device at 2+, starting game")
            StartGameNow()
            return
        end

        -- Otherwise we're trying to add a new player. Validate first.
        if device.Device == "Keyboard" and n >= 1 then
            ProbeLog("  keyboard not allowed for P" .. (n + 1))
            SetStage(MENU_STATE.INVALID_STATE_SECOND_KEYBOARD)
            return
        end

        if n >= 1 and MatchesExistingDevice(device) then
            -- At the P1_SELECTED stage same-device is an error (need >= 2 to
            -- start). At 2+ the matches-existing path above already started.
            ProbeLog("  same device as existing, error")
            SetStage(MENU_STATE.INVALID_STATE_SAME_DEVICE)
            return
        end

        ProbeLog("  adding P" .. (n + 1))
        SelectedGuiControl[n + 1] = device
        SetStage(SelectedStateFor(n + 1))
    end)

    menu:AddReflection("mControllerPress", btn)

    menu:LoadDefenitions("../Mods/TN_CoopMod/ControllerSelectionMenuScreen.sjson")
end)
