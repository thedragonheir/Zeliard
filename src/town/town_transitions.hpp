#pragma once

namespace Mdt
{
struct TownMapInfo;
struct TownTransitionData;
}

namespace TownTransitions
{
bool IsEdgeTransition(const Mdt::TownTransitionData& Transition, bool IsLeftEdgeTransition);
bool HasEdgeTransition(const Mdt::TownMapInfo& TownMap, bool IsLeftEdgeTransition);
}
