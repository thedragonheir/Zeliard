#include "town_scene.h"

#include <algorithm>
#include <cstdint>
#include <iomanip>
#include <filesystem>
#include <iostream>
#include <sstream>
#include <string>
#include <utility>

namespace Grp
{
bool LoadTownHeroSpriteFrame(const std::filesystem::path& Path, std::size_t FrameIndex, NpcSpriteFrame& Output, std::string& ErrorMessage);
}

namespace
{
constexpr std::size_t TownMapTileSize = 8;
constexpr std::size_t TownMapVisibleColumns = 320 / TownMapTileSize;
constexpr std::size_t TownMapViewportWidth = 320;
constexpr std::size_t TownEntityProximityRadiusPixels = 20;
constexpr std::size_t TownMapActorAnimationFrameDelay = 8;
constexpr std::size_t TownMapActorAnimationPhaseCount = 4;
constexpr std::size_t TownHeroLeftFacingFrameStart = 0;
constexpr std::size_t TownHeroRightFacingFrameStart = 5;
constexpr std::size_t TownNpcSpriteFramesPerBlock = 8;
constexpr std::size_t TownNpcSpriteFamilyCount = 5;
constexpr std::uint8_t TownMapBlockedTileIndexA = 0x3C;
constexpr std::uint8_t TownMapBlockedTileIndexB = 0x3D;

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

const char* GetTownMapCameraFollowModeName(bool CameraFollowEnabled)
{
    return CameraFollowEnabled ? "AUTO" : "MANUAL";
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

std::size_t GetTownMapActorFrameIndex(TownMapActorFacingDirection FacingDirection, bool ActorIsMoving, std::size_t AnimationPhase)
{
    const std::size_t FrameStartIndex = GetTownMapActorFrameStartIndex(FacingDirection);
    const std::size_t FramePhase = ActorIsMoving ? (AnimationPhase % TownMapActorAnimationPhaseCount) : 0;
    return FrameStartIndex + FramePhase;
}

std::size_t GetTownNpcSpriteFrameIndex(const Mdt::TownEntityMarker& EntityMarker)
{
    const std::size_t SpriteFamily = static_cast<std::size_t>(EntityMarker.NpcSpriteSelector & 0x0F);
    const std::size_t FacingOffset = (EntityMarker.NpcSpriteSelector & 0x80) == 0 ? 4 : 0;
    const std::size_t AnimationPhase = static_cast<std::size_t>(EntityMarker.NpcAnimationPhase & 3);

    return (SpriteFamily * TownNpcSpriteFramesPerBlock) + FacingOffset + AnimationPhase;
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
    return std::any_of(SpriteFrame.Pixels.begin(), SpriteFrame.Pixels.end(),
        [](std::uint8_t PaletteIndex)
        {
            return PaletteIndex != 0;
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

void DrawNpcSpriteFrameOnTownMap(SDL_Renderer* Renderer, const Grp::NpcSpriteFrame& SpriteFrame, const Main64Palette& Palette, float MapPixelX, float MapPixelY, std::size_t ScrollOffsetPixels)
{
    constexpr float SpritePixelSize = 1.0f;
    const float ScreenX = MapPixelX - static_cast<float>(ScrollOffsetPixels);

    for (std::size_t Row = 0; Row < Grp::NpcSpriteFrame::FrameHeight; ++Row)
    {
        for (std::size_t Column = 0; Column < Grp::NpcSpriteFrame::FrameWidth; ++Column)
        {
            const std::uint8_t PaletteIndex = SpriteFrame.Pixels[Row * Grp::NpcSpriteFrame::FrameWidth + Column];
            if (PaletteIndex == 0)
            {
                continue;
            }

            const SDL_Color& Color = Palette[PaletteIndex];
            SDL_SetRenderDrawColor(Renderer, Color.r, Color.g, Color.b, Color.a);

            const SDL_FRect PixelRect{
                ScreenX + static_cast<float>(Column) * SpritePixelSize,
                MapPixelY + static_cast<float>(Row) * SpritePixelSize,
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

std::size_t GetTownMapCameraFollowScrollOffset(const Mdt::TownMapInfo& TownMap, std::size_t ActorMapPixelX)
{
    const std::size_t MaximumScrollOffset = GetTownMapMaximumScrollOffset(TownMap);
    const std::size_t ActorCenterPixelX = ActorMapPixelX + (Grp::NpcSpriteFrame::FrameWidth / 2);
    const std::size_t ViewportCenterPixelX = TownMapViewportWidth / 2;
    const std::size_t DesiredScrollOffset = ActorCenterPixelX > ViewportCenterPixelX ? ActorCenterPixelX - ViewportCenterPixelX : 0;
    return std::min<std::size_t>(DesiredScrollOffset, MaximumScrollOffset);
}

std::size_t GetTownMapMaximumActorMapPixelX(const Mdt::TownMapInfo& TownMap)
{
    const std::size_t MapWidthPixels = static_cast<std::size_t>(TownMap.Width) * TownMapTileSize;
    const std::size_t ActorWidthPixels = Grp::NpcSpriteFrame::FrameWidth;
    return MapWidthPixels > ActorWidthPixels ? MapWidthPixels - ActorWidthPixels : 0;
}

std::size_t GetTownMapMaximumActorMapPixelY(const Mdt::TownMapInfo& TownMap)
{
    const std::size_t MapHeightPixels = static_cast<std::size_t>(TownMap.Height) * TownMapTileSize;
    const std::size_t ActorHeightPixels = Grp::NpcSpriteFrame::FrameHeight;
    return MapHeightPixels > ActorHeightPixels ? MapHeightPixels - ActorHeightPixels : 0;
}

void ClampTownMapActorPosition(const Mdt::TownMapInfo& TownMap, std::size_t& ActorMapPixelX, std::size_t& ActorMapPixelY)
{
    ActorMapPixelX = std::clamp(ActorMapPixelX, std::size_t{0}, GetTownMapMaximumActorMapPixelX(TownMap));
    ActorMapPixelY = std::clamp(ActorMapPixelY, std::size_t{0}, GetTownMapMaximumActorMapPixelY(TownMap));
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

void DrawTownEntityMarkers(SDL_Renderer* Renderer, const Mdt::TownMapInfo& TownMap, std::size_t ScrollOffsetPixels,
    Mdt::TownEntityKind EntityKind)
{
    for (const Mdt::TownEntityMarker& EntityMarker : TownMap.EntityMarkers)
    {
        if (EntityMarker.Kind != EntityKind)
        {
            continue;
        }

        DrawTownEntityMarker(Renderer, EntityMarker, ScrollOffsetPixels);
    }
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
    const std::size_t CellIndex = Column * TownMap.Height + Row;
    if (CellIndex >= TownMap.Cells.size())
    {
        return false;
    }

    TileIndex = TownMap.Cells[CellIndex];
    return true;
}

bool IsTownMapActorProbeBlocked(const Mdt::TownMapInfo& TownMap, std::size_t ActorMapPixelX, std::size_t ActorMapPixelY,
    TownMapActorFacingDirection ActorFacingDirection)
{
    // This is provisional and checks one leading-edge point instead of a full
    // footprint, which matches the current town collision evidence without
    // growing the debug path into a larger gameplay layer.
    std::size_t ProbePixelX = ActorMapPixelX + (Grp::NpcSpriteFrame::FrameWidth / 2);
    std::size_t ProbePixelY = ActorMapPixelY + (Grp::NpcSpriteFrame::FrameHeight / 2);

    switch (ActorFacingDirection)
    {
    case TownMapActorFacingDirection::Left:
        ProbePixelX = ActorMapPixelX;
        break;
    case TownMapActorFacingDirection::Right:
        ProbePixelX = ActorMapPixelX + Grp::NpcSpriteFrame::FrameWidth - 1;
        break;
    case TownMapActorFacingDirection::Up:
        ProbePixelY = ActorMapPixelY;
        break;
    case TownMapActorFacingDirection::Down:
        ProbePixelY = ActorMapPixelY + Grp::NpcSpriteFrame::FrameHeight - 1;
        break;
    }

    std::uint8_t TileIndex = 0;
    if (!TryGetTownMapTileIndexAtPixel(TownMap, ProbePixelX, ProbePixelY, TileIndex))
    {
        return false;
    }

    return IsTownMapBlockedTileIndex(TileIndex);
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

bool MoveTownMapActorPosition(const Mdt::TownMapInfo& TownMap, std::size_t& ActorMapPixelX, std::size_t& ActorMapPixelY,
    const bool* KeyboardState, TownMapActorFacingDirection& ActorFacingDirection, bool& ActorCollisionBlocked)
{
    ActorCollisionBlocked = false;
    if (KeyboardState == nullptr)
    {
        return false;
    }

    constexpr std::size_t ActorMoveSpeedPixels = 2;
    const std::size_t MaximumActorMapPixelX = GetTownMapMaximumActorMapPixelX(TownMap);
    const std::size_t MaximumActorMapPixelY = GetTownMapMaximumActorMapPixelY(TownMap);
    bool ActorMoved = false;

    if (KeyboardState[SDL_SCANCODE_LEFT] && !KeyboardState[SDL_SCANCODE_RIGHT])
    {
        const std::size_t PreviousActorMapPixelX = ActorMapPixelX;
        const std::size_t ProposedActorMapPixelX = ActorMapPixelX > ActorMoveSpeedPixels ? ActorMapPixelX - ActorMoveSpeedPixels : 0;
        if (!IsTownMapActorProbeBlocked(TownMap, ProposedActorMapPixelX, ActorMapPixelY, TownMapActorFacingDirection::Left))
        {
            ActorMapPixelX = ProposedActorMapPixelX;
            if (ActorMapPixelX != PreviousActorMapPixelX)
            {
                ActorFacingDirection = TownMapActorFacingDirection::Left;
                ActorMoved = true;
            }
        }
        else
        {
            ActorCollisionBlocked = true;
        }
    }
    else if (KeyboardState[SDL_SCANCODE_RIGHT] && !KeyboardState[SDL_SCANCODE_LEFT])
    {
        const std::size_t PreviousActorMapPixelX = ActorMapPixelX;
        const std::size_t ProposedActorMapPixelX = std::min<std::size_t>(ActorMapPixelX + ActorMoveSpeedPixels, MaximumActorMapPixelX);
        if (!IsTownMapActorProbeBlocked(TownMap, ProposedActorMapPixelX, ActorMapPixelY, TownMapActorFacingDirection::Right))
        {
            ActorMapPixelX = ProposedActorMapPixelX;
            if (ActorMapPixelX != PreviousActorMapPixelX)
            {
                ActorFacingDirection = TownMapActorFacingDirection::Right;
                ActorMoved = true;
            }
        }
        else
        {
            ActorCollisionBlocked = true;
        }
    }

    if (KeyboardState[SDL_SCANCODE_UP] && !KeyboardState[SDL_SCANCODE_DOWN])
    {
        const std::size_t PreviousActorMapPixelY = ActorMapPixelY;
        const std::size_t ProposedActorMapPixelY = ActorMapPixelY > ActorMoveSpeedPixels ? ActorMapPixelY - ActorMoveSpeedPixels : 0;
        if (!IsTownMapActorProbeBlocked(TownMap, ActorMapPixelX, ProposedActorMapPixelY, TownMapActorFacingDirection::Up))
        {
            ActorMapPixelY = ProposedActorMapPixelY;
            if (ActorMapPixelY != PreviousActorMapPixelY)
            {
                ActorFacingDirection = TownMapActorFacingDirection::Up;
                ActorMoved = true;
            }
        }
        else
        {
            ActorCollisionBlocked = true;
        }
    }
    else if (KeyboardState[SDL_SCANCODE_DOWN] && !KeyboardState[SDL_SCANCODE_UP])
    {
        const std::size_t PreviousActorMapPixelY = ActorMapPixelY;
        const std::size_t ProposedActorMapPixelY = std::min<std::size_t>(ActorMapPixelY + ActorMoveSpeedPixels, MaximumActorMapPixelY);
        if (!IsTownMapActorProbeBlocked(TownMap, ActorMapPixelX, ProposedActorMapPixelY, TownMapActorFacingDirection::Down))
        {
            ActorMapPixelY = ProposedActorMapPixelY;
            if (ActorMapPixelY != PreviousActorMapPixelY)
            {
                ActorFacingDirection = TownMapActorFacingDirection::Down;
                ActorMoved = true;
            }
        }
        else
        {
            ActorCollisionBlocked = true;
        }
    }

    ClampTownMapActorPosition(TownMap, ActorMapPixelX, ActorMapPixelY);
    return ActorMoved;
}
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

std::size_t TownScene::DrawTownNpcSprites(SDL_Renderer* Renderer, std::size_t ScrollOffsetPixels, std::size_t& NpcSpriteMissCount) const
{
    std::size_t RenderedNpcSpriteCount = 0;
    NpcSpriteMissCount = 0;

    for (const Mdt::TownEntityMarker& EntityMarker : TownMap.EntityMarkers)
    {
        if (EntityMarker.Kind != Mdt::TownEntityKind::Npc)
        {
            continue;
        }

        const std::size_t SpriteFamily = static_cast<std::size_t>(EntityMarker.NpcSpriteSelector & 0x0F);
        if (!IsConfirmedTownNpcSpriteFamily(SpriteFamily))
        {
            ++NpcSpriteMissCount;
            DrawTownEntityMarker(Renderer, EntityMarker, ScrollOffsetPixels);
            continue;
        }

        const std::size_t FrameIndex = GetTownNpcSpriteFrameIndex(EntityMarker);
        const Grp::NpcSpriteFrame* SpriteFrame = nullptr;
        if (!TryGetTownNpcSpriteFrame(FrameIndex, SpriteFrame))
        {
            ++NpcSpriteMissCount;
            DrawTownEntityMarker(Renderer, EntityMarker, ScrollOffsetPixels);
            continue;
        }

        // Keep the first pass anchored to the confirmed town entity row.
        DrawNpcSpriteFrameOnTownMap(Renderer, *SpriteFrame, Palette,
            static_cast<float>(EntityMarker.X * TownMapTileSize),
            static_cast<float>(EntityMarker.Y * TownMapTileSize),
            ScrollOffsetPixels);
        ++RenderedNpcSpriteCount;
    }

    return RenderedNpcSpriteCount;
}

TownScene::TownScene(const std::filesystem::path& ActorSpriteGrpPath, const std::filesystem::path& TownNpcSpriteGrpPath,
    const Mdt::TownMapInfo& TownMap,
    const Grp::PatternBank& PatternBank, const Main64Palette& Palette)
    : ActorSpriteGrpPath(ActorSpriteGrpPath), TownNpcSpriteGrpPath(TownNpcSpriteGrpPath), TownMap(TownMap), PatternBank(PatternBank), Palette(Palette)
{
    ActorFrameIndex = GetTownMapActorFrameIndex(ActorFacingDirection, false, ActorAnimationPhase);
    (void)UpdateTownMapActorFrame(ActorFrameIndex);

    ClampTownMapActorPosition(this->TownMap, ActorMapPixelX, ActorMapPixelY);
}

void TownScene::Update(const bool* KeyboardState)
{
    if (KeyboardState == nullptr)
    {
        return;
    }

    constexpr std::size_t ScrollSpeedPixels = 2;
    const std::size_t MaximumScrollOffset = GetTownMapMaximumScrollOffset(TownMap);

    if (CameraFollowEnabled)
    {
        ScrollOffsetPixels = GetTownMapCameraFollowScrollOffset(TownMap, ActorMapPixelX);
    }
    else if (KeyboardState[SDL_SCANCODE_PAGEUP] && !KeyboardState[SDL_SCANCODE_PAGEDOWN])
    {
        ScrollOffsetPixels = ScrollOffsetPixels > ScrollSpeedPixels ? ScrollOffsetPixels - ScrollSpeedPixels : 0;
    }
    else if (KeyboardState[SDL_SCANCODE_PAGEDOWN] && !KeyboardState[SDL_SCANCODE_PAGEUP])
    {
        ScrollOffsetPixels = std::min<std::size_t>(ScrollOffsetPixels + ScrollSpeedPixels, MaximumScrollOffset);
    }

    const TownMapActorFacingDirection PreviousTownMapActorFacingDirection = ActorFacingDirection;
    const bool ActorMoved = MoveTownMapActorPosition(TownMap, ActorMapPixelX, ActorMapPixelY, KeyboardState,
        ActorFacingDirection, ActorCollisionBlocked);

    if (ActorMoved)
    {
        if (ActorFacingDirection != PreviousTownMapActorFacingDirection)
        {
            ActorAnimationPhase = 0;
            ActorAnimationTickCount = 0;
        }
        else
        {
            ++ActorAnimationTickCount;
            if (ActorAnimationTickCount >= TownMapActorAnimationFrameDelay)
            {
                ActorAnimationTickCount = 0;
                ActorAnimationPhase = (ActorAnimationPhase + 1) % TownMapActorAnimationPhaseCount;
            }
        }
    }
    else
    {
        ActorAnimationTickCount = 0;
        ActorAnimationPhase = 0;
    }

    const std::size_t DesiredTownMapActorFrameIndex = GetTownMapActorFrameIndex(ActorFacingDirection, ActorMoved, ActorAnimationPhase);
    (void)UpdateTownMapActorFrame(DesiredTownMapActorFrameIndex);
}

void TownScene::Draw(SDL_Renderer* Renderer, const Grp::FontGroup* DebugFontGroup, bool DebugOverlayEnabled) const
{
    constexpr std::size_t TileSize = TownMapTileSize;
    constexpr std::size_t VisibleColumns = TownMapVisibleColumns;
    const std::size_t MaximumScrollOffset = GetTownMapMaximumScrollOffset(TownMap);
    const std::size_t ClampedScrollOffset = std::min<std::size_t>(ScrollOffsetPixels, MaximumScrollOffset);
    const std::size_t FirstColumn = ClampedScrollOffset / TileSize;
    const std::size_t ColumnPixelOffset = ClampedScrollOffset % TileSize;
    const std::size_t ColumnsAvailable = TownMap.Width > FirstColumn ? TownMap.Width - FirstColumn : 0;
    const std::size_t ColumnsToRender = std::min<std::size_t>(ColumnsAvailable, VisibleColumns + (ColumnPixelOffset != 0 ? 1 : 0));
    const std::size_t RowsToRender = TownMap.Height;
    const Grp::PatternTile& FallbackTile = GetFallbackPatternTile();

    for (std::size_t Column = 0; Column < ColumnsToRender; ++Column)
    {
        const std::size_t MapColumn = FirstColumn + Column;
        const float TileX = static_cast<float>(Column * TileSize) - static_cast<float>(ColumnPixelOffset);
        for (std::size_t Row = 0; Row < RowsToRender; ++Row)
        {
            const std::size_t CellIndex = MapColumn * TownMap.Height + Row;
            if (CellIndex >= TownMap.Cells.size())
            {
                continue;
            }

            const std::uint8_t TileIndex = TownMap.Cells[CellIndex];
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

            DrawPatternTile(Renderer, *Tile, Palette, TileX, static_cast<float>(Row * TileSize), 1.0f);
        }
    }

    if (BlockedTileOverlayEnabled)
    {
        SDL_SetRenderDrawBlendMode(Renderer, SDL_BLENDMODE_BLEND);
        SDL_SetRenderDrawColor(Renderer, 255, 48, 48, 96);

        for (std::size_t Column = 0; Column < ColumnsToRender; ++Column)
        {
            const std::size_t MapColumn = FirstColumn + Column;
            const float TileX = static_cast<float>(Column * TileSize) - static_cast<float>(ColumnPixelOffset);
            for (std::size_t Row = 0; Row < RowsToRender; ++Row)
            {
                const std::size_t CellIndex = MapColumn * TownMap.Height + Row;
                if (CellIndex >= TownMap.Cells.size())
                {
                    continue;
                }

                if (!IsTownMapBlockedTileIndex(TownMap.Cells[CellIndex]))
                {
                    continue;
                }

                const SDL_FRect PixelRect{
                    TileX,
                    static_cast<float>(Row * TileSize),
                    static_cast<float>(TileSize),
                    static_cast<float>(TileSize)
                };
                SDL_RenderFillRect(Renderer, &PixelRect);
            }
        }
    }

    std::size_t NpcSpriteMissCount = 0;
    const std::size_t RenderedNpcSpriteCount = TownEntityMarkersEnabled
        ? DrawTownNpcSprites(Renderer, ClampedScrollOffset, NpcSpriteMissCount)
        : 0;

    if (TownEntityMarkersEnabled)
    {
        DrawTownEntityMarkers(Renderer, TownMap, ClampedScrollOffset, Mdt::TownEntityKind::Door);
    }

    if (ActorFrameLoaded && ActorFrameVisible)
    {
        DrawNpcSpriteFrameOnTownMap(Renderer, ActorFrame, Palette, static_cast<float>(ActorMapPixelX),
            static_cast<float>(ActorMapPixelY), ClampedScrollOffset);
    }
    else
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
            "CAM " + std::string(GetTownMapCameraFollowModeName(CameraFollowEnabled)) + " X "
            + std::to_string(ClampedScrollOffset) + "/" + std::to_string(MaximumScrollOffset));
        DrawFontText(Renderer, *DebugFontGroup, StartX, StartY + LineSpacing * 2.0f, TextScale,
            "POS " + std::to_string(ActorMapPixelX) + "," + std::to_string(ActorMapPixelY) + " "
            + GetTownMapCollisionStatusName(ActorCollisionBlocked));
        DrawFontText(Renderer, *DebugFontGroup, StartX, StartY + LineSpacing * 3.0f, TextScale,
            std::string("TILE ") + (BlockedTileOverlayEnabled ? "ON" : "OFF") + " OBJ "
            + (TownEntityMarkersEnabled ? "ON" : "OFF"));
        DrawFontText(Renderer, *DebugFontGroup, StartX, StartY + LineSpacing * 4.0f, TextScale,
            "NPCSPR " + std::to_string(RenderedNpcSpriteCount) + "/" + std::to_string(NpcMarkerCount)
            + " NPCMISS " + std::to_string(NpcSpriteMissCount)
            + " DOOR " + std::to_string(DoorMarkerCount));
        DrawFontText(Renderer, *DebugFontGroup, StartX, StartY + LineSpacing * 5.0f, TextScale,
            GetTownEntityProximityStatus(TownMap, ActorMapPixelX, ActorMapPixelY));
    }
}

void TownScene::ToggleCameraFollow() noexcept
{
    CameraFollowEnabled = !CameraFollowEnabled;
}

void TownScene::ToggleBlockedTileOverlay() noexcept
{
    BlockedTileOverlayEnabled = !BlockedTileOverlayEnabled;
}

void TownScene::ToggleTownEntityMarkers() noexcept
{
    TownEntityMarkersEnabled = !TownEntityMarkersEnabled;
}

bool TownScene::IsCameraFollowEnabled() const noexcept
{
    return CameraFollowEnabled;
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
