#pragma once

#include <cstddef>
#include <cstdint>
#include <span>

#include "mcga_palette.hpp"

struct SDL_Renderer;

namespace Mcga
{
void DrawIndexedPixel(SDL_Renderer* Renderer, const Main64Palette& Palette, std::uint8_t PaletteIndex,
    float X, float Y);

void DrawIndexedImage(SDL_Renderer* Renderer, const Main64Palette& Palette,
    std::span<const std::uint8_t> Pixels, std::size_t Width, std::size_t Height,
    std::size_t ScreenX, std::size_t ScreenY);
}
