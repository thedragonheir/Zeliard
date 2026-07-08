#include "man_grp.h"

#include "grp_unpack.h"

#include <algorithm>
#include <array>
#include <cstddef>
#include <vector>

namespace Grp
{
namespace
{
constexpr std::size_t NpcFrameCount = 40;
constexpr std::size_t NpcTilesPerFrame = 6;
constexpr std::size_t NpcTilesAcross = 2;
constexpr std::size_t NpcTilesDown = 3;
constexpr std::size_t NpcTileWidth = 8;
constexpr std::size_t NpcTileHeight = 8;
constexpr std::size_t NpcFrameWidth = NpcTilesAcross * NpcTileWidth;
constexpr std::size_t NpcFrameHeight = NpcTilesDown * NpcTileHeight;
constexpr std::size_t NpcIndexTableBytes = 256;
constexpr std::size_t NpcIndexBytes = NpcFrameCount * NpcTilesPerFrame;
constexpr std::size_t NpcTileBytes = 48;
constexpr std::size_t TownHeroFrameCount = 10;
constexpr std::size_t DungeonHeroFrameCount = 91;
constexpr std::size_t DungeonHeroTilesPerFrame = 9;
constexpr std::size_t DungeonHeroTilesAcross = 3;
constexpr std::size_t DungeonHeroTilesDown = 3;
constexpr std::size_t DungeonHeroTileWidth = 8;
constexpr std::size_t DungeonHeroTileHeight = 8;
constexpr std::size_t DungeonHeroFrameHeaderBytes = DungeonHeroFrameCount * DungeonHeroTilesPerFrame;
constexpr std::size_t DungeonHeroTileBytes = 32;

constexpr std::array<std::uint8_t, TownHeroFrameCount * NpcTilesPerFrame> TownHeroFrameTileIndices{
    0x00, 0x02, 0x04, 0x01, 0x03, 0x05,
    0x06, 0x08, 0x0A, 0x07, 0x09, 0x0B,
    0x00, 0x0C, 0x0E, 0x01, 0x0D, 0x0F,
    0x06, 0x10, 0x12, 0x07, 0x11, 0x13,
    0x14, 0x16, 0x18, 0x15, 0x17, 0x19,
    0x1A, 0x1C, 0x1E, 0x1B, 0x1D, 0x1F,
    0x20, 0x22, 0x24, 0x21, 0x23, 0x25,
    0x1A, 0x26, 0x28, 0x1B, 0x27, 0x29,
    0x20, 0x2A, 0x2C, 0x21, 0x2B, 0x2D,
    0x14, 0x16, 0x18, 0x15, 0x17, 0x19
};

constexpr std::array<std::uint8_t, 16> DungeonHeroPaletteDecodeTable{
    0x00, 0x01, 0x02, 0x03,
    0x08, 0x09, 0x0A, 0x0B,
    0x10, 0x11, 0x12, 0x13,
    0x18, 0x19, 0x1A, 0x1B
};

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

void PopulateVisiblePixelsFromDrawModes(const std::array<std::uint8_t, NpcSpriteFrame::PixelCount>& DrawModes,
    std::array<std::uint8_t, NpcSpriteFrame::PixelCount>& VisiblePixels)
{
    for (std::size_t PixelIndex = 0; PixelIndex < DrawModes.size(); ++PixelIndex)
    {
        VisiblePixels[PixelIndex] = DrawModes[PixelIndex] == TransparentDrawMode ? 0 : 1;
    }
}

bool DecodeNpcTile(const std::vector<std::uint8_t>& Unpacked, std::size_t TileOffset,
    std::array<std::uint8_t, NpcTileWidth * NpcTileHeight>& Output,
    std::array<std::uint8_t, NpcTileWidth * NpcTileHeight>* DrawModes,
    std::string& ErrorMessage)
{
    Output.fill(0);
    if (DrawModes != nullptr)
    {
        DrawModes->fill(TransparentDrawMode);
    }

    for (std::size_t RowIndex = 0; RowIndex < NpcTileHeight; ++RowIndex)
    {
        const std::size_t RowOffset = TileOffset + RowIndex * 6;
        if (RowOffset + 6 > Unpacked.size())
        {
            ErrorMessage = "sprite tile data is truncated";
            return false;
        }

        std::uint16_t PlaneR = ReadBigEndianWord(Unpacked, RowOffset);
        std::uint16_t PlaneG = ReadBigEndianWord(Unpacked, RowOffset + 2);
        std::uint16_t PlaneB = ReadBigEndianWord(Unpacked, RowOffset + 4);

        const std::uint16_t TransparencyMask = static_cast<std::uint16_t>(~(PlaneR | PlaneG | PlaneB));
        const std::uint16_t WhiteMask = static_cast<std::uint16_t>(PlaneR & PlaneG & PlaneB);
        PlaneR = static_cast<std::uint16_t>(PlaneR & static_cast<std::uint16_t>(~WhiteMask));
        PlaneG = static_cast<std::uint16_t>(PlaneG & static_cast<std::uint16_t>(~WhiteMask));
        PlaneB = static_cast<std::uint16_t>(PlaneB & static_cast<std::uint16_t>(~WhiteMask));

        std::array<std::uint8_t, 8> RowPixels{};
        DecodeEightPixels(PlaneR, PlaneG, PlaneB, RowPixels);
        std::copy(RowPixels.begin(), RowPixels.end(), Output.begin() + static_cast<std::ptrdiff_t>(RowIndex * NpcTileWidth));

        if (DrawModes != nullptr)
        {
            for (std::size_t ColumnIndex = 0; ColumnIndex < NpcTileWidth; ++ColumnIndex)
            {
                const std::size_t PixelIndex = RowIndex * NpcTileWidth + ColumnIndex;
                const bool IsTransparent = ((TransparencyMask >> (14 - ColumnIndex * 2)) & 0x03) == 0x03;

                if (IsTransparent)
                {
                    (*DrawModes)[PixelIndex] = TransparentDrawMode;
                }
                else if (RowPixels[ColumnIndex] == 0)
                {
                    // The ASM mask keeps these pixels opaque, so zero-index pixels stay black here.
                    (*DrawModes)[PixelIndex] = BlackDrawMode;
                }
                else
                {
                    (*DrawModes)[PixelIndex] = ColorDrawMode;
                }
            }
        }
    }

    return true;
}

bool DecodeNpcFrame(const std::vector<std::uint8_t>& Unpacked, std::size_t TileBankOffset, std::size_t TileCount,
    std::size_t FrameIndex, std::array<std::uint8_t, NpcFrameWidth * NpcFrameHeight>& Output,
    std::array<std::uint8_t, NpcFrameWidth * NpcFrameHeight>* DrawModes,
    std::uint8_t& MinimumPaletteIndex, std::uint8_t& MaximumPaletteIndex, std::string& ErrorMessage)
{
    Output.fill(0);
    if (DrawModes != nullptr)
    {
        DrawModes->fill(TransparentDrawMode);
    }

    const std::size_t FrameIndexOffset = FrameIndex * NpcTilesPerFrame;
    for (std::size_t TileColumn = 0; TileColumn < NpcTilesAcross; ++TileColumn)
    {
        for (std::size_t TileRow = 0; TileRow < NpcTilesDown; ++TileRow)
        {
            const std::size_t SourceIndexOffset = FrameIndexOffset + TileColumn * NpcTilesDown + TileRow;
            const std::uint8_t SourceIndex = Unpacked[SourceIndexOffset];
            if (SourceIndex == 0)
            {
                ErrorMessage = "mman.grp frame " + std::to_string(FrameIndex) + " contains a zero tile index";
                return false;
            }

            const std::size_t TileIndex = static_cast<std::size_t>(SourceIndex - 1);
            if (TileIndex >= TileCount)
            {
                ErrorMessage = "mman.grp frame " + std::to_string(FrameIndex) + " references tile index " + std::to_string(TileIndex) + " outside the tile bank";
                return false;
            }

            std::array<std::uint8_t, NpcTileWidth * NpcTileHeight> TilePixels{};
            std::array<std::uint8_t, NpcTileWidth * NpcTileHeight> TileDrawModes{};
            const std::size_t TileOffset = TileBankOffset + TileIndex * NpcTileBytes;
            if (!DecodeNpcTile(Unpacked, TileOffset, TilePixels, DrawModes != nullptr ? &TileDrawModes : nullptr, ErrorMessage))
            {
                return false;
            }

            const std::size_t DestinationX = TileColumn * NpcTileWidth;
            const std::size_t DestinationY = TileRow * NpcTileHeight;
            for (std::size_t Row = 0; Row < NpcTileHeight; ++Row)
            {
                for (std::size_t Column = 0; Column < NpcTileWidth; ++Column)
                {
                    const std::uint8_t Pixel = TilePixels[Row * NpcTileWidth + Column];
                    const std::size_t SourcePixelIndex = Row * NpcTileWidth + Column;
                    const std::size_t DestinationPixelIndex = (DestinationY + Row) * NpcFrameWidth + (DestinationX + Column);
                    Output[DestinationPixelIndex] = Pixel;
                    if (DrawModes != nullptr)
                    {
                        (*DrawModes)[DestinationPixelIndex] = TileDrawModes[SourcePixelIndex];
                    }
                    MinimumPaletteIndex = std::min(MinimumPaletteIndex, Pixel);
                    MaximumPaletteIndex = std::max(MaximumPaletteIndex, Pixel);
                }
            }
        }
    }

    return true;
}

bool DecodeTownHeroFrame(const std::vector<std::uint8_t>& Unpacked, std::size_t FrameIndex,
    std::array<std::uint8_t, NpcFrameWidth * NpcFrameHeight>& Output,
    std::array<std::uint8_t, NpcFrameWidth * NpcFrameHeight>* DrawModes,
    std::string& ErrorMessage)
{
    Output.fill(0);
    if (DrawModes != nullptr)
    {
        DrawModes->fill(TransparentDrawMode);
    }

    const std::size_t TileCount = Unpacked.size() / NpcTileBytes;
    if (TileCount == 0)
    {
        ErrorMessage = "tman.grp tile bank does not contain any complete 8x8 tiles";
        return false;
    }

    const std::size_t FrameIndexOffset = FrameIndex * NpcTilesPerFrame;
    for (std::size_t TileColumn = 0; TileColumn < NpcTilesAcross; ++TileColumn)
    {
        for (std::size_t TileRow = 0; TileRow < NpcTilesDown; ++TileRow)
        {
            const std::size_t SourceIndexOffset = FrameIndexOffset + TileColumn * NpcTilesDown + TileRow;
            const std::size_t TileIndex = static_cast<std::size_t>(TownHeroFrameTileIndices[SourceIndexOffset]);
            if (TileIndex >= TileCount)
            {
                ErrorMessage = "tman.grp frame " + std::to_string(FrameIndex) + " references tile index "
                    + std::to_string(TileIndex) + " outside the tile bank";
                return false;
            }

            std::array<std::uint8_t, NpcTileWidth * NpcTileHeight> TilePixels{};
            std::array<std::uint8_t, NpcTileWidth * NpcTileHeight> TileDrawModes{};
            const std::size_t TileOffset = TileIndex * NpcTileBytes;
            if (!DecodeNpcTile(Unpacked, TileOffset, TilePixels, DrawModes != nullptr ? &TileDrawModes : nullptr, ErrorMessage))
            {
                return false;
            }

            const std::size_t DestinationX = TileColumn * NpcTileWidth;
            const std::size_t DestinationY = TileRow * NpcTileHeight;
            for (std::size_t Row = 0; Row < NpcTileHeight; ++Row)
            {
                for (std::size_t Column = 0; Column < NpcTileWidth; ++Column)
                {
                    const std::size_t SourcePixelIndex = Row * NpcTileWidth + Column;
                    const std::size_t DestinationPixelIndex = (DestinationY + Row) * NpcFrameWidth + (DestinationX + Column);
                    Output[DestinationPixelIndex] = TilePixels[SourcePixelIndex];
                    if (DrawModes != nullptr)
                    {
                        (*DrawModes)[DestinationPixelIndex] = TileDrawModes[SourcePixelIndex];
                    }
                }
            }
        }
    }

    return true;
}

void DecodeDungeonHeroTile(const std::array<std::uint8_t, DungeonHeroTileBytes>& TileBytes,
    std::array<std::uint8_t, DungeonHeroTileWidth * DungeonHeroTileHeight>& Output,
    std::array<std::uint8_t, DungeonHeroTileWidth * DungeonHeroTileHeight>& VisiblePixels)
{
    Output.fill(0);
    VisiblePixels.fill(0);

    for (std::size_t RowIndex = 0; RowIndex < DungeonHeroTileHeight; ++RowIndex)
    {
        const std::size_t RowOffset = RowIndex * 4;
        const std::uint16_t Plane0 = static_cast<std::uint16_t>(
            (static_cast<std::uint16_t>(TileBytes[RowOffset]) << 8) | TileBytes[RowOffset + 1]);
        const std::uint16_t Plane1 = static_cast<std::uint16_t>(
            (static_cast<std::uint16_t>(TileBytes[RowOffset + 2]) << 8) | TileBytes[RowOffset + 3]);
        const std::uint16_t Combined = static_cast<std::uint16_t>(Plane0 | Plane1);
        const std::uint16_t RowMask = static_cast<std::uint16_t>(~(Combined | (Combined >> 1) | (Combined << 2)));

        for (std::size_t ColumnIndex = 0; ColumnIndex < DungeonHeroTileWidth; ++ColumnIndex)
        {
            const std::size_t HighBitShift = 15 - ColumnIndex * 2;
            const std::size_t LowBitShift = 14 - ColumnIndex * 2;
            const std::uint8_t PaletteNibble = static_cast<std::uint8_t>(
                (((Plane1 >> HighBitShift) & 1) << 3)
                | (((Plane0 >> HighBitShift) & 1) << 2)
                | (((Plane1 >> LowBitShift) & 1) << 1)
                | ((Plane0 >> LowBitShift) & 1));
            const bool IsTransparent = ((RowMask >> LowBitShift) & 0x03) == 0x03;
            const std::size_t PixelIndex = RowIndex * DungeonHeroTileWidth + ColumnIndex;

            if (!IsTransparent)
            {
                Output[PixelIndex] = DungeonHeroPaletteDecodeTable[PaletteNibble];
                VisiblePixels[PixelIndex] = 1;
            }
        }
    }
}

bool ReadDungeonHeroTile(const std::vector<std::uint8_t>& Unpacked, std::size_t TileBankOffset, std::size_t TileIndex,
    std::array<std::uint8_t, DungeonHeroTileBytes>& Output, std::string& ErrorMessage)
{
    const std::size_t TileOffset = TileBankOffset + TileIndex * DungeonHeroTileBytes;
    if (TileOffset >= Unpacked.size())
    {
        ErrorMessage = "fman.grp references tile index " + std::to_string(TileIndex) + " outside the tile bank";
        return false;
    }

    Output.fill(0);

    // fman.grp's unpacked tile bank ends with a short final tile in the Python viewer,
    // so pad the available bytes instead of rejecting that last partial definition.
    const std::size_t AvailableBytes = std::min(DungeonHeroTileBytes, Unpacked.size() - TileOffset);
    std::copy_n(Unpacked.begin() + static_cast<std::ptrdiff_t>(TileOffset),
        AvailableBytes, Output.begin());
    return true;
}

bool DecodeDungeonHeroFrame(const std::vector<std::uint8_t>& Unpacked, std::size_t FrameIndex,
    std::array<std::uint8_t, DungeonHeroSpriteFrame::PixelCount>& Output,
    std::array<std::uint8_t, DungeonHeroSpriteFrame::PixelCount>& VisiblePixels,
    std::string& ErrorMessage)
{
    Output.fill(0);
    VisiblePixels.fill(0);

    if (Unpacked.size() < DungeonHeroFrameHeaderBytes)
    {
        ErrorMessage = "fman.grp unpacked data is too small for the frame header";
        return false;
    }

    const std::size_t TileBankOffset = DungeonHeroFrameHeaderBytes;
    const std::size_t FrameOffset = FrameIndex * DungeonHeroTilesPerFrame;
    for (std::size_t TileRow = 0; TileRow < DungeonHeroTilesDown; ++TileRow)
    {
        for (std::size_t TileColumn = 0; TileColumn < DungeonHeroTilesAcross; ++TileColumn)
        {
            const std::size_t SourceIndexOffset = FrameOffset + TileRow * DungeonHeroTilesAcross + TileColumn;
            const std::uint8_t TileIndex = Unpacked[SourceIndexOffset];
            if (TileIndex == 0)
            {
                continue;
            }

            std::array<std::uint8_t, DungeonHeroTileBytes> TileBytes{};
            if (!ReadDungeonHeroTile(Unpacked, TileBankOffset, TileIndex, TileBytes, ErrorMessage))
            {
                ErrorMessage = "fman.grp frame " + std::to_string(FrameIndex) + " " + ErrorMessage;
                return false;
            }

            std::array<std::uint8_t, DungeonHeroTileWidth * DungeonHeroTileHeight> TilePixels{};
            std::array<std::uint8_t, DungeonHeroTileWidth * DungeonHeroTileHeight> TileVisiblePixels{};
            DecodeDungeonHeroTile(TileBytes, TilePixels, TileVisiblePixels);

            const std::size_t DestinationX = TileColumn * DungeonHeroTileWidth;
            const std::size_t DestinationY = TileRow * DungeonHeroTileHeight;
            for (std::size_t Row = 0; Row < DungeonHeroTileHeight; ++Row)
            {
                for (std::size_t Column = 0; Column < DungeonHeroTileWidth; ++Column)
                {
                    const std::size_t SourcePixelIndex = Row * DungeonHeroTileWidth + Column;
                    const std::size_t DestinationPixelIndex =
                        (DestinationY + Row) * DungeonHeroSpriteFrame::FrameWidth + (DestinationX + Column);
                    Output[DestinationPixelIndex] = TilePixels[SourcePixelIndex];
                    VisiblePixels[DestinationPixelIndex] = TileVisiblePixels[SourcePixelIndex];
                }
            }
        }
    }

    return true;
}

bool LoadNpcSpriteData(const std::filesystem::path& Path, std::vector<std::uint8_t>& Unpacked, std::size_t& TileCount, std::string& ErrorMessage)
{
    if (!UnpackFile(Path, Unpacked, ErrorMessage))
    {
        return false;
    }

    if (Unpacked.size() < NpcIndexTableBytes)
    {
        ErrorMessage = "mman.grp unpacked data is too small for the 256-byte index table";
        return false;
    }

    for (std::size_t Index = NpcIndexBytes; Index < NpcIndexTableBytes; ++Index)
    {
        if (Unpacked[Index] != 0)
        {
            ErrorMessage = "mman.grp contains non-zero reserved bytes at the end of the index table";
            return false;
        }
    }

    const std::size_t TileBankOffset = NpcIndexTableBytes;
    const std::size_t TileBankBytes = Unpacked.size() - TileBankOffset;
    TileCount = TileBankBytes / NpcTileBytes;
    if (TileCount == 0)
    {
        ErrorMessage = "mman.grp tile bank does not contain any complete 8x8 tiles";
        return false;
    }

    ErrorMessage.clear();
    return true;
}

}

bool LoadNpcSpriteSheet(const std::filesystem::path& Path, SpriteSheetSummary& Output, std::string& ErrorMessage)
{
    std::vector<std::uint8_t> Unpacked;
    std::size_t TileCount = 0;
    if (!LoadNpcSpriteData(Path, Unpacked, TileCount, ErrorMessage))
    {
        return false;
    }

    Output = {};
    Output.UnpackedByteCount = Unpacked.size();
    Output.FrameCount = NpcFrameCount;
    Output.FrameWidth = NpcFrameWidth;
    Output.FrameHeight = NpcFrameHeight;
    Output.DecodedPixelCount = NpcFrameCount * NpcFrameWidth * NpcFrameHeight;

    const std::size_t TileBankOffset = NpcIndexTableBytes;
    std::uint8_t MinimumPaletteIndex = 255;
    std::uint8_t MaximumPaletteIndex = 0;
    std::array<std::uint8_t, NpcFrameWidth * NpcFrameHeight> FramePixels{};
    for (std::size_t FrameIndex = 0; FrameIndex < NpcFrameCount; ++FrameIndex)
    {
        if (!DecodeNpcFrame(Unpacked, TileBankOffset, TileCount, FrameIndex, FramePixels, nullptr, MinimumPaletteIndex, MaximumPaletteIndex, ErrorMessage))
        {
            return false;
        }
    }

    Output.MinimumPaletteIndex = MinimumPaletteIndex;
    Output.MaximumPaletteIndex = MaximumPaletteIndex;
    ErrorMessage.clear();
    return true;
}

bool LoadNpcSpriteFrame(const std::filesystem::path& Path, std::size_t FrameIndex, NpcSpriteFrame& Output, std::string& ErrorMessage)
{
    if (FrameIndex >= NpcFrameCount)
    {
        ErrorMessage = "mman.grp frame index " + std::to_string(FrameIndex) + " is outside the 40-frame sheet";
        return false;
    }

    std::vector<std::uint8_t> Unpacked;
    std::size_t TileCount = 0;
    if (!LoadNpcSpriteData(Path, Unpacked, TileCount, ErrorMessage))
    {
        return false;
    }

    const std::size_t TileBankOffset = NpcIndexTableBytes;
    Output = {};
    std::uint8_t MinimumPaletteIndex = 255;
    std::uint8_t MaximumPaletteIndex = 0;
    if (!DecodeNpcFrame(Unpacked, TileBankOffset, TileCount, FrameIndex, Output.Pixels, &Output.DrawModes, MinimumPaletteIndex, MaximumPaletteIndex, ErrorMessage))
    {
        return false;
    }

    PopulateVisiblePixelsFromDrawModes(Output.DrawModes, Output.VisiblePixels);
    ErrorMessage.clear();
    return true;
}

bool LoadTownHeroSpriteFrame(const std::filesystem::path& Path, std::size_t FrameIndex, NpcSpriteFrame& Output, std::string& ErrorMessage)
{
    if (FrameIndex >= TownHeroFrameCount)
    {
        ErrorMessage = "tman.grp frame index " + std::to_string(FrameIndex) + " is outside the 10-frame sheet";
        return false;
    }

    std::vector<std::uint8_t> Unpacked;
    if (!UnpackFile(Path, Unpacked, ErrorMessage))
    {
        return false;
    }

    if (!DecodeTownHeroFrame(Unpacked, FrameIndex, Output.Pixels, &Output.DrawModes, ErrorMessage))
    {
        return false;
    }

    PopulateVisiblePixelsFromDrawModes(Output.DrawModes, Output.VisiblePixels);
    ErrorMessage.clear();
    return true;
}

bool LoadDungeonHeroSpriteFrame(const std::filesystem::path& Path, std::size_t FrameIndex, DungeonHeroSpriteFrame& Output, std::string& ErrorMessage)
{
    if (FrameIndex >= DungeonHeroFrameCount)
    {
        ErrorMessage = "fman.grp frame index " + std::to_string(FrameIndex) + " is outside the 91-frame sheet";
        return false;
    }

    std::vector<std::uint8_t> Unpacked;
    if (!UnpackFile(Path, Unpacked, ErrorMessage))
    {
        return false;
    }

    Output = {};
    if (!DecodeDungeonHeroFrame(Unpacked, FrameIndex, Output.Pixels, Output.VisiblePixels, ErrorMessage))
    {
        return false;
    }

    ErrorMessage.clear();
    return true;
}
}
