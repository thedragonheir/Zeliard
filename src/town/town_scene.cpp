#include "town_scene.h"

#include <algorithm>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <filesystem>
#include <iostream>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

namespace Grp
{
bool LoadTownHeroSpriteFrame(const std::filesystem::path& Path, std::size_t FrameIndex, NpcSpriteFrame& Output, std::string& ErrorMessage);
}

namespace
{
constexpr std::size_t TownMapTileSize = 8;
constexpr std::size_t TownMapVisibleColumns = 320 / TownMapTileSize;
constexpr std::size_t TownMapViewportWidth = 320;
constexpr std::size_t TownHeroViewportLeftThreshold = 10;
constexpr std::size_t TownHeroViewportRightThreshold = 16;
constexpr std::size_t TownHeroProximityMapWidthColumns = 36;
constexpr std::size_t TownEntityProximityRadiusPixels = 20;
constexpr std::size_t TownMapActorAnimationPhaseCount = 4;
constexpr std::size_t TownHeroLeftFacingFrameStart = 0;
constexpr std::size_t TownHeroRightFacingFrameStart = 5;
constexpr std::size_t TownNpcSpriteFramesPerBlock = 8;
constexpr std::size_t TownNpcSpriteFamilyCount = 5;
constexpr std::size_t TownHeadLevelRow = 5;
constexpr std::uint8_t TownHeadLevelNpcMarkerTile = 0xFD;
constexpr std::uint8_t TownMapBlockedTileIndexA = 0x3C;
constexpr std::uint8_t TownMapBlockedTileIndexB = 0x3D;
constexpr std::size_t TownBackgroundStripWidth = 224;
constexpr std::size_t TownBackgroundStripHeight = 16;
constexpr std::size_t TownBackgroundStripLeftWidth = TownBackgroundStripWidth / 2;
constexpr std::size_t TownBackgroundStripLeftX = 48;
constexpr std::size_t TownBackgroundStripLeftY = 14 + 16 * 8;
constexpr std::size_t YmpdGroundOffset = 0x229E;
constexpr std::size_t YmpdGroundLength = 0x153;
constexpr std::size_t YmpdGround1Offset = 0x23F1;
constexpr std::size_t YmpdGround1Length = 0x174;
constexpr std::size_t CkpdGroundOffset = 0x1C25;
constexpr std::size_t CkpdGroundLength = 0x1C0;
constexpr std::size_t CkpdGround1Offset = 0x1DE5;
constexpr std::size_t CkpdGround1Length = 0x1C0;

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

void DrawTownBackgroundStrip(SDL_Renderer* Renderer, const std::array<std::uint8_t, TownBackgroundStripWidth * TownBackgroundStripHeight>& Pixels,
    const Main64Palette& Palette)
{
    SDL_SetRenderDrawBlendMode(Renderer, SDL_BLENDMODE_NONE);
    for (std::size_t Row = 0; Row < TownBackgroundStripHeight; ++Row)
    {
        for (std::size_t Column = 0; Column < TownBackgroundStripWidth; ++Column)
        {
            const std::uint8_t PaletteIndex = Pixels[Row * TownBackgroundStripWidth + Column];
            if (PaletteIndex >= Palette.size())
            {
                continue;
            }

            const SDL_Color& Color = Palette[PaletteIndex];
            SDL_SetRenderDrawColor(Renderer, Color.r, Color.g, Color.b, Color.a);

            const SDL_FRect PixelRect{
                static_cast<float>(TownBackgroundStripLeftX + Column),
                static_cast<float>(TownBackgroundStripLeftY + Row),
                1.0f,
                1.0f
            };
            SDL_RenderFillRect(Renderer, &PixelRect);
        }
    }
}

const char* GetTownMapActorFacingDirectionName(TownMapActorFacingDirection FacingDirection)
{
    switch (FacingDirection)
    {
    case TownMapActorFacingDirection::Right:
        return "RIGHT";

    case TownMapActorFacingDirection::Left:
        return "LEFT";

    case TownMapActorFacingDirection::Up:
        return "UP";

    case TownMapActorFacingDirection::Down:
        return "DOWN";
    }

    return "UNKNOWN";
}

std::size_t GetTownMapMaximumProximityMapLeftColumn(const Mdt::TownMapInfo& TownMap)
{
    return TownMap.Width > TownHeroProximityMapWidthColumns ? TownMap.Width - TownHeroProximityMapWidthColumns : 0;
}

std::size_t GetTownMapActorFrameStartIndex(TownMapActorFacingDirection FacingDirection)
{
    switch (FacingDirection)
    {
    case TownMapActorFacingDirection::Right:
        return TownHeroRightFacingFrameStart;

    case TownMapActorFacingDirection::Left:
        return TownHeroLeftFacingFrameStart;

    case TownMapActorFacingDirection::Up:
    case TownMapActorFacingDirection::Down:
        // tman.grp has confirmed left/right town hero poses. Keep vertical
        // movement visible with the right-facing set until that mapping is known.
        return TownHeroRightFacingFrameStart;
    }

    return TownHeroRightFacingFrameStart;
}

std::size_t GetTownMapActorFrameIndex(TownMapActorFacingDirection FacingDirection, [[maybe_unused]] bool ActorIsMoving,
    std::size_t AnimationPhase)
{
    const std::size_t FrameStartIndex = GetTownMapActorFrameStartIndex(FacingDirection);
    const std::size_t FramePhase = AnimationPhase % TownMapActorAnimationPhaseCount;
    return FrameStartIndex + FramePhase;
}

std::size_t GetTownNpcSpriteFrameIndexFromFields(std::uint8_t SpriteSelector, std::uint8_t AnimationPhase)
{
    const std::size_t SpriteFamily = static_cast<std::size_t>(SpriteSelector & 0x0F);
    const std::size_t FacingOffset = (SpriteSelector & 0x80) == 0 ? 4 : 0;
    const std::size_t FramePhase = static_cast<std::size_t>(AnimationPhase & 3);

    return (SpriteFamily * TownNpcSpriteFramesPerBlock) + FacingOffset + FramePhase;
}

constexpr std::uint8_t NpcAiTypeBobInPlace = 4;

std::size_t GetTownNpcSpriteFrameIndex(const Mdt::TownEntityMarker& EntityMarker)
{
    return GetTownNpcSpriteFrameIndexFromFields(EntityMarker.NpcSpriteSelector, EntityMarker.NpcAnimationPhase);
}

std::string FormatTownSpriteByte(std::uint8_t Value)
{
    std::ostringstream Stream;
    Stream << "0X" << std::uppercase << std::hex << std::setw(2) << std::setfill('0')
        << static_cast<unsigned int>(Value);
    return Stream.str();
}

bool IsConfirmedTownNpcSpriteFamily(std::size_t SpriteFamily)
{
    // The checked town data uses selector families 0 through 4, and the sprite
    // viewer now confirms the same 8-frame block arithmetic for those families.
    return SpriteFamily < TownNpcSpriteFamilyCount;
}

bool IsNpcSpriteFrameVisible(const Grp::NpcSpriteFrame& SpriteFrame)
{
    return std::any_of(SpriteFrame.DrawModes.begin(), SpriteFrame.DrawModes.end(),
        [](std::uint8_t DrawMode)
        {
            return DrawMode != Grp::TransparentDrawMode;
        });
}

const char* GetTownMapActorSpriteStatusName(bool ActorFrameLoaded, bool ActorFrameVisible)
{
    if (!ActorFrameLoaded)
    {
        return "MISS";
    }

    return ActorFrameVisible ? "OK" : "EMPTY";
}

std::string GetTownNpcSpriteDebugSummary(const Mdt::TownEntityMarker& EntityMarker)
{
    const std::size_t SpriteFamily = static_cast<std::size_t>(EntityMarker.NpcSpriteSelector & 0x0F);
    std::string Summary = "NPC ID " + std::to_string(static_cast<unsigned int>(EntityMarker.NpcId))
        + " SEL " + FormatTownSpriteByte(EntityMarker.NpcSpriteSelector)
        + " PH " + FormatTownSpriteByte(EntityMarker.NpcAnimationPhase);

    if (IsConfirmedTownNpcSpriteFamily(SpriteFamily))
    {
        Summary += " FR " + std::to_string(GetTownNpcSpriteFrameIndex(EntityMarker));
    }
    else
    {
        Summary += " FR ?";
    }

    return Summary;
}

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

void DrawPatternTile(SDL_Renderer* Renderer, const Grp::PatternTile& Tile, const Main64Palette& Palette, float TileX, float TileY, float PixelSize)
{
    for (std::size_t Row = 0; Row < 8; ++Row)
    {
        for (std::size_t Column = 0; Column < 8; ++Column)
        {
            const std::uint8_t PaletteIndex = Tile.Pixels[Row * 8 + Column];
            const SDL_Color& Color = Palette[PaletteIndex];
            SDL_SetRenderDrawColor(Renderer, Color.r, Color.g, Color.b, Color.a);

            const SDL_FRect PixelRect{
                TileX + static_cast<float>(Column) * PixelSize,
                TileY + static_cast<float>(Row) * PixelSize,
                PixelSize,
                PixelSize
            };
            SDL_RenderFillRect(Renderer, &PixelRect);
        }
    }
}

void DrawNpcSpriteFrameColumnSliceOnTownMap(SDL_Renderer* Renderer, const Grp::NpcSpriteFrame& SpriteFrame,
    const Main64Palette& Palette, std::size_t MapPixelX, std::size_t MapPixelY,
    std::size_t ScrollOffsetPixels, std::size_t MapColumn)
{
    constexpr float SpritePixelSize = 1.0f;
    const std::size_t ColumnLeftPixel = MapColumn * TownMapTileSize;
    const std::size_t ColumnRightPixel = ColumnLeftPixel + TownMapTileSize;
    const std::size_t SpriteRightPixel = MapPixelX + Grp::NpcSpriteFrame::FrameWidth;
    if (SpriteRightPixel <= ColumnLeftPixel || MapPixelX >= ColumnRightPixel)
    {
        return;
    }

    const std::size_t FirstSpriteColumn = ColumnLeftPixel > MapPixelX ? ColumnLeftPixel - MapPixelX : 0;
    const std::size_t LastSpriteColumn = std::min<std::size_t>(Grp::NpcSpriteFrame::FrameWidth,
        ColumnRightPixel - MapPixelX);

    SDL_SetRenderDrawBlendMode(Renderer, SDL_BLENDMODE_NONE);
    for (std::size_t Row = 0; Row < Grp::NpcSpriteFrame::FrameHeight; ++Row)
    {
        for (std::size_t Column = FirstSpriteColumn; Column < LastSpriteColumn; ++Column)
        {
            const std::size_t PixelIndex = Row * Grp::NpcSpriteFrame::FrameWidth + Column;
            const std::uint8_t DrawMode = SpriteFrame.DrawModes[PixelIndex];
            if (DrawMode == Grp::TransparentDrawMode)
            {
                continue;
            }

            if (DrawMode == Grp::BlackDrawMode)
            {
                SDL_SetRenderDrawColor(Renderer, 0, 0, 0, 255);
            }
            else
            {
                const std::uint8_t PaletteIndex = SpriteFrame.Pixels[PixelIndex];
                const SDL_Color& Color = Palette[PaletteIndex];
                SDL_SetRenderDrawColor(Renderer, Color.r, Color.g, Color.b, Color.a);
            }

            const SDL_FRect PixelRect{
                static_cast<float>(MapPixelX + Column) - static_cast<float>(ScrollOffsetPixels),
                static_cast<float>(MapPixelY) + static_cast<float>(Row) * SpritePixelSize,
                SpritePixelSize,
                SpritePixelSize
            };
            SDL_RenderFillRect(Renderer, &PixelRect);
        }
    }
}

void DrawTownMapActorFallbackMarker(SDL_Renderer* Renderer, float MapPixelX, float MapPixelY, std::size_t ScrollOffsetPixels)
{
    constexpr float MarkerSize = 10.0f;
    constexpr float LineSize = 2.0f;
    const float ScreenX = MapPixelX - static_cast<float>(ScrollOffsetPixels)
        + (static_cast<float>(Grp::NpcSpriteFrame::FrameWidth) - MarkerSize) * 0.5f;
    const float ScreenY = MapPixelY + (static_cast<float>(Grp::NpcSpriteFrame::FrameHeight) - MarkerSize) * 0.5f;

    SDL_SetRenderDrawBlendMode(Renderer, SDL_BLENDMODE_BLEND);
    SDL_SetRenderDrawColor(Renderer, 255, 64, 224, 232);
    const SDL_FRect MarkerRect{
        ScreenX,
        ScreenY,
        MarkerSize,
        MarkerSize
    };
    SDL_RenderFillRect(Renderer, &MarkerRect);

    SDL_SetRenderDrawColor(Renderer, 255, 255, 255, 255);
    SDL_RenderRect(Renderer, &MarkerRect);

    const SDL_FRect HorizontalLine{
        ScreenX + 2.0f,
        ScreenY + (MarkerSize - LineSize) * 0.5f,
        MarkerSize - 4.0f,
        LineSize
    };
    SDL_RenderFillRect(Renderer, &HorizontalLine);

    const SDL_FRect VerticalLine{
        ScreenX + (MarkerSize - LineSize) * 0.5f,
        ScreenY + 2.0f,
        LineSize,
        MarkerSize - 4.0f
    };
    SDL_RenderFillRect(Renderer, &VerticalLine);
}

std::size_t GetTownMapMaximumScrollOffset(const Mdt::TownMapInfo& TownMap)
{
    const std::size_t MapWidthPixels = static_cast<std::size_t>(TownMap.Width) * TownMapTileSize;
    return MapWidthPixels > TownMapViewportWidth ? MapWidthPixels - TownMapViewportWidth : 0;
}

bool IsTownMapBlockedTileIndex(std::uint8_t TileIndex)
{
    return TileIndex == TownMapBlockedTileIndexA || TileIndex == TownMapBlockedTileIndexB;
}

const SDL_Color& GetTownEntityMarkerColor(Mdt::TownEntityKind EntityKind)
{
    static const SDL_Color DoorColor{255, 176, 64, 216};
    static const SDL_Color NpcColor{96, 224, 255, 216};

    return EntityKind == Mdt::TownEntityKind::Door ? DoorColor : NpcColor;
}

std::size_t CountTownEntityMarkers(const Mdt::TownMapInfo& TownMap, Mdt::TownEntityKind EntityKind)
{
    return static_cast<std::size_t>(std::count_if(TownMap.EntityMarkers.begin(), TownMap.EntityMarkers.end(),
        [EntityKind](const Mdt::TownEntityMarker& EntityMarker)
        {
            return EntityMarker.Kind == EntityKind;
        }));
}

struct TownEntityProximityResult
{
    const Mdt::TownEntityMarker* Marker = nullptr;
    std::size_t DistanceSquared = 0;
};

TownEntityProximityResult FindNearestTownEntityMarker(const Mdt::TownMapInfo& TownMap,
    std::size_t ActorMapPixelX, std::size_t ActorMapPixelY)
{
    const std::size_t ActorCenterPixelX = ActorMapPixelX + (Grp::NpcSpriteFrame::FrameWidth / 2);
    const std::size_t ActorCenterPixelY = ActorMapPixelY + (Grp::NpcSpriteFrame::FrameHeight / 2);
    const std::size_t ProximityRadiusSquared = TownEntityProximityRadiusPixels * TownEntityProximityRadiusPixels;

    TownEntityProximityResult Result{};
    for (const Mdt::TownEntityMarker& EntityMarker : TownMap.EntityMarkers)
    {
        const std::size_t EntityCenterPixelX = (static_cast<std::size_t>(EntityMarker.X) * TownMapTileSize) + (TownMapTileSize / 2);
        const std::size_t EntityCenterPixelY = (static_cast<std::size_t>(EntityMarker.Y) * TownMapTileSize) + (TownMapTileSize / 2);
        const std::size_t DeltaPixelX = ActorCenterPixelX > EntityCenterPixelX ? ActorCenterPixelX - EntityCenterPixelX : EntityCenterPixelX - ActorCenterPixelX;
        const std::size_t DeltaPixelY = ActorCenterPixelY > EntityCenterPixelY ? ActorCenterPixelY - EntityCenterPixelY : EntityCenterPixelY - ActorCenterPixelY;
        const std::size_t DistanceSquared = (DeltaPixelX * DeltaPixelX) + (DeltaPixelY * DeltaPixelY);

        if (DistanceSquared > ProximityRadiusSquared)
        {
            continue;
        }

        if (Result.Marker == nullptr || DistanceSquared < Result.DistanceSquared)
        {
            Result.Marker = &EntityMarker;
            Result.DistanceSquared = DistanceSquared;
        }
    }

    return Result;
}

std::string GetTownEntityProximityStatus(const Mdt::TownMapInfo& TownMap, std::size_t ActorMapPixelX, std::size_t ActorMapPixelY)
{
    const TownEntityProximityResult ProximityResult = FindNearestTownEntityMarker(TownMap, ActorMapPixelX, ActorMapPixelY);
    if (ProximityResult.Marker == nullptr)
    {
        return "NEAR NONE";
    }

    if (ProximityResult.Marker->Kind == Mdt::TownEntityKind::Npc)
    {
        return "NEAR " + GetTownNpcSpriteDebugSummary(*ProximityResult.Marker);
    }

    return "NEAR DOOR " + std::to_string(static_cast<unsigned int>(ProximityResult.Marker->DoorType));
}

void DrawTownEntityMarker(SDL_Renderer* Renderer, const Mdt::TownEntityMarker& EntityMarker, std::size_t ScrollOffsetPixels)
{
    constexpr float MarkerSize = 6.0f;
    constexpr float MarkerInset = 1.0f;

    const float ScreenX = static_cast<float>(EntityMarker.X * TownMapTileSize) - static_cast<float>(ScrollOffsetPixels) + MarkerInset;
    const float ScreenY = static_cast<float>(EntityMarker.Y * TownMapTileSize) + MarkerInset;
    const SDL_Color& Color = GetTownEntityMarkerColor(EntityMarker.Kind);

    SDL_SetRenderDrawBlendMode(Renderer, SDL_BLENDMODE_BLEND);
    SDL_SetRenderDrawColor(Renderer, Color.r, Color.g, Color.b, Color.a);
    const SDL_FRect MarkerRect{
        ScreenX,
        ScreenY,
        MarkerSize,
        MarkerSize
    };
    SDL_RenderFillRect(Renderer, &MarkerRect);

    if (EntityMarker.Kind == Mdt::TownEntityKind::Door)
    {
        SDL_SetRenderDrawColor(Renderer, 32, 16, 0, 240);

        const SDL_FRect DoorStripe{
            ScreenX + 1.0f,
            ScreenY + 2.0f,
            MarkerSize - 2.0f,
            2.0f
        };
        SDL_RenderFillRect(Renderer, &DoorStripe);

        SDL_SetRenderDrawColor(Renderer, 255, 208, 112, 240);
        SDL_RenderRect(Renderer, &MarkerRect);
    }
    else
    {
        SDL_SetRenderDrawColor(Renderer, 32, 96, 112, 240);

        const SDL_FRect NpcCore{
            ScreenX + 2.0f,
            ScreenY + 2.0f,
            2.0f,
            2.0f
        };
        SDL_RenderFillRect(Renderer, &NpcCore);

        SDL_SetRenderDrawColor(Renderer, 192, 255, 255, 240);
        SDL_RenderRect(Renderer, &MarkerRect);
    }
}

void DrawTownEntityMarkersForColumn(SDL_Renderer* Renderer, const Mdt::TownMapInfo& TownMap,
    std::size_t ScrollOffsetPixels, Mdt::TownEntityKind EntityKind, std::size_t MapColumn)
{
    for (const Mdt::TownEntityMarker& EntityMarker : TownMap.EntityMarkers)
    {
        if (EntityMarker.Kind != EntityKind || EntityMarker.X != MapColumn)
        {
            continue;
        }

        DrawTownEntityMarker(Renderer, EntityMarker, ScrollOffsetPixels);
    }
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

const char* GetTownMapCollisionStatusName(bool ActorCollisionBlocked)
{
    return ActorCollisionBlocked ? "COL BLOCK" : "COL OK";
}

void DrawFontText(SDL_Renderer* Renderer, const Grp::FontGroup& FontGroup, float StartX, float StartY, float Scale, const std::string& Text)
{
    constexpr std::size_t GlyphWidth = 8;
    constexpr std::size_t GlyphHeight = 8;

    SDL_SetRenderDrawColor(Renderer, 255, 255, 255, 255);

    float CursorX = StartX;
    float CursorY = StartY;
    const float GlyphAdvance = static_cast<float>(GlyphWidth) * Scale;
    const float LineAdvance = static_cast<float>(GlyphHeight) * Scale;

    for (char Ch : Text)
    {
        if (Ch == '\n')
        {
            CursorX = StartX;
            CursorY += LineAdvance;
            continue;
        }

        const unsigned char Character = static_cast<unsigned char>(Ch);
        if (Character < 32)
        {
            CursorX += GlyphAdvance;
            continue;
        }

        const std::size_t GlyphIndex = static_cast<std::size_t>(Character - 32);
        if (GlyphIndex >= FontGroup.Glyphs.size())
        {
            CursorX += GlyphAdvance;
            continue;
        }

        const Grp::FontGlyph& Glyph = FontGroup.Glyphs[GlyphIndex];
        for (std::size_t Row = 0; Row < GlyphHeight; ++Row)
        {
            const std::uint8_t Bits = Glyph.Rows[Row];
            for (std::size_t Column = 0; Column < GlyphWidth; ++Column)
            {
                if (((Bits >> (7 - Column)) & 1) == 0)
                {
                    continue;
                }

                const SDL_FRect PixelRect{
                    CursorX + static_cast<float>(Column) * Scale,
                    CursorY + static_cast<float>(Row) * Scale,
                    Scale,
                    Scale
                };
                SDL_RenderFillRect(Renderer, &PixelRect);
            }
        }

        CursorX += GlyphAdvance;
    }
}

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

        DrawNpcSpriteFrameColumnSliceOnTownMap(Renderer, *SliceIterator->SpriteFrame, Palette,
            SliceIterator->MapPixelX, SliceIterator->MapPixelY, SliceIterator->ScrollOffsetPixels,
            SliceIterator->MapColumn);

        if (SliceIterator->IsCurrentColumn)
        {
            ++RenderedNpcSpriteCount;
        }

        SliceIterator = Slices.erase(SliceIterator);
    }
}

std::size_t TownScene::GetTownNpcSpriteFrameIndex(std::uint8_t SpriteSelector, std::uint8_t AnimationPhase)
{
    return GetTownNpcSpriteFrameIndexFromFields(SpriteSelector, AnimationPhase);
}

std::uint8_t TownScene::GetTownNpcRuntimeRecordSpriteColumnMatch(const TownNpcRuntimeRecord& RuntimeRecord,
    std::size_t MapColumn)
{
    const std::size_t NpcColumn = static_cast<std::size_t>(RuntimeRecord.X);
    if (NpcColumn == MapColumn)
    {
        // Mirror sprite_x_coordinate_lookup: 2 means the current column, 1 means the next column.
        return 2;
    }

    if (NpcColumn == MapColumn + 1)
    {
        return 1;
    }

    return 0;
}

const TownScene::TownNpcRuntimeRecord* TownScene::FindNonPassableTownNpcAtXPos(
    const std::vector<TownNpcRuntimeRecord>& TownNpcArray, std::size_t TargetX) noexcept
{
    for (const TownNpcRuntimeRecord& RuntimeRecord : TownNpcArray)
    {
        if (static_cast<std::size_t>(RuntimeRecord.X) != TargetX)
        {
            continue;
        }

        if ((RuntimeRecord.NpcFlags & 0x40) == 0)
        {
            continue;
        }

        return &RuntimeRecord;
    }

    return nullptr;
}

bool TownScene::TryGetTownNpcSpriteFrame(std::size_t FrameIndex, const Grp::NpcSpriteFrame*& SpriteFrame) const
{
    if (FrameIndex >= TownNpcSpriteFrameCount)
    {
        return false;
    }

    if (!TownNpcSpriteFrameLoaded[FrameIndex])
    {
        Grp::NpcSpriteFrame LoadedFrame;
        std::string LoadErrorMessage;
        if (!Grp::LoadNpcSpriteFrame(TownNpcSpriteGrpPath, FrameIndex, LoadedFrame, LoadErrorMessage))
        {
            if (!TownNpcSpriteFrameWarningPrinted)
            {
                std::cerr << TownNpcSpriteGrpPath.filename().string() << " town NPC frame " << FrameIndex
                    << " load failed: " << LoadErrorMessage << '\n';
                TownNpcSpriteFrameWarningPrinted = true;
            }

            return false;
        }

        TownNpcSpriteFrames[FrameIndex] = std::move(LoadedFrame);
        TownNpcSpriteFrameLoaded[FrameIndex] = true;
        TownNpcSpriteFrameVisible[FrameIndex] = IsNpcSpriteFrameVisible(TownNpcSpriteFrames[FrameIndex]);
    }

    if (!TownNpcSpriteFrameVisible[FrameIndex])
    {
        return false;
    }

    SpriteFrame = &TownNpcSpriteFrames[FrameIndex];
    return true;
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
        + static_cast<std::size_t>(TownHeroState.HeroXInViewport) + 4;
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
    const std::size_t ProximityMapScrollOffsetPixels = static_cast<std::size_t>(TownHeroState.ProximityMapLeftColumnX)
        * TownMapTileSize;
    return std::min<std::size_t>(ProximityMapScrollOffsetPixels, GetTownMapMaximumScrollOffset(TownMap));
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

void TownScene::UpdateTownHeroRuntimeState(const bool* KeyboardState) noexcept
{
    if (KeyboardState == nullptr)
    {
        SyncTownHeroRuntimeProjection();
        return;
    }

    const bool LeftPressed = KeyboardState[SDL_SCANCODE_LEFT] && !KeyboardState[SDL_SCANCODE_RIGHT];
    const bool RightPressed = KeyboardState[SDL_SCANCODE_RIGHT] && !KeyboardState[SDL_SCANCODE_LEFT];
    const std::size_t MaximumProximityMapLeftColumn = GetTownMapMaximumProximityMapLeftColumn(TownMap);
    bool HeroMoved = false;

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
        TownMovementFrameCountdown = 0;
        SyncTownHeroRuntimeProjection();
        return;
    }

    if (TownMovementFrameCountdown > 0)
    {
        --TownMovementFrameCountdown;
        if (TownMovementFrameCountdown > 0)
        {
            SyncTownHeroRuntimeProjection();
            return;
        }
    }

    if (LeftPressed)
    {
        const std::size_t TargetX = GetTownHeroAbsoluteX() - 1;
        const bool BlockedByNpc = FindNonPassableTownNpcAtXPos(TownNpcArray, TargetX) != nullptr;

        if (!BlockedByNpc && TownHeroState.HeroXInViewport > TownHeroViewportLeftThreshold)
        {
            --TownHeroState.HeroXInViewport;
            HeroMoved = true;
        }
        else if (!BlockedByNpc && TownHeroState.ProximityMapLeftColumnX > 0)
        {
            --TownHeroState.ProximityMapLeftColumnX;
            HeroMoved = true;
        }
        else if (!BlockedByNpc && TownHeroState.HeroXInViewport > 0)
        {
            --TownHeroState.HeroXInViewport;
            HeroMoved = true;
        }

        if (HeroMoved)
        {
            TownMovementFrameCountdown = TownMovementFrameDelay;
        }
    }
    else if (RightPressed)
    {
        const std::size_t TargetX = GetTownHeroAbsoluteX() + 1;
        const bool BlockedByNpc = FindNonPassableTownNpcAtXPos(TownNpcArray, TargetX) != nullptr;

        if (!BlockedByNpc && TownHeroState.HeroXInViewport < TownHeroViewportRightThreshold)
        {
            ++TownHeroState.HeroXInViewport;
            HeroMoved = true;
        }
        else if (!BlockedByNpc && TownHeroState.ProximityMapLeftColumnX < MaximumProximityMapLeftColumn)
        {
            ++TownHeroState.ProximityMapLeftColumnX;
            HeroMoved = true;
        }
        else if (!BlockedByNpc && TownHeroState.HeroXInViewport < 28)
        {
            // Match the DOS off-screen sentinel; the map handoff itself is still provisional.
            ++TownHeroState.HeroXInViewport;
            HeroMoved = true;
        }

        if (HeroMoved)
        {
            TownMovementFrameCountdown = TownMovementFrameDelay;
        }
    }

    if (HeroMoved)
    {
        TownHeroState.HeroAnimationPhase = static_cast<std::uint8_t>((TownHeroState.HeroAnimationPhase + 1) & 3);
    }
    else
    {
        TownMovementFrameCountdown = 0;
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
    TownNpcRuntimeRecords.reserve(CountTownEntityMarkers(TownMap, Mdt::TownEntityKind::Npc));

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

void TownScene::UpdateTownNpcRuntimeRecordsShell() const
{
    // Match the confirmed bob-in-place phase step and leave every other AI path neutral.
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

    for (TownNpcRuntimeRecord& TownNpcRuntimeRecord : TownNpcArray)
    {
        switch (TownNpcRuntimeRecord.NpcAiType)
        {
        case NpcAiTypeBobInPlace:
            UpdateTownNpcBobInPlace(TownNpcRuntimeRecord);
            break;

        default:
            break;
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

const TownScene::TownNpcRuntimeRecord* TownScene::FindFirstTownNpcRuntimeRecordForColumnAfterCurrent(
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
    TownNpcSpriteShadowBuffer& ShadowBuffer, bool DrawDebugFallbackMarker,
    TownColumnRenderStats& RenderStats) const
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

        const bool HasSpriteFrame = IsConfirmedTownNpcSpriteFamily(SpriteFamily) && TryGetTownNpcSpriteFrame(FrameIndex, SpriteFrame);

        if (ColumnMatch == 2)
        {
            if (!HasSpriteFrame)
            {
                ++RenderStats.NpcSpriteMissCount;
                if (DrawDebugFallbackMarker)
                {
                    // Keep this hidden outside the debug overlay because the assembly does not confirm
                    // a fallback marker for missing NPC sprite frames.
                    Mdt::TownEntityMarker FallbackMarker{};
                    FallbackMarker.Kind = Mdt::TownEntityKind::Npc;
                    FallbackMarker.X = RuntimeRecord->X;
                    FallbackMarker.Y = TownHeadLevelRow;
                    FallbackMarker.NpcSpriteSelector = RuntimeRecord->SpriteSelector;
                    FallbackMarker.NpcAnimationPhase = RuntimeRecord->AnimationPhase;
                    DrawTownEntityMarker(Renderer, FallbackMarker, ScrollOffsetPixels);
                }
            }
            else
            {
                ShadowBuffer.AddCurrentColumnSlice(*SpriteFrame,
                    SpriteColumn * TownMapTileSize,
                    TownHeadLevelRow * TownMapTileSize,
                    ScrollOffsetPixels,
                    SpriteColumn);
                ShadowBuffer.AddNextColumnSlice(*SpriteFrame,
                    SpriteColumn * TownMapTileSize,
                    TownHeadLevelRow * TownMapTileSize,
                    ScrollOffsetPixels,
                    SpriteColumn + 1);
            }
        }
        else if (ColumnMatch == 1 && HasSpriteFrame)
        {
            ShadowBuffer.AddCurrentColumnSlice(*SpriteFrame,
                SpriteColumn * TownMapTileSize,
                TownHeadLevelRow * TownMapTileSize,
                ScrollOffsetPixels,
                SpriteColumn);
        }

        RuntimeRecord = FindFirstTownNpcRuntimeRecordForColumnAfterCurrent(TownNpcArray, RuntimeRecord, MapColumn);
    }
}

void TownScene::RenderTownColumn(SDL_Renderer* Renderer, std::size_t MapColumn, float ScreenTileX,
    const TownHeadLevelTiles& HeadLevelTiles, const std::vector<TownNpcRuntimeRecord>& TownNpcArray,
    std::size_t ScrollOffsetPixels, TownNpcSpriteShadowBuffer& ShadowBuffer, bool DrawDebugEntityMarkers,
    bool DrawDebugFallbackMarker, TownColumnRenderStats& RenderStats) const
{
    const Grp::PatternTile& FallbackTile = GetFallbackPatternTile();
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
        else if (!TryGetTownMapTileIndexAtCell(TownMap, MapColumn, Row, TileIndex))
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
                std::cerr << "cmap.mdt tile at column " << MapColumn << ", row " << Row
                    << " uses tile index " << static_cast<int>(TileIndex)
                    << " outside the cpat.grp pattern bank; drawing fallback tiles." << '\n';
                FallbackWarningPrinted = true;
            }

            Tile = &FallbackTile;
        }

        DrawPatternTile(Renderer, *Tile, Palette, ScreenTileX, static_cast<float>(Row * TownMapTileSize), 1.0f);

        if (BlockedTileOverlayEnabled && IsTownMapBlockedTileIndex(TileIndex))
        {
            SDL_SetRenderDrawBlendMode(Renderer, SDL_BLENDMODE_BLEND);
            SDL_SetRenderDrawColor(Renderer, 255, 48, 48, 96);
            const SDL_FRect PixelRect{
                ScreenTileX,
                static_cast<float>(Row * TownMapTileSize),
                static_cast<float>(TownMapTileSize),
                static_cast<float>(TownMapTileSize)
            };
            SDL_RenderFillRect(Renderer, &PixelRect);
        }
    }

    if (DrawDebugEntityMarkers)
    {
        DrawTownEntityMarkersForColumn(Renderer, TownMap, ScrollOffsetPixels, Mdt::TownEntityKind::Door, MapColumn);
    }

    // Match the DOS flow: only the row-5 0xFD marker opens the NPC compositor.
    if (HasTownNpcMarker)
    {
        DispatchTownSpecialTile(Renderer, MapColumn, TownNpcArray, ScrollOffsetPixels,
            ShadowBuffer, DrawDebugFallbackMarker, RenderStats);
    }

    // Flush only the slices that belong to the column whose background was just drawn.
    ShadowBuffer.FlushForMapColumn(Renderer, Palette, MapColumn, RenderStats.RenderedNpcSpriteCount);

    if (ActorFrameLoaded && ActorFrameVisible)
    {
        DrawNpcSpriteFrameColumnSliceOnTownMap(Renderer, ActorFrame, Palette, ActorMapPixelX, ActorMapPixelY,
            ScrollOffsetPixels, MapColumn);
    }
}

TownScene::TownScene(const std::filesystem::path& ActorSpriteGrpPath, const std::filesystem::path& TownNpcSpriteGrpPath,
    const Mdt::TownMapInfo& TownMap,
    const Grp::PatternBank& PatternBank, const Main64Palette& Palette)
    : ActorSpriteGrpPath(ActorSpriteGrpPath), TownNpcSpriteGrpPath(TownNpcSpriteGrpPath), TownMap(TownMap), PatternBank(PatternBank), Palette(Palette)
{
    TownNpcArray = BuildTownNpcRuntimeRecords(TownMap);
    TownBackgroundStripUsesCkpd = TownMap.HasMiddleLayer;
    const std::filesystem::path TownBackgroundBinPath = ActorSpriteGrpPath.parent_path()
        / (TownBackgroundStripUsesCkpd ? "ckpd.bin" : "ympd.bin");
    std::string TownBackgroundStripErrorMessage;
    TownBackgroundStripLoaded = LoadTownBackgroundStripPixels(TownBackgroundBinPath, TownBackgroundStripUsesCkpd,
        TownBackgroundStripPixels, TownBackgroundStripErrorMessage);
    if (!TownBackgroundStripLoaded)
    {
        std::cerr << TownBackgroundBinPath.filename().string() << " lower strip load failed: "
            << TownBackgroundStripErrorMessage << '\n';
    }
    ActorFrameIndex = GetTownMapActorFrameIndex(ActorFacingDirection, false, ActorAnimationPhase);
    (void)UpdateTownMapActorFrame(ActorFrameIndex);
    SyncTownHeroRuntimeProjection();
}

void TownScene::Update(const bool* KeyboardState)
{
    if (KeyboardState == nullptr)
    {
        return;
    }

    UpdateTownHeroRuntimeState(KeyboardState);
    const std::size_t DesiredTownMapActorFrameIndex = GetTownMapActorFrameIndex(ActorFacingDirection, true, ActorAnimationPhase);
    (void)UpdateTownMapActorFrame(DesiredTownMapActorFrameIndex);
}

void TownScene::Draw(SDL_Renderer* Renderer, const Grp::FontGroup* DebugFontGroup, bool DebugOverlayEnabled) const
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
    UpdateTownNpcRuntimeRecordsShell();
    TownColumnRenderStats RenderStats{};
    TownNpcSpriteShadowBuffer ShadowBuffer;
    ShadowBuffer.Reserve(TownNpcArray.size() * 2);

    for (std::size_t Column = 0; Column < ColumnsToRender; ++Column)
    {
        const std::size_t MapColumn = FirstColumn + Column;
        const float TileX = static_cast<float>(Column * TileSize) - static_cast<float>(ColumnPixelOffset);
        RenderTownColumn(Renderer, MapColumn, TileX, HeadLevelTiles, TownNpcArray, ClampedScrollOffset,
            ShadowBuffer, TownEntityMarkersEnabled, DebugOverlayEnabled, RenderStats);
    }

    RestoreHeadLevelTilesFromNpcs(HeadLevelTiles);

    if (TownBackgroundStripLoaded)
    {
        DrawTownBackgroundStrip(Renderer, TownBackgroundStripPixels, Palette);
    }

    if (!(ActorFrameLoaded && ActorFrameVisible))
    {
        DrawTownMapActorFallbackMarker(Renderer, static_cast<float>(ActorMapPixelX),
            static_cast<float>(ActorMapPixelY), ClampedScrollOffset);
    }

    if (DebugOverlayEnabled && DebugFontGroup != nullptr)
    {
        constexpr float TextScale = 1.0f;
        constexpr float StartX = 8.0f;
        constexpr float StartY = 8.0f;
        constexpr float LineSpacing = 10.0f;
        const std::size_t NpcMarkerCount = CountTownEntityMarkers(TownMap, Mdt::TownEntityKind::Npc);
        const std::size_t DoorMarkerCount = CountTownEntityMarkers(TownMap, Mdt::TownEntityKind::Door);

        DrawFontText(Renderer, *DebugFontGroup, StartX, StartY, TextScale,
            "ACT F" + std::to_string(ActorFrameIndex) + " " + GetTownMapActorFacingDirectionName(ActorFacingDirection)
            + " ACTSPR " + GetTownMapActorSpriteStatusName(ActorFrameLoaded, ActorFrameVisible));
        DrawFontText(Renderer, *DebugFontGroup, StartX, StartY + LineSpacing, TextScale,
            "POS " + std::to_string(ActorMapPixelX) + "," + std::to_string(ActorMapPixelY) + " "
            + GetTownMapCollisionStatusName(ActorCollisionBlocked));
        DrawFontText(Renderer, *DebugFontGroup, StartX, StartY + LineSpacing * 2.0f, TextScale,
            std::string("TILE ") + (BlockedTileOverlayEnabled ? "ON" : "OFF") + " OBJ "
            + (TownEntityMarkersEnabled ? "ON" : "OFF"));
        DrawFontText(Renderer, *DebugFontGroup, StartX, StartY + LineSpacing * 3.0f, TextScale,
            "NPCSPR " + std::to_string(RenderStats.RenderedNpcSpriteCount) + "/" + std::to_string(NpcMarkerCount)
            + " NPCMISS " + std::to_string(RenderStats.NpcSpriteMissCount)
            + " DOOR " + std::to_string(DoorMarkerCount));
        DrawFontText(Renderer, *DebugFontGroup, StartX, StartY + LineSpacing * 4.0f, TextScale,
            GetTownEntityProximityStatus(TownMap, ActorMapPixelX, ActorMapPixelY));
    }
}

void TownScene::ToggleBlockedTileOverlay() noexcept
{
    BlockedTileOverlayEnabled = !BlockedTileOverlayEnabled;
}

void TownScene::ToggleTownEntityMarkers() noexcept
{
    TownEntityMarkersEnabled = !TownEntityMarkersEnabled;
}

bool TownScene::IsBlockedTileOverlayEnabled() const noexcept
{
    return BlockedTileOverlayEnabled;
}

bool TownScene::IsTownEntityMarkersEnabled() const noexcept
{
    return TownEntityMarkersEnabled;
}

bool TownScene::UpdateTownMapActorFrame(std::size_t DesiredActorFrameIndex)
{
    if (DesiredActorFrameIndex == ActorFrameIndex && ActorFrameLoaded)
    {
        return ActorFrameVisible;
    }

    Grp::NpcSpriteFrame RequestedActorFrame;
    std::string RequestedActorFrameErrorMessage;
    if (!Grp::LoadTownHeroSpriteFrame(ActorSpriteGrpPath, DesiredActorFrameIndex, RequestedActorFrame, RequestedActorFrameErrorMessage))
    {
        if (!ActorFrameWarningPrinted)
        {
            std::cerr << ActorSpriteGrpPath.filename().string() << " actor sprite frame " << DesiredActorFrameIndex
                << " load failed: " << RequestedActorFrameErrorMessage << '\n';
            ActorFrameWarningPrinted = true;
        }

        ActorFrameIndex = DesiredActorFrameIndex;
        ActorFrameLoaded = false;
        ActorFrameVisible = false;
        return false;
    }

    ActorFrameIndex = DesiredActorFrameIndex;
    ActorFrame = std::move(RequestedActorFrame);
    ActorFrameLoaded = true;
    ActorFrameVisible = IsNpcSpriteFrameVisible(ActorFrame);
    ActorAnimationTickCount = 0;
    return ActorFrameVisible;
}
