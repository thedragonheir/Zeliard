#include <SDL3/SDL.h>

#include "grp/pat_grp.h"
#include "grp/grp_unpack.h"
#include "mcga/mcga_palette.h"
#include "mdt/town_mdt.h"

#include <cstdint>
#include <filesystem>
#include <fstream>
#include <initializer_list>
#include <iomanip>
#include <iostream>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif

#include "town/town.h"

#if defined(_WIN32) && !defined(__EMSCRIPTEN__)
extern "C"
{
    // Ask hybrid laptops to prefer the dedicated GPU.
    __declspec(dllexport) unsigned long NvOptimusEnablement = 1;
    __declspec(dllexport) int AmdPowerXpressRequestHighPerformance = 1;
}
#endif

namespace
{
    const std::filesystem::path ProjectRoot = ZELIARD_PROJECT_ROOT;
    constexpr int InternalWidth = 320;
    constexpr int InternalHeight = 200;
    constexpr int WindowWidth = 960;
    constexpr int WindowHeight = 720;
    constexpr SDL_RendererLogicalPresentation LogicalPresentation = SDL_LOGICAL_PRESENTATION_STRETCH;

    constexpr int MaxTownTicksPerFrame = 5;

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

    std::filesystem::path ResolveFirstExistingPath(std::initializer_list<std::filesystem::path> CandidatePaths)
    {
        for (const std::filesystem::path& CandidatePath : CandidatePaths)
        {
            if (!CandidatePath.empty() && std::filesystem::exists(CandidatePath))
            {
                return CandidatePath;
            }
        }

        if (CandidatePaths.size() == 0)
        {
            return {};
        }

        return *CandidatePaths.begin();
    }

    std::filesystem::path GetTownPatternBankPath(std::uint8_t PatternGroupId)
    {
        switch (PatternGroupId)
        {
        case 0:
            return ResolveFirstExistingPath({
                ProjectRoot / "game" / "0" / "cpat.grp",
                ProjectRoot / "tools" / "grpviewer" / "cpat.grp"
                });

        case 1:
            return ResolveFirstExistingPath({
                ProjectRoot / "game" / "0" / "mpat.grp",
                ProjectRoot / "tools" / "grpviewer" / "mpat.grp"
                });

        case 2:
            return ResolveFirstExistingPath({
                ProjectRoot / "game" / "0" / "dpat.grp",
                ProjectRoot / "tools" / "grpviewer" / "dpat.grp"
                });
        }

        return {};
    }

    bool LoadTownPatternBank(std::uint8_t PatternGroupId, Grp::PatternBank& PatternBank)
    {
        std::vector<std::uint8_t> Unpacked;
        std::string ErrorMessage;
        const std::filesystem::path GrpPath = GetTownPatternBankPath(PatternGroupId);
        if (GrpPath.empty())
        {
            std::cerr << "invalid town pattern group id: " << static_cast<unsigned int>(PatternGroupId) << '\n';
            return false;
        }

        if (!Grp::UnpackFile(GrpPath, Unpacked, ErrorMessage))
        {
            std::cerr << GrpPath.filename().string() << " load failed: " << ErrorMessage << '\n';
            return false;
        }

        if (!Grp::DecodePatternBank(Unpacked, PatternBank, ErrorMessage))
        {
            std::cerr << GrpPath.filename().string() << " pattern decode failed: " << ErrorMessage << '\n';
            return false;
        }

        std::ostringstream SpecialTileStream;
        SpecialTileStream << std::uppercase << std::hex << std::setfill('0');
        for (std::size_t TileIndex = 0; TileIndex < PatternBank.SpecialTileIndices.size(); ++TileIndex)
        {
            if (TileIndex > 0)
            {
                SpecialTileStream << ' ';
            }

            SpecialTileStream << std::setw(2)
                << static_cast<unsigned int>(PatternBank.SpecialTileIndices[TileIndex]);
        }

        std::cout << GrpPath.filename().string() << " pattern bank loaded: " << PatternBank.Tiles.size()
            << " patterns, " << Unpacked.size() << " source bytes, "
            << (PatternBank.Tiles.size() * 64) << " decoded pixels, "
            << "palette indices " << static_cast<int>(PatternBank.MinimumPaletteIndex) << ".."
            << static_cast<int>(PatternBank.MaximumPaletteIndex)
            << ", special tiles "
            << (PatternBank.SpecialTileIndices.empty() ? "none" : SpecialTileStream.str()) << "." << '\n';
        return true;
    }

    std::filesystem::path GetTownNpcSpriteGrpPath(const std::vector<std::uint8_t>& FileBytes)
    {
        constexpr std::uint16_t TownDescriptorAddress = 0xC000;
        constexpr std::size_t TownNpcBankSelectorOffset = 1;
        const std::string NpcGrpName = [&FileBytes]() -> std::string
            {
                if (FileBytes.size() < 2)
                {
                    return "mman.grp";
                }

                const std::uint16_t DescriptorPointer = static_cast<std::uint16_t>(
                    FileBytes[0] | (static_cast<std::uint16_t>(FileBytes[1]) << 8));
                if (DescriptorPointer < TownDescriptorAddress)
                {
                    return "mman.grp";
                }

                const std::size_t DescriptorOffset = static_cast<std::size_t>(DescriptorPointer - TownDescriptorAddress);
                if (DescriptorOffset + TownNpcBankSelectorOffset >= FileBytes.size())
                {
                    return "mman.grp";
                }

                return FileBytes[DescriptorOffset + TownNpcBankSelectorOffset] != 0 ? "cman.grp" : "mman.grp";
            }();

        return ProjectRoot / "game" / "0" / NpcGrpName;
    }

    std::filesystem::path GetTownMdtPath(std::uint8_t TownId)
    {
        switch (TownId)
        {
        case 0:
            return ProjectRoot / "game" / "0" / "cmap.mdt";

        case 1:
            return ProjectRoot / "game" / "0" / "mrmp.mdt";

        case 2:
            return ProjectRoot / "game" / "0" / "stmp.mdt";

        case 3:
            return ProjectRoot / "game" / "0" / "bsmp.mdt";

        case 4:
            return ProjectRoot / "game" / "0" / "hlmp.mdt";

        case 5:
            return ProjectRoot / "game" / "0" / "tmmp.mdt";

        case 6:
            return ProjectRoot / "game" / "0" / "drmp.mdt";

        case 7:
            return ProjectRoot / "game" / "0" / "llmp.mdt";

        case 8:
            return ProjectRoot / "game" / "0" / "prmp.mdt";

        case 9:
            return ProjectRoot / "game" / "0" / "esmp.mdt";
        }

        return {};
    }

    bool LoadTownMap(std::uint8_t TownId, Mdt::TownMapInfo& TownMap, std::filesystem::path& TownNpcSpriteGrpPath)
    {
        const std::filesystem::path MdtPath = GetTownMdtPath(TownId);
        if (MdtPath.empty())
        {
            std::cerr << "invalid town id: " << static_cast<unsigned int>(TownId) << '\n';
            return false;
        }

        std::vector<std::uint8_t> FileBytes;
        std::string ErrorMessage;
        if (!ReadWholeFile(MdtPath, FileBytes))
        {
            std::cerr << MdtPath.filename().string() << " load failed: failed to open " << MdtPath.string() << std::endl;
            return false;
        }

        Mdt::TownMapInfo MapInfo;
        if (!Mdt::ParseTownMap(FileBytes, MapInfo, ErrorMessage))
        {
            std::cerr << MdtPath.filename().string() << " parse failed: " << ErrorMessage << std::endl;
            return false;
        }

        std::cout << MdtPath.filename().string() << " parsed: " << MdtPath.string() << ", width " << MapInfo.Width
            << ", height " << MapInfo.Height << ", cells " << MapInfo.CellCount
            << ", tile indices " << static_cast<int>(MapInfo.MinimumTileIndex) << ".."
            << static_cast<int>(MapInfo.MaximumTileIndex) << "." << std::endl;
        TownNpcSpriteGrpPath = GetTownNpcSpriteGrpPath(FileBytes);
        TownMap = std::move(MapInfo);
        return true;
    }

    struct ZeliardApp
    {
        Mdt::TownMapInfo TownMap;
        std::filesystem::path TownNpcSpriteGrpPath;
        std::filesystem::path TownActorSpriteGrpPath;
        Grp::PatternBank TownPatternBank;
        Main64Palette Palette{};
        std::optional<TownScene> TownMapScene;
        SDL_Window* Window = nullptr;
        SDL_Renderer* Renderer = nullptr;
        bool TownMapLoaded = false;
        bool TownPatternBankLoaded = false;
        bool PaletteLoaded = false;
        bool TownReady = false;
        bool TownFramePresented = false;
        bool Running = false;
        std::uint64_t LastTownTickNs = 0;
        std::uint64_t TownTickAccumNs = 0;
    };

    void LoadZeliardContent(ZeliardApp& App)
    {
        App.TownNpcSpriteGrpPath = ProjectRoot / "game" / "0" / "mman.grp";
        constexpr std::uint8_t StartingTownId = 0; // CMAP / stdply.bin place_map_id 0x80 start.
        App.TownMapLoaded = LoadTownMap(StartingTownId, App.TownMap, App.TownNpcSpriteGrpPath);
        if (!App.TownMapLoaded)
        {
            std::cerr << "town MDT parse validation failed; continuing anyway." << '\n';
        }
        else
        {
            std::cout << "town NPC sprite group selected: " << App.TownNpcSpriteGrpPath.filename().string() << '\n';
        }

        App.TownPatternBankLoaded = App.TownMapLoaded
            && LoadTownPatternBank(App.TownMap.TownPatternGroupId, App.TownPatternBank);
        if (!App.TownPatternBankLoaded)
        {
            std::cerr << "town pattern bank decode failed; continuing anyway." << '\n';
        }

        std::string PaletteErrorMessage;
        App.PaletteLoaded = Mcga::LoadMain64Palette(ProjectRoot, App.Palette, PaletteErrorMessage);
        if (!App.PaletteLoaded)
        {
            std::cerr << "cpat.grp palette load failed: " << PaletteErrorMessage << '\n';
        }

        App.TownActorSpriteGrpPath = ProjectRoot / "game" / "0" / "tman.grp";
        App.TownMapScene.emplace(App.TownActorSpriteGrpPath, App.TownNpcSpriteGrpPath, App.TownMap, App.TownPatternBank, App.Palette);
        App.TownReady = App.TownMapLoaded && App.TownPatternBankLoaded && App.PaletteLoaded;
    }

    bool InitializeZeliardApp(ZeliardApp& App)
    {
        LoadZeliardContent(App);

        if (!SDL_Init(SDL_INIT_VIDEO))
        {
            std::cerr << "SDL_Init failed: " << SDL_GetError() << '\n';
            return false;
        }

        App.Window = SDL_CreateWindow("Zeliard", WindowWidth, WindowHeight, 0);
        if (!App.Window)
        {
            std::cerr << "SDL_CreateWindow failed: " << SDL_GetError() << '\n';
            return false;
        }

        App.Renderer = SDL_CreateRenderer(App.Window, nullptr);
        if (!App.Renderer)
        {
            std::cerr << "SDL_CreateRenderer failed: " << SDL_GetError() << '\n';
            return false;
        }

        if (!SDL_SetRenderVSync(App.Renderer, 1))
        {
            std::cerr << "SDL_SetRenderVSync failed: " << SDL_GetError() << '\n';
        }

        const char* RendererName = SDL_GetRendererName(App.Renderer);
        std::cout << "SDL renderer selected: " << (RendererName != nullptr ? RendererName : "unknown") << '\n';

        if (!SDL_SetRenderLogicalPresentation(App.Renderer, InternalWidth, InternalHeight, LogicalPresentation))
        {
            std::cerr << "SDL_SetRenderLogicalPresentation failed: " << SDL_GetError() << '\n';
            return false;
        }

        int ActualWindowWidth = 0;
        int ActualWindowHeight = 0;
        SDL_GetWindowSize(App.Window, &ActualWindowWidth, &ActualWindowHeight);
        std::cout << "display: 4:3"
            << ", window " << ActualWindowWidth << "x" << ActualWindowHeight
            << ", logical " << InternalWidth << "x" << InternalHeight << '\n';

        App.LastTownTickNs = SDL_GetTicksNS();
        App.TownTickAccumNs = 0;

        App.Running = true;
        return true;
    }

    bool RunZeliardFrame(ZeliardApp& App)
    {
        SDL_Event Event;
        while (SDL_PollEvent(&Event))
        {
            if (Event.type == SDL_EVENT_QUIT)
            {
                App.Running = false;
            }
            else if (Event.type == SDL_EVENT_KEY_DOWN && Event.key.key == SDLK_ESCAPE)
            {
                App.Running = false;
            }
        }

        const std::uint64_t CurrentTicksNs = SDL_GetTicksNS();
        if (App.TownReady && App.TownMapScene.has_value())
        {
            const bool* KeyboardState = SDL_GetKeyboardState(nullptr);
            if (App.LastTownTickNs == 0)
            {
                App.LastTownTickNs = CurrentTicksNs;
                App.TownTickAccumNs = 0;
            }
            else
            {
                App.TownTickAccumNs += CurrentTicksNs - App.LastTownTickNs;
                App.LastTownTickNs = CurrentTicksNs;
            }

            int TownUpdatesThisFrame = 0;
            bool TownUpdatedThisFrame = false;
            while (App.TownTickAccumNs >= TownScene::TownTickNs
                && TownUpdatesThisFrame < MaxTownTicksPerFrame)
            {
                App.TownTickAccumNs -= TownScene::TownTickNs;
                ++TownUpdatesThisFrame;
                TownUpdatedThisFrame = true;

                const std::optional<Mdt::TownTransitionData> TownTransition = App.TownMapScene->Update(KeyboardState);
                if (!TownTransition.has_value())
                {
                    continue;
                }

                const bool IsLeftEdgeTransition = (TownTransition->Flags & 1) != 0;
                Mdt::TownMapInfo DestinationTownMap;
                std::filesystem::path DestinationTownNpcSpriteGrpPath = App.TownNpcSpriteGrpPath;
                Grp::PatternBank DestinationTownPatternBank;

                if (LoadTownMap(TownTransition->DestinationMapId, DestinationTownMap, DestinationTownNpcSpriteGrpPath)
                    && LoadTownPatternBank(TownTransition->PatternGroupId, DestinationTownPatternBank))
                {
                    App.TownMap = std::move(DestinationTownMap);
                    App.TownNpcSpriteGrpPath = std::move(DestinationTownNpcSpriteGrpPath);
                    App.TownPatternBank = std::move(DestinationTownPatternBank);

                    if (IsLeftEdgeTransition)
                    {
                        App.TownMapScene->ReloadTownStateAfterLeftEdgeTransition();
                    }
                    else
                    {
                        App.TownMapScene->ReloadTownStateAfterRightEdgeTransition();
                    }
                }
                else
                {
                    std::cerr << "town transition reload failed; staying on the current town." << '\n';
                }

                // Drop pending catch-up ticks after a transition attempt.
                App.TownTickAccumNs = 0;
                App.LastTownTickNs = CurrentTicksNs;
                break;
            }

            if (TownUpdatesThisFrame == MaxTownTicksPerFrame)
            {
                App.TownTickAccumNs = 0;
            }

            if (TownUpdatedThisFrame || !App.TownFramePresented)
            {
                SDL_SetRenderDrawColor(App.Renderer, 12, 18, 12, 255);
                SDL_RenderClear(App.Renderer);

                App.TownMapScene->Draw(App.Renderer);
                SDL_RenderPresent(App.Renderer);
                App.TownFramePresented = true;
            }
            else
            {
#ifndef __EMSCRIPTEN__
                SDL_Delay(1);
#endif
            }
        }
        else
        {
#ifndef __EMSCRIPTEN__
            SDL_Delay(1);
#endif
        }
        return App.Running;
    }

    void ShutdownZeliardApp(ZeliardApp& App)
    {
        if (App.Renderer != nullptr)
        {
            SDL_DestroyRenderer(App.Renderer);
            App.Renderer = nullptr;
        }

        if (App.Window != nullptr)
        {
            SDL_DestroyWindow(App.Window);
            App.Window = nullptr;
        }

        SDL_Quit();
    }

#ifdef __EMSCRIPTEN__
    void RunZeliardMainLoop(void* UserData)
    {
        auto* App = static_cast<ZeliardApp*>(UserData);
        if (App == nullptr || !RunZeliardFrame(*App))
        {
            emscripten_cancel_main_loop();
        }
    }
#endif
}

int main()
{
    auto App = std::make_unique<ZeliardApp>();

    if (!InitializeZeliardApp(*App))
    {
        ShutdownZeliardApp(*App);
        return 1;
    }

#ifdef __EMSCRIPTEN__
    emscripten_set_main_loop_arg(RunZeliardMainLoop, App.get(), 0, true);
    App.release();
    return 0;
#else
    while (App->Running)
    {
        if (!RunZeliardFrame(*App))
        {
            break;
        }
    }

    ShutdownZeliardApp(*App);
    return 0;
#endif
}
