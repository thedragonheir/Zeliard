#pragma once

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <string>

namespace Grp
{
struct SpriteSheetSummary
{
    std::size_t UnpackedByteCount = 0;
    std::size_t FrameCount = 0;
    std::size_t FrameWidth = 0;
    std::size_t FrameHeight = 0;
    std::size_t DecodedPixelCount = 0;
    std::uint8_t MinimumPaletteIndex = 0;
    std::uint8_t MaximumPaletteIndex = 0;
};

bool LoadNpcSpriteSheet(const std::filesystem::path& Path, SpriteSheetSummary& Output, std::string& ErrorMessage);
}
