#include "pat_grp.hpp"

#include <algorithm>
#include <cstddef>

namespace Grp
{
namespace
{
constexpr std::size_t PatternHeaderSize = 256;
constexpr std::size_t PatternTileBytes = 48;

std::uint16_t ReadLittleEndianWord(const std::vector<std::uint8_t>& Data, std::size_t Offset)
{
    return static_cast<std::uint16_t>(Data[Offset] | (static_cast<std::uint16_t>(Data[Offset + 1]) << 8));
}

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

std::uint8_t DecodeTransparencyMaskByte(std::uint16_t MaskPlane)
{
    std::uint8_t Output = 0;

    for (std::size_t PixelIndex = 0; PixelIndex < 8; ++PixelIndex)
    {
        const std::uint8_t FirstBit = static_cast<std::uint8_t>((MaskPlane & 0x8000) != 0);
        MaskPlane = RotateLeft16(MaskPlane);

        const std::uint8_t SecondBit = static_cast<std::uint8_t>((MaskPlane & 0x8000) != 0);
        MaskPlane = RotateLeft16(MaskPlane);

        const std::uint8_t TransparencyBit = static_cast<std::uint8_t>((FirstBit != 0 && SecondBit != 0) ? 1 : 0);
        Output = static_cast<std::uint8_t>((Output << 1) | TransparencyBit);
    }

    return Output;
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

bool DecodeAnimationReplacementRules(const std::vector<std::uint8_t>& Unpacked, std::size_t ReplacementTableOffset,
    std::vector<PatternAnimationReplacement>& Output, std::string& ErrorMessage)
{
    if (ReplacementTableOffset >= Unpacked.size())
    {
        ErrorMessage = "pattern bank animation replacement table offset is out of range";
        return false;
    }

    const std::uint8_t ReplacementCount = Unpacked[ReplacementTableOffset];
    const std::size_t ReplacementTableSize = 1 + static_cast<std::size_t>(ReplacementCount) * 2;
    if (ReplacementTableOffset + ReplacementTableSize > Unpacked.size())
    {
        ErrorMessage = "pattern bank animation replacement table is truncated";
        return false;
    }

    Output.clear();
    Output.reserve(ReplacementCount);
    for (std::size_t ReplacementIndex = 0; ReplacementIndex < ReplacementCount; ++ReplacementIndex)
    {
        const std::size_t EntryOffset = ReplacementTableOffset + 1 + ReplacementIndex * 2;
        Output.push_back(PatternAnimationReplacement{
            Unpacked[EntryOffset],
            Unpacked[EntryOffset + 1]
        });
    }

    return true;
}

bool DecodeSpecialTileIndices(const std::vector<std::uint8_t>& Unpacked, std::size_t SpecialTileListOffset,
    std::vector<std::uint8_t>& Output, std::string& ErrorMessage)
{
    if (SpecialTileListOffset >= Unpacked.size())
    {
        ErrorMessage = "pattern bank special tile list offset is out of range";
        return false;
    }

    const std::uint8_t SpecialTileCount = Unpacked[SpecialTileListOffset];
    const std::size_t SpecialTileListSize = 1 + static_cast<std::size_t>(SpecialTileCount);
    if (SpecialTileListOffset + SpecialTileListSize > Unpacked.size())
    {
        ErrorMessage = "pattern bank special tile list is truncated";
        return false;
    }

    Output.assign(Unpacked.begin() + static_cast<std::ptrdiff_t>(SpecialTileListOffset + 1),
        Unpacked.begin() + static_cast<std::ptrdiff_t>(SpecialTileListOffset + SpecialTileListSize));
    return true;
}

bool DecodePatternTile(const std::vector<std::uint8_t>& Unpacked, std::size_t PatternIndex, std::size_t ModeTableOffset,
    PatternTile& Output, std::uint8_t& MinimumPaletteIndex, std::uint8_t& MaximumPaletteIndex, std::string& ErrorMessage)
{
    const std::size_t HeaderIndex = ModeTableOffset + PatternIndex;
    if (HeaderIndex >= Unpacked.size())
    {
        ErrorMessage = "pattern bank mode table is truncated";
        return false;
    }

    Output.ModeByte = Unpacked[HeaderIndex];
    const std::uint8_t Mode = Output.ModeByte > 4 ? 0 : Output.ModeByte;
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
        std::uint8_t TransparencyMask = 0;

        switch (Mode)
        {
        case 0:
            PlaneR = Word0;
            PlaneG = Word1;
            PlaneB = Word2;
            TransparencyMask = 0;
            break;

        case 1:
            PlaneR = Word0;
            PlaneG = Word1;
            PlaneB = 0;
            TransparencyMask = DecodeTransparencyMaskByte(Word2);
            break;

        case 2:
            PlaneR = Word0;
            PlaneG = 0;
            PlaneB = Word2;
            TransparencyMask = DecodeTransparencyMaskByte(Word1);
            break;

        case 3:
            PlaneR = 0;
            PlaneG = Word1;
            PlaneB = Word2;
            TransparencyMask = DecodeTransparencyMaskByte(Word0);
            break;

        case 4:
            PlaneR = Word0;
            PlaneG = Word1;
            PlaneB = Word2;
            TransparencyMask = 0xFF;
            break;
        }

        std::array<std::uint8_t, 8> RowPixels{};
        DecodeEightPixels(PlaneR, PlaneG, PlaneB, RowPixels);
        Output.TransparencyMaskRows[RowIndex] = TransparencyMask;

        for (std::size_t ColumnIndex = 0; ColumnIndex < RowPixels.size(); ++ColumnIndex)
        {
            const std::uint8_t Pixel = RowPixels[ColumnIndex];
            if (Pixel > 63)
            {
                ErrorMessage = "pattern bank decoded palette index out of range";
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
    Output.SpecialTileIndices.clear();
    Output.AnimationReplacementRules.clear();
    Output.MinimumPaletteIndex = 0;
    Output.MaximumPaletteIndex = 0;

    if (Unpacked.size() < PatternHeaderSize || (Unpacked.size() - PatternHeaderSize) % PatternTileBytes != 0)
    {
        ErrorMessage = "pattern bank unpacked size does not match the 256-byte header plus 48-byte tiles: got "
            + std::to_string(Unpacked.size()) + " bytes";
        return false;
    }

    const std::size_t PatternCount = (Unpacked.size() - PatternHeaderSize) / PatternTileBytes;
    const std::size_t ModeTableOffset = ReadLittleEndianWord(Unpacked, 0);
    const std::size_t SpecialTileListOffset = ReadLittleEndianWord(Unpacked, 2);
    const std::size_t ReplacementTableOffset = ReadLittleEndianWord(Unpacked, 4);

    if (ModeTableOffset + PatternCount > SpecialTileListOffset || SpecialTileListOffset > ReplacementTableOffset)
    {
        ErrorMessage = "pattern bank header pointers are inconsistent";
        return false;
    }

    Output.Tiles.resize(PatternCount);

    std::uint8_t MinimumPaletteIndex = 63;
    std::uint8_t MaximumPaletteIndex = 0;
    for (std::size_t PatternIndex = 0; PatternIndex < PatternCount; ++PatternIndex)
    {
        if (!DecodePatternTile(Unpacked, PatternIndex, ModeTableOffset, Output.Tiles[PatternIndex],
                MinimumPaletteIndex, MaximumPaletteIndex, ErrorMessage))
        {
            return false;
        }
    }

    if (!DecodeSpecialTileIndices(Unpacked, SpecialTileListOffset, Output.SpecialTileIndices, ErrorMessage))
    {
        return false;
    }

    if (!DecodeAnimationReplacementRules(Unpacked, ReplacementTableOffset, Output.AnimationReplacementRules, ErrorMessage))
    {
        return false;
    }

    Output.MinimumPaletteIndex = MinimumPaletteIndex;
    Output.MaximumPaletteIndex = MaximumPaletteIndex;
    ErrorMessage.clear();
    return true;
}
}
