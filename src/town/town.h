#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>
#include <vector>

#include <SDL3/SDL.h>

#include "../grp/font_grp.h"
#include "../grp/pat_grp.h"
#include "../grp/man_grp.h"
#include "../mdt/town_mdt.h"
#include "../hud/mole_panels.h"
#include "../hud/tears.h"
#include "../mcga/mcga_palette.h"
#include "town_actors.h"

class TownScene
{
public:
    static constexpr std::size_t TownBackgroundMountainWidth = 224;
    static constexpr std::size_t TownBackgroundMountainHeight = 88;
    static constexpr std::size_t TownMoleDecorationPanelWidth = Hud::MoleDecorationPanelWidth;
    static constexpr std::size_t TownMoleDecorationPanelHeight = Hud::MoleDecorationPanelHeight;
    static constexpr std::size_t TownMoleTopTearsBaseWidth = Hud::MoleTopTearsBaseWidth;
    static constexpr std::size_t TownMoleTopTearsBaseHeight = Hud::MoleTopTearsBaseHeight;
    static constexpr std::size_t TownMoleBottomStatusBaseWidth = Hud::MoleBottomStatusBaseWidth;
    static constexpr std::size_t TownMoleBottomStatusBaseHeight = Hud::MoleBottomStatusBaseHeight;
    static constexpr std::uint64_t PitInputFrequencyHz = 1'193'182;
    static constexpr std::uint64_t PitReloadValue = 0x13B1;
    static constexpr std::uint64_t DosStandardSpeedConst = 5;
    static constexpr std::uint64_t DosTownWaitTickMultiplier = 4;
    static constexpr std::uint64_t DosTownWaitTicks = DosStandardSpeedConst * DosTownWaitTickMultiplier;
    // Keep native pacing aligned with the assembly-backed DOS wait tick count.
    static constexpr std::uint64_t NativeTownCalibrationTicks = DosTownWaitTicks;
    static constexpr std::uint64_t TownTickNs =
        (1'000'000'000ULL * NativeTownCalibrationTicks * PitReloadValue) / PitInputFrequencyHz;

    TownScene(const std::filesystem::path& ActorSpriteGrpPath, const std::filesystem::path& TownNpcSpriteGrpPath,
        const Mdt::TownMapInfo& TownMap,
        const Grp::PatternBank& PatternBank, const Main64Palette& Palette);

    std::optional<Mdt::TownTransitionData> Update(const bool* KeyboardState);
    void Draw(SDL_Renderer* Renderer) const;
    void ReloadTownState();
    void ReloadTownStateAfterRightEdgeTransition();
    void ReloadTownStateAfterLeftEdgeTransition();
    std::uint8_t GetHeroXInViewport() const noexcept;
    std::uint16_t GetProximityMapLeftColumnX() const noexcept;

private:
    // stdply.bin seeds the normal CMAP startup here; do not reuse the Falter warp back to Dorado values.
    static constexpr std::uint8_t TownHeroStartupXInViewport = 0x0A;
    static constexpr std::uint16_t TownHeroStartupProximityMapLeftColumnX = 0x001E;
    static constexpr std::uint8_t TownHeroStartupFacingDirection = 0;
    static constexpr std::uint8_t TownHeroStartupAnimationPhase = 0;

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
        std::uint8_t HeroXInViewport = TownHeroStartupXInViewport;
        std::uint16_t ProximityMapLeftColumnX = TownHeroStartupProximityMapLeftColumnX;
        std::uint8_t FacingDirection = TownHeroStartupFacingDirection; // bit 0: 0=right, 1=left
        std::uint8_t HeroAnimationPhase = TownHeroStartupAnimationPhase;
    };

    struct TownHudHealthState
    {
        std::uint16_t HeroHp = 80;
        std::uint16_t HeroMaxHp = 80;
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
    void ResetTownSceneState(std::optional<TownHeroRuntimeState> TransitionHeroState) noexcept;
    void ReloadTownState(std::optional<TownHeroRuntimeState> TransitionHeroState, bool LoadTownNpcRecords);
    std::optional<Mdt::TownTransitionData> GetEdgeTownTransition(bool IsLeftEdgeTransition) const;
    bool TryGetTownNpcSpriteFrame(std::size_t FrameIndex, const Grp::NpcSpriteFrame*& SpriteFrame) const;
    std::size_t GetTownHeroAbsoluteX() const noexcept;
    std::size_t GetTownHeroMapPixelX() const noexcept;
    std::size_t GetTownHeroMapPixelY() const noexcept;
    std::size_t GetTownHeroScrollOffsetPixels() const noexcept;
    void AdvanceTownBackgroundStripScrollOffset(std::ptrdiff_t PixelDelta) noexcept;
    void SyncTownHeroRuntimeProjection() noexcept;
    void SyncTownHeroStartupActorFrame() noexcept;
    void UpdateTownHeroRuntimeState(const bool* KeyboardState) noexcept;
    bool StartTownDialogForNpc(std::size_t NpcRuntimeIndex, bool RestoreNpcState);
    bool TryOpenTownDialog();
    bool TryOpenTownSpecialDialog();
    bool BuildTownDialogPage();
    void InitializeTownDialogOverlay();
    void ClearTownDialogOverlayRect(std::size_t Left, std::size_t Top, std::size_t Width, std::size_t Height);
    void ScrollTownDialogTextAreaOnePixel();
    void RenderTownDialogTextToOverlay();
    void DrawTownDialogGlyphToOverlay(std::size_t StartX, std::size_t StartY, std::uint8_t ColorSelector,
        char Character);
    void AdvanceTownDialog();
    void UpdateTownDialogTownFrame();
    void DrawTownDialog(SDL_Renderer* Renderer) const;
    void LogTearsCollectedOverlayState(std::uint8_t RawTearsCount, std::size_t DrawCount) const;
    void RenderTownColumn(SDL_Renderer* Renderer, std::size_t MapColumn, float ScreenTileX,
        const TownHeadLevelTiles& HeadLevelTiles, const std::vector<TownNpcRuntimeRecord>& TownNpcArray,
        std::size_t ScrollOffsetPixels, TownNpcSpriteShadowBuffer& ShadowBuffer,
        TownColumnRenderStats& RenderStats) const;
    void DispatchTownSpecialTile(SDL_Renderer* Renderer, std::size_t MapColumn,
        const std::vector<TownNpcRuntimeRecord>& TownNpcArray, std::size_t ScrollOffsetPixels,
        TownNpcSpriteShadowBuffer& ShadowBuffer, TownColumnRenderStats& RenderStats) const;

    TownHeadLevelTiles SaveHeadLevelTilesInNpcs() const;
    void RestoreHeadLevelTilesFromNpcs(TownHeadLevelTiles& HeadLevelTiles) const;
    static std::vector<TownNpcRuntimeRecord> BuildTownNpcRuntimeRecords(const Mdt::TownMapInfo& TownMap);
    void SyncTownNpcFacingTowardHero() const;
    void UpdateTownNpcRuntimeRecords() const;
    static std::size_t GetTownNpcSpriteFrameIndex(std::uint8_t SpriteSelector, std::uint8_t AnimationPhase);
    static std::uint8_t GetTownNpcRuntimeRecordSpriteColumnMatch(const TownNpcRuntimeRecord& RuntimeRecord,
        std::size_t MapColumn);
    static const TownNpcRuntimeRecord* FindBlockingTownNpcAtX(
        const std::vector<TownNpcRuntimeRecord>& TownNpcArray, std::size_t TargetX) noexcept;
    static const TownNpcRuntimeRecord* FindFirstTownNpcRuntimeRecordForColumn(
        const std::vector<TownNpcRuntimeRecord>& TownNpcArray, std::size_t MapColumn);
    static const TownNpcRuntimeRecord* FindNextTownNpcRuntimeRecordForColumn(
        const std::vector<TownNpcRuntimeRecord>& TownNpcArray, const TownNpcRuntimeRecord* CurrentRuntimeRecord,
        std::size_t MapColumn);

    static constexpr std::size_t TownMapActorInitialMapPixelX = 160;
    static constexpr std::size_t TownMapActorInitialMapPixelY = 40;
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

    bool ActorFrameLoaded = false;
    bool ActorFrameVisible = false;
    bool ActorFrameWarningPrinted = false;
    bool ActorCollisionBlocked = false;
    bool TownBackgroundMountainLayerLoaded = false;
    bool TownBackgroundStripLoaded = false;
    bool TownBackgroundStripUsesCkpd = false;
    bool TownMoleDecorationPanelsLoaded = false;
    bool TownMoleTopTearsBaseLoaded = false;
    bool TownMoleBottomStatusBaseLoaded = false;
    bool TownTearsOverlayIconsLoaded = false;
    bool TownTrainingSwordItemSpriteLoaded = false;
    bool TownHudFontsLoaded = false;
    std::size_t TownBackgroundStripScrollPx = 0;
    mutable std::vector<std::uint8_t> TownRuntimeCells;
    bool TownEdgeTransitionQueued = false;
    mutable bool FallbackWarningPrinted = false;
    mutable std::array<Grp::NpcSpriteFrame, TownNpcSpriteFrameCount> TownNpcSpriteFrames{};
    mutable std::array<bool, TownNpcSpriteFrameCount> TownNpcSpriteFrameLoaded{};
    mutable std::array<bool, TownNpcSpriteFrameCount> TownNpcSpriteFrameVisible{};
    mutable bool TownNpcSpriteFrameWarningPrinted = false;
    mutable std::vector<TownNpcRuntimeRecord> TownNpcArray;
    bool TownDialogOpen = false;
    bool TownDialogHasMorePages = false;
    bool TownSpaceWasDown = false;
    bool TownAltWasDown = false;
    bool TownDialogControlWarningPrinted = false;
    bool TownDialogRestoreNpcState = false;
    std::size_t TownDialogNpcRuntimeIndex = 0;
    std::uint8_t TownDialogNpcOriginalFacing = 0;
    std::uint8_t TownDialogNpcOriginalSpriteSelector = 0;
    std::uint8_t TownDialogNpcOriginalAiType = 0;
    std::size_t TownDialogConversationIndex = 0;
    std::size_t TownDialogByteOffset = 0;
    std::size_t TownDialogLineCount = 0;
    bool TownDialogContinuationCursorVisible = false;
    std::size_t TownDialogBoxLeftX = 0;
    std::size_t TownDialogBoxTopY = 0;
    std::size_t TownDialogBoxHeight = 0;
    std::size_t TownDialogCharX = 0;
    std::size_t TownDialogCharY = 0;
    std::size_t TownDialogLinesRendered = 0;
    std::size_t TownDialogRenderTextOffset = 0;
    std::string TownDialogPageText;
    std::vector<std::uint8_t> TownDialogOverlayPixels;
    std::array<std::uint8_t, TownBackgroundMountainWidth * TownBackgroundMountainHeight> TownBackgroundMountainLayerPixels{};
    std::array<std::uint8_t, 224 * 16> TownBackgroundStripPixels{};
    std::array<std::uint8_t, TownMoleDecorationPanelWidth * TownMoleDecorationPanelHeight> TownMoleLeftDecorationPanelPixels{};
    std::array<std::uint8_t, TownMoleDecorationPanelWidth * TownMoleDecorationPanelHeight> TownMoleRightDecorationPanelPixels{};
    std::array<std::uint8_t, TownMoleTopTearsBaseWidth * TownMoleTopTearsBaseHeight> TownMoleTopTearsBasePixels{};
    std::array<std::uint8_t, TownMoleBottomStatusBaseWidth * TownMoleBottomStatusBaseHeight> TownMoleBottomStatusBasePixels{};
    std::array<std::uint8_t, 20 * 18> TownTrainingSwordItemSpritePixels{};
    Grp::FontGroup TownBoldFontGroup;
    Grp::FontGroup TownThinFontGroup;
    Grp::FontGroup TownDigitFontGroup;
    Hud::TearsOverlayIconPixels TownTearsOverlaySmallIconPixels{};
    Hud::TearsOverlayIconPixels TownTearsOverlayLargeIconPixels{};
    mutable bool TownTearsOverlayStateLogInitialized = false;
    mutable std::uint8_t TownTearsOverlayLastLoggedRawCount = 0;
    mutable std::size_t TownTearsOverlayLastLoggedDrawCount = 0;
    TownHudHealthState TownHudHealth;
    Grp::NpcSpriteFrame ActorFrame;
};
