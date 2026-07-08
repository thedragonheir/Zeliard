#include "town_transitions.h"

#include "town.h"

#include <algorithm>

namespace
{
constexpr std::size_t TownHeroRightEdgeTransitionSentinel = 27;
constexpr std::uint8_t TownHeroLeftEdgeTransitionSentinel = 0xFF;
constexpr std::size_t TownHeroProximityMapWidthColumns = 36;
}

namespace TownTransitions
{
bool IsEdgeTransition(const Mdt::TownTransitionData& Transition, bool IsLeftEdgeTransition)
{
    const bool TransitionIsLeftEdge = (Transition.Flags & 1) != 0;
    return TransitionIsLeftEdge == IsLeftEdgeTransition && (Transition.Flags & 0xFE) == 0;
}

bool HasEdgeTransition(const Mdt::TownMapInfo& TownMap, bool IsLeftEdgeTransition)
{
    return std::any_of(TownMap.TransitionData.begin(), TownMap.TransitionData.end(),
        [IsLeftEdgeTransition](const Mdt::TownTransitionData& Transition)
        {
            return IsEdgeTransition(Transition, IsLeftEdgeTransition);
        });
}
}

void TownScene::ReloadTownState()
{
    ReloadTownState(std::nullopt, true);
}

void TownScene::ReloadTownStateAfterRightEdgeTransition()
{
    TownHeroRuntimeState TransitionHeroState{};
    TransitionHeroState.HeroXInViewport = 0;
    TransitionHeroState.ProximityMapLeftColumnX = 0;
    TransitionHeroState.FacingDirection = 0;
    TransitionHeroState.HeroAnimationPhase = 0;
    ReloadTownState(TransitionHeroState, true);
}

void TownScene::ReloadTownStateAfterLeftEdgeTransition()
{
    TownHeroRuntimeState TransitionHeroState{};
    TransitionHeroState.HeroXInViewport = 26;
    TransitionHeroState.ProximityMapLeftColumnX = TownMap.Width > TownHeroProximityMapWidthColumns
        ? static_cast<std::uint16_t>(TownMap.Width - TownHeroProximityMapWidthColumns)
        : 0;
    TransitionHeroState.FacingDirection = 0;
    TransitionHeroState.HeroAnimationPhase = 0;
    ReloadTownState(TransitionHeroState, true);
}

std::optional<Mdt::TownTransitionData> TownScene::GetEdgeTownTransition(bool IsLeftEdgeTransition) const
{
    if (TownEdgeTransitionQueued)
    {
        return std::nullopt;
    }

    if (IsLeftEdgeTransition)
    {
        if (TownHeroState.HeroXInViewport != TownHeroLeftEdgeTransitionSentinel)
        {
            return std::nullopt;
        }
    }
    else if (TownHeroState.HeroXInViewport != TownHeroRightEdgeTransitionSentinel)
    {
        return std::nullopt;
    }

    for (const Mdt::TownTransitionData& Transition : TownMap.TransitionData)
    {
        if (!TownTransitions::IsEdgeTransition(Transition, IsLeftEdgeTransition))
        {
            continue;
        }

        return Transition;
    }

    return std::nullopt;
}
