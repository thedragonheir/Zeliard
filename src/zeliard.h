#pragma once

#include <cstdint>
#include <filesystem>
#include <optional>

#include "grp/pat_grp.h"
#include "mcga/mcga_palette.h"
#include "mdt/town_mdt.h"
#include "town/town.h"

namespace Zeliard
{
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

    bool InitializeZeliardApp(ZeliardApp& App);
    bool RunZeliardFrame(ZeliardApp& App);
    void ShutdownZeliardApp(ZeliardApp& App);
}
