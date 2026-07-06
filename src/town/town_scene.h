#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <vector>

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
    TownScene(const std::filesystem::path& ActorSpriteGrpPath, const std::filesystem::path& TownNpcSpriteGrpPath,
        const Mdt::TownMapInfo& TownMap,
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
    struct TownSavedHeadLevelTile
    {
        std::size_t Column = 0;
        std::uint8_t TileIndex = 0;
    };

    struct TownHeadLevelTiles
    {
        std::vector<std::uint8_t> Tiles;
        std::vector<std::uint8_t> OriginalTiles;
        std::vector<bool> HasOriginalTile;
        std::vector<TownSavedHeadLevelTile> SavedTiles;
    };

    struct TownColumnRenderStats
    {
        std::size_t RenderedNpcSpriteCount = 0;
        std::size_t NpcSpriteMissCount = 0;
    };

    struct TownHeroRuntimeState
    {
        std::uint8_t HeroXInViewport = 12;
        std::uint16_t ProximityMapLeftColumnX = 4;
        std::uint8_t FacingDirection = 0; // bit 0: 0=right, 1=left
        std::uint8_t HeroAnimationPhase = 0;
    };

    struct TownNpcRuntimeRecord
    {
        std::uint16_t X = 0;
        std::uint8_t Facing = 0;
        std::uint8_t HeadTile = 0;
        std::uint8_t AnimPhase = 0;
        std::uint8_t AiType = 0;
        std::uint8_t Flags = 0;
        std::uint8_t Id = 0;
    };

    struct TownNpcRuntimeView
    {
        TownNpcRuntimeView() = default;
        explicit TownNpcRuntimeView(const TownNpcRuntimeRecord& RuntimeRecord)
            : X(RuntimeRecord.X), HeadTile(RuntimeRecord.HeadTile), Facing(RuntimeRecord.Facing),
              AnimPhase(RuntimeRecord.AnimPhase)
        {
        }

        std::uint16_t X = 0;
        std::uint8_t HeadTile = 0;
        std::uint8_t Facing = 0;
        std::uint8_t AnimPhase = 0;
    };

    bool UpdateTownMapActorFrame(std::size_t DesiredActorFrameIndex);
    bool TryGetTownNpcSpriteFrame(std::size_t FrameIndex, const Grp::NpcSpriteFrame*& SpriteFrame) const;
    std::size_t GetTownHeroAbsoluteX() const noexcept;
    std::size_t GetTownHeroMapPixelX() const noexcept;
    std::size_t GetTownHeroMapPixelY() const noexcept;
    std::size_t GetTownHeroScrollOffsetPixels() const noexcept;
    void SyncTownHeroRuntimeProjection() noexcept;
    void UpdateTownHeroRuntimeState(const bool* KeyboardState) noexcept;
    void RenderTownColumn(SDL_Renderer* Renderer, std::size_t MapColumn, float ScreenTileX,
        const TownHeadLevelTiles& HeadLevelTiles, const std::vector<TownNpcRuntimeView>& TownNpcRuntimeViews,
        std::size_t ScrollOffsetPixels, bool DrawDebugEntityMarkers, bool DrawDebugFallbackMarker,
        TownColumnRenderStats& RenderStats) const;
    void DispatchTownSpecialTile(SDL_Renderer* Renderer, std::size_t MapColumn,
        const std::vector<TownNpcRuntimeView>& TownNpcRuntimeViews, std::size_t ScrollOffsetPixels,
        bool DrawDebugFallbackMarker,
        TownColumnRenderStats& RenderStats) const;

    static TownHeadLevelTiles SaveHeadLevelTilesInNpcs(const Mdt::TownMapInfo& TownMap);
    static void RestoreHeadLevelTilesFromNpcs(TownHeadLevelTiles& HeadLevelTiles);
    static std::vector<TownNpcRuntimeRecord> BuildTownNpcRuntimeRecords(const Mdt::TownMapInfo& TownMap,
        const TownHeadLevelTiles& HeadLevelTiles);
    void UpdateTownNpcRuntimeRecordsShell(std::vector<TownNpcRuntimeRecord>& TownNpcRuntimeRecords) const;
    static std::vector<TownNpcRuntimeView> BuildTownNpcRuntimeViews(
        const std::vector<TownNpcRuntimeRecord>& TownNpcRuntimeRecords);
    static std::size_t GetTownNpcSpriteFrameIndex(std::uint8_t NpcFacing, std::uint8_t NpcAnimPhase);
    static std::uint8_t GetTownNpcRuntimeViewSpriteColumnMatch(const TownNpcRuntimeView& RuntimeView,
        std::size_t MapColumn);
    static const TownNpcRuntimeView* FindFirstTownNpcRuntimeViewForColumn(
        const std::vector<TownNpcRuntimeView>& TownNpcRuntimeViews, std::size_t MapColumn);
    static const TownNpcRuntimeView* FindFirstTownNpcRuntimeViewForColumnAfterCurrent(
        const std::vector<TownNpcRuntimeView>& TownNpcRuntimeViews, const TownNpcRuntimeView* CurrentRuntimeView,
        std::size_t MapColumn);
    void DrawTownNpcRuntimeViewCurrentColumnSliceOnTownMap(SDL_Renderer* Renderer, const TownNpcRuntimeView& RuntimeView,
        const Grp::NpcSpriteFrame& SpriteFrame, std::size_t ScrollOffsetPixels,
        TownColumnRenderStats& RenderStats) const;
    void DrawTownNpcRuntimeViewNextColumnSliceOnTownMap(SDL_Renderer* Renderer, const TownNpcRuntimeView& RuntimeView,
        const Grp::NpcSpriteFrame& SpriteFrame, std::size_t ScrollOffsetPixels) const;
    void DrawTownNpcRuntimeViewColumnSliceOnTownMap(SDL_Renderer* Renderer, const TownNpcRuntimeView& RuntimeView,
        const Grp::NpcSpriteFrame& SpriteFrame, std::size_t MapColumn, std::size_t ScrollOffsetPixels) const;

    static constexpr std::size_t TownMapActorInitialMapPixelX = 160;
    static constexpr std::size_t TownMapActorInitialMapPixelY = 40;
    // Provisional until DOSBox confirms the exact held-input cadence.
    static constexpr std::size_t TownMovementFrameDelay = 4;
    static constexpr std::size_t TownNpcSpriteFrameCount = 40;

    const std::filesystem::path ActorSpriteGrpPath;
    const std::filesystem::path TownNpcSpriteGrpPath;
    const Mdt::TownMapInfo& TownMap;
    const Grp::PatternBank& PatternBank;
    const Main64Palette& Palette;

    TownHeroRuntimeState TownHeroState;
    TownMapActorFacingDirection ActorFacingDirection = TownMapActorFacingDirection::Right;
    std::size_t ActorAnimationPhase = 0;
    std::size_t ActorAnimationTickCount = 0;
    std::size_t ActorFrameIndex = 0;
    std::size_t ActorMapPixelX = TownMapActorInitialMapPixelX;
    std::size_t ActorMapPixelY = TownMapActorInitialMapPixelY;
    std::size_t ScrollOffsetPixels = 0;
    std::size_t TownMovementFrameCountdown = 0;

    bool ActorFrameLoaded = false;
    bool ActorFrameVisible = false;
    bool ActorFrameWarningPrinted = false;
    bool ActorCollisionBlocked = false;
    bool CameraFollowEnabled = true;
    bool BlockedTileOverlayEnabled = false;
    bool TownEntityMarkersEnabled = false;
    mutable bool FallbackWarningPrinted = false;
    mutable std::array<Grp::NpcSpriteFrame, TownNpcSpriteFrameCount> TownNpcSpriteFrames{};
    mutable std::array<bool, TownNpcSpriteFrameCount> TownNpcSpriteFrameLoaded{};
    mutable std::array<bool, TownNpcSpriteFrameCount> TownNpcSpriteFrameVisible{};
    mutable bool TownNpcSpriteFrameWarningPrinted = false;
    Grp::NpcSpriteFrame ActorFrame;
};
