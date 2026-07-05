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
    // Keep the raw table bytes around so debug overlays can show what was parsed.
    std::uint8_t DoorType = 0;
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
