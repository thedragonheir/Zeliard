#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace Mdt
{
enum class TownEntityKind
{
    Door,
    Npc
};

struct TownEntityMarker
{
    TownEntityKind Kind = TownEntityKind::Door;
    std::uint16_t X = 0;
    // Derived from the town head-level row; the MDT tables only store X.
    std::uint16_t Y = 0;
    // Keep the raw table bytes around so debug overlays can show what was parsed.
    std::uint8_t DoorType = 0;
    // Byte 2 in the raw NPC record: the sprite selector used by town rendering.
    std::uint8_t NpcSpriteSelector = 0;
    // Byte 4 in the raw NPC record: the animation phase used by town rendering.
    std::uint8_t NpcAnimationPhase = 0;
    // Byte 5 in the raw NPC record: the AI type used by the original update loop.
    std::uint8_t NpcAiType = 0;
    // Byte 6 in the raw NPC record: NPC flags, including the non-passable bit.
    std::uint8_t NpcFlags = 0;
    // Byte 7 in the raw NPC record: the dialogue lookup key.
    std::uint8_t NpcId = 0;
};

struct TownNpcPatrolBoundaries
{
    // Shared patrol range used by the town NPC walk AI.
    std::uint16_t MinimumX = 0;
    std::uint16_t MaximumX = 0;
};

struct TownTransitionData
{
    // Bit 0 selects the edge direction; the remaining bits route to the
    // dungeon transition path in the assembly.
    std::uint8_t Flags = 0;
    std::uint8_t DestinationMapId = 0;
    // Town transitions use this byte to select the NPC sprite group.
    std::uint8_t NpcSpriteGroupId = 0;
    // Town transitions use this byte to select the pattern bank.
    std::uint8_t PatternGroupId = 0;
};

struct TownNameRenderingInfo
{
    bool IsValid = false;
    std::uint16_t Pointer = 0;
    std::uint8_t LeftMargin = 0;
    std::uint8_t TopMargin = 0;
    std::uint8_t FineXOffset = 0;
    std::uint8_t CharacterCount = 0;
    std::string Text;
};

struct TownMapInfo
{
    std::uint16_t Width = 0;
    std::uint16_t Height = 8;
    std::size_t CellCount = 0;
    std::uint8_t MinimumTileIndex = 0;
    std::uint8_t MaximumTileIndex = 0;
    // town_descriptor_addr[3] selects the YMPD/CKPD background module.
    bool HasMiddleLayer = false;
    std::uint8_t TownId = 0;
    std::uint8_t TownPatternGroupId = 0;
    std::uint16_t TransitionTablePointer = 0;
    TownNameRenderingInfo TownNameInfo{};
    bool HasNpcPatrolBoundaries = false;
    TownNpcPatrolBoundaries NpcPatrolBoundaries{};
    std::vector<std::uint8_t> Cells;
    std::vector<TownEntityMarker> EntityMarkers;
    // npc_conversations_addr points to this table of FF-terminated dialog bytes.
    std::vector<std::vector<std::uint8_t>> NpcConversations;
    std::vector<TownTransitionData> TransitionData;
};

bool ParseTownMap(const std::vector<std::uint8_t>& Data, TownMapInfo& Output, std::string& ErrorMessage);
}
