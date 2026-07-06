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

    void ToggleBlockedTileOverlay() noexcept;
    void ToggleTownEntityMarkers() noexcept;

    bool IsBlockedTileOverlayEnabled() const noexcept;
    bool IsTownEntityMarkersEnabled() const noexcept;

private:
    struct TownHeadLevelTiles
    {
        std::vector<std::uint8_t> Tiles;
        std::vector<std::uint8_t> OriginalTiles;
        std::vector<bool> HasOriginalTile;
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
        std::uint8_t HeadTile = 0;
        // Keep this separate from SpriteSelector so future AI can flip facing
        // without disturbing the sprite-family byte.
        std::uint8_t Facing = 0;
        std::uint8_t SpriteSelector = 0;
        std::uint8_t AnimationPhase = 0;
        std::uint8_t NpcAiType = 0;
        std::uint8_t NpcFlags = 0;
        std::uint8_t NpcId = 0;
    };

    struct TownNpcSpriteShadowSlice
    {
        const Grp::NpcSpriteFrame* SpriteFrame = nullptr;
        std::size_t MapPixelX = 0;
        std::size_t MapPixelY = 0;
        std::size_t ScrollOffsetPixels = 0;
        std::size_t MapColumn = 0;
        bool IsCurrentColumn = false;
    };

    struct TownNpcSpriteShadowBuffer
    {
        void Reserve(std::size_t SliceCount)
        {
            Slices.reserve(SliceCount);
        }

        void AddCurrentColumnSlice(const Grp::NpcSpriteFrame& SpriteFrame, std::size_t MapPixelX,
            std::size_t MapPixelY, std::size_t ScrollOffsetPixels, std::size_t MapColumn)
        {
            Slices.push_back(TownNpcSpriteShadowSlice{
                &SpriteFrame,
                MapPixelX,
                MapPixelY,
                ScrollOffsetPixels,
                MapColumn,
                true
            });
        }

        void AddNextColumnSlice(const Grp::NpcSpriteFrame& SpriteFrame, std::size_t MapPixelX,
            std::size_t MapPixelY, std::size_t ScrollOffsetPixels, std::size_t MapColumn)
        {
            Slices.push_back(TownNpcSpriteShadowSlice{
                &SpriteFrame,
                MapPixelX,
                MapPixelY,
                ScrollOffsetPixels,
                MapColumn,
                false
            });
        }

        void FlushForMapColumn(SDL_Renderer* Renderer, const Main64Palette& Palette, std::size_t MapColumn,
            std::size_t& RenderedNpcSpriteCount);

        std::vector<TownNpcSpriteShadowSlice> Slices;
    };

    bool UpdateTownMapActorFrame(std::size_t DesiredActorFrameIndex);
    bool TryGetTownNpcSpriteFrame(std::size_t FrameIndex, const Grp::NpcSpriteFrame*& SpriteFrame) const;
    std::size_t GetTownHeroAbsoluteX() const noexcept;
    std::size_t GetTownHeroMapPixelX() const noexcept;
    std::size_t GetTownHeroMapPixelY() const noexcept;
    std::size_t GetTownHeroScrollOffsetPixels() const noexcept;
    void AdvanceTownBackgroundStripScrollOffset(std::ptrdiff_t PixelDelta) noexcept;
    void SyncTownHeroRuntimeProjection() noexcept;
    void UpdateTownHeroRuntimeState(const bool* KeyboardState) noexcept;
    void RenderTownColumn(SDL_Renderer* Renderer, std::size_t MapColumn, float ScreenTileX,
        const TownHeadLevelTiles& HeadLevelTiles, const std::vector<TownNpcRuntimeRecord>& TownNpcArray,
        std::size_t ScrollOffsetPixels, TownNpcSpriteShadowBuffer& ShadowBuffer, bool DrawDebugEntityMarkers,
        bool DrawDebugFallbackMarker, TownColumnRenderStats& RenderStats) const;
    void DispatchTownSpecialTile(SDL_Renderer* Renderer, std::size_t MapColumn,
        const std::vector<TownNpcRuntimeRecord>& TownNpcArray, std::size_t ScrollOffsetPixels,
        TownNpcSpriteShadowBuffer& ShadowBuffer, bool DrawDebugFallbackMarker,
        TownColumnRenderStats& RenderStats) const;

    TownHeadLevelTiles SaveHeadLevelTilesInNpcs() const;
    void RestoreHeadLevelTilesFromNpcs(TownHeadLevelTiles& HeadLevelTiles) const;
    static std::vector<TownNpcRuntimeRecord> BuildTownNpcRuntimeRecords(const Mdt::TownMapInfo& TownMap);
    void UpdateTownNpcRuntimeRecordsShell() const;
    static std::size_t GetTownNpcSpriteFrameIndex(std::uint8_t SpriteSelector, std::uint8_t AnimationPhase);
    static std::uint8_t GetTownNpcRuntimeRecordSpriteColumnMatch(const TownNpcRuntimeRecord& RuntimeRecord,
        std::size_t MapColumn);
    static const TownNpcRuntimeRecord* FindNonPassableTownNpcAtXPos(
        const std::vector<TownNpcRuntimeRecord>& TownNpcArray, std::size_t TargetX) noexcept;
    static const TownNpcRuntimeRecord* FindFirstTownNpcRuntimeRecordForColumn(
        const std::vector<TownNpcRuntimeRecord>& TownNpcArray, std::size_t MapColumn);
    static const TownNpcRuntimeRecord* FindFirstTownNpcRuntimeRecordForColumnAfterCurrent(
        const std::vector<TownNpcRuntimeRecord>& TownNpcArray, const TownNpcRuntimeRecord* CurrentRuntimeRecord,
        std::size_t MapColumn);

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
    bool BlockedTileOverlayEnabled = false;
    bool TownEntityMarkersEnabled = false;
    bool TownBackgroundStripLoaded = false;
    bool TownBackgroundStripUsesCkpd = false;
    std::size_t TownBackgroundStripScrollOffsetPixels = 0;
    mutable bool FallbackWarningPrinted = false;
    mutable std::array<Grp::NpcSpriteFrame, TownNpcSpriteFrameCount> TownNpcSpriteFrames{};
    mutable std::array<bool, TownNpcSpriteFrameCount> TownNpcSpriteFrameLoaded{};
    mutable std::array<bool, TownNpcSpriteFrameCount> TownNpcSpriteFrameVisible{};
    mutable bool TownNpcSpriteFrameWarningPrinted = false;
    mutable std::vector<TownNpcRuntimeRecord> TownNpcArray;
    std::array<std::uint8_t, 224 * 16> TownBackgroundStripPixels{};
    Grp::NpcSpriteFrame ActorFrame;
};
