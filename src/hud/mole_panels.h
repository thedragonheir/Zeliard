#pragma once

#include <cstddef>
#include <cstdint>
#include <span>

#include "../mcga/mcga_palette.h"

struct SDL_Renderer;

namespace Hud
{
constexpr std::size_t MoleDecorationPanelWidth = 48;
constexpr std::size_t MoleDecorationPanelHeight = 200;
constexpr std::size_t MoleTopTearsBaseWidth = 224;
constexpr std::size_t MoleTopTearsBaseHeight = 13;
constexpr std::size_t MoleBottomStatusBaseWidth = 224;
constexpr std::size_t MoleBottomStatusBaseHeight = 42;

void DrawMolePanel(SDL_Renderer* Renderer, const Main64Palette& Palette,
    std::span<const std::uint8_t> Pixels, std::size_t Width, std::size_t Height,
    std::size_t ScreenX, std::size_t ScreenY);
}
