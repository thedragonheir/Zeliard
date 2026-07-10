#include "font_grp.hpp"

#include <algorithm>
#include <cstddef>
#include <vector>

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

bool ReadFontGroupRange(const std::vector<std::uint8_t>& Unpacked, std::size_t GroupIndex, std::size_t& Start, std::size_t& End, std::string& ErrorMessage)
{
    if (Unpacked.size() < FontHeaderSize)
    {
        ErrorMessage = "font.grp unpacked data is too small for the font group header";
        return false;
    }

    if (GroupIndex >= FontGroupCount)
    {
        ErrorMessage = "font.grp requested font group is out of range";
        return false;
    }

    std::array<std::size_t, FontGroupCount> Offsets{};
    std::vector<std::size_t> ValidOffsets;
    for (std::size_t Index = 0; Index < FontGroupCount; ++Index)
    {
        Offsets[Index] = ReadLittleEndianWord(Unpacked, Index * 2);
        if (Offsets[Index] >= FontHeaderSize && Offsets[Index] < Unpacked.size())
        {
            ValidOffsets.push_back(Offsets[Index]);
        }
    }

    Start = Offsets[GroupIndex];
    if (Start < FontHeaderSize || Start >= Unpacked.size())
    {
        ErrorMessage = "font.grp contains an invalid font group offset";
        return false;
    }

    std::sort(ValidOffsets.begin(), ValidOffsets.end());
    ValidOffsets.erase(std::unique(ValidOffsets.begin(), ValidOffsets.end()), ValidOffsets.end());

    End = Unpacked.size();
    for (std::size_t Offset : ValidOffsets)
    {
        if (Offset > Start)
        {
            End = Offset;
            break;
        }
    }

    if (End <= Start)
    {
        ErrorMessage = "font.grp font group has an invalid byte range";
        return false;
    }

    return true;
}

bool DecodeFontGroupAtIndex(const std::vector<std::uint8_t>& Unpacked, std::size_t GroupIndex, FontGroup& Output, std::string& ErrorMessage, std::string* WarningMessage)
{
    Output.Glyphs.clear();
    if (WarningMessage != nullptr)
    {
        WarningMessage->clear();
    }

    std::size_t GroupStart = 0;
    std::size_t GroupEnd = 0;
    if (!ReadFontGroupRange(Unpacked, GroupIndex, GroupStart, GroupEnd, ErrorMessage))
    {
        return false;
    }

    const std::size_t GroupSize = GroupEnd - GroupStart;
    if (GroupSize < GlyphBytes)
    {
        ErrorMessage = "font.grp font group is too small for 8x8 glyphs";
        return false;
    }

    const std::size_t TrailingBytes = GroupSize % GlyphBytes;
    if (TrailingBytes > 1)
    {
        ErrorMessage = "font.grp font group has unexpected trailing bytes";
        return false;
    }

    const std::size_t GlyphCount = GroupSize / GlyphBytes;
    Output.Glyphs.resize(GlyphCount);

    for (std::size_t GlyphIndex = 0; GlyphIndex < GlyphCount; ++GlyphIndex)
    {
        const std::size_t GlyphOffset = GroupStart + GlyphIndex * GlyphBytes;
        for (std::size_t Row = 0; Row < GlyphBytes; ++Row)
        {
            Output.Glyphs[GlyphIndex].Rows[Row] = Unpacked[GlyphOffset + Row];
        }
    }

    if (TrailingBytes == 1)
    {
        if (WarningMessage != nullptr)
        {
            *WarningMessage = "font.grp group " + std::to_string(GroupIndex) + " has 1 trailing byte; ignoring it";
        }
    }

    return true;
}
}

bool DecodeFontGroup(const std::vector<std::uint8_t>& Unpacked, std::size_t GroupIndex, FontGroup& Output, std::string& ErrorMessage, std::string* WarningMessage)
{
    const bool Success = DecodeFontGroupAtIndex(Unpacked, GroupIndex, Output, ErrorMessage, WarningMessage);
    if (Success)
    {
        ErrorMessage.clear();
    }

    return Success;
}

bool DecodeFirstFontGroup(const std::vector<std::uint8_t>& Unpacked, FontGroup& Output, std::string& ErrorMessage, std::string* WarningMessage)
{
    return DecodeFontGroup(Unpacked, 0, Output, ErrorMessage, WarningMessage);
}
}
