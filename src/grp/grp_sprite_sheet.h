#pragma once

#include <array>
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

struct NpcSpriteFrame
{
    static constexpr std::size_t FrameWidth = 16;
    static constexpr std::size_t FrameHeight = 24;
    static constexpr std::size_t PixelCount = FrameWidth * FrameHeight;

    std::array<std::uint8_t, PixelCount> Pixels{};
};

bool LoadNpcSpriteSheet(const std::filesystem::path& Path, SpriteSheetSummary& Output, std::string& ErrorMessage);
bool LoadNpcSpriteFrame(const std::filesystem::path& Path, std::size_t FrameIndex, NpcSpriteFrame& Output, std::string& ErrorMessage);
}
