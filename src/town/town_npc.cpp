#include "town_npc.h"

#include "town.h"

#include <algorithm>
#include <iostream>
#include <string>
#include <utility>

namespace
{
constexpr std::size_t TownNpcSpriteFramesPerBlock = 8;
constexpr std::size_t TownNpcSpriteFamilyCount = 5;

bool IsSpriteFrameVisible(const Grp::NpcSpriteFrame& SpriteFrame)
{
    return std::any_of(SpriteFrame.DrawModes.begin(), SpriteFrame.DrawModes.end(),
        [](std::uint8_t DrawMode)
        {
            return DrawMode != Grp::TransparentDrawMode;
        });
}
}

namespace TownNpc
{
bool IsConfirmedSpriteFamily(std::size_t SpriteFamily)
{
    // The checked town data uses selector families 0 through 4, and the sprite
    // viewer confirms the same 8-frame block arithmetic for those families.
    return SpriteFamily < TownNpcSpriteFamilyCount;
}
}

std::size_t TownScene::GetTownNpcSpriteFrameIndex(std::uint8_t SpriteSelector,
    std::uint8_t AnimationPhase)
{
    const std::size_t SpriteFamily = static_cast<std::size_t>(SpriteSelector & 0x0F);
    const std::size_t FacingOffset = (SpriteSelector & 0x80) == 0 ? 4 : 0;
    const std::size_t FramePhase = static_cast<std::size_t>(AnimationPhase & 3);

    return (SpriteFamily * TownNpcSpriteFramesPerBlock) + FacingOffset + FramePhase;
}

std::uint8_t TownScene::GetTownNpcRuntimeRecordSpriteColumnMatch(
    const TownNpcRuntimeRecord& RuntimeRecord, std::size_t MapColumn)
{
    const std::size_t NpcColumn = static_cast<std::size_t>(RuntimeRecord.X);
    if (NpcColumn == MapColumn)
    {
        // Mirror sprite_x_coordinate_lookup: 2 means the current column, 1 means the next column.
        return 2;
    }

    if (NpcColumn == MapColumn + 1)
    {
        return 1;
    }

    return 0;
}

const TownScene::TownNpcRuntimeRecord* TownScene::FindBlockingTownNpcAtX(
    const std::vector<TownNpcRuntimeRecord>& TownNpcArray, std::size_t TargetX) noexcept
{
    for (const TownNpcRuntimeRecord& RuntimeRecord : TownNpcArray)
    {
        if (static_cast<std::size_t>(RuntimeRecord.X) != TargetX)
        {
            continue;
        }

        if ((RuntimeRecord.NpcFlags & 0x40) == 0)
        {
            continue;
        }

        return &RuntimeRecord;
    }

    return nullptr;
}

bool TownScene::TryGetTownNpcSpriteFrame(std::size_t FrameIndex,
    const Grp::NpcSpriteFrame*& SpriteFrame) const
{
    if (FrameIndex >= TownNpcSpriteFrameCount)
    {
        return false;
    }

    if (!TownNpcSpriteFrameLoaded[FrameIndex])
    {
        Grp::NpcSpriteFrame LoadedFrame;
        std::string LoadErrorMessage;
        if (!Grp::LoadNpcSpriteFrame(TownNpcSpriteGrpPath, FrameIndex, LoadedFrame, LoadErrorMessage))
        {
            if (!TownNpcSpriteFrameWarningPrinted)
            {
                std::cerr << TownNpcSpriteGrpPath.filename().string() << " town NPC frame "
                    << FrameIndex << " load failed: " << LoadErrorMessage << '\n';
                TownNpcSpriteFrameWarningPrinted = true;
            }

            return false;
        }

        TownNpcSpriteFrames[FrameIndex] = std::move(LoadedFrame);
        TownNpcSpriteFrameLoaded[FrameIndex] = true;
        TownNpcSpriteFrameVisible[FrameIndex] = IsSpriteFrameVisible(TownNpcSpriteFrames[FrameIndex]);
    }

    if (!TownNpcSpriteFrameVisible[FrameIndex])
    {
        return false;
    }

    SpriteFrame = &TownNpcSpriteFrames[FrameIndex];
    return true;
}
