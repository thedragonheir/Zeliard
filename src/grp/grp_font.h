#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <vector>

namespace Grp
{
struct FontGlyph
{
    std::array<std::uint8_t, 8> Rows{};
};

struct FontGroup
{
    std::vector<FontGlyph> Glyphs;
};

bool DecodeFirstFontGroup(const std::vector<std::uint8_t>& Unpacked, FontGroup& Output, std::string& ErrorMessage);
}
