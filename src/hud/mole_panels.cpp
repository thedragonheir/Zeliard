#include "mole_panels.h"

#include "../mcga/mcga_draw.h"

namespace Hud
{
void DrawMolePanel(SDL_Renderer* Renderer, const Main64Palette& Palette,
    std::span<const std::uint8_t> Pixels, std::size_t Width, std::size_t Height,
    std::size_t ScreenX, std::size_t ScreenY)
{
    Mcga::DrawIndexedImage(Renderer, Palette, Pixels, Width, Height, ScreenX, ScreenY);
}
}
