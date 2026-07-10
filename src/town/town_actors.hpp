#pragma once

#include <cstddef>

namespace Mdt
{
struct TownMapInfo;
}

enum class TownMapActorFacingDirection
{
    Right,
    Left,
    Up,
    Down
};

namespace TownActors
{
std::size_t GetMaximumProximityMapLeftColumn(const Mdt::TownMapInfo& TownMap);
std::size_t GetActorFrameIndex(TownMapActorFacingDirection FacingDirection, bool ActorIsMoving,
    std::size_t AnimationPhase);
}
