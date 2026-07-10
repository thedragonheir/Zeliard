#include "town_actors.hpp"

#include "town.hpp"

#include <algorithm>
#include <iostream>
#include <string>
#include <utility>

namespace Grp
{
bool LoadTownHeroSpriteFrame(const std::filesystem::path& Path, std::size_t FrameIndex,
    NpcSpriteFrame& Output, std::string& ErrorMessage);
}

namespace
{
constexpr std::size_t TownHeroProximityMapWidthColumns = 36;
constexpr std::size_t TownMapActorAnimationPhaseCount = 4;
constexpr std::size_t TownHeroLeftFacingFrameStart = 0;
constexpr std::size_t TownHeroRightFacingFrameStart = 5;

std::size_t GetActorFrameStartIndex(TownMapActorFacingDirection FacingDirection)
{
    switch (FacingDirection)
    {
    case TownMapActorFacingDirection::Right:
        return TownHeroRightFacingFrameStart;

    case TownMapActorFacingDirection::Left:
        return TownHeroLeftFacingFrameStart;

    case TownMapActorFacingDirection::Up:
    case TownMapActorFacingDirection::Down:
        // tman.grp has confirmed left/right town hero poses. Keep vertical
        // movement visible with the right-facing set until that mapping is known.
        return TownHeroRightFacingFrameStart;
    }

    return TownHeroRightFacingFrameStart;
}

bool IsSpriteFrameVisible(const Grp::NpcSpriteFrame& SpriteFrame)
{
    return std::any_of(SpriteFrame.DrawModes.begin(), SpriteFrame.DrawModes.end(),
        [](std::uint8_t DrawMode)
        {
            return DrawMode != Grp::TransparentDrawMode;
        });
}
}

namespace TownActors
{
std::size_t GetMaximumProximityMapLeftColumn(const Mdt::TownMapInfo& TownMap)
{
    return TownMap.Width > TownHeroProximityMapWidthColumns
        ? TownMap.Width - TownHeroProximityMapWidthColumns
        : 0;
}

std::size_t GetActorFrameIndex(TownMapActorFacingDirection FacingDirection,
    [[maybe_unused]] bool ActorIsMoving, std::size_t AnimationPhase)
{
    const std::size_t FrameStartIndex = GetActorFrameStartIndex(FacingDirection);
    const std::size_t FramePhase = AnimationPhase % TownMapActorAnimationPhaseCount;
    return FrameStartIndex + FramePhase;
}
}

bool TownScene::UpdateTownMapActorFrame(std::size_t DesiredActorFrameIndex)
{
    if (DesiredActorFrameIndex == ActorFrameIndex && ActorFrameLoaded)
    {
        return ActorFrameVisible;
    }

    Grp::NpcSpriteFrame RequestedActorFrame;
    std::string RequestedActorFrameErrorMessage;
    if (!Grp::LoadTownHeroSpriteFrame(ActorSpriteGrpPath, DesiredActorFrameIndex,
            RequestedActorFrame, RequestedActorFrameErrorMessage))
    {
        if (!ActorFrameWarningPrinted)
        {
            std::cerr << ActorSpriteGrpPath.filename().string() << " actor sprite frame "
                << DesiredActorFrameIndex << " load failed: " << RequestedActorFrameErrorMessage << '\n';
            ActorFrameWarningPrinted = true;
        }

        ActorFrameIndex = DesiredActorFrameIndex;
        ActorFrameLoaded = false;
        ActorFrameVisible = false;
        return false;
    }

    ActorFrameIndex = DesiredActorFrameIndex;
    ActorFrame = std::move(RequestedActorFrame);
    ActorFrameLoaded = true;
    ActorFrameVisible = IsSpriteFrameVisible(ActorFrame);
    ActorAnimationTickCount = 0;
    return ActorFrameVisible;
}
