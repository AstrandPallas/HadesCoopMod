//
// Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
// Licensed under the MIT license. See LICENSE file in the project root for details.
//

#include "PlayerManagerExtension.h"
#include "../interface/PlayerManager.h"
#include "../HookTable.h"

// EASTL vector::resize(size_type n, const value_type& value).
// __fastcall on x64 Windows: rcx=this, rdx=n, r8=&value.
// We pass a pointer-to-nullptr as the fill value.
template <typename T>
static void ResizeEastlPlayerVector(void *resizeFnPtr, void *vec, size_t newSize) {
    T fillValue = nullptr;
    auto fn = (void(__fastcall *)(void *, size_t, T const *))resizeFnPtr;
    fn(vec, newSize, &fillValue);
}

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

    // Engine pre-allocates m_palyers at size 2. To allocate slot >= 2 we have
    // to grow the vector first, using the engine's own resize (resolved via
    // GetSymbolAddress at init) so the existing 2-slot storage and any new
    // storage share the same allocator (forge).
    auto *resizeFn = (void *)HookTable::Instance().Vector_Player_Resize;
    if (resizeFn && instance->m_palyers.size() <= index) {
        ResizeEastlPlayerVector<SGG::Player *>(resizeFn, &instance->m_palyers, index + 1);
    }

    if (instance->m_palyers.size() <= index)
        return nullptr;  // resize didn't take — bail rather than corrupt memory

    if (instance->m_palyers[index] != nullptr)
        return nullptr;

    uint8_t controller = 1;

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
