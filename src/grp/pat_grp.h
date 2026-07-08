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
    std::uint8_t ModeByte = 0;
    std::array<std::uint8_t, 8> TransparencyMaskRows{};
};

struct PatternAnimationReplacement
{
    std::uint8_t SourceTile = 0;
    std::uint8_t ReplacementTile = 0;
};

struct PatternBank
{
    std::vector<PatternTile> Tiles;
    std::vector<std::uint8_t> SpecialTileIndices;
    std::vector<PatternAnimationReplacement> AnimationReplacementRules;
    std::uint8_t MinimumPaletteIndex = 0;
    std::uint8_t MaximumPaletteIndex = 0;
};

bool DecodePatternBank(const std::vector<std::uint8_t>& Unpacked, PatternBank& Output, std::string& ErrorMessage);
}
