//
// Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
// Licensed under the MIT license. See LICENSE file in the project root for details.
//

#pragma once

#include "../include/HadesModApi.h"

struct HookTable {
    static HookTable& Instance();
    void Init(IModApi::GetSymbolAddress_t GetSymbolAddress);

	size_t PlayerManager_Instance;
    size_t PlayerManager_AddPlayer;
    size_t PlayerManager_AssignController;

    // Pointers to the engine's already-compiled EASTL vector::resize for
    // the player/input vectors. Lets us grow m_palyers / m_inputMethods past
    // the engine's built-in size of 2 (needed for 3rd/4th players).
    size_t Vector_Player_Resize;
    size_t Vector_InputHandler_Resize;

    // Engine's InputHandler constructor — we placement-call this on our
    // static storage to get a real engine-initialized handler for P3/P4.
    size_t InputHandler_Constructor;

    size_t Player_Player;

    size_t PlayerUnit_PlayerUnit;

    size_t UnitManager_ENTITY_MANAGER;
    size_t UnitManager_Add;
    size_t UnitManager_Get;
    size_t UnitManager_CreatePlayerUnit;

    size_t Unit_Delete;

    size_t Interact_Use;

    size_t World_Instance;
    size_t World_GetActiveThing;

    size_t GameDataManager_GetUnitData;

    uintptr_t getGamePadNameForIndex;
};
