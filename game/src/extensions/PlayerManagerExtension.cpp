//
// Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
// Licensed under the MIT license. See LICENSE file in the project root for details.
//

#include "PlayerManagerExtension.h"
#include "../interface/PlayerManager.h"
#include "../HookTable.h"

#include <cstring>

// EASTL vector::resize(size_type n, const value_type& value).
// __fastcall on x64 Windows: rcx=this, rdx=n, r8=&value.
// We pass a pointer-to-nullptr as the fill value.
template <typename T>
static void ResizeEastlPlayerVector(void *resizeFnPtr, void *vec, size_t newSize) {
    T fillValue = nullptr;
    auto fn = (void(__fastcall *)(void *, size_t, T const *))resizeFnPtr;
    fn(vec, newSize, &fillValue);
}

// Static storage for the input handlers we synthesize for slots beyond what
// Hades pre-creates (the engine builds 2 entries in m_inputMethods at startup;
// we provide our own for slots 2+ = P3+). These live for process lifetime and
// are never freed — m_inputMethods only stores pointers, so the engine's own
// destructors won't try to delete our static storage. Initialized by copying
// the existing gamepad handler (m_inputMethods[1]) so internal engine state
// (deadzone, repeat-delay, direction caches, etc.) is consistent.
static SGG::InputHandler g_extraInputHandlers[MAX_PLAYERS];

bool PlayerManagerExtension::AssignGamepad(size_t playerIndex, uint8_t gamepadIndex) {
    if (GetPlayersCount() < playerIndex + 1)
        return false;

    auto *player = SGG::PlayerManager::Instance()->GetPlayer(playerIndex);

    if (!player)
        return false;

    auto *input = GetInput(player->GetControllerIndex());

    if (!input)
        return false;

    input->SetGamepadId(gamepadIndex);

    return true;
}

uint8_t PlayerManagerExtension::GetGamepad(size_t playerIndex) {
    if (GetPlayersCount() < playerIndex + 1)
        return -1;

    auto *player = SGG::PlayerManager::Instance()->GetPlayer(playerIndex);

    if (!player)
        return -1;

    auto *input = GetInput(player->GetControllerIndex());

    if (!input)
        return -1;

    return input->GetGamepadId();
}

bool PlayerManagerExtension::AssignController(SGG::Player *player, uint8_t ccontroler) {
    SGG::PlayerManager::Instance()->AssignController(player, ccontroler);
    return false;
}

bool PlayerManagerExtension::HasPlayer(size_t index) {
    auto *instance = SGG::PlayerManager::Instance();
    if (instance->m_palyers.size() <= index)
        return false;

    return instance->m_palyers[index];
}

// TODO use RemovePlayer from the game
void PlayerManagerExtension::RemovePlayer(size_t index) {
    auto *instance = SGG::PlayerManager::Instance();
    if (instance->m_palyers.size() <= index)
        return;

    auto *player = instance->m_palyers[index];

    if (player) {
        delete player;
        instance->m_palyers[index] = nullptr;
    }
}

SGG::Player *PlayerManagerExtension::CreatePlayer(size_t index) {
    auto *instance = SGG::PlayerManager::Instance();

    if (index >= MAX_PLAYERS)
        return nullptr;

    // Grow m_palyers via the engine's own resize so the existing 2-slot storage
    // and any new storage share the same forge allocator.
    auto *resizePlayers = (void *)HookTable::Instance().Vector_Player_Resize;
    if (resizePlayers && instance->m_palyers.size() <= index) {
        ResizeEastlPlayerVector<SGG::Player *>(resizePlayers, &instance->m_palyers, index + 1);
    }

    // m_inputMethods is left at its original size and not modified. Three
    // attempts to give slot >= 2 its own InputHandler all crashed mid room
    // load with no Lua trace (engine-level death): memcpy from slot 1
    // aliased opaque pad_end[0x64] state; zero-init left fields the engine
    // dereferenced; placement-calling sgg::InputHandler::InputHandler
    // (resolved through the symbol table) still crashed. Strong indication
    // the engine has a separate input-pump registry that handlers must
    // belong to — just sitting in m_inputMethods isn't enough — and we
    // don't yet know the registration call.
    //
    // For now, every new slot uses controller index 1 (the existing engine-
    // managed gamepad slot). P3 and P4 spawn and play, but they share P2's
    // gamepad routing. Real per-slot input requires either finding the
    // engine's input-method-add call or asking the Hades Modding Discord.

    if (instance->m_palyers.size() <= index)
        return nullptr;  // resize didn't take — bail rather than corrupt memory

    if (instance->m_palyers[index] != nullptr)
        return nullptr;

    uint8_t controller = (index == 0) ? 0 : 1;

    auto player = instance->AddPlayer(index);

    AssignController(player, controller);

    return player;
}

SGG::Player *PlayerManagerExtension::GetPlayer(size_t index) {
    return SGG::PlayerManager::Instance()->m_palyers[index];
}
SGG::InputHandler *PlayerManagerExtension::GetInput(size_t index) {
    return SGG::PlayerManager::Instance()->m_inputMethods[index];
};

size_t PlayerManagerExtension::GetPlayersCount() const noexcept {
    size_t size = 0;
    for (auto *player : SGG::PlayerManager::Instance()->m_palyers)
        if (player)
            size++;

    return size;
}
