#pragma once

#include <array>
#include <cstddef>
#include <filesystem>

#include <SDL3/SDL.h>

#include "../grp/grp_font.h"
#include "../grp/grp_pattern_bank.h"
#include "../grp/grp_sprite_sheet.h"
#include "../mdt/mdt_map.h"

using Main64Palette = std::array<SDL_Color, 64>;

enum class TownMapActorFacingDirection
{
    Right,
    Left,
    Up,
    Down
};

class TownScene
{
public:
    TownScene(const std::filesystem::path& SpriteGrpPath, const Mdt::TownMapInfo& TownMap,
        const Grp::PatternBank& PatternBank, const Main64Palette& Palette);

    void Update(const bool* KeyboardState);
    void Draw(SDL_Renderer* Renderer, const Grp::FontGroup* DebugFontGroup, bool DebugOverlayEnabled) const;

    void ToggleCameraFollow() noexcept;
    void ToggleBlockedTileOverlay() noexcept;
    void ToggleTownEntityMarkers() noexcept;

    bool IsCameraFollowEnabled() const noexcept;
    bool IsBlockedTileOverlayEnabled() const noexcept;
    bool IsTownEntityMarkersEnabled() const noexcept;

private:
    bool UpdateTownMapActorFrame(std::size_t DesiredActorFrameIndex);
    bool TryGetTownNpcSpriteFrame(std::size_t FrameIndex, const Grp::NpcSpriteFrame*& SpriteFrame) const;
    std::size_t DrawTownNpcSprites(SDL_Renderer* Renderer, std::size_t ScrollOffsetPixels) const;

    static constexpr std::size_t TownMapActorInitialMapPixelX = 160;
    static constexpr std::size_t TownMapActorInitialMapPixelY = 40;
    static constexpr std::size_t TownNpcSpriteFrameCount = 40;

    const std::filesystem::path SpriteGrpPath;
    const Mdt::TownMapInfo& TownMap;
    const Grp::PatternBank& PatternBank;
    const Main64Palette& Palette;

    TownMapActorFacingDirection ActorFacingDirection = TownMapActorFacingDirection::Right;
    std::size_t ActorAnimationPhase = 0;
    std::size_t ActorAnimationTickCount = 0;
    std::size_t ActorFrameIndex = 0;
    std::size_t ActorMapPixelX = TownMapActorInitialMapPixelX;
    std::size_t ActorMapPixelY = TownMapActorInitialMapPixelY;
    std::size_t ScrollOffsetPixels = 0;

    bool ActorFrameLoaded = false;
    bool ActorCollisionBlocked = false;
    bool CameraFollowEnabled = true;
    bool BlockedTileOverlayEnabled = false;
    bool TownEntityMarkersEnabled = false;
    mutable bool FallbackWarningPrinted = false;
    mutable std::array<Grp::NpcSpriteFrame, TownNpcSpriteFrameCount> TownNpcSpriteFrames{};
    mutable std::array<bool, TownNpcSpriteFrameCount> TownNpcSpriteFrameLoaded{};
    mutable bool TownNpcSpriteFrameWarningPrinted = false;
    Grp::NpcSpriteFrame ActorFrame;
};
