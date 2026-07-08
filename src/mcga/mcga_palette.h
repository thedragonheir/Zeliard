#pragma once

#include <array>
#include <filesystem>
#include <string>

#include <SDL3/SDL.h>

using Main64Palette = std::array<SDL_Color, 64>;

namespace Mcga
{
bool LoadMain64Palette(const std::filesystem::path& ProjectRoot, Main64Palette& Palette,
    std::string& ErrorMessage);
}
