#include <SDL3/SDL.h>

#include "grp/grp_font.h"
#include "grp/grp_unpacker.h"

#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

namespace
{
const std::filesystem::path ProjectRoot = ZELIARD_PROJECT_ROOT;

bool ReadWholeFile(const std::filesystem::path& Path, std::vector<std::uint8_t>& Output)
{
    std::ifstream Input(Path, std::ios::binary | std::ios::ate);
    if (!Input)
    {
        return false;
    }

    const std::streamsize FileSize = Input.tellg();
    if (FileSize < 0)
    {
        return false;
    }

    Output.resize(static_cast<std::size_t>(FileSize));
    Input.seekg(0, std::ios::beg);
    if (FileSize > 0 && !Input.read(reinterpret_cast<char*>(Output.data()), FileSize))
    {
        return false;
    }

    return true;
}

bool ValidateGrpUnpack()
{
    std::vector<std::uint8_t> Unpacked;
    std::vector<std::uint8_t> Expected;
    std::string ErrorMessage;
    const std::filesystem::path GrpPath = ProjectRoot / "tools" / "grpviewer" / "cpat.grp";
    const std::filesystem::path UnpPath = ProjectRoot / "tools" / "grpviewer" / "cpat.grp.unp";

    if (!Grp::UnpackFile(GrpPath, Unpacked, ErrorMessage))
    {
        std::cerr << "GRP validation mismatch: " << ErrorMessage << '\n';
        return false;
    }

    if (!ReadWholeFile(UnpPath, Expected))
    {
        std::cerr << "GRP validation mismatch: failed to open " << UnpPath.string() << '\n';
        return false;
    }

    if (Unpacked == Expected)
    {
        std::cout << "GRP validation match: " << GrpPath.string() << " matches " << UnpPath.string()
                  << " (" << Unpacked.size() << " bytes)." << '\n';
        return true;
    }

    std::cout << "GRP validation mismatch: " << GrpPath.string() << " unpacked to " << Unpacked.size()
              << " bytes, expected " << Expected.size() << " bytes." << '\n';
    return false;
}

bool LoadFontGroup(Grp::FontGroup& FontGroup)
{
    std::vector<std::uint8_t> Unpacked;
    std::string ErrorMessage;
    const std::filesystem::path GrpPath = ProjectRoot / "tools" / "grpviewer" / "font.grp";

    if (!Grp::UnpackFile(GrpPath, Unpacked, ErrorMessage))
    {
        std::cerr << "font.grp load failed: " << ErrorMessage << '\n';
        return false;
    }

    if (!Grp::DecodeFirstFontGroup(Unpacked, FontGroup, ErrorMessage))
    {
        std::cerr << "font.grp parse failed: " << ErrorMessage << '\n';
        return false;
    }

    std::cout << "font.grp loaded: first font group has " << FontGroup.Glyphs.size()
              << " 8x8 glyphs (" << Unpacked.size() << " unpacked bytes)." << '\n';
    return true;
}

void DrawFontGlyphGrid(SDL_Renderer* Renderer, const Grp::FontGroup& FontGroup)
{
    constexpr int Columns = 16;
    constexpr float StartX = 16.0f;
    constexpr float StartY = 16.0f;
    constexpr float PixelSize = 2.0f;
    constexpr float GlyphStep = 18.0f;

    SDL_SetRenderDrawColor(Renderer, 255, 255, 255, 255);

    for (std::size_t GlyphIndex = 0; GlyphIndex < FontGroup.Glyphs.size(); ++GlyphIndex)
    {
        const int GlyphColumn = static_cast<int>(GlyphIndex % Columns);
        const int GlyphRow = static_cast<int>(GlyphIndex / Columns);
        const float GlyphX = StartX + static_cast<float>(GlyphColumn) * GlyphStep;
        const float GlyphY = StartY + static_cast<float>(GlyphRow) * GlyphStep;

        for (std::size_t Row = 0; Row < 8; ++Row)
        {
            const std::uint8_t Bits = FontGroup.Glyphs[GlyphIndex].Rows[Row];
            for (std::size_t Column = 0; Column < 8; ++Column)
            {
                if (((Bits >> (7 - Column)) & 1) == 0)
                {
                    continue;
                }

                const SDL_FRect PixelRect{
                    GlyphX + static_cast<float>(Column) * PixelSize,
                    GlyphY + static_cast<float>(Row) * PixelSize,
                    PixelSize,
                    PixelSize
                };
                SDL_RenderFillRect(Renderer, &PixelRect);
            }
        }
    }
}
}

int main()
{
    const bool ValidationMatch = ValidateGrpUnpack();
    Grp::FontGroup FontGroup;
    const bool FontLoaded = LoadFontGroup(FontGroup);

    if (!SDL_Init(SDL_INIT_VIDEO))
    {
        std::cerr << "SDL_Init failed: " << SDL_GetError() << '\n';
        return 1;
    }

    SDL_Window* Window = SDL_CreateWindow("Zeliard", 960, 600, 0);
    if (!Window)
    {
        std::cerr << "SDL_CreateWindow failed: " << SDL_GetError() << '\n';
        SDL_Quit();
        return 1;
    }

    SDL_Renderer* Renderer = SDL_CreateRenderer(Window, nullptr);
    if (!Renderer)
    {
        std::cerr << "SDL_CreateRenderer failed: " << SDL_GetError() << '\n';
        SDL_DestroyWindow(Window);
        SDL_Quit();
        return 1;
    }

    if (!SDL_SetRenderLogicalPresentation(Renderer, 320, 200, SDL_LOGICAL_PRESENTATION_LETTERBOX))
    {
        std::cerr << "SDL_SetRenderLogicalPresentation failed: " << SDL_GetError() << '\n';
        SDL_DestroyRenderer(Renderer);
        SDL_DestroyWindow(Window);
        SDL_Quit();
        return 1;
    }

    bool Running = true;
    while (Running)
    {
        SDL_Event Event;
        while (SDL_PollEvent(&Event))
        {
            if (Event.type == SDL_EVENT_QUIT)
            {
                Running = false;
            }
            else if (Event.type == SDL_EVENT_KEY_DOWN && Event.key.key == SDLK_ESCAPE)
            {
                Running = false;
            }
        }

        if (FontLoaded)
        {
            SDL_SetRenderDrawColor(Renderer, 16, 24, 32, 255);
        }
        else
        {
            SDL_SetRenderDrawColor(Renderer, 48, 16, 16, 255);
        }
        SDL_RenderClear(Renderer);

        if (FontLoaded)
        {
            DrawFontGlyphGrid(Renderer, FontGroup);
        }

        SDL_RenderPresent(Renderer);
        SDL_Delay(16);
    }

    SDL_DestroyRenderer(Renderer);
    SDL_DestroyWindow(Window);
    SDL_Quit();
    return ValidationMatch ? 0 : 1;
}
