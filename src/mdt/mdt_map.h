#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace Mdt
{
struct TownMapInfo
{
    std::uint16_t Width = 0;
    std::uint16_t Height = 8;
    std::size_t CellCount = 0;
    std::uint8_t MinimumTileIndex = 0;
    std::uint8_t MaximumTileIndex = 0;
    std::vector<std::uint8_t> Cells;
};

bool ParseTownMap(const std::vector<std::uint8_t>& Data, TownMapInfo& Output, std::string& ErrorMessage);
}
