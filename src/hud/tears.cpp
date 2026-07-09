#include "tears.h"

#include <algorithm>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <vector>

std::uint8_t TearsOfEsmesantiCount = 0;

namespace Hud
{
namespace
{
bool ReadWholeFile(const std::filesystem::path& Path, std::vector<std::uint8_t>& Output,
    std::string& ErrorMessage)
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

std::string FormatHexOffset(std::size_t Offset)
{
    std::ostringstream Output;
    Output << "0x" << std::uppercase << std::hex << std::setw(4) << std::setfill('0') << Offset;
    return Output.str();
}
}

bool LoadTearsOverlayIcons(const std::filesystem::path& GmmcgaBinPath,
    TearsOverlayIconPixels& SmallBlueIconPixels, TearsOverlayIconPixels& LargeRedIconPixels,
    std::string& ErrorMessage)
{
    std::vector<std::uint8_t> FileBytes;
    if (!ReadWholeFile(GmmcgaBinPath, FileBytes, ErrorMessage))
    {
        return false;
    }

    if (FileBytes.size() < LargeTearIconFileOffset + TearsIconByteCount)
    {
        ErrorMessage = GmmcgaBinPath.filename().string()
            + " is too small to contain the collected Tears icons";
        return false;
    }

    std::copy_n(FileBytes.begin() + static_cast<std::ptrdiff_t>(TearsOverlaySmallIconFileOffset),
        TearsIconByteCount, SmallBlueIconPixels.begin());
    std::copy_n(FileBytes.begin() + static_cast<std::ptrdiff_t>(LargeTearIconFileOffset),
        TearsIconByteCount, LargeRedIconPixels.begin());

    std::cerr << GmmcgaBinPath.filename().string() << " collected Tears icons: "
        << "AL=0 source span " << FormatHexOffset(TearsOverlaySmallIconFileOffset) << ".."
        << FormatHexOffset(TearsOverlaySmallIconFileOffset + TearsIconByteCount)
        << ", AL=1 source span " << FormatHexOffset(LargeTearIconFileOffset) << ".."
        << FormatHexOffset(LargeTearIconFileOffset + TearsIconByteCount)
        << ", icon size " << TearsOverlayIconWidth << " x " << TearsOverlayIconHeight << '\n';

    ErrorMessage.clear();
    return true;
}

void DrawTearsOverlayIcon(SDL_Renderer* Renderer, const std::array<SDL_Color, 64>& Palette,
    const TearsOverlayIconPixels& IconPixels, std::size_t ScreenX, std::size_t ScreenY)
{
    SDL_SetRenderDrawBlendMode(Renderer, SDL_BLENDMODE_NONE);
    for (std::size_t Row = 0; Row < TearsOverlayIconHeight; ++Row)
    {
        for (std::size_t Column = 0; Column < TearsOverlayIconWidth; ++Column)
        {
            const std::uint8_t PaletteIndex = IconPixels[Row * TearsOverlayIconWidth + Column];
            if (PaletteIndex == TearsOverlayTransparentIndex || PaletteIndex >= Palette.size())
            {
                continue;
            }

            const SDL_Color& Color = Palette[PaletteIndex];
            SDL_SetRenderDrawColor(Renderer, Color.r, Color.g, Color.b, Color.a);

            const SDL_FRect PixelRect{
                static_cast<float>(ScreenX + Column),
                static_cast<float>(ScreenY + Row),
                1.0f,
                1.0f
            };
            SDL_RenderFillRect(Renderer, &PixelRect);
        }
    }
}

void DrawTearsOverlay(SDL_Renderer* Renderer, const std::array<SDL_Color, 64>& Palette,
    const TearsOverlayIconPixels& SmallBlueIconPixels, const TearsOverlayIconPixels& LargeRedIconPixels,
    std::uint8_t TearsOfEsmesantiCount, bool ShowAllTearsIcons)
{
    const std::size_t DrawCount = ShowAllTearsIcons
        ? MaxTearsOverlayCount
        : std::min<std::size_t>(TearsOfEsmesantiCount, MaxTearsOverlayCount);

    for (std::size_t TearIndex = 0; TearIndex < DrawCount; ++TearIndex)
    {
        const std::size_t IconIndex = TearIndex == MaxTearsOverlayCount - 1 ? 1 : 0;
        const SDL_Point Position = TearsOverlayPositions[TearIndex];

        DrawTearsOverlayIcon(Renderer, Palette,
            IconIndex == 0 ? SmallBlueIconPixels : LargeRedIconPixels,
            static_cast<std::size_t>(Position.x), static_cast<std::size_t>(Position.y));
    }
}
}
