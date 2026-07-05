#include <SDL3/SDL.h>

#include "grp/grp_font.h"
#include "grp/grp_unpacker.h"

#include <array>
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

bool LoadFontGroups(std::array<Grp::FontGroup, 3>& FontGroups, std::array<bool, 3>& FontGroupAvailable)
{
    std::vector<std::uint8_t> Unpacked;
    std::string ErrorMessage;
    const std::filesystem::path GrpPath = ProjectRoot / "tools" / "grpviewer" / "font.grp";

    if (!Grp::UnpackFile(GrpPath, Unpacked, ErrorMessage))
    {
        std::cerr << "font.grp load failed: " << ErrorMessage << '\n';
        return false;
    }

    bool AnyGroupLoaded = false;
    for (std::size_t GroupIndex = 0; GroupIndex < FontGroups.size(); ++GroupIndex)
    {
        std::string WarningMessage;
        if (Grp::DecodeFontGroup(Unpacked, GroupIndex, FontGroups[GroupIndex], ErrorMessage, &WarningMessage))
        {
            FontGroupAvailable[GroupIndex] = true;
            AnyGroupLoaded = true;
            if (!WarningMessage.empty())
            {
                std::cerr << WarningMessage << '\n';
            }
        }
        else
        {
            FontGroupAvailable[GroupIndex] = false;
            std::cerr << "font.grp parse skipped for group " << GroupIndex << ": " << ErrorMessage << '\n';
        }
    }

    if (!AnyGroupLoaded)
    {
        std::cerr << "font.grp parse failed: no usable font groups were found" << '\n';
        return false;
    }

    std::size_t AvailableGroupCount = 0;
    for (bool IsAvailable : FontGroupAvailable)
    {
        if (IsAvailable)
        {
            ++AvailableGroupCount;
        }
    }

    std::cout << "font.grp loaded: " << AvailableGroupCount << " font groups available ("
              << Unpacked.size() << " unpacked bytes)." << '\n';
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

void PrintActiveFontGroup(std::size_t GroupIndex, const Grp::FontGroup& FontGroup)
{
    std::cout << "font.grp active group " << GroupIndex << " has " << FontGroup.Glyphs.size()
              << " 8x8 glyphs." << '\n';
}
}

int main()
{
    const bool ValidationMatch = ValidateGrpUnpack();
    std::array<Grp::FontGroup, 3> FontGroups{};
    std::array<bool, 3> FontGroupAvailable{};
    const bool FontLoaded = LoadFontGroups(FontGroups, FontGroupAvailable);
    std::size_t ActiveFontGroupIndex = 0;

    if (FontLoaded && !FontGroupAvailable[ActiveFontGroupIndex])
    {
        for (std::size_t GroupIndex = 0; GroupIndex < FontGroupAvailable.size(); ++GroupIndex)
        {
            if (FontGroupAvailable[GroupIndex])
            {
                ActiveFontGroupIndex = GroupIndex;
                break;
            }
        }
    }

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
            else if (Event.type == SDL_EVENT_KEY_DOWN && !Event.key.repeat)
            {
                std::size_t RequestedGroupIndex = 0;
                bool HasSelection = true;

                if (Event.key.key == SDLK_1)
                {
                    RequestedGroupIndex = 0;
                }
                else if (Event.key.key == SDLK_2)
                {
                    RequestedGroupIndex = 1;
                }
                else if (Event.key.key == SDLK_3)
                {
                    RequestedGroupIndex = 2;
                }
                else
                {
                    HasSelection = false;
                }

                if (HasSelection && RequestedGroupIndex < FontGroupAvailable.size() && FontGroupAvailable[RequestedGroupIndex] && RequestedGroupIndex != ActiveFontGroupIndex)
                {
                    ActiveFontGroupIndex = RequestedGroupIndex;
                    PrintActiveFontGroup(ActiveFontGroupIndex, FontGroups[ActiveFontGroupIndex]);
                }
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
            if (ActiveFontGroupIndex < FontGroupAvailable.size() && FontGroupAvailable[ActiveFontGroupIndex])
            {
                DrawFontGlyphGrid(Renderer, FontGroups[ActiveFontGroupIndex]);
            }
        }

        SDL_RenderPresent(Renderer);
        SDL_Delay(16);
    }

    SDL_DestroyRenderer(Renderer);
    SDL_DestroyWindow(Window);
    SDL_Quit();
    return ValidationMatch ? 0 : 1;
}
