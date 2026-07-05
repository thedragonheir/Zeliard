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
    // Byte 7 in the raw NPC record: the dialogue lookup key.
    std::uint8_t NpcId = 0;
};

struct TownMapInfo
{
    std::uint16_t Width = 0;
    std::uint16_t Height = 8;
    std::size_t CellCount = 0;
    std::uint8_t MinimumTileIndex = 0;
    std::uint8_t MaximumTileIndex = 0;
    std::vector<std::uint8_t> Cells;
    std::vector<TownEntityMarker> EntityMarkers;
};

bool ParseTownMap(const std::vector<std::uint8_t>& Data, TownMapInfo& Output, std::string& ErrorMessage);
}
