#pragma once

#include <cstddef>
#include <cstdint>
#include <span>

#include "../mcga/mcga_palette.h"

struct SDL_Renderer;

namespace Grp
{
struct NpcSpriteFrame;
struct PatternTile;
}

namespace TownRender
{
void DrawBackgroundStrip(SDL_Renderer* Renderer, std::span<const std::uint8_t> Pixels,
    const Main64Palette& Palette, std::size_t ScrollOffsetPixels);
void DrawMountainLayer(SDL_Renderer* Renderer, std::span<const std::uint8_t> Pixels,
    const Main64Palette& Palette);
void DrawPatternTile(SDL_Renderer* Renderer, const Grp::PatternTile& Tile,
    const Main64Palette& Palette, float TileX, float TileY, float PixelSize,
    bool UseTransparencyMask);
void DrawNpcFrameColumnSlice(SDL_Renderer* Renderer,
    const Grp::NpcSpriteFrame& SpriteFrame, const Main64Palette& Palette,
    std::size_t MapPixelX, std::size_t MapPixelY, std::size_t ScrollOffsetPixels,
    std::size_t MapColumn);
void DrawActorFallbackMarker(SDL_Renderer* Renderer, float MapPixelX, float MapPixelY,
    std::size_t ScrollOffsetPixels);
}
