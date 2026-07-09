#include "town.h"

#include <algorithm>
#include <bitset>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <filesystem>
#include <iostream>
#include <optional>
#include <sstream>
#include <span>
#include <string>
#include <vector>

#include "../grp/font_grp.h"
#include "../grp/grp_unpack.h"
#include "../mcga/mcga_draw.h"
#include "town_npc.h"
#include "town_render.h"
#include "town_transitions.h"

namespace
{
constexpr std::size_t TownMapTileSize = 8;
constexpr std::size_t TownMapVisibleColumns = 28;
constexpr std::size_t TownMapViewportWidth = TownMapVisibleColumns * TownMapTileSize;
constexpr std::size_t TownViewportLeftX = 48;
constexpr std::size_t TownViewportTopY = 14 + 8 * TownMapTileSize;
// The visible viewport starts 4 columns into the proximity window.
constexpr std::size_t TownVisibleViewportColumnOffset = 4;
constexpr std::size_t TownMovementTileAheadRow = 7;
constexpr std::size_t TownHeroViewportLeftThreshold = 10;
constexpr std::size_t TownHeroViewportRightThreshold = 16;
constexpr std::size_t TownHeroRightEdgeTransitionSentinel = 27;
constexpr std::uint8_t TownNpcPatrolStepPhaseMaskOneBit = 0x10;
constexpr std::uint8_t TownNpcPatrolStepPhaseMaskTwoBit = 0x30;
constexpr std::uint8_t TownNpcPatrolBounceTurnMask = 0x07;
constexpr std::size_t TownHeadLevelRow = 5;
constexpr std::uint8_t TownHeadLevelNpcMarkerTile = 0xFD;
constexpr std::size_t TownBackgroundStripWidth = 224;
constexpr std::size_t TownBackgroundStripHeight = 16;
constexpr std::size_t TownBackgroundStripLeftWidth = TownBackgroundStripWidth / 2;
constexpr std::size_t TownMoleDecorationPanelWidth = TownScene::TownMoleDecorationPanelWidth;
constexpr std::size_t TownMoleDecorationPanelHeight = TownScene::TownMoleDecorationPanelHeight;
constexpr std::size_t TownMoleDecorationPanelPlaneWidthBytes = TownMoleDecorationPanelWidth / 4;
constexpr std::size_t TownMoleDecorationPanelDecodedByteCount = TownMoleDecorationPanelPlaneWidthBytes * TownMoleDecorationPanelHeight;
constexpr std::size_t TownMoleDecorationPanelLeftX = 0;
constexpr std::size_t TownMoleDecorationPanelRightX = 272;
constexpr std::size_t TownMoleTopTearsBaseWidth = TownScene::TownMoleTopTearsBaseWidth;
constexpr std::size_t TownMoleTopTearsBaseHeight = TownScene::TownMoleTopTearsBaseHeight;
constexpr std::size_t TownMoleTopTearsBasePlaneWidthBytes = TownMoleTopTearsBaseWidth / 4;
constexpr std::size_t TownMoleTopTearsBaseDecodedByteCount = TownMoleTopTearsBasePlaneWidthBytes * TownMoleTopTearsBaseHeight;
constexpr std::size_t TownMoleTopTearsBaseLeftX = 48;
constexpr std::size_t TownMoleTopTearsBaseTopY = 0;
constexpr std::size_t TownMoleTopLogoOffset = 0x04AE;
constexpr std::size_t TownMoleTopLogoLength = 0x028F;
constexpr std::size_t TownMoleTopLogoDecodedByteCount = TownMoleTopTearsBaseDecodedByteCount;
constexpr std::size_t TownMoleTopDemoTextOffset = 0x073D;
constexpr std::size_t TownMoleTopDemoTextLength = 0x0190;
constexpr std::uint8_t TownMoleTopTearsBaseRleMarkerHigh = 0x90;
constexpr std::size_t TownMoleBorder1Offset = 0x8CD;
constexpr std::size_t TownMoleBorder1Length = 0x80E;
constexpr std::size_t TownMoleBorder2Offset = 0x10DB;
constexpr std::size_t TownMoleBorder2Length = 0x786;
constexpr std::size_t TownMoleFrame1Offset = 0x1861;
constexpr std::size_t TownMoleFrame1Length = 0x827;
constexpr std::size_t TownMoleFrame2Offset = 0x2088;
constexpr std::size_t TownMoleFrame2Length = 0x711;
constexpr std::size_t TownMoleBottomStatusBaseWidth = TownScene::TownMoleBottomStatusBaseWidth;
constexpr std::size_t TownMoleBottomStatusBaseHeight = TownScene::TownMoleBottomStatusBaseHeight;
constexpr std::size_t TownMoleBottomStatusBasePlaneWidthBytes = TownMoleBottomStatusBaseWidth / 4;
constexpr std::size_t TownMoleBottomStatusBaseDecodedByteCount = TownMoleBottomStatusBasePlaneWidthBytes * TownMoleBottomStatusBaseHeight;
constexpr std::size_t TownMoleBottomStatusBaseLeftX = 48;
constexpr std::size_t TownMoleBottomStatusBaseTopY = 158;
constexpr std::size_t TownMoleBottomStatusBaseOffset = 0x2799;
constexpr std::size_t TownMoleBottomStatusBaseLength = 0x18D;
constexpr std::size_t TownMoleBottomStatusBaseRleMarkerHigh = 0x50;
constexpr std::size_t TownMoleBottomStatusBaseSecondPlaneFillWordCount = 0x4B0;
constexpr std::size_t TownMoleBottomStatusBaseSecondPlaneFillByteCount =
    TownMoleBottomStatusBaseSecondPlaneFillWordCount * sizeof(std::uint16_t);
constexpr std::uint8_t TownTrainingSwordType = 1;
constexpr std::size_t TownItempGroupOffsetCount = 7;
constexpr std::size_t TownItempGroupOffsetTableByteCount = TownItempGroupOffsetCount * sizeof(std::uint16_t);
constexpr std::size_t TownItempGroup0Offset = 0x000E;
constexpr std::size_t TownItempGroup0EndOffset = 0x0662;
constexpr std::size_t TownSwordItemSpriteWidth = 20;
constexpr std::size_t TownSwordItemSpriteHeight = 18;
constexpr std::size_t TownSwordItemSpriteRowStride = 15;
constexpr std::size_t TownSwordItemSpriteSourceByteCount = TownSwordItemSpriteRowStride * TownSwordItemSpriteHeight;
constexpr std::size_t TownSwordItemGroup0SpriteCount = 6;
constexpr std::size_t TownSwordItemSpritePixelCount = TownSwordItemSpriteWidth * TownSwordItemSpriteHeight;
constexpr std::size_t TownSwordItemHudScreenX = 0x18 * 8;
constexpr std::size_t TownSwordItemHudScreenY = 0xAB;
constexpr std::size_t TownScreenStride = 320;
constexpr std::size_t TownHeroHealthDestinationOffset = 0xCC14;
constexpr std::size_t TownHeroHealthBarX = TownHeroHealthDestinationOffset % TownScreenStride;
constexpr std::size_t TownHeroHealthBarY = TownHeroHealthDestinationOffset / TownScreenStride;
constexpr std::size_t TownHeroHealthBarMaximumPixels = 100;
constexpr std::size_t TownHeroMaxHealthBarHeight = 6;
constexpr std::size_t TownHeroHealthBarHeight = 5;
constexpr std::uint16_t TownHeroHealthClampValue = 0x0320;
constexpr std::uint8_t TownHeroMaxHealthColor = 0x12;
constexpr std::uint8_t TownHeroMaxHealthMask = 0x2D;
constexpr std::uint8_t TownHeroHealthColor = 9;
constexpr std::uint8_t TownHeroHealthMask = 0x12;
constexpr std::uint8_t TownHeroEmptyHealthColor = 0;
constexpr std::uint8_t TownHeroEmptyHealthMask = 0x12;
constexpr std::size_t YmpdMountainPlaneByteWidth = 56;
constexpr std::size_t YmpdMountainPlaneHeight = 88;
constexpr std::size_t YmpdMountainPlaneDecodedByteCount = YmpdMountainPlaneByteWidth * YmpdMountainPlaneHeight;
constexpr std::size_t TownSpriteBandPixelY = TownHeadLevelRow * TownMapTileSize;
constexpr std::size_t YmpdMountain0Offset = 0x5E7;
constexpr std::size_t YmpdMountain0Length = 0xE72;
constexpr std::size_t YmpdMountain1Offset = 0x1459;
constexpr std::size_t YmpdMountain1Length = 0xE45;
constexpr std::size_t YmpdGroundOffset = 0x229E;
constexpr std::size_t YmpdGroundLength = 0x153;
constexpr std::size_t YmpdGround1Offset = 0x23F1;
constexpr std::size_t YmpdGround1Length = 0x174;
constexpr std::size_t CkpdGroundOffset = 0x1C25;
constexpr std::size_t CkpdGround1Offset = 0x1DE5;
constexpr std::size_t CkpdGround1Length = 0x1C0;
constexpr std::array<std::uint8_t, 16> TownMoleUnpackTable =
{
    0, 1, 5, 3, 8, 9, 0x0D, 0x0B,
    0x28, 0x29, 0x2D, 0x2B, 0x18, 0x19, 0x1D, 0x1B
};

bool ReadWholeFile(const std::filesystem::path& Path, std::vector<std::uint8_t>& Output, std::string& ErrorMessage)
{
    std::ifstream Input(Path, std::ios::binary | std::ios::ate);
    if (!Input)
    {
        ErrorMessage = "failed to open " + Path.string();
        return false;
    }

    const std::streamsize FileSize = Input.tellg();
    if (FileSize < 0)
    {
        ErrorMessage = "failed to get size for " + Path.string();
        return false;
    }

    Output.resize(static_cast<std::size_t>(FileSize));
    Input.seekg(0, std::ios::beg);
    if (FileSize > 0 && !Input.read(reinterpret_cast<char*>(Output.data()), FileSize))
    {
        ErrorMessage = "failed to read " + Path.string();
        return false;
    }

    ErrorMessage.clear();
    return true;
}

std::string FormatHexOffset(std::size_t Offset)
{
    std::ostringstream Output;
    Output << "0x" << std::uppercase << std::hex << std::setw(4) << std::setfill('0') << Offset;
    return Output.str();
}

std::string FormatHexByte(std::uint8_t Value)
{
    std::ostringstream Output;
    Output << "0x" << std::uppercase << std::hex << std::setw(2) << std::setfill('0')
        << static_cast<int>(Value);
    return Output.str();
}

std::uint16_t ReadLittleEndianWord(const std::vector<std::uint8_t>& Data, std::size_t Offset)
{
    return static_cast<std::uint16_t>(Data[Offset]
        | (static_cast<std::uint16_t>(Data[Offset + 1]) << 8));
}

void DecodeFourPixelsFromTownItemPlanes(std::uint16_t& Plane1, std::uint16_t& Plane2,
    std::uint16_t& Plane3, std::uint8_t* Output)
{
    auto ShiftPlaneBitIntoPixel = [](std::uint16_t& Plane, std::uint8_t& Pixel)
    {
        const std::uint8_t Carry = (Plane & 0x8000) != 0 ? 1 : 0;
        Plane = static_cast<std::uint16_t>((Plane << 1) | Carry);
        Pixel = static_cast<std::uint8_t>((Pixel << 1) | Carry);
    };

    for (std::size_t PixelIndex = 0; PixelIndex < 4; ++PixelIndex)
    {
        std::uint8_t Pixel = 0;
        ShiftPlaneBitIntoPixel(Plane3, Pixel);
        ShiftPlaneBitIntoPixel(Plane2, Pixel);
        ShiftPlaneBitIntoPixel(Plane1, Pixel);
        ShiftPlaneBitIntoPixel(Plane3, Pixel);
        ShiftPlaneBitIntoPixel(Plane2, Pixel);
        ShiftPlaneBitIntoPixel(Plane1, Pixel);
        Output[PixelIndex] = Pixel;
    }
}

void DecodeEightPixelsFromTownItemPlanes(std::uint16_t Plane1, std::uint16_t Plane2,
    std::uint16_t Plane3, std::uint8_t* Output)
{
    DecodeFourPixelsFromTownItemPlanes(Plane1, Plane2, Plane3, Output);
    DecodeFourPixelsFromTownItemPlanes(Plane1, Plane2, Plane3, Output + 4);
}

bool DecodeYmpdExtract28Bytes(const std::vector<std::uint8_t>& FileBytes, std::size_t& SourceOffset,
    std::size_t SourceLimit, std::array<std::uint8_t, 28>& Output, std::string& ErrorMessage)
{
    std::size_t OutputIndex = 0;
    while (OutputIndex < Output.size())
    {
        if (SourceOffset >= SourceLimit)
        {
            ErrorMessage = "YMPD RLE stream ended before 28 bytes were decoded";
            return false;
        }

        const std::uint8_t Token = FileBytes[SourceOffset++];
        std::uint8_t RepeatCount = 1;
        std::uint8_t Value = Token;

        if ((Token & 0xF0) == 0x60)
        {
            RepeatCount = static_cast<std::uint8_t>(Token & 0x0F);
            Value = 0;
        }

        for (std::uint8_t RepeatIndex = 0; RepeatIndex < RepeatCount; ++RepeatIndex)
        {
            if (OutputIndex >= Output.size())
            {
                ErrorMessage = "YMPD RLE stream overran a 28-byte block";
                return false;
            }

            Output[OutputIndex++] = Value;
        }
    }

    ErrorMessage.clear();
    return true;
}

bool DecodeYmpdGroundStream(const std::vector<std::uint8_t>& FileBytes, std::size_t SourceOffset,
    std::size_t SourceLength, std::array<std::uint8_t, 448>& Output, std::string& ErrorMessage)
{
    const std::size_t SourceLimit = SourceOffset + SourceLength;
    for (std::size_t BlockIndex = 0; BlockIndex < 16; ++BlockIndex)
    {
        std::array<std::uint8_t, 28> Block{};
        if (!DecodeYmpdExtract28Bytes(FileBytes, SourceOffset, SourceLimit, Block, ErrorMessage))
        {
            return false;
        }

        std::copy(Block.begin(), Block.end(), Output.begin() + static_cast<std::ptrdiff_t>(BlockIndex * Block.size()));
    }

    ErrorMessage.clear();
    return true;
}

bool DecodeYmpdMountainPlane(const std::vector<std::uint8_t>& FileBytes, std::size_t& SourceOffset,
    std::size_t SourceLimit, std::array<std::uint8_t, YmpdMountainPlaneDecodedByteCount>& Output,
    std::size_t& DecodedByteCount, std::string& ErrorMessage)
{
    std::size_t OutputIndex = 0;

    while (OutputIndex < Output.size())
    {
        if (SourceOffset >= SourceLimit)
        {
            ErrorMessage = "YMPD mountain RLE stream ended before 88 x 56 bytes were decoded";
            return false;
        }

        const std::uint8_t Token = FileBytes[SourceOffset++];
        std::size_t RepeatCount = 1;
        std::uint8_t Value = Token;

        if (Token == 6)
        {
            if (SourceOffset + 1 >= SourceLimit)
            {
                ErrorMessage = "YMPD mountain RLE stream ended in a repeat token";
                return false;
            }

            Value = FileBytes[SourceOffset++];
            RepeatCount = static_cast<std::size_t>(FileBytes[SourceOffset++]);
            if (RepeatCount == 0)
            {
                RepeatCount = 256;
            }
        }

        for (std::size_t RepeatIndex = 0; RepeatIndex < RepeatCount; ++RepeatIndex)
        {
            if (OutputIndex >= Output.size())
            {
                ErrorMessage = "YMPD mountain RLE stream overran an 88 x 56 byte plane";
                return false;
            }

            Output[OutputIndex++] = Value;
        }
    }

    DecodedByteCount = OutputIndex;
    ErrorMessage.clear();
    return true;
}

bool DecodeMoleRlePlane(const std::vector<std::uint8_t>& FileBytes, std::size_t& SourceOffset,
    std::size_t SourceLimit, std::span<std::uint8_t> Output, std::size_t& DecodedByteCount,
    std::uint8_t RleMarkerHigh, bool EnableRleFlag, std::string& ErrorMessage)
{
    std::size_t OutputIndex = 0;

    while (true)
    {
        if (SourceOffset >= SourceLimit)
        {
            ErrorMessage = "MOLE RLE stream ended before the panel was decoded";
            return false;
        }

        const std::uint8_t Token = FileBytes[SourceOffset++];
        if (Token == 0)
        {
            if (OutputIndex != Output.size())
            {
                ErrorMessage = "MOLE RLE stream terminated before the panel was complete";
                return false;
            }

            DecodedByteCount = OutputIndex;
            ErrorMessage.clear();
            return true;
        }

        const std::uint8_t HighNibble = static_cast<std::uint8_t>(Token & 0xF0);
        std::size_t RepeatCount = 1;
        std::uint8_t Value = Token;

        if (HighNibble == RleMarkerHigh)
        {
            RepeatCount = static_cast<std::size_t>(Token & 0x0F);
            Value = 0xAA;
        }
        else if (HighNibble == 0x40)
        {
            RepeatCount = static_cast<std::size_t>(Token & 0x0F);
            Value = 0x00;
        }
        else if (EnableRleFlag && HighNibble == 0xD0)
        {
            RepeatCount = static_cast<std::size_t>(Token & 0x0F);
            Value = 0xFF;
        }

        if (RepeatCount == 0)
        {
            RepeatCount = 256;
        }

        for (std::size_t RepeatIndex = 0; RepeatIndex < RepeatCount; ++RepeatIndex)
        {
            if (OutputIndex >= Output.size())
            {
                ErrorMessage = "MOLE RLE stream overran the panel plane";
                return false;
            }

            Output[OutputIndex++] = Value;
        }
    }
}

std::uint8_t DecodeMoleMcgaPixel(std::uint8_t& Dl, std::uint8_t& Dh)
{
    auto ShiftLeftWithCarry = [](std::uint8_t& Value) -> std::uint8_t
    {
        const std::uint8_t Carry = static_cast<std::uint8_t>((Value & 0x80) != 0 ? 1 : 0);
        Value = static_cast<std::uint8_t>(Value << 1);
        return Carry;
    };

    std::uint8_t PixelIndex = 0;

    PixelIndex = static_cast<std::uint8_t>(PixelIndex + PixelIndex + ShiftLeftWithCarry(Dh));
    PixelIndex = static_cast<std::uint8_t>(PixelIndex + PixelIndex + ShiftLeftWithCarry(Dl));
    PixelIndex = static_cast<std::uint8_t>(PixelIndex + PixelIndex + ShiftLeftWithCarry(Dh));
    PixelIndex = static_cast<std::uint8_t>(PixelIndex + PixelIndex + ShiftLeftWithCarry(Dl));
    PixelIndex = static_cast<std::uint8_t>(PixelIndex & 0x0F);
    return TownMoleUnpackTable[PixelIndex];
}

void DecodeMoleMcgaScanline(const std::uint8_t* SourceLeft, const std::uint8_t* SourceRight, std::uint8_t* DestinationRow,
    std::size_t SourceByteCount)
{
    for (std::size_t ByteIndex = 0; ByteIndex < SourceByteCount; ++ByteIndex)
    {
        std::uint8_t Dl = SourceLeft[ByteIndex];
        std::uint8_t Dh = SourceRight[ByteIndex];

        for (std::size_t PixelGroupIndex = 0; PixelGroupIndex < 4; ++PixelGroupIndex)
        {
            DestinationRow[ByteIndex * 4 + PixelGroupIndex] = DecodeMoleMcgaPixel(Dl, Dh);
        }
    }
}

void DecodeMoleMcgaPanelPixels(const std::uint8_t* Plane0, const std::uint8_t* Plane1, std::size_t PanelWidthPixels,
    std::size_t PanelHeightPixels, std::size_t PlaneWidthBytes, std::uint8_t* Output)
{
    for (std::size_t RowIndex = 0; RowIndex < PanelHeightPixels; ++RowIndex)
    {
        DecodeMoleMcgaScanline(Plane0 + RowIndex * PlaneWidthBytes, Plane1 + RowIndex * PlaneWidthBytes,
            Output + RowIndex * PanelWidthPixels, PlaneWidthBytes);
    }
}

void LogMolePanelPixels(const char* PanelName, std::size_t PanelWidthPixels, std::size_t PanelHeightPixels,
    const std::uint8_t* Pixels)
{
    std::bitset<256> UniquePaletteIndices;
    for (std::size_t PixelIndex = 0; PixelIndex < PanelWidthPixels * PanelHeightPixels; ++PixelIndex)
    {
        UniquePaletteIndices.set(Pixels[PixelIndex]);
    }

    std::cerr << "mole.bin " << PanelName << " panel: "
        << "final panel dimensions " << PanelWidthPixels << " x " << PanelHeightPixels
        << " pixels, unique palette indices (" << UniquePaletteIndices.count() << "): ";

    bool IsFirstPaletteIndex = true;
    for (std::size_t PaletteIndex = 0; PaletteIndex < UniquePaletteIndices.size(); ++PaletteIndex)
    {
        if (!UniquePaletteIndices.test(PaletteIndex))
        {
            continue;
        }

        if (!IsFirstPaletteIndex)
        {
            std::cerr << ',';
        }

        std::cerr << PaletteIndex;
        IsFirstPaletteIndex = false;
    }

    std::cerr << '\n';
}

bool LoadTownMoleTopTearsBasePanel(const std::filesystem::path& MoleBinPath,
    std::array<std::uint8_t, TownMoleTopTearsBaseWidth * TownMoleTopTearsBaseHeight>& TopTearsBasePixels,
    std::string& ErrorMessage)
{
    std::vector<std::uint8_t> FileBytes;
    if (!ReadWholeFile(MoleBinPath, FileBytes, ErrorMessage))
    {
        return false;
    }

    if (FileBytes.size() < TownMoleTopDemoTextOffset + TownMoleTopDemoTextLength)
    {
        ErrorMessage = MoleBinPath.filename().string() + " is too small to contain the MOLE top tears base panel";
        return false;
    }

    std::array<std::uint8_t, TownMoleTopLogoDecodedByteCount> TopLogoDecodedBytes{};
    std::array<std::uint8_t, TownMoleTopTearsBaseDecodedByteCount> TopDemoTextDecodedBytes{};
    std::size_t TopLogoSourceOffset = TownMoleTopLogoOffset;
    std::size_t TopDemoTextSourceOffset = TownMoleTopDemoTextOffset;
    std::size_t TopLogoDecodedByteCount = 0;
    std::size_t TopDemoTextDecodedByteCount = 0;

    std::cerr << MoleBinPath.filename().string() << " top tears base panel: "
        << "title_logo " << FormatHexOffset(TownMoleTopLogoOffset) << ".."
        << FormatHexOffset(TownMoleTopLogoOffset + TownMoleTopLogoLength)
        << ", title_demo_text " << FormatHexOffset(TownMoleTopDemoTextOffset) << ".."
        << FormatHexOffset(TownMoleTopDemoTextOffset + TownMoleTopDemoTextLength)
        << ", RLE marker high nibble " << FormatHexByte(TownMoleTopTearsBaseRleMarkerHigh)
        << ", rle_flag state " << FormatHexByte(0x00) << '\n';

    if (!DecodeMoleRlePlane(FileBytes, TopLogoSourceOffset,
            TownMoleTopLogoOffset + TownMoleTopLogoLength, TopLogoDecodedBytes,
            TopLogoDecodedByteCount, TownMoleTopTearsBaseRleMarkerHigh, false, ErrorMessage))
    {
        return false;
    }

    if (TopLogoSourceOffset != TownMoleTopLogoOffset + TownMoleTopLogoLength)
    {
        ErrorMessage = MoleBinPath.filename().string() + " title_logo_data ended at "
            + FormatHexOffset(TopLogoSourceOffset) + " instead of "
            + FormatHexOffset(TownMoleTopLogoOffset + TownMoleTopLogoLength);
        return false;
    }

    if (!DecodeMoleRlePlane(FileBytes, TopDemoTextSourceOffset,
            TownMoleTopDemoTextOffset + TownMoleTopDemoTextLength, TopDemoTextDecodedBytes,
            TopDemoTextDecodedByteCount, TownMoleTopTearsBaseRleMarkerHigh, false, ErrorMessage))
    {
        return false;
    }

    if (TopDemoTextSourceOffset != TownMoleTopDemoTextOffset + TownMoleTopDemoTextLength)
    {
        ErrorMessage = MoleBinPath.filename().string() + " title_demo_text_data ended at "
            + FormatHexOffset(TopDemoTextSourceOffset) + " instead of "
            + FormatHexOffset(TownMoleTopDemoTextOffset + TownMoleTopDemoTextLength);
        return false;
    }

    if (TopLogoDecodedByteCount != TownMoleTopLogoDecodedByteCount
        || TopDemoTextDecodedByteCount != TownMoleTopTearsBaseDecodedByteCount)
    {
        ErrorMessage = MoleBinPath.filename().string() + " top tears base streams did not decode to the expected sizes";
        return false;
    }

    DecodeMoleMcgaPanelPixels(TopLogoDecodedBytes.data(), TopDemoTextDecodedBytes.data(), TownMoleTopTearsBaseWidth,
        TownMoleTopTearsBaseHeight, TownMoleTopTearsBasePlaneWidthBytes, TopTearsBasePixels.data());

    std::cerr << MoleBinPath.filename().string() << " top tears base panel: "
        << "title_logo decoded " << TopLogoDecodedByteCount << " bytes, "
        << "title_demo_text decoded " << TopDemoTextDecodedByteCount << " bytes, "
        << "rendered strip uses the first " << TownMoleTopTearsBaseDecodedByteCount << " bytes from each plane, "
        << "final dimensions " << TownMoleTopTearsBaseWidth << " x " << TownMoleTopTearsBaseHeight
        << " pixels, render position x = " << TownMoleTopTearsBaseLeftX
        << ", y = " << TownMoleTopTearsBaseTopY << '\n';

    LogMolePanelPixels("top tears base", TownMoleTopTearsBaseWidth, TownMoleTopTearsBaseHeight,
        TopTearsBasePixels.data());

    ErrorMessage.clear();
    return true;
}

bool LoadTownMoleDecorationPanels(const std::filesystem::path& MoleBinPath,
    std::array<std::uint8_t, TownMoleDecorationPanelWidth * TownMoleDecorationPanelHeight>& LeftPanelPixels,
    std::array<std::uint8_t, TownMoleDecorationPanelWidth * TownMoleDecorationPanelHeight>& RightPanelPixels,
    std::string& ErrorMessage)
{
    std::vector<std::uint8_t> FileBytes;
    if (!ReadWholeFile(MoleBinPath, FileBytes, ErrorMessage))
    {
        return false;
    }

    if (FileBytes.size() < TownMoleFrame2Offset + TownMoleFrame2Length)
    {
        ErrorMessage = MoleBinPath.filename().string() + " is too small to contain the MOLE decoration panels";
        return false;
    }

    std::array<std::uint8_t, TownMoleDecorationPanelDecodedByteCount> LeftPlane0{};
    std::array<std::uint8_t, TownMoleDecorationPanelDecodedByteCount> LeftPlane1{};
    std::array<std::uint8_t, TownMoleDecorationPanelDecodedByteCount> RightPlane0{};
    std::array<std::uint8_t, TownMoleDecorationPanelDecodedByteCount> RightPlane1{};
    std::size_t LeftPlane0SourceOffset = TownMoleBorder1Offset;
    std::size_t LeftPlane1SourceOffset = TownMoleBorder2Offset;
    std::size_t RightPlane0SourceOffset = TownMoleFrame1Offset;
    std::size_t RightPlane1SourceOffset = TownMoleFrame2Offset;
    std::size_t LeftPlane0DecodedByteCount = 0;
    std::size_t LeftPlane1DecodedByteCount = 0;
    std::size_t RightPlane0DecodedByteCount = 0;
    std::size_t RightPlane1DecodedByteCount = 0;

    if (!DecodeMoleRlePlane(FileBytes, LeftPlane0SourceOffset, TownMoleBorder1Offset + TownMoleBorder1Length,
            LeftPlane0, LeftPlane0DecodedByteCount, 0x10, false, ErrorMessage))
    {
        return false;
    }

    if (LeftPlane0SourceOffset != TownMoleBorder1Offset + TownMoleBorder1Length)
    {
        ErrorMessage = MoleBinPath.filename().string() + " title_border1_data ended at "
            + FormatHexOffset(LeftPlane0SourceOffset) + " instead of "
            + FormatHexOffset(TownMoleBorder1Offset + TownMoleBorder1Length);
        return false;
    }

    if (!DecodeMoleRlePlane(FileBytes, LeftPlane1SourceOffset, TownMoleBorder2Offset + TownMoleBorder2Length,
            LeftPlane1, LeftPlane1DecodedByteCount, 0x10, false, ErrorMessage))
    {
        return false;
    }

    if (LeftPlane1SourceOffset != TownMoleBorder2Offset + TownMoleBorder2Length)
    {
        ErrorMessage = MoleBinPath.filename().string() + " title_border2_data ended at "
            + FormatHexOffset(LeftPlane1SourceOffset) + " instead of "
            + FormatHexOffset(TownMoleBorder2Offset + TownMoleBorder2Length);
        return false;
    }

    if (!DecodeMoleRlePlane(FileBytes, RightPlane0SourceOffset, TownMoleFrame1Offset + TownMoleFrame1Length,
            RightPlane0, RightPlane0DecodedByteCount, 0x10, false, ErrorMessage))
    {
        return false;
    }

    if (RightPlane0SourceOffset != TownMoleFrame1Offset + TownMoleFrame1Length)
    {
        ErrorMessage = MoleBinPath.filename().string() + " title_frame1_data ended at "
            + FormatHexOffset(RightPlane0SourceOffset) + " instead of "
            + FormatHexOffset(TownMoleFrame1Offset + TownMoleFrame1Length);
        return false;
    }

    if (!DecodeMoleRlePlane(FileBytes, RightPlane1SourceOffset, TownMoleFrame2Offset + TownMoleFrame2Length,
            RightPlane1, RightPlane1DecodedByteCount, 0x10, false, ErrorMessage))
    {
        return false;
    }

    if (RightPlane1SourceOffset != TownMoleFrame2Offset + TownMoleFrame2Length)
    {
        ErrorMessage = MoleBinPath.filename().string() + " title_frame2_data ended at "
            + FormatHexOffset(RightPlane1SourceOffset) + " instead of "
            + FormatHexOffset(TownMoleFrame2Offset + TownMoleFrame2Length);
        return false;
    }

    if (LeftPlane0DecodedByteCount != TownMoleDecorationPanelDecodedByteCount
        || LeftPlane1DecodedByteCount != TownMoleDecorationPanelDecodedByteCount
        || RightPlane0DecodedByteCount != TownMoleDecorationPanelDecodedByteCount
        || RightPlane1DecodedByteCount != TownMoleDecorationPanelDecodedByteCount)
    {
        ErrorMessage = MoleBinPath.filename().string() + " MOLE panel streams did not decode to exactly "
            + std::to_string(TownMoleDecorationPanelDecodedByteCount) + " bytes";
        return false;
    }

    std::cerr << MoleBinPath.filename().string() << " left panel decoded plane sizes: "
        << "title_border1 " << TownMoleDecorationPanelPlaneWidthBytes << " x " << TownMoleDecorationPanelHeight
        << " bytes from " << FormatHexOffset(TownMoleBorder1Offset) << " to "
        << FormatHexOffset(TownMoleBorder1Offset + TownMoleBorder1Length) << ", title_border2 "
        << TownMoleDecorationPanelPlaneWidthBytes << " x " << TownMoleDecorationPanelHeight
        << " bytes from " << FormatHexOffset(TownMoleBorder2Offset) << " to "
        << FormatHexOffset(TownMoleBorder2Offset + TownMoleBorder2Length) << '\n';
    std::cerr << MoleBinPath.filename().string() << " right panel decoded plane sizes: "
        << "title_frame1 " << TownMoleDecorationPanelPlaneWidthBytes << " x " << TownMoleDecorationPanelHeight
        << " bytes from " << FormatHexOffset(TownMoleFrame1Offset) << " to "
        << FormatHexOffset(TownMoleFrame1Offset + TownMoleFrame1Length) << ", title_frame2 "
        << TownMoleDecorationPanelPlaneWidthBytes << " x " << TownMoleDecorationPanelHeight
        << " bytes from " << FormatHexOffset(TownMoleFrame2Offset) << " to "
        << FormatHexOffset(TownMoleFrame2Offset + TownMoleFrame2Length) << '\n';

    DecodeMoleMcgaPanelPixels(LeftPlane0.data(), LeftPlane1.data(), TownMoleDecorationPanelWidth,
        TownMoleDecorationPanelHeight, TownMoleDecorationPanelPlaneWidthBytes, LeftPanelPixels.data());
    DecodeMoleMcgaPanelPixels(RightPlane0.data(), RightPlane1.data(), TownMoleDecorationPanelWidth,
        TownMoleDecorationPanelHeight, TownMoleDecorationPanelPlaneWidthBytes, RightPanelPixels.data());

    LogMolePanelPixels("left", TownMoleDecorationPanelWidth, TownMoleDecorationPanelHeight, LeftPanelPixels.data());
    LogMolePanelPixels("right", TownMoleDecorationPanelWidth, TownMoleDecorationPanelHeight, RightPanelPixels.data());

    ErrorMessage.clear();
    return true;
}

bool LoadTownMoleBottomStatusBasePanel(const std::filesystem::path& MoleBinPath,
    std::array<std::uint8_t, TownMoleBottomStatusBaseWidth * TownMoleBottomStatusBaseHeight>& BottomStatusBasePixels,
    std::string& ErrorMessage)
{
    std::vector<std::uint8_t> FileBytes;
    if (!ReadWholeFile(MoleBinPath, FileBytes, ErrorMessage))
    {
        return false;
    }

    if (FileBytes.size() < TownMoleBottomStatusBaseOffset + TownMoleBottomStatusBaseLength)
    {
        ErrorMessage = MoleBinPath.filename().string() + " is too small to contain the MOLE bottom/status base panel";
        return false;
    }

    std::array<std::uint8_t, TownMoleBottomStatusBaseDecodedByteCount> BottomPlane0{};
    std::array<std::uint8_t, TownMoleBottomStatusBaseSecondPlaneFillByteCount> BottomPlane1{};
    std::size_t BottomPlane0SourceOffset = TownMoleBottomStatusBaseOffset;
    std::size_t BottomPlane0DecodedByteCount = 0;

    std::cerr << MoleBinPath.filename().string() << " bottom/status base panel: "
        << "source span " << FormatHexOffset(TownMoleBottomStatusBaseOffset) << ".."
        << FormatHexOffset(TownMoleBottomStatusBaseOffset + TownMoleBottomStatusBaseLength)
        << ", RLE marker high nibble " << FormatHexByte(static_cast<std::uint8_t>(TownMoleBottomStatusBaseRleMarkerHigh))
        << ", rle_flag state " << FormatHexByte(0xFF) << '\n';

    if (!DecodeMoleRlePlane(FileBytes, BottomPlane0SourceOffset,
            TownMoleBottomStatusBaseOffset + TownMoleBottomStatusBaseLength, BottomPlane0,
            BottomPlane0DecodedByteCount, static_cast<std::uint8_t>(TownMoleBottomStatusBaseRleMarkerHigh), true, ErrorMessage))
    {
        return false;
    }

    if (BottomPlane0SourceOffset != TownMoleBottomStatusBaseOffset + TownMoleBottomStatusBaseLength)
    {
        ErrorMessage = MoleBinPath.filename().string() + " title_screen_final_data ended at "
            + FormatHexOffset(BottomPlane0SourceOffset) + " instead of "
            + FormatHexOffset(TownMoleBottomStatusBaseOffset + TownMoleBottomStatusBaseLength);
        return false;
    }

    if (BottomPlane0DecodedByteCount != TownMoleBottomStatusBaseDecodedByteCount)
    {
        ErrorMessage = MoleBinPath.filename().string() + " bottom/status base plane decoded to "
            + std::to_string(BottomPlane0DecodedByteCount) + " bytes instead of "
            + std::to_string(TownMoleBottomStatusBaseDecodedByteCount);
        return false;
    }

    DecodeMoleMcgaPanelPixels(BottomPlane0.data(), BottomPlane1.data(), TownMoleBottomStatusBaseWidth,
        TownMoleBottomStatusBaseHeight, TownMoleBottomStatusBasePlaneWidthBytes, BottomStatusBasePixels.data());

    std::cerr << MoleBinPath.filename().string() << " bottom/status base panel: "
        << "plane0 decoded " << BottomPlane0DecodedByteCount << " bytes, "
        << "plane1 zero fill " << TownMoleBottomStatusBaseSecondPlaneFillWordCount << " words ("
        << TownMoleBottomStatusBaseSecondPlaneFillByteCount << " bytes), "
        << "consumed bytes " << (BottomPlane0SourceOffset - TownMoleBottomStatusBaseOffset) << ", "
        << "final dimensions " << TownMoleBottomStatusBaseWidth << " x " << TownMoleBottomStatusBaseHeight
        << " pixels, render position x = " << TownMoleBottomStatusBaseLeftX
        << ", y = " << TownMoleBottomStatusBaseTopY << '\n';

    LogMolePanelPixels("bottom/status base", TownMoleBottomStatusBaseWidth, TownMoleBottomStatusBaseHeight,
        BottomStatusBasePixels.data());

    ErrorMessage.clear();
    return true;
}

void DecodeYmpdScanline(const std::uint8_t* SourceRow, std::uint8_t* DestinationLeftHalf)
{
    for (std::size_t ByteIndex = 0; ByteIndex < TownBackgroundStripLeftWidth / 8; ++ByteIndex)
    {
        std::uint16_t TopWord = static_cast<std::uint16_t>(SourceRow[ByteIndex * 2] << 8)
            | static_cast<std::uint16_t>(SourceRow[ByteIndex * 2 + 1]);
        std::uint16_t BottomWord = static_cast<std::uint16_t>(SourceRow[28 + ByteIndex * 2] << 8)
            | static_cast<std::uint16_t>(SourceRow[28 + ByteIndex * 2 + 1]);

        for (std::size_t PixelIndex = 0; PixelIndex < 8; ++PixelIndex)
        {
            std::uint8_t Pixel = 0;

            Pixel = static_cast<std::uint8_t>(Pixel << 1);
            Pixel = static_cast<std::uint8_t>(Pixel | ((TopWord & 0x8000) != 0 ? 1 : 0));
            TopWord = static_cast<std::uint16_t>(TopWord << 1);

            Pixel = static_cast<std::uint8_t>(Pixel << 1);
            Pixel = static_cast<std::uint8_t>(Pixel | ((BottomWord & 0x8000) != 0 ? 1 : 0));
            BottomWord = static_cast<std::uint16_t>(BottomWord << 1);

            Pixel = static_cast<std::uint8_t>(Pixel << 1);

            Pixel = static_cast<std::uint8_t>(Pixel << 1);
            Pixel = static_cast<std::uint8_t>(Pixel | ((TopWord & 0x8000) != 0 ? 1 : 0));
            TopWord = static_cast<std::uint16_t>(TopWord << 1);

            Pixel = static_cast<std::uint8_t>(Pixel << 1);
            Pixel = static_cast<std::uint8_t>(Pixel | ((BottomWord & 0x8000) != 0 ? 1 : 0));
            BottomWord = static_cast<std::uint16_t>(BottomWord << 1);

            Pixel = static_cast<std::uint8_t>(Pixel << 1);

            DestinationLeftHalf[ByteIndex * 8 + PixelIndex] = Pixel;
        }
    }
}

std::uint8_t DecodeCkpdPixel(std::uint8_t& Dl, std::uint8_t& Dh)
{
    std::uint8_t Pixel = 0;

    Pixel = static_cast<std::uint8_t>(Pixel << 1);
    Pixel = static_cast<std::uint8_t>(Pixel | ((Dh & 0x80) != 0 ? 1 : 0));
    Dh = static_cast<std::uint8_t>(Dh << 1);

    Pixel = static_cast<std::uint8_t>(Pixel << 1);
    Pixel = static_cast<std::uint8_t>(Pixel | ((Dl & 0x80) != 0 ? 1 : 0));
    Dl = static_cast<std::uint8_t>(Dl << 1);

    Pixel = static_cast<std::uint8_t>(Pixel << 1);

    Pixel = static_cast<std::uint8_t>(Pixel << 1);
    Pixel = static_cast<std::uint8_t>(Pixel | ((Dh & 0x80) != 0 ? 1 : 0));
    Dh = static_cast<std::uint8_t>(Dh << 1);

    Pixel = static_cast<std::uint8_t>(Pixel << 1);
    Pixel = static_cast<std::uint8_t>(Pixel | ((Dl & 0x80) != 0 ? 1 : 0));
    Dl = static_cast<std::uint8_t>(Dl << 1);

    Pixel = static_cast<std::uint8_t>(Pixel << 1);
    return Pixel;
}

std::uint8_t DecodeYmpdMountainPixel(std::uint8_t& Dl, std::uint8_t& Dh)
{
    auto ShiftLeftWithCarry = [](std::uint8_t& Value) -> std::uint8_t
    {
        const std::uint8_t Carry = static_cast<std::uint8_t>((Value & 0x80) != 0 ? 1 : 0);
        Value = static_cast<std::uint8_t>(Value << 1);
        return Carry;
    };

    std::uint8_t Pixel = 0;

    Pixel = static_cast<std::uint8_t>(Pixel + Pixel + ShiftLeftWithCarry(Dh));

    Pixel = static_cast<std::uint8_t>(Pixel + Pixel);

    Pixel = static_cast<std::uint8_t>(Pixel + Pixel + ShiftLeftWithCarry(Dl));

    Pixel = static_cast<std::uint8_t>(Pixel + Pixel + ShiftLeftWithCarry(Dh));

    Pixel = static_cast<std::uint8_t>(Pixel + Pixel);

    Pixel = static_cast<std::uint8_t>(Pixel + Pixel + ShiftLeftWithCarry(Dl));

    return Pixel;
}

void DecodeCkpdScanline(const std::uint8_t* SourceLeft, const std::uint8_t* SourceRight, std::uint8_t* DestinationLeftHalf)
{
    for (std::size_t ByteIndex = 0; ByteIndex < TownBackgroundStripLeftWidth / 4; ++ByteIndex)
    {
        std::uint8_t Dl = SourceLeft[ByteIndex];
        std::uint8_t Dh = SourceRight[ByteIndex];

        for (std::size_t PixelGroupIndex = 0; PixelGroupIndex < 4; ++PixelGroupIndex)
        {
            DestinationLeftHalf[ByteIndex * 4 + PixelGroupIndex] = DecodeCkpdPixel(Dl, Dh);
        }
    }
}

void DecodeYmpdMountainScanline(const std::uint8_t* SourceLeft, const std::uint8_t* SourceRight,
    std::uint8_t* DestinationRow)
{
    constexpr std::size_t MountainPixelsPerSourceByte = TownScene::TownBackgroundMountainWidth / YmpdMountainPlaneByteWidth;

    for (std::size_t ByteIndex = 0; ByteIndex < YmpdMountainPlaneByteWidth; ++ByteIndex)
    {
        std::uint8_t Dl = SourceLeft[ByteIndex];
        std::uint8_t Dh = SourceRight[ByteIndex];

        for (std::size_t PixelGroupIndex = 0; PixelGroupIndex < 4; ++PixelGroupIndex)
        {
            DestinationRow[ByteIndex * MountainPixelsPerSourceByte + PixelGroupIndex] = DecodeYmpdMountainPixel(Dl, Dh);
        }
    }
}

bool LoadTownBackgroundStripPixels(const std::filesystem::path& TownBackgroundBinPath, bool TownHasMiddleLayer,
    std::array<std::uint8_t, TownBackgroundStripWidth * TownBackgroundStripHeight>& Output, std::string& ErrorMessage)
{
    std::vector<std::uint8_t> FileBytes;
    if (!ReadWholeFile(TownBackgroundBinPath, FileBytes, ErrorMessage))
    {
        return false;
    }

    if (TownHasMiddleLayer)
    {
        // The MCGA town path uses the raw mode4_mcga tables here, not the
        // compressed sub_3300 render_something pair.
        if (FileBytes.size() < CkpdGround1Offset + CkpdGround1Length)
        {
            ErrorMessage = TownBackgroundBinPath.filename().string() + " is too small to contain the CKPD MCGA ground tables";
            return false;
        }

        for (std::size_t RowIndex = 0; RowIndex < TownBackgroundStripHeight; ++RowIndex)
        {
            const std::size_t SourceOffset = RowIndex * TownBackgroundStripLeftWidth / 4;
            std::uint8_t* DestinationRow = Output.data() + RowIndex * TownBackgroundStripWidth;
            DecodeCkpdScanline(FileBytes.data() + CkpdGroundOffset + SourceOffset,
                FileBytes.data() + CkpdGround1Offset + SourceOffset, DestinationRow);
            std::copy(DestinationRow, DestinationRow + static_cast<std::ptrdiff_t>(TownBackgroundStripLeftWidth),
                DestinationRow + TownBackgroundStripLeftWidth);
        }

        ErrorMessage.clear();
        return true;
    }

    if (FileBytes.size() < YmpdGround1Offset + YmpdGround1Length)
    {
        ErrorMessage = TownBackgroundBinPath.filename().string() + " is too small to contain the YMPD ground tables";
        return false;
    }

    std::array<std::uint8_t, 448> Ground{};
    std::array<std::uint8_t, 448> Ground1{};
    if (!DecodeYmpdGroundStream(FileBytes, YmpdGroundOffset, YmpdGroundLength, Ground, ErrorMessage))
    {
        return false;
    }

    if (!DecodeYmpdGroundStream(FileBytes, YmpdGround1Offset, YmpdGround1Length, Ground1, ErrorMessage))
    {
        return false;
    }

    for (std::size_t RowIndex = 0; RowIndex < 8; ++RowIndex)
    {
        std::uint8_t* DestinationRow = Output.data() + RowIndex * TownBackgroundStripWidth;
        DecodeYmpdScanline(Ground.data() + RowIndex * 56, DestinationRow);
        std::copy(DestinationRow, DestinationRow + static_cast<std::ptrdiff_t>(TownBackgroundStripLeftWidth),
            DestinationRow + TownBackgroundStripLeftWidth);
    }

    for (std::size_t RowIndex = 0; RowIndex < 8; ++RowIndex)
    {
        std::uint8_t* DestinationRow = Output.data() + (RowIndex + 8) * TownBackgroundStripWidth;
        DecodeYmpdScanline(Ground1.data() + RowIndex * 56, DestinationRow);
        std::copy(DestinationRow, DestinationRow + static_cast<std::ptrdiff_t>(TownBackgroundStripLeftWidth),
            DestinationRow + TownBackgroundStripLeftWidth);
    }

    ErrorMessage.clear();
    return true;
}

bool LoadTownBackgroundMountainLayerPixels(const std::filesystem::path& TownBackgroundBinPath,
    std::array<std::uint8_t, TownScene::TownBackgroundMountainWidth * TownScene::TownBackgroundMountainHeight>& Output, std::string& ErrorMessage)
{
    std::vector<std::uint8_t> FileBytes;
    if (!ReadWholeFile(TownBackgroundBinPath, FileBytes, ErrorMessage))
    {
        return false;
    }

    if (FileBytes.size() < YmpdMountain1Offset + YmpdMountain1Length)
    {
        ErrorMessage = TownBackgroundBinPath.filename().string() + " is too small to contain the YMPD mountain tables";
        return false;
    }

    std::array<std::uint8_t, YmpdMountainPlaneDecodedByteCount> Mountain0{};
    std::array<std::uint8_t, YmpdMountainPlaneDecodedByteCount> Mountain1{};
    std::size_t Mountain0SourceOffset = YmpdMountain0Offset;
    std::size_t Mountain1SourceOffset = YmpdMountain1Offset;
    std::size_t Mountain0DecodedByteCount = 0;
    std::size_t Mountain1DecodedByteCount = 0;
    if (!DecodeYmpdMountainPlane(FileBytes, Mountain0SourceOffset, YmpdMountain0Offset + YmpdMountain0Length,
            Mountain0, Mountain0DecodedByteCount, ErrorMessage))
    {
        return false;
    }

    if (!DecodeYmpdMountainPlane(FileBytes, Mountain1SourceOffset, YmpdMountain1Offset + YmpdMountain1Length,
            Mountain1, Mountain1DecodedByteCount, ErrorMessage))
    {
        return false;
    }

    if (Mountain0DecodedByteCount != YmpdMountainPlaneDecodedByteCount || Mountain1DecodedByteCount != YmpdMountainPlaneDecodedByteCount)
    {
        ErrorMessage = TownBackgroundBinPath.filename().string() + " mountain streams did not decode to exactly "
            + std::to_string(YmpdMountainPlaneDecodedByteCount) + " bytes";
        return false;
    }

    std::cerr << TownBackgroundBinPath.filename().string() << " mountain streams: "
        << "mountains0 " << FormatHexOffset(YmpdMountain0Offset) << " -> " << Mountain0DecodedByteCount
        << " bytes ending at " << FormatHexOffset(Mountain0SourceOffset) << ", "
        << "mountains1 " << FormatHexOffset(YmpdMountain1Offset) << " -> " << Mountain1DecodedByteCount
        << " bytes ending at " << FormatHexOffset(Mountain1SourceOffset) << '\n';

    for (std::size_t RowIndex = 0; RowIndex < YmpdMountainPlaneHeight; ++RowIndex)
    {
        std::uint8_t* DestinationRow = Output.data() + RowIndex * TownScene::TownBackgroundMountainWidth;
        DecodeYmpdMountainScanline(Mountain0.data() + RowIndex * YmpdMountainPlaneByteWidth,
            Mountain1.data() + RowIndex * YmpdMountainPlaneByteWidth, DestinationRow);
    }

    std::bitset<256> UniquePaletteIndices;
    for (const std::uint8_t Pixel : Output)
    {
        UniquePaletteIndices.set(Pixel);
    }

    std::cerr << TownBackgroundBinPath.filename().string() << " mountain layer: "
        << "decoded plane size 56 x 88 bytes, "
        << "rendered mountain size 224 x 88 pixels, "
        << "final mountain pixel count " << Output.size() << ", "
        << "unique palette indices (" << UniquePaletteIndices.count() << "): ";

    bool IsFirstPaletteIndex = true;
    for (std::size_t PaletteIndex = 0; PaletteIndex < UniquePaletteIndices.size(); ++PaletteIndex)
    {
        if (!UniquePaletteIndices.test(PaletteIndex))
        {
            continue;
        }

        if (!IsFirstPaletteIndex)
        {
            std::cerr << ',';
        }

        std::cerr << PaletteIndex;
        IsFirstPaletteIndex = false;
    }

    std::cerr << '\n';

    ErrorMessage.clear();
    return true;
}

bool DecodeTownSwordItemSprite(const std::vector<std::uint8_t>& Unpacked, std::size_t SpriteOffset,
    std::array<std::uint8_t, TownSwordItemSpritePixelCount>& Output, std::string& ErrorMessage)
{
    const std::size_t SpriteEndOffset = SpriteOffset + TownSwordItemSpriteSourceByteCount;
    if (SpriteEndOffset > Unpacked.size())
    {
        ErrorMessage = "Training Sword source span "
            + FormatHexOffset(SpriteOffset) + ".." + FormatHexOffset(SpriteEndOffset)
            + " is past the unpacked itemp.grp size";
        return false;
    }

    for (std::size_t Row = 0; Row < TownSwordItemSpriteHeight; ++Row)
    {
        const std::uint8_t* RowBytes = Unpacked.data() + SpriteOffset + Row * TownSwordItemSpriteRowStride;
        std::uint8_t* DestinationRow = Output.data() + Row * TownSwordItemSpriteWidth;

        DecodeEightPixelsFromTownItemPlanes(
            static_cast<std::uint16_t>((RowBytes[0] << 8) | RowBytes[1]),
            static_cast<std::uint16_t>((RowBytes[9] << 8) | RowBytes[8]),
            static_cast<std::uint16_t>((RowBytes[10] << 8) | RowBytes[11]),
            DestinationRow);
        DecodeEightPixelsFromTownItemPlanes(
            static_cast<std::uint16_t>((RowBytes[2] << 8) | RowBytes[3]),
            static_cast<std::uint16_t>((RowBytes[7] << 8) | RowBytes[6]),
            static_cast<std::uint16_t>((RowBytes[12] << 8) | RowBytes[13]),
            DestinationRow + 8);
        std::uint16_t Plane1 = static_cast<std::uint16_t>(RowBytes[4] << 8);
        std::uint16_t Plane2 = static_cast<std::uint16_t>(RowBytes[5] << 8);
        std::uint16_t Plane3 = static_cast<std::uint16_t>(RowBytes[14] << 8);
        DecodeFourPixelsFromTownItemPlanes(Plane1, Plane2, Plane3, DestinationRow + 16);
    }

    ErrorMessage.clear();
    return true;
}

bool LoadTownTrainingSwordItemSprite(const std::filesystem::path& ItempGrpPath,
    std::array<std::uint8_t, TownSwordItemSpritePixelCount>& TrainingSwordPixels,
    std::string& ErrorMessage)
{
    std::vector<std::uint8_t> Unpacked;
    if (!Grp::UnpackFile(ItempGrpPath, Unpacked, ErrorMessage))
    {
        return false;
    }

    if (Unpacked.size() < TownItempGroupOffsetTableByteCount)
    {
        ErrorMessage = ItempGrpPath.filename().string() + " unpacked data is too small for the item group offset table";
        return false;
    }

    std::array<std::uint16_t, TownItempGroupOffsetCount> GroupOffsets{};
    for (std::size_t GroupIndex = 0; GroupIndex < GroupOffsets.size(); ++GroupIndex)
    {
        GroupOffsets[GroupIndex] = ReadLittleEndianWord(Unpacked, GroupIndex * sizeof(std::uint16_t));
    }

    if (GroupOffsets[0] != TownItempGroup0Offset || GroupOffsets[1] != TownItempGroup0EndOffset)
    {
        ErrorMessage = ItempGrpPath.filename().string() + " group 0 offsets are "
            + FormatHexOffset(GroupOffsets[0]) + ".." + FormatHexOffset(GroupOffsets[1])
            + " instead of " + FormatHexOffset(TownItempGroup0Offset) + ".."
            + FormatHexOffset(TownItempGroup0EndOffset);
        return false;
    }

    if (GroupOffsets[1] > Unpacked.size())
    {
        ErrorMessage = ItempGrpPath.filename().string() + " group 0 end offset "
            + FormatHexOffset(GroupOffsets[1]) + " is past the unpacked size";
        return false;
    }

    if (TownItempGroup0EndOffset - TownItempGroup0Offset
        != TownSwordItemGroup0SpriteCount * TownSwordItemSpriteSourceByteCount)
    {
        ErrorMessage = ItempGrpPath.filename().string() + " group 0 size does not match six sword item sprites";
        return false;
    }

    const std::size_t SpriteIndex = static_cast<std::size_t>(TownTrainingSwordType - 1);
    const std::size_t SpriteOffset = TownItempGroup0Offset + SpriteIndex * TownSwordItemSpriteSourceByteCount;
    const std::size_t SpriteEndOffset = SpriteOffset + TownSwordItemSpriteSourceByteCount;
    if (SpriteEndOffset > TownItempGroup0EndOffset)
    {
        ErrorMessage = ItempGrpPath.filename().string() + " Training Sword sprite overruns item group 0";
        return false;
    }

    if (!DecodeTownSwordItemSprite(Unpacked, SpriteOffset, TrainingSwordPixels, ErrorMessage))
    {
        return false;
    }

    std::cerr << ItempGrpPath.filename().string() << " Training Sword item sprite: "
        << "unpacked " << Unpacked.size() << " bytes, group 0 "
        << FormatHexOffset(GroupOffsets[0]) << ".." << FormatHexOffset(GroupOffsets[1])
        << ", sword type " << static_cast<int>(TownTrainingSwordType)
        << ", sprite index " << SpriteIndex
        << ", source span " << FormatHexOffset(SpriteOffset) << ".." << FormatHexOffset(SpriteEndOffset)
        << ", source bytes " << TownSwordItemSpriteSourceByteCount
        << ", decoded pixels " << TownSwordItemSpritePixelCount
        << ", render position x = " << TownSwordItemHudScreenX
        << ", y = " << TownSwordItemHudScreenY << '\n';

    ErrorMessage.clear();
    return true;
}

constexpr std::uint8_t NpcAiTypeLookAtHeroAndBob = 0;
constexpr std::uint8_t NpcAiTypePatrol1BitPhase = 1;
constexpr std::uint8_t NpcAiTypePatrol2BitPhase = 2;
constexpr std::uint8_t NpcAiTypeFaceHero = 3;
constexpr std::uint8_t NpcAiTypeBobInPlace = 4;
constexpr std::uint8_t NpcAiTypePatrolBounce1Bit = 5;
constexpr std::uint8_t NpcAiTypePatrolBounce2Bit = 6;

const Grp::PatternTile& GetFallbackPatternTile()
{
    static const Grp::PatternTile FallbackTile = []
    {
        Grp::PatternTile Tile{};
        for (std::size_t Row = 0; Row < 8; ++Row)
        {
            for (std::size_t Column = 0; Column < 8; ++Column)
            {
                const bool IsBright = ((Row + Column) % 2) == 0;
                Tile.Pixels[Row * 8 + Column] = IsBright ? 63 : 0;
            }
        }
        return Tile;
    }();

    return FallbackTile;
}

const Grp::PatternAnimationReplacement* FindPatternAnimationReplacement(const Grp::PatternBank& PatternBank,
    std::uint8_t TileIndex)
{
    for (const Grp::PatternAnimationReplacement& AnimationReplacement : PatternBank.AnimationReplacementRules)
    {
        if (AnimationReplacement.SourceTile == TileIndex)
        {
            return &AnimationReplacement;
        }
    }

    return nullptr;
}

void AdvanceTownPatternAnimations(std::vector<std::uint8_t>& TownRuntimeCells, const Mdt::TownMapInfo& TownMap,
    const Grp::PatternBank& PatternBank)
{
    const std::size_t AnimatedRowCount = std::min<std::size_t>(3, TownMap.Height);
    for (std::size_t Row = 0; Row < AnimatedRowCount; ++Row)
    {
        for (std::size_t Column = 0; Column < TownMap.Width; ++Column)
        {
            const std::size_t CellIndex = Column * TownMap.Height + Row;
            if (CellIndex >= TownRuntimeCells.size())
            {
                continue;
            }

            const std::uint8_t TileIndex = TownRuntimeCells[CellIndex];
            const Grp::PatternAnimationReplacement* AnimationReplacement = FindPatternAnimationReplacement(PatternBank,
                TileIndex);
            if (AnimationReplacement != nullptr)
            {
                TownRuntimeCells[CellIndex] = AnimationReplacement->ReplacementTile;
            }
        }
    }
}

std::size_t GetTownMapMaximumScrollOffset(const Mdt::TownMapInfo& TownMap)
{
    const std::size_t MapWidthPixels = static_cast<std::size_t>(TownMap.Width) * TownMapTileSize;
    return MapWidthPixels > TownMapViewportWidth ? MapWidthPixels - TownMapViewportWidth : 0;
}

bool IsTownMapBlockedTileIndex(const Grp::PatternBank& PatternBank, std::uint8_t TileIndex)
{
    return std::find(PatternBank.SpecialTileIndices.begin(), PatternBank.SpecialTileIndices.end(), TileIndex)
        != PatternBank.SpecialTileIndices.end();
}

bool TryGetTownMapTileIndexAtCell(const Mdt::TownMapInfo& TownMap, std::size_t Column, std::size_t Row,
    std::uint8_t& TileIndex)
{
    if (Column >= TownMap.Width || Row >= TownMap.Height)
    {
        return false;
    }

    const std::size_t CellIndex = Column * TownMap.Height + Row;
    if (CellIndex >= TownMap.Cells.size())
    {
        return false;
    }

    TileIndex = TownMap.Cells[CellIndex];
    return true;
}

bool TryGetTownMapTileIndexAtPixel(const Mdt::TownMapInfo& TownMap, std::size_t PixelX, std::size_t PixelY,
    std::uint8_t& TileIndex)
{
    const std::size_t MapWidthPixels = static_cast<std::size_t>(TownMap.Width) * TownMapTileSize;
    const std::size_t MapHeightPixels = static_cast<std::size_t>(TownMap.Height) * TownMapTileSize;
    if (PixelX >= MapWidthPixels || PixelY >= MapHeightPixels)
    {
        return false;
    }

    const std::size_t Column = PixelX / TownMapTileSize;
    const std::size_t Row = PixelY / TownMapTileSize;
    return TryGetTownMapTileIndexAtCell(TownMap, Column, Row, TileIndex);
}

bool IsTownHeroBlockedByTownTile(const Mdt::TownMapInfo& TownMap, const Grp::PatternBank& PatternBank,
    std::size_t ProximityMapLeftColumnX, std::size_t HeroXInViewport, bool MovingLeft)
{
    // Match loc_6781 and loc_67F4: probe row 7 one tile ahead of Duke before
    // any horizontal move or scroll can happen.
    const std::size_t TileAheadColumn = ProximityMapLeftColumnX + HeroXInViewport + (MovingLeft ? 3 : 6);
    std::uint8_t TileIndex = 0;
    if (!TryGetTownMapTileIndexAtCell(TownMap, TileAheadColumn, TownMovementTileAheadRow, TileIndex))
    {
        return true;
    }

    return IsTownMapBlockedTileIndex(PatternBank, TileIndex);
}

const char* GetTownMapCollisionStatusName(bool ActorCollisionBlocked)
{
    return ActorCollisionBlocked ? "COL BLOCK" : "COL OK";
}

bool LoadTownHudFontGroups(const std::filesystem::path& FontGrpPath, Grp::FontGroup& BoldFontOutput,
    Grp::FontGroup& ThinFontOutput, Grp::FontGroup& DigitFontOutput, std::string& ErrorMessage)
{
    constexpr std::size_t BoldFontGroupIndex = 0;
    constexpr std::size_t DigitFontGroupIndex = 1;
    constexpr std::size_t ThinFontGroupIndex = 2;

    std::vector<std::uint8_t> Unpacked;
    if (!Grp::UnpackFile(FontGrpPath, Unpacked, ErrorMessage))
    {
        return false;
    }

    std::string BoldWarningMessage;
    if (!Grp::DecodeFontGroup(Unpacked, BoldFontGroupIndex, BoldFontOutput, ErrorMessage, &BoldWarningMessage))
    {
        return false;
    }

    if (!BoldWarningMessage.empty())
    {
        std::cerr << BoldWarningMessage << '\n';
    }

    std::string DigitWarningMessage;
    if (!Grp::DecodeFontGroup(Unpacked, DigitFontGroupIndex, DigitFontOutput, ErrorMessage, &DigitWarningMessage))
    {
        return false;
    }

    if (!DigitWarningMessage.empty())
    {
        std::cerr << DigitWarningMessage << '\n';
    }

    std::string ThinWarningMessage;
    if (!Grp::DecodeFontGroup(Unpacked, ThinFontGroupIndex, ThinFontOutput, ErrorMessage, &ThinWarningMessage))
    {
        return false;
    }

    if (!ThinWarningMessage.empty())
    {
        std::cerr << ThinWarningMessage << '\n';
    }

    ErrorMessage.clear();
    return true;
}

void FillTownHudRect(SDL_Renderer* Renderer, const Main64Palette& Palette, std::uint8_t PaletteIndex,
    float X, float Y, float Width, float Height)
{
    if (PaletteIndex >= Palette.size())
    {
        return;
    }

    const SDL_Color& Color = Palette[PaletteIndex];
    SDL_SetRenderDrawBlendMode(Renderer, SDL_BLENDMODE_NONE);
    SDL_SetRenderDrawColor(Renderer, Color.r, Color.g, Color.b, Color.a);
    const SDL_FRect Rect{ X, Y, Width, Height };
    SDL_RenderFillRect(Renderer, &Rect);
}

void DrawTownTrainingSwordItemSprite(SDL_Renderer* Renderer, const Main64Palette& Palette,
    const std::array<std::uint8_t, TownSwordItemSpritePixelCount>& Pixels)
{
    SDL_SetRenderDrawBlendMode(Renderer, SDL_BLENDMODE_NONE);
    for (std::size_t Row = 0; Row < TownSwordItemSpriteHeight; ++Row)
    {
        for (std::size_t Column = 0; Column < TownSwordItemSpriteWidth; ++Column)
        {
            const std::uint8_t PaletteIndex = Pixels[Row * TownSwordItemSpriteWidth + Column];
            Mcga::DrawIndexedPixel(Renderer, Palette, PaletteIndex,
                static_cast<float>(TownSwordItemHudScreenX + Column),
                static_cast<float>(TownSwordItemHudScreenY + Row));
        }
    }
}

void DrawTownThinFontGlyph(SDL_Renderer* Renderer, const Main64Palette& Palette, const Grp::FontGroup& FontGroup,
    float StartX, float StartY, std::uint8_t PrimaryColorIndex, std::uint8_t ShadowColorIndex, char Character)
{
    const unsigned char CharacterIndex = static_cast<unsigned char>(Character);
    if (CharacterIndex < 32)
    {
        return;
    }

    const std::size_t GlyphIndex = static_cast<std::size_t>(CharacterIndex - 32);
    if (GlyphIndex >= FontGroup.Glyphs.size())
    {
        return;
    }

    const Grp::FontGlyph& Glyph = FontGroup.Glyphs[GlyphIndex];

    for (std::size_t Row = 0; Row < 8 && Row < Glyph.Rows.size(); ++Row)
    {
        const std::uint8_t Bits = Glyph.Rows[Row];
        for (std::size_t Column = 0; Column < 4; ++Column)
        {
            if (((Bits >> (7 - Column)) & 1) == 0)
            {
                continue;
            }

            Mcga::DrawIndexedPixel(Renderer, Palette, ShadowColorIndex, StartX + static_cast<float>(Column + 1),
                StartY + static_cast<float>(Row));
            Mcga::DrawIndexedPixel(Renderer, Palette, PrimaryColorIndex, StartX + static_cast<float>(Column),
                StartY + static_cast<float>(Row));
        }
    }
}

void DrawTownThinFontText(SDL_Renderer* Renderer, const Main64Palette& Palette, const Grp::FontGroup& FontGroup,
    float StartX, float StartY, std::uint8_t PrimaryColorIndex, std::uint8_t ShadowColorIndex,
    const std::string& Text)
{
    float CursorX = StartX;
    for (char Character : Text)
    {
        if (Character == '\n')
        {
            CursorX = StartX;
            StartY += 8.0f;
            continue;
        }

        DrawTownThinFontGlyph(Renderer, Palette, FontGroup, CursorX, StartY, PrimaryColorIndex, ShadowColorIndex,
            Character);
        CursorX += 5.0f;
    }
}

void DrawTownDecimalDigitGlyph(SDL_Renderer* Renderer, const Main64Palette& Palette, const Grp::FontGroup& FontGroup,
    float StartX, float StartY, std::uint8_t DigitValue)
{
    FillTownHudRect(Renderer, Palette, 5, StartX, StartY, 6.0f, 7.0f);

    if (DigitValue == 0xFF || DigitValue >= FontGroup.Glyphs.size())
    {
        return;
    }

    const Grp::FontGlyph& Glyph = FontGroup.Glyphs[DigitValue];
    for (std::size_t Row = 0; Row < 7 && Row < Glyph.Rows.size(); ++Row)
    {
        const std::uint8_t Bits = Glyph.Rows[Row];
        for (std::size_t Column = 0; Column < 6; ++Column)
        {
            if (((Bits >> (5 - Column)) & 1) == 0)
            {
                continue;
            }

            Mcga::DrawIndexedPixel(Renderer, Palette, 9, StartX + static_cast<float>(Column),
                StartY + static_cast<float>(Row));
        }
    }
}

void DrawTownDecimalZeroField(SDL_Renderer* Renderer, const Main64Palette& Palette, const Grp::FontGroup& FontGroup,
    float StartX, float StartY, std::size_t FirstDigitBufferIndex, std::size_t DigitCount)
{
    constexpr std::array<std::uint8_t, 7> ZeroDigitBuffer{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0 };

    for (std::size_t DigitIndex = 0; DigitIndex < DigitCount; ++DigitIndex)
    {
        const std::size_t BufferIndex = FirstDigitBufferIndex + DigitIndex;
        if (BufferIndex >= ZeroDigitBuffer.size())
        {
            return;
        }

        DrawTownDecimalDigitGlyph(Renderer, Palette, FontGroup, StartX + static_cast<float>(DigitIndex * 6),
            StartY, ZeroDigitBuffer[BufferIndex]);
    }
}

void DrawTownHudBar(SDL_Renderer* Renderer, const Main64Palette& Palette, std::uint8_t PaddingLeft,
    std::uint8_t PaddingTop, std::uint8_t ColumnCount)
{
    const float StartX = 48.0f + static_cast<float>(PaddingLeft);
    const float StartY = 158.0f + static_cast<float>(PaddingTop);

    FillTownHudRect(Renderer, Palette, 0, StartX, StartY, 1.0f, 10.0f);
    if (ColumnCount == 0)
    {
        return;
    }

    const float FillX = StartX + 1.0f;
    const float FillWidth = static_cast<float>(ColumnCount);
    FillTownHudRect(Renderer, Palette, 0, FillX, StartY, FillWidth, 1.0f);
    FillTownHudRect(Renderer, Palette, 5, FillX, StartY + 1.0f, FillWidth, 8.0f);
    FillTownHudRect(Renderer, Palette, 0x2D, FillX, StartY + 9.0f, FillWidth, 1.0f);
}

void DrawTownHudBars(SDL_Renderer* Renderer, const Main64Palette& Palette)
{
    DrawTownHudBar(Renderer, Palette, 0x02, 0x04, 0x21);
    DrawTownHudBar(Renderer, Palette, 0x02, 0x1C, 0x42);
    DrawTownHudBar(Renderer, Palette, 0x48, 0x1C, 0x42);
    DrawTownHudBar(Renderer, Palette, 0x02, 0x10, 0x88);
}

std::size_t NormalizeTownHeroHealthTo100(std::uint16_t Value)
{
    if (Value > TownHeroHealthClampValue)
    {
        return TownHeroHealthBarMaximumPixels;
    }

    return Value >> 3;
}

void ApplyTownHeroHealthVerticalLine(std::array<std::uint8_t,
    TownHeroHealthBarMaximumPixels * TownHeroMaxHealthBarHeight>& Pixels,
    std::size_t Column, std::size_t Height, std::uint8_t Color, std::uint8_t Mask)
{
    for (std::size_t Row = 0; Row < Height; ++Row)
    {
        std::uint8_t& Pixel = Pixels[Row * TownHeroHealthBarMaximumPixels + Column];
        Pixel = static_cast<std::uint8_t>((Pixel & Mask) | Color);
    }
}

void DrawTownHeroHealthBar(SDL_Renderer* Renderer, const Main64Palette& Palette,
    const std::array<std::uint8_t, TownMoleBottomStatusBaseWidth * TownMoleBottomStatusBaseHeight>& BottomStatusBasePixels,
    bool BottomStatusBaseLoaded, std::uint16_t HeroMaxHp, std::uint16_t HeroHp)
{
    std::array<std::uint8_t, TownHeroHealthBarMaximumPixels * TownHeroMaxHealthBarHeight> Pixels{};
    for (std::size_t Row = 0; Row < TownHeroMaxHealthBarHeight; ++Row)
    {
        for (std::size_t Column = 0; Column < TownHeroHealthBarMaximumPixels; ++Column)
        {
            if (!BottomStatusBaseLoaded)
            {
                continue;
            }

            const std::size_t SourceX = TownHeroHealthBarX + Column - TownMoleBottomStatusBaseLeftX;
            const std::size_t SourceY = TownHeroHealthBarY + Row - TownMoleBottomStatusBaseTopY;
            Pixels[Row * TownHeroHealthBarMaximumPixels + Column] =
                BottomStatusBasePixels[SourceY * TownMoleBottomStatusBaseWidth + SourceX];
        }
    }

    const std::size_t MaxHealthPixels = NormalizeTownHeroHealthTo100(HeroMaxHp);
    for (std::size_t Column = 0; Column < MaxHealthPixels; ++Column)
    {
        ApplyTownHeroHealthVerticalLine(Pixels, Column, TownHeroMaxHealthBarHeight,
            TownHeroMaxHealthColor, TownHeroMaxHealthMask);
    }

    const std::size_t CurrentHealthPixels = NormalizeTownHeroHealthTo100(HeroHp);
    for (std::size_t Column = 0; Column < CurrentHealthPixels; ++Column)
    {
        ApplyTownHeroHealthVerticalLine(Pixels, Column, TownHeroHealthBarHeight,
            TownHeroHealthColor, TownHeroHealthMask);
    }

    for (std::size_t Column = CurrentHealthPixels; Column < TownHeroHealthBarMaximumPixels; ++Column)
    {
        ApplyTownHeroHealthVerticalLine(Pixels, Column, TownHeroHealthBarHeight,
            TownHeroEmptyHealthColor, TownHeroEmptyHealthMask);
    }

    SDL_SetRenderDrawBlendMode(Renderer, SDL_BLENDMODE_NONE);
    for (std::size_t Row = 0; Row < TownHeroMaxHealthBarHeight; ++Row)
    {
        for (std::size_t Column = 0; Column < TownHeroHealthBarMaximumPixels; ++Column)
        {
            Mcga::DrawIndexedPixel(Renderer, Palette, Pixels[Row * TownHeroHealthBarMaximumPixels + Column],
                static_cast<float>(TownHeroHealthBarX + Column),
                static_cast<float>(TownHeroHealthBarY + Row));
        }
    }
}

}

void TownScene::UpdateTownPatternAnimations()
{
    AdvanceTownPatternAnimations(TownRuntimeCells, TownMap, PatternBank);
}

void TownScene::TownNpcSpriteShadowBuffer::FlushForMapColumn(SDL_Renderer* Renderer, const Main64Palette& Palette,
    std::size_t MapColumn, std::size_t& RenderedNpcSpriteCount)
{
    for (auto SliceIterator = Slices.begin(); SliceIterator != Slices.end(); )
    {
        if (SliceIterator->MapColumn != MapColumn)
        {
            ++SliceIterator;
            continue;
        }

        TownRender::DrawNpcFrameColumnSlice(Renderer, *SliceIterator->SpriteFrame, Palette,
            SliceIterator->MapPixelX, SliceIterator->MapPixelY, SliceIterator->ScrollOffsetPixels,
            SliceIterator->MapColumn);

        if (SliceIterator->IsCurrentColumn)
        {
            ++RenderedNpcSpriteCount;
        }

        SliceIterator = Slices.erase(SliceIterator);
    }
}

TownScene::TownHeadLevelTiles TownScene::SaveHeadLevelTilesInNpcs() const
{
    TownHeadLevelTiles HeadLevelTiles;
    HeadLevelTiles.Tiles.assign(TownMap.Width, 0);
    HeadLevelTiles.OriginalTiles.assign(TownMap.Width, 0);
    HeadLevelTiles.HasOriginalTile.assign(TownMap.Width, false);

    for (std::size_t Column = 0; Column < TownMap.Width; ++Column)
    {
        std::uint8_t TileIndex = 0;
        if (TryGetTownMapTileIndexAtCell(TownMap, Column, TownHeadLevelRow, TileIndex))
        {
            HeadLevelTiles.Tiles[Column] = TileIndex;
            HeadLevelTiles.OriginalTiles[Column] = TileIndex;
            HeadLevelTiles.HasOriginalTile[Column] = true;
        }
    }

    // Keep the saved head tile in the live NPC record so the restore path can
    // put the row back together later without a separate sidecar view.
    for (TownNpcRuntimeRecord& TownNpcRuntimeRecord : TownNpcArray)
    {
        const std::size_t Column = static_cast<std::size_t>(TownNpcRuntimeRecord.X);
        if (Column >= HeadLevelTiles.Tiles.size())
        {
            continue;
        }

        TownNpcRuntimeRecord.HeadTile = HeadLevelTiles.Tiles[Column];
        HeadLevelTiles.Tiles[Column] = TownHeadLevelNpcMarkerTile;
    }

    return HeadLevelTiles;
}

std::size_t TownScene::GetTownHeroAbsoluteX() const noexcept
{
    return static_cast<std::size_t>(TownHeroState.ProximityMapLeftColumnX)
        + static_cast<std::size_t>(TownHeroState.HeroXInViewport) + TownVisibleViewportColumnOffset;
}

std::size_t TownScene::GetTownHeroMapPixelX() const noexcept
{
    const std::size_t HeroAbsoluteX = GetTownHeroAbsoluteX();
    return HeroAbsoluteX == 0 ? 0 : HeroAbsoluteX * TownMapTileSize - 1;
}

std::size_t TownScene::GetTownHeroMapPixelY() const noexcept
{
    return TownMapActorInitialMapPixelY;
}

std::size_t TownScene::GetTownHeroScrollOffsetPixels() const noexcept
{
    const std::size_t VisibleViewportLeftColumn = static_cast<std::size_t>(TownHeroState.ProximityMapLeftColumnX)
        + TownVisibleViewportColumnOffset;
    const std::size_t VisibleViewportScrollOffsetPixels = VisibleViewportLeftColumn * TownMapTileSize;
    return std::min<std::size_t>(VisibleViewportScrollOffsetPixels, GetTownMapMaximumScrollOffset(TownMap));
}

void TownScene::AdvanceTownBackgroundStripScrollOffset(std::ptrdiff_t PixelDelta) noexcept
{
    const std::ptrdiff_t StripWidth = static_cast<std::ptrdiff_t>(TownBackgroundStripWidth);
    std::ptrdiff_t NewOffset = static_cast<std::ptrdiff_t>(TownBackgroundStripScrollPx) + PixelDelta;
    NewOffset %= StripWidth;
    if (NewOffset < 0)
    {
        NewOffset += StripWidth;
    }

    TownBackgroundStripScrollPx = static_cast<std::size_t>(NewOffset);
}

void TownScene::SyncTownHeroRuntimeProjection() noexcept
{
    ActorFacingDirection = (TownHeroState.FacingDirection & 1) != 0
        ? TownMapActorFacingDirection::Left
        : TownMapActorFacingDirection::Right;
    ActorAnimationPhase = static_cast<std::size_t>(TownHeroState.HeroAnimationPhase & 3);
    ActorMapPixelX = GetTownHeroMapPixelX();
    ActorMapPixelY = GetTownHeroMapPixelY();
    ScrollOffsetPixels = GetTownHeroScrollOffsetPixels();
    ActorCollisionBlocked = false;
}

void TownScene::SyncTownHeroStartupActorFrame() noexcept
{
    const std::size_t StartupStandingAnimationPhase = static_cast<std::size_t>(TownHeroState.HeroAnimationPhase | 1);
    ActorFrameIndex = TownActors::GetActorFrameIndex(ActorFacingDirection, false, StartupStandingAnimationPhase);
    (void)UpdateTownMapActorFrame(ActorFrameIndex);
}

void TownScene::UpdateTownHeroRuntimeState(const bool* KeyboardState) noexcept
{
    if (KeyboardState == nullptr)
    {
        SyncTownHeroRuntimeProjection();
        return;
    }

    const bool LeftPressed = KeyboardState[SDL_SCANCODE_LEFT] && !KeyboardState[SDL_SCANCODE_RIGHT];
    const bool RightPressed = KeyboardState[SDL_SCANCODE_RIGHT] && !KeyboardState[SDL_SCANCODE_LEFT];
    const std::size_t MaximumProximityMapLeftColumn =
        TownActors::GetMaximumProximityMapLeftColumn(TownMap);

    if (LeftPressed)
    {
        TownHeroState.FacingDirection |= 1;
    }
    else if (RightPressed)
    {
        TownHeroState.FacingDirection &= 0xFE;
    }
    else
    {
        TownHeroState.HeroAnimationPhase |= 1;
        SyncTownHeroRuntimeProjection();
        return;
    }

    if (LeftPressed)
    {
        if (IsTownHeroBlockedByTownTile(TownMap, PatternBank, TownHeroState.ProximityMapLeftColumnX,
                TownHeroState.HeroXInViewport, true))
        {
            SyncTownHeroRuntimeProjection();
            ActorCollisionBlocked = true;
            return;
        }

        const std::size_t TargetX = GetTownHeroAbsoluteX() - 1;
        if (FindBlockingTownNpcAtX(TownNpcArray, TargetX) != nullptr)
        {
            SyncTownHeroRuntimeProjection();
            ActorCollisionBlocked = true;
            return;
        }

        if (TownHeroState.HeroXInViewport > TownHeroViewportLeftThreshold)
        {
            TownHeroState.HeroAnimationPhase = static_cast<std::uint8_t>((TownHeroState.HeroAnimationPhase + 1) & 3);
            TownHeroState.FacingDirection |= 1;
            --TownHeroState.HeroXInViewport;
        }
        else if (TownHeroState.ProximityMapLeftColumnX > 0)
        {
            TownHeroState.HeroAnimationPhase = static_cast<std::uint8_t>((TownHeroState.HeroAnimationPhase + 1) & 3);
            TownHeroState.FacingDirection |= 1;
            --TownHeroState.ProximityMapLeftColumnX;
            // The assembly scrolls the floor band in 8px steps when the
            // viewport pans, so keep the strip phase aligned to that step.
            AdvanceTownBackgroundStripScrollOffset(8);
        }
        else if (TownHeroState.HeroXInViewport > 0)
        {
            TownHeroState.HeroAnimationPhase = static_cast<std::uint8_t>((TownHeroState.HeroAnimationPhase + 1) & 3);
            TownHeroState.FacingDirection |= 1;
            --TownHeroState.HeroXInViewport;
        }
        else if (TownTransitions::HasEdgeTransition(TownMap, true))
        {
            TownHeroState.HeroAnimationPhase = static_cast<std::uint8_t>((TownHeroState.HeroAnimationPhase + 1) & 3);
            TownHeroState.FacingDirection |= 1;
            // DOS detects the left transition after this byte wraps to 0xFF.
            --TownHeroState.HeroXInViewport;
        }
    }
    else if (RightPressed)
    {
        if (IsTownHeroBlockedByTownTile(TownMap, PatternBank, TownHeroState.ProximityMapLeftColumnX,
                TownHeroState.HeroXInViewport, false))
        {
            SyncTownHeroRuntimeProjection();
            ActorCollisionBlocked = true;
            return;
        }

        const std::size_t TargetX = GetTownHeroAbsoluteX() + 1;
        if (FindBlockingTownNpcAtX(TownNpcArray, TargetX) != nullptr)
        {
            SyncTownHeroRuntimeProjection();
            ActorCollisionBlocked = true;
            return;
        }

        if (TownHeroState.HeroXInViewport < TownHeroViewportRightThreshold)
        {
            TownHeroState.HeroAnimationPhase = static_cast<std::uint8_t>((TownHeroState.HeroAnimationPhase + 1) & 3);
            TownHeroState.FacingDirection &= 0xFE;
            ++TownHeroState.HeroXInViewport;
        }
        else if (TownHeroState.ProximityMapLeftColumnX < MaximumProximityMapLeftColumn)
        {
            TownHeroState.HeroAnimationPhase = static_cast<std::uint8_t>((TownHeroState.HeroAnimationPhase + 1) & 3);
            TownHeroState.FacingDirection &= 0xFE;
            ++TownHeroState.ProximityMapLeftColumnX;
            // Matching the left scroll call keeps the strip moving with the
            // town view instead of drifting independently.
            AdvanceTownBackgroundStripScrollOffset(-8);
        }
        else if (TownHeroState.HeroXInViewport < TownHeroRightEdgeTransitionSentinel)
        {
            TownHeroState.HeroAnimationPhase = static_cast<std::uint8_t>((TownHeroState.HeroAnimationPhase + 1) & 3);
            TownHeroState.FacingDirection &= 0xFE;
            ++TownHeroState.HeroXInViewport;
        }
    }

    SyncTownHeroRuntimeProjection();
}

void TownScene::RestoreHeadLevelTilesFromNpcs(TownHeadLevelTiles& HeadLevelTiles) const
{
    for (const TownNpcRuntimeRecord& TownNpcRuntimeRecord : TownNpcArray)
    {
        const std::size_t Column = static_cast<std::size_t>(TownNpcRuntimeRecord.X);
        if (TownNpcRuntimeRecord.HeadTile == TownHeadLevelNpcMarkerTile || Column >= HeadLevelTiles.Tiles.size())
        {
            continue;
        }

        HeadLevelTiles.Tiles[Column] = TownNpcRuntimeRecord.HeadTile;
    }
}

std::vector<TownScene::TownNpcRuntimeRecord> TownScene::BuildTownNpcRuntimeRecords(const Mdt::TownMapInfo& TownMap)
{
    // Mirror the confirmed NPC STRUC bytes here. The C++ path still uses
    // vectors instead of a synthetic 0xFFFF terminator, so the live mirror is
    // built from parsed town markers and stops at the end of that list.
    std::vector<TownNpcRuntimeRecord> TownNpcRuntimeRecords;
    TownNpcRuntimeRecords.reserve(static_cast<std::size_t>(std::count_if(TownMap.EntityMarkers.begin(),
        TownMap.EntityMarkers.end(),
        [](const Mdt::TownEntityMarker& EntityMarker)
        {
            return EntityMarker.Kind == Mdt::TownEntityKind::Npc;
        })));

    for (const Mdt::TownEntityMarker& EntityMarker : TownMap.EntityMarkers)
    {
        if (EntityMarker.Kind != Mdt::TownEntityKind::Npc)
        {
            continue;
        }

        const std::size_t Column = static_cast<std::size_t>(EntityMarker.X);
        if (Column >= TownMap.Width)
        {
            continue;
        }

        std::uint8_t HeadTile = 0;
        if (!TryGetTownMapTileIndexAtCell(TownMap, Column, TownHeadLevelRow, HeadTile))
        {
            continue;
        }

        TownNpcRuntimeRecords.push_back(TownNpcRuntimeRecord{
            EntityMarker.X,
            HeadTile,
            static_cast<std::uint8_t>((EntityMarker.NpcSpriteSelector & 0x80) != 0 ? 1 : 0),
            EntityMarker.NpcSpriteSelector,
            EntityMarker.NpcAnimationPhase,
            EntityMarker.NpcAiType,
            EntityMarker.NpcFlags,
            EntityMarker.NpcId
        });
    }

    return TownNpcRuntimeRecords;
}

void TownScene::UpdateTownNpcRuntimeRecords() const
{
    const auto SetTownNpcFacing = [](TownNpcRuntimeRecord& RuntimeRecord, bool FaceLeft)
    {
        RuntimeRecord.Facing = FaceLeft ? 1 : 0;
        if (FaceLeft)
        {
            RuntimeRecord.SpriteSelector |= 0x80;
        }
        else
        {
            RuntimeRecord.SpriteSelector &= 0x7F;
        }
    };

    const auto ToggleTownNpcFacing = [&SetTownNpcFacing](TownNpcRuntimeRecord& RuntimeRecord)
    {
        SetTownNpcFacing(RuntimeRecord, RuntimeRecord.Facing == 0);
    };

    const auto UpdateTownNpcFacingTowardHero = [&SetTownNpcFacing](TownNpcRuntimeRecord& RuntimeRecord,
        std::size_t HeroAbsoluteX)
    {
        SetTownNpcFacing(RuntimeRecord, HeroAbsoluteX < RuntimeRecord.X);
    };

    const auto UpdateTownNpcBobInPlace = [](TownNpcRuntimeRecord& RuntimeRecord)
    {
        std::uint8_t AnimPhase = static_cast<std::uint8_t>(RuntimeRecord.AnimationPhase + 0x10);
        RuntimeRecord.AnimationPhase = AnimPhase;

        if ((AnimPhase & 0x30) != 0)
        {
            return;
        }

        RuntimeRecord.AnimationPhase = static_cast<std::uint8_t>((AnimPhase + 1) & 1);
    };

    const auto AdvanceTownNpcPatrolPhase = [](TownNpcRuntimeRecord& RuntimeRecord, std::uint8_t PhaseMask) -> bool
    {
        std::uint8_t AnimPhase = static_cast<std::uint8_t>(RuntimeRecord.AnimationPhase + 0x10);
        RuntimeRecord.AnimationPhase = AnimPhase;
        if ((AnimPhase & PhaseMask) != 0)
        {
            return false;
        }

        RuntimeRecord.AnimationPhase = static_cast<std::uint8_t>((AnimPhase + 1) & 0x0F);
        return true;
    };

    const auto UpdateTownNpcPatrolBetweenBoundaries = [&AdvanceTownNpcPatrolPhase, &SetTownNpcFacing](TownNpcRuntimeRecord& RuntimeRecord,
        const Mdt::TownNpcPatrolBoundaries& PatrolBoundaries, bool HasPatrolBoundaries, std::uint8_t PhaseMask)
    {
        if (!AdvanceTownNpcPatrolPhase(RuntimeRecord, PhaseMask))
        {
            return;
        }

        if (!HasPatrolBoundaries)
        {
            return;
        }

        std::uint16_t NpcX = RuntimeRecord.X;
        if (RuntimeRecord.Facing != 0)
        {
            --NpcX;
            RuntimeRecord.X = NpcX;
            if (NpcX <= PatrolBoundaries.MinimumX)
            {
                SetTownNpcFacing(RuntimeRecord, false);
            }
            return;
        }

        ++NpcX;
        RuntimeRecord.X = NpcX;
        if (NpcX > PatrolBoundaries.MaximumX)
        {
            SetTownNpcFacing(RuntimeRecord, true);
        }
    };

    const auto UpdateTownNpcPatrolBounce = [&AdvanceTownNpcPatrolPhase, &ToggleTownNpcFacing](TownNpcRuntimeRecord& RuntimeRecord,
        std::uint8_t PhaseMask)
    {
        if (!AdvanceTownNpcPatrolPhase(RuntimeRecord, PhaseMask))
        {
            return;
        }

        if ((RuntimeRecord.AnimationPhase & TownNpcPatrolBounceTurnMask) == 0)
        {
            ToggleTownNpcFacing(RuntimeRecord);
            return;
        }

        std::uint16_t NpcX = RuntimeRecord.X;
        if (RuntimeRecord.Facing != 0)
        {
            --NpcX;
        }
        else
        {
            ++NpcX;
        }

        RuntimeRecord.X = NpcX;
    };

    const std::size_t HeroAbsoluteX = TownHeroState.HeroXInViewport + TownVisibleViewportColumnOffset
        + TownHeroState.ProximityMapLeftColumnX;

    for (TownNpcRuntimeRecord& TownNpcRuntimeRecord : TownNpcArray)
    {
        switch (TownNpcRuntimeRecord.NpcAiType)
        {
        case NpcAiTypeLookAtHeroAndBob:
            UpdateTownNpcFacingTowardHero(TownNpcRuntimeRecord, HeroAbsoluteX);
            UpdateTownNpcBobInPlace(TownNpcRuntimeRecord);
            break;

        case NpcAiTypePatrol1BitPhase:
            UpdateTownNpcPatrolBetweenBoundaries(TownNpcRuntimeRecord, TownMap.NpcPatrolBoundaries,
                TownMap.HasNpcPatrolBoundaries,
                TownNpcPatrolStepPhaseMaskOneBit);
            break;

        case NpcAiTypePatrol2BitPhase:
            UpdateTownNpcPatrolBetweenBoundaries(TownNpcRuntimeRecord, TownMap.NpcPatrolBoundaries,
                TownMap.HasNpcPatrolBoundaries,
                TownNpcPatrolStepPhaseMaskTwoBit);
            break;

        case NpcAiTypeFaceHero:
            UpdateTownNpcFacingTowardHero(TownNpcRuntimeRecord, HeroAbsoluteX);
            break;

        case NpcAiTypeBobInPlace:
            UpdateTownNpcBobInPlace(TownNpcRuntimeRecord);
            break;

        case NpcAiTypePatrolBounce1Bit:
            UpdateTownNpcPatrolBounce(TownNpcRuntimeRecord, TownNpcPatrolStepPhaseMaskOneBit);
            break;

        case NpcAiTypePatrolBounce2Bit:
            UpdateTownNpcPatrolBounce(TownNpcRuntimeRecord, TownNpcPatrolStepPhaseMaskTwoBit);
            break;

        case TownNpcAiTypeStatic:
            break;

        default:
            break;
        }
    }
}

void TownScene::SyncTownNpcFacingTowardHero() const
{
    const std::size_t HeroAbsoluteX = TownHeroState.HeroXInViewport + TownVisibleViewportColumnOffset
        + TownHeroState.ProximityMapLeftColumnX;

    const auto SyncTownNpcFacing = [HeroAbsoluteX](TownNpcRuntimeRecord& RuntimeRecord)
    {
        const bool FaceLeft = HeroAbsoluteX < RuntimeRecord.X;
        RuntimeRecord.Facing = FaceLeft ? 1 : 0;
        if (FaceLeft)
        {
            RuntimeRecord.SpriteSelector |= 0x80;
        }
        else
        {
            RuntimeRecord.SpriteSelector &= 0x7F;
        }
    };

    for (TownNpcRuntimeRecord& TownNpcRuntimeRecord : TownNpcArray)
    {
        if (TownNpcRuntimeRecord.NpcAiType == NpcAiTypeLookAtHeroAndBob
            || TownNpcRuntimeRecord.NpcAiType == NpcAiTypeFaceHero)
        {
            SyncTownNpcFacing(TownNpcRuntimeRecord);
        }
    }
}

const TownScene::TownNpcRuntimeRecord* TownScene::FindFirstTownNpcRuntimeRecordForColumn(
    const std::vector<TownNpcRuntimeRecord>& TownNpcArray, std::size_t MapColumn)
{
    for (const TownNpcRuntimeRecord& RuntimeRecord : TownNpcArray)
    {
        if (GetTownNpcRuntimeRecordSpriteColumnMatch(RuntimeRecord, MapColumn) != 0)
        {
            return &RuntimeRecord;
        }
    }

    return nullptr;
}

const TownScene::TownNpcRuntimeRecord* TownScene::FindNextTownNpcRuntimeRecordForColumn(
    const std::vector<TownNpcRuntimeRecord>& TownNpcArray, const TownNpcRuntimeRecord* CurrentRuntimeRecord,
    std::size_t MapColumn)
{
    bool CurrentRuntimeRecordFound = false;
    for (const TownNpcRuntimeRecord& RuntimeRecord : TownNpcArray)
    {
        if (!CurrentRuntimeRecordFound)
        {
            CurrentRuntimeRecordFound = &RuntimeRecord == CurrentRuntimeRecord;
            continue;
        }

        if (GetTownNpcRuntimeRecordSpriteColumnMatch(RuntimeRecord, MapColumn) != 0)
        {
            return &RuntimeRecord;
        }
    }

    return nullptr;
}

void TownScene::DispatchTownSpecialTile(SDL_Renderer* Renderer, std::size_t MapColumn,
    const std::vector<TownNpcRuntimeRecord>& TownNpcArray, std::size_t ScrollOffsetPixels,
    TownNpcSpriteShadowBuffer& ShadowBuffer, TownColumnRenderStats& RenderStats) const
{
    const TownNpcRuntimeRecord* RuntimeRecord = FindFirstTownNpcRuntimeRecordForColumn(TownNpcArray, MapColumn);
    while (RuntimeRecord != nullptr)
    {
        const std::uint8_t ColumnMatch = GetTownNpcRuntimeRecordSpriteColumnMatch(*RuntimeRecord, MapColumn);
        const std::size_t SpriteColumn = static_cast<std::size_t>(RuntimeRecord->X);
        const std::size_t SpriteFamily = static_cast<std::size_t>(RuntimeRecord->SpriteSelector & 0x0F);
        const std::size_t FrameIndex = TownScene::GetTownNpcSpriteFrameIndex(RuntimeRecord->SpriteSelector,
            RuntimeRecord->AnimationPhase);
        const Grp::NpcSpriteFrame* SpriteFrame = nullptr;

        const bool HasSpriteFrame =
            TownNpc::IsConfirmedSpriteFamily(SpriteFamily)
            && TryGetTownNpcSpriteFrame(FrameIndex, SpriteFrame);

        if (ColumnMatch == 2)
        {
            if (!HasSpriteFrame)
            {
                ++RenderStats.NpcSpriteMissCount;
            }
            else
            {
                ShadowBuffer.AddCurrentColumnSlice(*SpriteFrame,
                    SpriteColumn * TownMapTileSize,
                    TownSpriteBandPixelY,
                    ScrollOffsetPixels,
                    SpriteColumn);
                ShadowBuffer.AddNextColumnSlice(*SpriteFrame,
                    SpriteColumn * TownMapTileSize,
                    TownSpriteBandPixelY,
                    ScrollOffsetPixels,
                    SpriteColumn + 1);
            }
        }
        else if (ColumnMatch == 1 && HasSpriteFrame)
        {
            ShadowBuffer.AddCurrentColumnSlice(*SpriteFrame,
                SpriteColumn * TownMapTileSize,
                TownSpriteBandPixelY,
                ScrollOffsetPixels,
                SpriteColumn);
        }

        RuntimeRecord = FindNextTownNpcRuntimeRecordForColumn(TownNpcArray, RuntimeRecord, MapColumn);
    }
}

void TownScene::RenderTownColumn(SDL_Renderer* Renderer, std::size_t MapColumn, float ScreenTileX,
    const TownHeadLevelTiles& HeadLevelTiles, const std::vector<TownNpcRuntimeRecord>& TownNpcArray,
    std::size_t ScrollOffsetPixels, TownNpcSpriteShadowBuffer& ShadowBuffer,
    TownColumnRenderStats& RenderStats) const
{
    const Grp::PatternTile& FallbackTile = GetFallbackPatternTile();
    const auto TryGetRuntimeTileIndexAtCell = [this](std::size_t Column, std::size_t Row, std::uint8_t& TileIndex) -> bool
    {
        if (Column >= TownMap.Width || Row >= TownMap.Height)
        {
            return false;
        }

        const std::size_t CellIndex = Column * TownMap.Height + Row;
        if (CellIndex >= TownRuntimeCells.size())
        {
            return false;
        }

        TileIndex = TownRuntimeCells[CellIndex];
        return true;
    };

    const bool HasTownNpcMarker = MapColumn < HeadLevelTiles.Tiles.size()
        && HeadLevelTiles.Tiles[MapColumn] == TownHeadLevelNpcMarkerTile;

    for (std::size_t Row = 0; Row < TownMap.Height; ++Row)
    {
        std::uint8_t TileIndex = 0;
        if (Row == TownHeadLevelRow && MapColumn < HeadLevelTiles.Tiles.size())
        {
            TileIndex = HeadLevelTiles.Tiles[MapColumn];
            if (TileIndex == TownHeadLevelNpcMarkerTile && MapColumn < HeadLevelTiles.OriginalTiles.size()
                && HeadLevelTiles.HasOriginalTile[MapColumn])
            {
                TileIndex = HeadLevelTiles.OriginalTiles[MapColumn];
            }
        }
        else if (!TryGetRuntimeTileIndexAtCell(MapColumn, Row, TileIndex))
        {
            continue;
        }

        const Grp::PatternTile* Tile = nullptr;
        if (TileIndex < PatternBank.Tiles.size())
        {
            Tile = &PatternBank.Tiles[TileIndex];
        }
        else
        {
            if (!FallbackWarningPrinted)
            {
                std::cerr << "town MDT tile at column " << MapColumn << ", row " << Row
                    << " uses tile index " << static_cast<int>(TileIndex)
                    << " outside the active town pattern bank; drawing fallback tiles." << '\n';
                FallbackWarningPrinted = true;
            }

            Tile = &FallbackTile;
        }

        const bool UseTransparencyMask = Row < 3;
        TownRender::DrawPatternTile(Renderer, *Tile, Palette,
            static_cast<float>(TownViewportLeftX) + ScreenTileX,
            static_cast<float>(TownViewportTopY + Row * TownMapTileSize), 1.0f, UseTransparencyMask);

    }

    // Match the DOS flow: only the row-5 0xFD marker opens the NPC compositor.
    if (HasTownNpcMarker)
    {
        DispatchTownSpecialTile(Renderer, MapColumn, TownNpcArray, ScrollOffsetPixels,
            ShadowBuffer, RenderStats);
    }

    // Flush only the slices that belong to the column whose background was just drawn.
    ShadowBuffer.FlushForMapColumn(Renderer, Palette, MapColumn, RenderStats.RenderedNpcSpriteCount);

    if (ActorFrameLoaded && ActorFrameVisible)
    {
        TownRender::DrawNpcFrameColumnSlice(Renderer, ActorFrame, Palette,
            ActorMapPixelX, ActorMapPixelY,
            ScrollOffsetPixels, MapColumn);
    }
}

TownScene::TownScene(const std::filesystem::path& ActorSpriteGrpPath, const std::filesystem::path& TownNpcSpriteGrpPath,
    const Mdt::TownMapInfo& TownMap,
    const Grp::PatternBank& PatternBank, const Main64Palette& Palette)
    : ActorSpriteGrpPath(ActorSpriteGrpPath), TownNpcSpriteGrpPath(TownNpcSpriteGrpPath), TownMap(TownMap), PatternBank(PatternBank), Palette(Palette)
{
    ReloadTownState();
}

void TownScene::ResetTownSceneState(std::optional<TownHeroRuntimeState> TransitionHeroState) noexcept
{
    TownHeroState = TownHeroRuntimeState{};
    if (TransitionHeroState.has_value())
    {
        TownHeroState = *TransitionHeroState;
    }

    ActorFacingDirection = TownMapActorFacingDirection::Right;
    ActorAnimationPhase = 0;
    ActorAnimationTickCount = 0;
    ActorFrameIndex = 0;
    ActorMapPixelX = TownMapActorInitialMapPixelX;
    ActorMapPixelY = TownMapActorInitialMapPixelY;
    ScrollOffsetPixels = 0;
    ActorFrameLoaded = false;
    ActorFrameVisible = false;
    ActorFrameWarningPrinted = false;
    ActorCollisionBlocked = false;
    TownBackgroundMountainLayerLoaded = false;
    TownBackgroundStripLoaded = false;
    TownBackgroundStripUsesCkpd = false;
    TownMoleDecorationPanelsLoaded = false;
    TownMoleTopTearsBaseLoaded = false;
    TownMoleBottomStatusBaseLoaded = false;
    TownTearsOverlayIconsLoaded = false;
    TownTrainingSwordItemSpriteLoaded = false;
    TownHudFontsLoaded = false;
    TownBackgroundStripScrollPx = 0;
    TownRuntimeCells.clear();
    TownNpcArray.clear();
    TownDialogOpen = false;
    TownDialogHasMorePages = false;
    TownDialogContinuationCursorVisible = false;
    TownSpaceWasDown = false;
    TownAltWasDown = false;
    TownDialogControlWarningPrinted = false;
    TownDialogRestoreNpcState = false;
    TownDialogNpcRuntimeIndex = 0;
    TownDialogNpcOriginalFacing = 0;
    TownDialogNpcOriginalSpriteSelector = 0;
    TownDialogNpcOriginalAiType = 0;
    TownDialogConversationIndex = 0;
    TownDialogByteOffset = 0;
    TownDialogLineCount = 0;
    TownDialogBoxLeftX = 0;
    TownDialogBoxTopY = 0;
    TownDialogBoxHeight = 0;
    TownDialogCharX = 0;
    TownDialogCharY = 0;
    TownDialogLinesRendered = 0;
    TownDialogRenderTextOffset = 0;
    TownDialogPageText.clear();
    TownDialogOverlayPixels.clear();
    TownEdgeTransitionQueued = false;
    FallbackWarningPrinted = false;
    TownNpcSpriteFrames.fill({});
    TownNpcSpriteFrameLoaded.fill(false);
    TownNpcSpriteFrameVisible.fill(false);
    TownNpcSpriteFrameWarningPrinted = false;
    TownBackgroundMountainLayerPixels.fill(0);
    TownBackgroundStripPixels.fill(0);
    TownBoldFontGroup.Glyphs.clear();
    TownThinFontGroup.Glyphs.clear();
    TownDigitFontGroup.Glyphs.clear();
}

void TownScene::ReloadTownState(std::optional<TownHeroRuntimeState> TransitionHeroState, bool LoadTownNpcRecords)
{
    ResetTownSceneState(TransitionHeroState);

    TownRuntimeCells = TownMap.Cells;
    if (LoadTownNpcRecords)
    {
        // Rebuild the active town NPC runtime records from the loaded map.
        TownNpcArray = BuildTownNpcRuntimeRecords(TownMap);
        SyncTownNpcFacingTowardHero();
    }
    TownBackgroundStripUsesCkpd = TownMap.HasMiddleLayer;
    const std::filesystem::path TownBackgroundBinPath = ActorSpriteGrpPath.parent_path()
        / (TownBackgroundStripUsesCkpd ? "ckpd.bin" : "ympd.bin");
    if (!TownBackgroundStripUsesCkpd)
    {
        std::string TownBackgroundMountainLayerErrorMessage;
        TownBackgroundMountainLayerLoaded = LoadTownBackgroundMountainLayerPixels(TownBackgroundBinPath,
            TownBackgroundMountainLayerPixels, TownBackgroundMountainLayerErrorMessage);
        if (!TownBackgroundMountainLayerLoaded)
        {
            std::cerr << TownBackgroundBinPath.filename().string() << " mountain layer load failed: "
                << TownBackgroundMountainLayerErrorMessage << '\n';
        }
    }

    std::string TownBackgroundStripErrorMessage;
    TownBackgroundStripLoaded = LoadTownBackgroundStripPixels(TownBackgroundBinPath, TownBackgroundStripUsesCkpd,
        TownBackgroundStripPixels, TownBackgroundStripErrorMessage);
    if (!TownBackgroundStripLoaded)
    {
        std::cerr << TownBackgroundBinPath.filename().string() << " lower strip load failed: "
            << TownBackgroundStripErrorMessage << '\n';
    }

    const std::filesystem::path TownMoleBinPath = ActorSpriteGrpPath.parent_path() / "mole.bin";
    std::string TownMoleTopTearsBaseErrorMessage;
    TownMoleTopTearsBaseLoaded = LoadTownMoleTopTearsBasePanel(TownMoleBinPath,
        TownMoleTopTearsBasePixels, TownMoleTopTearsBaseErrorMessage);
    if (!TownMoleTopTearsBaseLoaded)
    {
        std::cerr << TownMoleBinPath.filename().string() << " top tears base panel load failed: "
            << TownMoleTopTearsBaseErrorMessage << '\n';
    }

    std::string TownMoleDecorationPanelsErrorMessage;
    TownMoleDecorationPanelsLoaded = LoadTownMoleDecorationPanels(TownMoleBinPath,
        TownMoleLeftDecorationPanelPixels, TownMoleRightDecorationPanelPixels, TownMoleDecorationPanelsErrorMessage);
    if (!TownMoleDecorationPanelsLoaded)
    {
        std::cerr << TownMoleBinPath.filename().string() << " decoration panel load failed: "
            << TownMoleDecorationPanelsErrorMessage << '\n';
    }

    std::string TownMoleBottomStatusBaseErrorMessage;
    TownMoleBottomStatusBaseLoaded = LoadTownMoleBottomStatusBasePanel(TownMoleBinPath,
        TownMoleBottomStatusBasePixels, TownMoleBottomStatusBaseErrorMessage);
    if (!TownMoleBottomStatusBaseLoaded)
    {
        std::cerr << TownMoleBinPath.filename().string() << " bottom/status base panel load failed: "
            << TownMoleBottomStatusBaseErrorMessage << '\n';
    }

    const std::filesystem::path TownGmmcgaBinPath = ActorSpriteGrpPath.parent_path().parent_path() / "gmmcga.bin";
    std::string TownTearsOverlayIconsErrorMessage;
    TownTearsOverlayIconsLoaded = Hud::LoadTearsOverlayIcons(TownGmmcgaBinPath,
        TownTearsOverlaySmallIconPixels, TownTearsOverlayLargeIconPixels, TownTearsOverlayIconsErrorMessage);
    if (!TownTearsOverlayIconsLoaded)
    {
        std::cerr << TownGmmcgaBinPath.filename().string() << " collected Tears icon load failed: "
            << TownTearsOverlayIconsErrorMessage << '\n';
    }

    const std::filesystem::path TownItempGrpPath = ActorSpriteGrpPath.parent_path() / "itemp.grp";
    std::string TownTrainingSwordItemSpriteErrorMessage;
    TownTrainingSwordItemSpriteLoaded = LoadTownTrainingSwordItemSprite(TownItempGrpPath,
        TownTrainingSwordItemSpritePixels, TownTrainingSwordItemSpriteErrorMessage);
    if (!TownTrainingSwordItemSpriteLoaded)
    {
        std::cerr << TownItempGrpPath.filename().string() << " Training Sword item sprite load failed: "
            << TownTrainingSwordItemSpriteErrorMessage << '\n';
    }

    const std::filesystem::path TownFontGrpPath = ActorSpriteGrpPath.parent_path() / "font.grp";
    std::string TownHudFontErrorMessage;
    TownHudFontsLoaded = LoadTownHudFontGroups(TownFontGrpPath, TownBoldFontGroup, TownThinFontGroup,
        TownDigitFontGroup, TownHudFontErrorMessage);
    if (!TownHudFontsLoaded)
    {
        std::cerr << TownFontGrpPath.filename().string() << " HUD font load failed: "
            << TownHudFontErrorMessage << '\n';
    }

    SyncTownHeroRuntimeProjection();
    if (TransitionHeroState.has_value())
    {
        ActorFrameIndex = TownActors::GetActorFrameIndex(ActorFacingDirection, false, ActorAnimationPhase);
        (void)UpdateTownMapActorFrame(ActorFrameIndex);
    }
    else
    {
        SyncTownHeroStartupActorFrame();
    }
}

std::optional<Mdt::TownTransitionData> TownScene::Update(const bool* KeyboardState)
{
    if (KeyboardState == nullptr)
    {
        return std::nullopt;
    }

    const bool SpaceIsDown = KeyboardState[SDL_SCANCODE_SPACE];
    const bool SpacePressedThisTick = SpaceIsDown && !TownSpaceWasDown;
    const bool AltIsDown = KeyboardState[SDL_SCANCODE_LALT] || KeyboardState[SDL_SCANCODE_RALT];
    const bool AltPressedThisTick = AltIsDown && !TownAltWasDown;
    TownSpaceWasDown = SpaceIsDown;
    TownAltWasDown = AltIsDown;

    if (TownDialogOpen)
    {
        if (SpacePressedThisTick || AltPressedThisTick)
        {
            AdvanceTownDialog();
        }

        if (TownDialogOpen)
        {
            UpdateTownDialogTownFrame();
        }
        return std::nullopt;
    }

    if (SpacePressedThisTick && TryOpenTownDialog())
    {
        UpdateTownDialogTownFrame();
        return std::nullopt;
    }

    if (const std::optional<Mdt::TownTransitionData> Transition = GetEdgeTownTransition(true))
    {
        TownEdgeTransitionQueued = true;
        return Transition;
    }

    if (const std::optional<Mdt::TownTransitionData> Transition = GetEdgeTownTransition(false))
    {
        TownEdgeTransitionQueued = true;
        return Transition;
    }

    if (TryOpenTownSpecialDialog())
    {
        UpdateTownDialogTownFrame();
        return std::nullopt;
    }

    UpdateTownHeroRuntimeState(KeyboardState);
    UpdateTownNpcRuntimeRecords();
    UpdateTownPatternAnimations();

    if (const std::optional<Mdt::TownTransitionData> Transition = GetEdgeTownTransition(true))
    {
        TownEdgeTransitionQueued = true;
        return Transition;
    }

    if (const std::optional<Mdt::TownTransitionData> Transition = GetEdgeTownTransition(false))
    {
        TownEdgeTransitionQueued = true;
        return Transition;
    }

    const std::size_t DesiredTownMapActorFrameIndex =
        TownActors::GetActorFrameIndex(ActorFacingDirection, true, ActorAnimationPhase);
    (void)UpdateTownMapActorFrame(DesiredTownMapActorFrameIndex);
    return std::nullopt;
}

std::uint8_t TownScene::GetHeroXInViewport() const noexcept
{
    return TownHeroState.HeroXInViewport;
}

std::uint16_t TownScene::GetProximityMapLeftColumnX() const noexcept
{
    return TownHeroState.ProximityMapLeftColumnX;
}

void TownScene::Draw(SDL_Renderer* Renderer) const
{
    constexpr std::size_t TileSize = TownMapTileSize;
    constexpr std::size_t VisibleColumns = TownMapVisibleColumns;
    const std::size_t ClampedScrollOffset = std::min<std::size_t>(ScrollOffsetPixels,
        GetTownMapMaximumScrollOffset(TownMap));
    const std::size_t FirstColumn = ClampedScrollOffset / TileSize;
    const std::size_t ColumnPixelOffset = ClampedScrollOffset % TileSize;
    const std::size_t ColumnsAvailable = TownMap.Width > FirstColumn ? TownMap.Width - FirstColumn : 0;
    const std::size_t ColumnsToRender = std::min<std::size_t>(ColumnsAvailable, VisibleColumns + (ColumnPixelOffset != 0 ? 1 : 0));
    TownHeadLevelTiles HeadLevelTiles = SaveHeadLevelTilesInNpcs();
    TownColumnRenderStats RenderStats{};
    TownNpcSpriteShadowBuffer ShadowBuffer;
    ShadowBuffer.Reserve(TownNpcArray.size() * 2);

    if (TownMoleDecorationPanelsLoaded)
    {
        Hud::DrawMolePanel(Renderer, Palette, TownMoleLeftDecorationPanelPixels,
            TownMoleDecorationPanelWidth, TownMoleDecorationPanelHeight, TownMoleDecorationPanelLeftX, 0);
        Hud::DrawMolePanel(Renderer, Palette, TownMoleRightDecorationPanelPixels,
            TownMoleDecorationPanelWidth, TownMoleDecorationPanelHeight, TownMoleDecorationPanelRightX, 0);
    }

    if (TownMoleTopTearsBaseLoaded)
    {
        Hud::DrawMolePanel(Renderer, Palette, TownMoleTopTearsBasePixels,
            TownMoleTopTearsBaseWidth, TownMoleTopTearsBaseHeight,
            TownMoleTopTearsBaseLeftX, TownMoleTopTearsBaseTopY);
    }

    if (TownTearsOverlayIconsLoaded)
    {
        Hud::DrawTearsOverlay(Renderer, Palette, TownTearsOverlaySmallIconPixels, TownTearsOverlayLargeIconPixels,
            TearsOfEsmesantiCount, false);
    }

    if (TownBackgroundMountainLayerLoaded)
    {
        TownRender::DrawMountainLayer(Renderer, TownBackgroundMountainLayerPixels, Palette);
    }

    for (std::size_t Column = 0; Column < ColumnsToRender; ++Column)
    {
        const std::size_t MapColumn = FirstColumn + Column;
        const float TileX = static_cast<float>(Column * TileSize) - static_cast<float>(ColumnPixelOffset);
        RenderTownColumn(Renderer, MapColumn, TileX, HeadLevelTiles, TownNpcArray, ClampedScrollOffset,
            ShadowBuffer, RenderStats);
    }

    RestoreHeadLevelTilesFromNpcs(HeadLevelTiles);

    if (TownBackgroundStripLoaded)
    {
        TownRender::DrawBackgroundStrip(Renderer, TownBackgroundStripPixels, Palette,
            TownBackgroundStripScrollPx);
    }

    if (TownMoleBottomStatusBaseLoaded)
    {
        Hud::DrawMolePanel(Renderer, Palette, TownMoleBottomStatusBasePixels,
            TownMoleBottomStatusBaseWidth, TownMoleBottomStatusBaseHeight,
            TownMoleBottomStatusBaseLeftX, TownMoleBottomStatusBaseTopY);
    }

    if (TownTrainingSwordItemSpriteLoaded)
    {
        DrawTownTrainingSwordItemSprite(Renderer, Palette, TownTrainingSwordItemSpritePixels);
    }

    DrawTownHudBars(Renderer, Palette);
    DrawTownHeroHealthBar(Renderer, Palette, TownMoleBottomStatusBasePixels, TownMoleBottomStatusBaseLoaded,
        TownHudHealth.HeroMaxHp, TownHudHealth.HeroHp);

    if (TownHudFontsLoaded && !TownThinFontGroup.Glyphs.empty() && !TownDigitFontGroup.Glyphs.empty())
    {
        DrawTownThinFontText(Renderer, Palette, TownThinFontGroup, 56.0f, 163.0f, 0x1B, 0x12, "LIFE");
        DrawTownThinFontText(Renderer, Palette, TownThinFontGroup, 123.0f, 187.0f, 0x1B, 0x12, "ALMAS");
        DrawTownThinFontText(Renderer, Palette, TownThinFontGroup, 53.0f, 187.0f, 0x1B, 0x12, "GOLD");
        DrawTownThinFontText(Renderer, Palette, TownThinFontGroup, 53.0f, 175.0f, 0x1B, 0x12, "PLACE");

        DrawTownDecimalZeroField(Renderer, Palette, TownDigitFontGroup, 78.0f, 187.0f, 1, 6);
        DrawTownDecimalZeroField(Renderer, Palette, TownDigitFontGroup, 154.0f, 187.0f, 2, 5);

        if (TownMap.TownNameInfo.IsValid)
        {
            DrawTownThinFontText(Renderer, Palette, TownThinFontGroup,
                static_cast<float>(TownMap.TownNameInfo.LeftMargin * 4 + TownMap.TownNameInfo.FineXOffset),
                static_cast<float>(TownMap.TownNameInfo.TopMargin),
                9, 0x2D, TownMap.TownNameInfo.Text);
        }
    }

    LogTearsCollectedOverlayState(TearsOfEsmesantiCount,
        std::min<std::size_t>(TearsOfEsmesantiCount, Hud::MaxTearsOverlayCount));

    if (!(ActorFrameLoaded && ActorFrameVisible))
    {
        TownRender::DrawActorFallbackMarker(Renderer, static_cast<float>(ActorMapPixelX),
            static_cast<float>(ActorMapPixelY), ClampedScrollOffset);
    }

    if (TownDialogOpen)
    {
        DrawTownDialog(Renderer);
    }
}

void TownScene::LogTearsCollectedOverlayState(std::uint8_t RawTearsCount, std::size_t DrawCount) const
{
    if (!TownTearsOverlayStateLogInitialized
        || RawTearsCount != TownTearsOverlayLastLoggedRawCount
        || DrawCount != TownTearsOverlayLastLoggedDrawCount)
    {
        std::cerr << "town tears overlay state: raw count " << static_cast<unsigned int>(RawTearsCount)
            << ", draw count " << DrawCount << '\n';
        TownTearsOverlayStateLogInitialized = true;
        TownTearsOverlayLastLoggedRawCount = RawTearsCount;
        TownTearsOverlayLastLoggedDrawCount = DrawCount;
    }
}
