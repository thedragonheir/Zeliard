#include "mcga_draw.h"

#include <SDL3/SDL.h>

namespace Mcga
{
void DrawIndexedPixel(SDL_Renderer* Renderer, const Main64Palette& Palette, std::uint8_t PaletteIndex,
    float X, float Y)
{
    if (PaletteIndex >= Palette.size())
    {
        return;
    }

    const SDL_Color& Color = Palette[PaletteIndex];
    SDL_SetRenderDrawColor(Renderer, Color.r, Color.g, Color.b, Color.a);
    const SDL_FRect Rect{ X, Y, 1.0f, 1.0f };
    SDL_RenderFillRect(Renderer, &Rect);
}

void DrawIndexedImage(SDL_Renderer* Renderer, const Main64Palette& Palette,
    std::span<const std::uint8_t> Pixels, std::size_t Width, std::size_t Height,
    std::size_t ScreenX, std::size_t ScreenY)
{
    SDL_SetRenderDrawBlendMode(Renderer, SDL_BLENDMODE_NONE);
    for (std::size_t Row = 0; Row < Height; ++Row)
    {
        for (std::size_t Column = 0; Column < Width; ++Column)
        {
            DrawIndexedPixel(Renderer, Palette, Pixels[Row * Width + Column],
                static_cast<float>(ScreenX + Column), static_cast<float>(ScreenY + Row));
        }
    }
}
}
