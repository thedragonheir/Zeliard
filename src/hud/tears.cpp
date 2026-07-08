#include "tears.h"

#include <algorithm>

namespace Hud
{
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
    std::uint8_t TearsOfEsmesantiCount, bool TearsOverlayDebugOverrideEnabled)
{
    const std::size_t DrawCount = TearsOverlayDebugOverrideEnabled
        ? TearsOverlayMaximumCount
        : std::min<std::size_t>(TearsOfEsmesantiCount, TearsOverlayMaximumCount);

    for (std::size_t TearIndex = 0; TearIndex < DrawCount; ++TearIndex)
    {
        const std::size_t IconIndex = TearIndex == TearsOverlayMaximumCount - 1 ? 1 : 0;
        const SDL_Point Position = TearsOverlayPositions[TearIndex];

        DrawTearsOverlayIcon(Renderer, Palette,
            IconIndex == 0 ? SmallBlueIconPixels : LargeRedIconPixels,
            static_cast<std::size_t>(Position.x), static_cast<std::size_t>(Position.y));
    }
}
}
