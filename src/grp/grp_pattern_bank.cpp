#include "grp_pattern_bank.h"

#include <algorithm>
#include <cstddef>

namespace Grp
{
namespace
{
constexpr std::size_t PatternHeaderSize = 256;
constexpr std::size_t PatternCount = 157;
constexpr std::size_t PatternTileBytes = 48;
constexpr std::size_t PatternExpectedSize = PatternHeaderSize + PatternCount * PatternTileBytes;

std::uint16_t ReadBigEndianWord(const std::vector<std::uint8_t>& Data, std::size_t Offset)
{
    return static_cast<std::uint16_t>((static_cast<std::uint16_t>(Data[Offset]) << 8) | Data[Offset + 1]);
}

std::uint16_t RotateLeft16(std::uint16_t Value)
{
    return static_cast<std::uint16_t>((Value << 1) | (Value >> 15));
}

void DecodeFourPixels(std::uint16_t& PlaneR, std::uint16_t& PlaneG, std::uint16_t& PlaneB, std::array<std::uint8_t, 4>& Output)
{
    for (std::size_t PixelIndex = 0; PixelIndex < Output.size(); ++PixelIndex)
    {
        std::uint8_t Pixel = 0;

        PlaneB = RotateLeft16(PlaneB);
        Pixel = static_cast<std::uint8_t>((Pixel << 1) | (PlaneB & 1));
        PlaneG = RotateLeft16(PlaneG);
        Pixel = static_cast<std::uint8_t>((Pixel << 1) | (PlaneG & 1));
        PlaneR = RotateLeft16(PlaneR);
        Pixel = static_cast<std::uint8_t>((Pixel << 1) | (PlaneR & 1));
        PlaneB = RotateLeft16(PlaneB);
        Pixel = static_cast<std::uint8_t>((Pixel << 1) | (PlaneB & 1));
        PlaneG = RotateLeft16(PlaneG);
        Pixel = static_cast<std::uint8_t>((Pixel << 1) | (PlaneG & 1));
        PlaneR = RotateLeft16(PlaneR);
        Pixel = static_cast<std::uint8_t>((Pixel << 1) | (PlaneR & 1));

        Output[PixelIndex] = static_cast<std::uint8_t>(Pixel & 0x3F);
    }
}

void DecodeEightPixels(std::uint16_t& PlaneR, std::uint16_t& PlaneG, std::uint16_t& PlaneB, std::array<std::uint8_t, 8>& Output)
{
    std::array<std::uint8_t, 4> LeftHalf{};
    std::array<std::uint8_t, 4> RightHalf{};

    DecodeFourPixels(PlaneR, PlaneG, PlaneB, LeftHalf);
    DecodeFourPixels(PlaneR, PlaneG, PlaneB, RightHalf);

    std::copy(LeftHalf.begin(), LeftHalf.end(), Output.begin());
    std::copy(RightHalf.begin(), RightHalf.end(), Output.begin() + static_cast<std::ptrdiff_t>(LeftHalf.size()));
}

bool DecodePatternTile(const std::vector<std::uint8_t>& Unpacked, std::size_t PatternIndex, PatternTile& Output, std::uint8_t& MinimumPaletteIndex, std::uint8_t& MaximumPaletteIndex, std::string& ErrorMessage)
{
    const std::size_t HeaderIndex = 6 + PatternIndex;
    const std::uint8_t Mode = Unpacked[HeaderIndex] > 4 ? 0 : Unpacked[HeaderIndex];
    const std::size_t TileOffset = PatternHeaderSize + PatternIndex * PatternTileBytes;

    for (std::size_t RowIndex = 0; RowIndex < 8; ++RowIndex)
    {
        const std::size_t RowOffset = TileOffset + RowIndex * 6;
        const std::uint16_t Word0 = ReadBigEndianWord(Unpacked, RowOffset);
        const std::uint16_t Word1 = ReadBigEndianWord(Unpacked, RowOffset + 2);
        const std::uint16_t Word2 = ReadBigEndianWord(Unpacked, RowOffset + 4);

        std::uint16_t PlaneR = 0;
        std::uint16_t PlaneG = 0;
        std::uint16_t PlaneB = 0;

        switch (Mode)
        {
        case 0:
        case 4:
            PlaneR = Word0;
            PlaneG = Word1;
            PlaneB = Word2;
            break;

        case 1:
            PlaneR = Word0;
            PlaneG = Word1;
            PlaneB = 0;
            break;

        case 2:
            PlaneR = Word0;
            PlaneG = 0;
            PlaneB = Word2;
            break;

        case 3:
            PlaneR = 0;
            PlaneG = Word1;
            PlaneB = Word2;
            break;
        }

        std::array<std::uint8_t, 8> RowPixels{};
        DecodeEightPixels(PlaneR, PlaneG, PlaneB, RowPixels);

        for (std::size_t ColumnIndex = 0; ColumnIndex < RowPixels.size(); ++ColumnIndex)
        {
            const std::uint8_t Pixel = RowPixels[ColumnIndex];
            if (Pixel > 63)
            {
                ErrorMessage = "cpat.grp decoded palette index out of range";
                return false;
            }

            Output.Pixels[RowIndex * 8 + ColumnIndex] = Pixel;
            MinimumPaletteIndex = std::min(MinimumPaletteIndex, Pixel);
            MaximumPaletteIndex = std::max(MaximumPaletteIndex, Pixel);
        }
    }

    return true;
}
}

bool DecodePatternBank(const std::vector<std::uint8_t>& Unpacked, PatternBank& Output, std::string& ErrorMessage)
{
    Output.Tiles.clear();
    Output.MinimumPaletteIndex = 0;
    Output.MaximumPaletteIndex = 0;

    if (Unpacked.size() != PatternExpectedSize)
    {
        ErrorMessage = "cpat.grp unpacked size mismatch: expected " + std::to_string(PatternExpectedSize) + " bytes, got " + std::to_string(Unpacked.size()) + " bytes";
        return false;
    }

    Output.Tiles.resize(PatternCount);

    std::uint8_t MinimumPaletteIndex = 63;
    std::uint8_t MaximumPaletteIndex = 0;
    for (std::size_t PatternIndex = 0; PatternIndex < PatternCount; ++PatternIndex)
    {
        if (!DecodePatternTile(Unpacked, PatternIndex, Output.Tiles[PatternIndex], MinimumPaletteIndex, MaximumPaletteIndex, ErrorMessage))
        {
            return false;
        }
    }

    Output.MinimumPaletteIndex = MinimumPaletteIndex;
    Output.MaximumPaletteIndex = MaximumPaletteIndex;
    ErrorMessage.clear();
    return true;
}
}
