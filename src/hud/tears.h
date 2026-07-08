#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <string>

#include <SDL3/SDL.h>

// Mirrors the global Tear-count byte until the save/global-state wiring lands.
extern std::uint8_t TearsOfEsmesantiCount;

namespace Hud
{
constexpr std::size_t TearsOverlayIconWidth = 16;
constexpr std::size_t TearsOverlayIconHeight = 13;
constexpr std::size_t TearsOverlayIconByteCount = TearsOverlayIconWidth * TearsOverlayIconHeight;
constexpr std::uint8_t TearsOverlayTransparentIndex = 0x80;
constexpr std::size_t TearsOverlayMaximumCount = 9;
constexpr std::size_t TearsOverlaySmallIconFileOffset = 0x0A61;
constexpr std::size_t TearsOverlayLargeIconFileOffset = 0x0B31;

using TearsOverlayIconPixels = std::array<std::uint8_t, TearsOverlayIconByteCount>;

constexpr std::array<SDL_Point, TearsOverlayMaximumCount> TearsOverlayPositions{{
    { 60, 0 },
    { 244, 0 },
    { 84, 0 },
    { 220, 0 },
    { 108, 0 },
    { 196, 0 },
    { 132, 0 },
    { 172, 0 },
    { 152, 0 }
}};

bool LoadTearsOverlayIcons(const std::filesystem::path& GmmcgaBinPath,
    TearsOverlayIconPixels& SmallBlueIconPixels, TearsOverlayIconPixels& LargeRedIconPixels,
    std::string& ErrorMessage);

void DrawTearsOverlayIcon(SDL_Renderer* Renderer, const std::array<SDL_Color, 64>& Palette,
    const TearsOverlayIconPixels& IconPixels, std::size_t ScreenX, std::size_t ScreenY);

void DrawTearsOverlay(SDL_Renderer* Renderer, const std::array<SDL_Color, 64>& Palette,
    const TearsOverlayIconPixels& SmallBlueIconPixels, const TearsOverlayIconPixels& LargeRedIconPixels,
    std::uint8_t TearsOfEsmesantiCount, bool TearsOverlayDebugOverrideEnabled);
}
