#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <vector>

namespace Grp
{
struct PatternTile
{
    std::array<std::uint8_t, 64> Pixels{};
};

struct PatternBank
{
    std::vector<PatternTile> Tiles;
    std::uint8_t MinimumPaletteIndex = 0;
    std::uint8_t MaximumPaletteIndex = 0;
};

bool DecodePatternBank(const std::vector<std::uint8_t>& Unpacked, PatternBank& Output, std::string& ErrorMessage);
}
