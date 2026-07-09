#include "town_render.h"

#include <algorithm>

#include <SDL3/SDL.h>

#include "../grp/man_grp.h"
#include "../grp/pat_grp.h"

namespace
{
constexpr std::size_t TownMapTileSize = 8;
constexpr std::size_t TownViewportLeftX = 48;
constexpr std::size_t TownViewportTopY = 14 + 8 * TownMapTileSize;
constexpr std::size_t TownBackgroundStripWidth = 224;
constexpr std::size_t TownBackgroundStripHeight = 16;
constexpr std::size_t TownBackgroundStripLeftX = 48;
constexpr std::size_t TownBackgroundStripLeftY = 14 + 16 * 8;
constexpr std::size_t TownBackgroundMountainWidth = 224;
constexpr std::size_t TownBackgroundMountainHeight = 88;
constexpr std::size_t TownBackgroundMountainLeftX = 48;
constexpr std::size_t TownBackgroundMountainTopY = 14;
}

namespace TownRender
{
void DrawBackgroundStrip(SDL_Renderer* Renderer, std::span<const std::uint8_t> Pixels,
    const Main64Palette& Palette, std::size_t ScrollOffsetPixels)
{
    SDL_SetRenderDrawBlendMode(Renderer, SDL_BLENDMODE_NONE);
    for (std::size_t Row = 0; Row < TownBackgroundStripHeight; ++Row)
    {
        for (std::size_t Column = 0; Column < TownBackgroundStripWidth; ++Column)
        {
            // Mirror the DOS floor-band scroll by sampling the decoded strip
            // with a cyclic 8px phase instead of moving the strip rectangle.
            const std::size_t SourceColumn =
                (Column + TownBackgroundStripWidth - ScrollOffsetPixels) % TownBackgroundStripWidth;
            const std::uint8_t PaletteIndex = Pixels[Row * TownBackgroundStripWidth + SourceColumn];
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

void DrawMountainLayer(SDL_Renderer* Renderer, std::span<const std::uint8_t> Pixels,
    const Main64Palette& Palette)
{
    SDL_SetRenderDrawBlendMode(Renderer, SDL_BLENDMODE_NONE);
    for (std::size_t Row = 0; Row < TownBackgroundMountainHeight; ++Row)
    {
        for (std::size_t Column = 0; Column < TownBackgroundMountainWidth; ++Column)
        {
            const std::uint8_t PaletteIndex = Pixels[Row * TownBackgroundMountainWidth + Column];
            if (PaletteIndex >= Palette.size())
            {
                continue;
            }

            const SDL_Color& Color = Palette[PaletteIndex];
            SDL_SetRenderDrawColor(Renderer, Color.r, Color.g, Color.b, Color.a);
            const SDL_FRect PixelRect{
                static_cast<float>(TownBackgroundMountainLeftX + Column),
                static_cast<float>(TownBackgroundMountainTopY + Row),
                1.0f,
                1.0f
            };
            SDL_RenderFillRect(Renderer, &PixelRect);
        }
    }
}

void DrawPatternTile(SDL_Renderer* Renderer, const Grp::PatternTile& Tile,
    const Main64Palette& Palette, float TileX, float TileY, float PixelSize,
    bool UseTransparencyMask)
{
    for (std::size_t Row = 0; Row < 8; ++Row)
    {
        const std::uint8_t TransparencyMaskRow =
            UseTransparencyMask ? Tile.TransparencyMaskRows[Row] : 0;
        for (std::size_t Column = 0; Column < 8; ++Column)
        {
            if ((TransparencyMaskRow & static_cast<std::uint8_t>(0x80 >> Column)) != 0)
            {
                continue;
            }

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

void DrawNpcFrameColumnSlice(SDL_Renderer* Renderer,
    const Grp::NpcSpriteFrame& SpriteFrame, const Main64Palette& Palette,
    std::size_t MapPixelX, std::size_t MapPixelY, std::size_t ScrollOffsetPixels,
    std::size_t MapColumn)
{
    constexpr float SpritePixelSize = 1.0f;
    const std::size_t ColumnLeftPixel = MapColumn * TownMapTileSize;
    const std::size_t ColumnRightPixel = ColumnLeftPixel + TownMapTileSize;
    const std::size_t SpriteRightPixel = MapPixelX + Grp::NpcSpriteFrame::FrameWidth;
    if (SpriteRightPixel <= ColumnLeftPixel || MapPixelX >= ColumnRightPixel)
    {
        return;
    }

    const std::size_t FirstSpriteColumn =
        ColumnLeftPixel > MapPixelX ? ColumnLeftPixel - MapPixelX : 0;
    const std::size_t LastSpriteColumn = std::min<std::size_t>(
        Grp::NpcSpriteFrame::FrameWidth, ColumnRightPixel - MapPixelX);

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
                static_cast<float>(TownViewportLeftX + MapPixelX + Column)
                    - static_cast<float>(ScrollOffsetPixels),
                static_cast<float>(TownViewportTopY + MapPixelY)
                    + static_cast<float>(Row) * SpritePixelSize,
                SpritePixelSize,
                SpritePixelSize
            };
            SDL_RenderFillRect(Renderer, &PixelRect);
        }
    }
}

void DrawActorFallbackMarker(SDL_Renderer* Renderer, float MapPixelX, float MapPixelY,
    std::size_t ScrollOffsetPixels)
{
    constexpr float MarkerSize = 10.0f;
    constexpr float LineSize = 2.0f;
    const float ScreenX = static_cast<float>(TownViewportLeftX) + MapPixelX
        - static_cast<float>(ScrollOffsetPixels)
        + (static_cast<float>(Grp::NpcSpriteFrame::FrameWidth) - MarkerSize) * 0.5f;
    const float ScreenY = static_cast<float>(TownViewportTopY) + MapPixelY
        + (static_cast<float>(Grp::NpcSpriteFrame::FrameHeight) - MarkerSize) * 0.5f;

    SDL_SetRenderDrawBlendMode(Renderer, SDL_BLENDMODE_BLEND);
    SDL_SetRenderDrawColor(Renderer, 255, 64, 224, 232);
    const SDL_FRect MarkerRect{ ScreenX, ScreenY, MarkerSize, MarkerSize };
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
}
