#include "grp_font.h"

#include <algorithm>
#include <cstddef>

namespace Grp
{
namespace
{
constexpr std::size_t FontGroupCount = 3;
constexpr std::size_t FontHeaderSize = FontGroupCount * 2;
constexpr std::size_t GlyphBytes = 8;

std::uint16_t ReadLittleEndianWord(const std::vector<std::uint8_t>& Data, std::size_t Offset)
{
    return static_cast<std::uint16_t>(Data[Offset] | (static_cast<std::uint16_t>(Data[Offset + 1]) << 8));
}
}

bool DecodeFirstFontGroup(const std::vector<std::uint8_t>& Unpacked, FontGroup& Output, std::string& ErrorMessage)
{
    Output.Glyphs.clear();

    if (Unpacked.size() < FontHeaderSize)
    {
        ErrorMessage = "font.grp unpacked data is too small for the font group header";
        return false;
    }

    std::array<std::size_t, FontGroupCount> Offsets{};
    for (std::size_t Index = 0; Index < FontGroupCount; ++Index)
    {
        Offsets[Index] = ReadLittleEndianWord(Unpacked, Index * 2);
        if (Offsets[Index] < FontHeaderSize || Offsets[Index] >= Unpacked.size())
        {
            ErrorMessage = "font.grp contains an invalid font group offset";
            return false;
        }
    }

    const std::size_t FirstGroupStart = Offsets[0];
    std::size_t FirstGroupEnd = Unpacked.size();
    for (std::size_t Index = 1; Index < FontGroupCount; ++Index)
    {
        if (Offsets[Index] > FirstGroupStart)
        {
            FirstGroupEnd = std::min(FirstGroupEnd, Offsets[Index]);
        }
    }

    if (FirstGroupEnd <= FirstGroupStart)
    {
        ErrorMessage = "font.grp first font group has an invalid byte range";
        return false;
    }

    const std::size_t FirstGroupSize = FirstGroupEnd - FirstGroupStart;
    if (FirstGroupSize % GlyphBytes != 0)
    {
        ErrorMessage = "font.grp first font group is not aligned to 8-byte glyphs";
        return false;
    }

    const std::size_t GlyphCount = FirstGroupSize / GlyphBytes;
    Output.Glyphs.resize(GlyphCount);

    for (std::size_t GlyphIndex = 0; GlyphIndex < GlyphCount; ++GlyphIndex)
    {
        const std::size_t GlyphOffset = FirstGroupStart + GlyphIndex * GlyphBytes;
        for (std::size_t Row = 0; Row < GlyphBytes; ++Row)
        {
            Output.Glyphs[GlyphIndex].Rows[Row] = Unpacked[GlyphOffset + Row];
        }
    }

    return true;
}
}
