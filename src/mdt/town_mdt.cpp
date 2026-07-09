#include "town_mdt.h"

#include <algorithm>
#include <utility>

namespace Mdt
{
namespace
{
constexpr std::size_t TownHeaderSize = 0x17;
constexpr std::uint16_t TownHeight = 8;
constexpr std::size_t TownDoorEntrySize = 3;
constexpr std::size_t TownNpcEntrySize = 8;
constexpr std::size_t TownTransitionEntrySize = 4;
constexpr std::uint16_t TownEntityHeadLevelRow = 5;
constexpr std::size_t TownNpcConversationsPointerOffset = 0x0D;
constexpr std::size_t NpcPatrolBoundsPointerOffset = 0x11;
constexpr std::size_t NpcPatrolBoundsByteCount = 4;
constexpr std::size_t TownNameInfoPointerOffset = 0x04;
constexpr std::size_t TownNameRenderingInfoHeaderByteCount = 4;

std::uint16_t ReadTownWord(const std::vector<std::uint8_t>& Data, std::size_t Offset)
{
    return static_cast<std::uint16_t>(Data[Offset]
        | (static_cast<std::uint16_t>(Data[Offset + 1]) << 8));
}

std::size_t GetTownPointerOffset(std::uint16_t Pointer, std::size_t DataSize)
{
    if (Pointer == 0 || Pointer == 0xFFFF)
    {
        return DataSize;
    }

    if (Pointer >= 0xC000)
    {
        const std::size_t Offset = static_cast<std::size_t>(Pointer - 0xC000);
        return Offset < DataSize ? Offset : DataSize;
    }

    return Pointer < DataSize ? Pointer : DataSize;
}

std::uint16_t GetTownEntityHeadLevelRow(TownEntityKind EntityKind)
{
    // The town entity tables only store columns. The original game anchors both
    // town doors and NPCs to the head-level row at town_tiles + 5.
    switch (EntityKind)
    {
    case TownEntityKind::Door:
        return TownEntityHeadLevelRow;

    case TownEntityKind::Npc:
        return TownEntityHeadLevelRow;
    }

    return TownEntityHeadLevelRow;
}

void ParseTownEntityMarkers(const std::vector<std::uint8_t>& Data, std::uint16_t DoorsPointer,
    std::uint16_t NpcPointer, TownMapInfo& Output)
{
    // Keep this limited to the confirmed town door and NPC tables; the scripted
    // object table remains unresolved and should stay out of the debug overlay.
    const std::size_t DoorsOffset = GetTownPointerOffset(DoorsPointer, Data.size());
    for (std::size_t Offset = DoorsOffset; Offset + 2 < Data.size(); Offset += TownDoorEntrySize)
    {
        if (Data[Offset] == 0xFF && Data[Offset + 1] == 0xFF)
        {
            break;
        }

        TownEntityMarker Marker{};
        Marker.Kind = TownEntityKind::Door;
        Marker.X = static_cast<std::uint16_t>(Data[Offset] | (static_cast<std::uint16_t>(Data[Offset + 1]) << 8));
        Marker.Y = GetTownEntityHeadLevelRow(Marker.Kind);
        Marker.DoorType = Data[Offset + 2];
        Output.EntityMarkers.push_back(Marker);
    }

    const std::size_t NpcOffset = GetTownPointerOffset(NpcPointer, Data.size());
    for (std::size_t Offset = NpcOffset; Offset + 2 < Data.size(); Offset += TownNpcEntrySize)
    {
        if (Data[Offset] == 0xFF && Data[Offset + 1] == 0xFF)
        {
            break;
        }

        TownEntityMarker Marker{};
        Marker.Kind = TownEntityKind::Npc;
        Marker.X = static_cast<std::uint16_t>(Data[Offset] | (static_cast<std::uint16_t>(Data[Offset + 1]) << 8));
        Marker.Y = GetTownEntityHeadLevelRow(Marker.Kind);
        Marker.NpcSpriteSelector = Data[Offset + 2];
        Marker.NpcAnimationPhase = Data[Offset + 4];
        Marker.NpcAiType = Data[Offset + 5];
        Marker.NpcFlags = Data[Offset + 6];
        Marker.NpcId = Data[Offset + 7];
        Output.EntityMarkers.push_back(Marker);
    }
}

void ParseTownTransitionData(const std::vector<std::uint8_t>& Data, std::uint16_t TransitionPointer,
    std::uint16_t DoorsPointer, TownMapInfo& Output)
{
    Output.TransitionData.clear();

    if (TransitionPointer == 0 || TransitionPointer == 0xFFFF || DoorsPointer == 0
        || DoorsPointer == 0xFFFF || TransitionPointer > DoorsPointer)
    {
        return;
    }

    const std::size_t TransitionOffset = GetTownPointerOffset(TransitionPointer, Data.size());
    const std::size_t TransitionLimit = GetTownPointerOffset(DoorsPointer, Data.size());
    if (TransitionOffset >= TransitionLimit)
    {
        return;
    }

    for (std::size_t Offset = TransitionOffset; Offset + TownTransitionEntrySize <= TransitionLimit;
        Offset += TownTransitionEntrySize)
    {
        TownTransitionData Transition{};
        Transition.Flags = Data[Offset];
        Transition.DestinationMapId = Data[Offset + 1];
        Transition.NpcSpriteGroupId = Data[Offset + 2];
        Transition.PatternGroupId = Data[Offset + 3];
        Output.TransitionData.push_back(Transition);
    }
}

void ParseTownNameRenderingInfo(const std::vector<std::uint8_t>& Data, TownMapInfo& Output)
{
    Output.TownNameInfo = {};

    if (Data.size() <= TownNameInfoPointerOffset + 1)
    {
        return;
    }

    const std::uint16_t NamePointer = static_cast<std::uint16_t>(Data[TownNameInfoPointerOffset]
        | (static_cast<std::uint16_t>(Data[TownNameInfoPointerOffset + 1]) << 8));
    const std::size_t NameOffset = GetTownPointerOffset(NamePointer, Data.size());
    if (NameOffset + TownNameRenderingInfoHeaderByteCount > Data.size())
    {
        return;
    }

    const std::size_t CharacterCountOffset = NameOffset + 3;
    const std::size_t TextOffset = NameOffset + TownNameRenderingInfoHeaderByteCount;
    const std::uint8_t CharacterCount = Data[CharacterCountOffset];
    if (TextOffset + CharacterCount > Data.size())
    {
        return;
    }

    TownNameRenderingInfo NameInfo{};
    NameInfo.IsValid = true;
    NameInfo.Pointer = NamePointer;
    NameInfo.LeftMargin = Data[NameOffset];
    NameInfo.TopMargin = Data[NameOffset + 1];
    NameInfo.FineXOffset = Data[NameOffset + 2];
    NameInfo.CharacterCount = CharacterCount;
    NameInfo.Text.assign(reinterpret_cast<const char*>(Data.data() + static_cast<std::ptrdiff_t>(TextOffset)),
        reinterpret_cast<const char*>(Data.data() + static_cast<std::ptrdiff_t>(TextOffset + CharacterCount)));
    Output.TownNameInfo = std::move(NameInfo);
}

bool ParseTownNpcConversations(const std::vector<std::uint8_t>& Data, std::uint16_t ConversationsPointer,
    TownMapInfo& Output, std::string& ErrorMessage)
{
    Output.NpcConversations.clear();

    if (ConversationsPointer == 0 || ConversationsPointer == 0xFFFF)
    {
        return true;
    }

    const std::size_t TableOffset = GetTownPointerOffset(ConversationsPointer, Data.size());
    if (TableOffset + sizeof(std::uint16_t) > Data.size())
    {
        ErrorMessage = "town MDT NPC conversation pointer table is outside the file";
        return false;
    }

    const std::uint16_t FirstTextPointer = ReadTownWord(Data, TableOffset);
    const std::size_t FirstTextOffset = GetTownPointerOffset(FirstTextPointer, Data.size());
    if (FirstTextOffset <= TableOffset || FirstTextOffset > Data.size()
        || (FirstTextOffset - TableOffset) % sizeof(std::uint16_t) != 0)
    {
        ErrorMessage = "town MDT NPC conversation table has an invalid first text pointer";
        return false;
    }

    const std::size_t ConversationCount = (FirstTextOffset - TableOffset) / sizeof(std::uint16_t);
    Output.NpcConversations.reserve(ConversationCount);
    for (std::size_t ConversationIndex = 0; ConversationIndex < ConversationCount; ++ConversationIndex)
    {
        const std::size_t PointerOffset = TableOffset + ConversationIndex * sizeof(std::uint16_t);
        const std::uint16_t TextPointer = ReadTownWord(Data, PointerOffset);
        const std::size_t TextOffset = GetTownPointerOffset(TextPointer, Data.size());
        if (TextOffset >= Data.size())
        {
            ErrorMessage = "town MDT NPC conversation text pointer is outside the file";
            return false;
        }

        std::vector<std::uint8_t> DialogBytes;
        bool HasTerminator = false;
        for (std::size_t Offset = TextOffset; Offset < Data.size(); ++Offset)
        {
            DialogBytes.push_back(Data[Offset]);
            if (Data[Offset] == 0xFF)
            {
                HasTerminator = true;
                break;
            }
        }

        if (!HasTerminator)
        {
            ErrorMessage = "town MDT NPC conversation text is missing its FF terminator";
            return false;
        }

        Output.NpcConversations.push_back(std::move(DialogBytes));
    }

    return true;
}
}

bool ParseTownMap(const std::vector<std::uint8_t>& Data, TownMapInfo& Output, std::string& ErrorMessage)
{
    if (Data.size() < TownHeaderSize + TownHeight)
    {
        ErrorMessage = "town MDT is too small to contain the header and map grid";
        return false;
    }

    const std::uint16_t Width = static_cast<std::uint16_t>(Data[0x02] | (static_cast<std::uint16_t>(Data[0x03]) << 8));
    if (Width == 0)
    {
        ErrorMessage = "town MDT has an invalid map width of 0";
        return false;
    }

    const std::size_t CellCount = static_cast<std::size_t>(Width) * TownHeight;
    if (CellCount / TownHeight != Width)
    {
        ErrorMessage = "town MDT map width is too large";
        return false;
    }

    const std::size_t GridStart = TownHeaderSize;
    const std::size_t GridEnd = GridStart + CellCount;
    if (GridEnd > Data.size())
    {
        ErrorMessage = "town MDT map grid is truncated";
        return false;
    }

    Output.Cells.assign(Data.begin() + static_cast<std::ptrdiff_t>(GridStart), Data.begin() + static_cast<std::ptrdiff_t>(GridEnd));
    const auto [MinimumIt, MaximumIt] = std::minmax_element(Output.Cells.begin(), Output.Cells.end());

    Output.Width = Width;
    Output.Height = TownHeight;
    Output.CellCount = CellCount;
    Output.MinimumTileIndex = *MinimumIt;
    Output.MaximumTileIndex = *MaximumIt;
    Output.HasMiddleLayer = (Data[0x03] & 1) != 0;
    Output.TownId = Data[0x06];
    Output.TownPatternGroupId = 0;
    Output.TransitionTablePointer = static_cast<std::uint16_t>(Data[0x07]
        | (static_cast<std::uint16_t>(Data[0x08]) << 8));
    Output.TownNameInfo = {};
    Output.HasNpcPatrolBoundaries = false;
    Output.NpcPatrolBoundaries = {};

    Output.EntityMarkers.clear();
    Output.NpcConversations.clear();
    const std::uint16_t DoorsPointer = static_cast<std::uint16_t>(Data[0x09]
        | (static_cast<std::uint16_t>(Data[0x0A]) << 8));
    const std::uint16_t NpcPatrolBoundariesPointer = static_cast<std::uint16_t>(Data[NpcPatrolBoundsPointerOffset]
        | (static_cast<std::uint16_t>(Data[NpcPatrolBoundsPointerOffset + 1]) << 8));
    const std::uint16_t NpcPointer = static_cast<std::uint16_t>(Data[0x0F]
        | (static_cast<std::uint16_t>(Data[0x10]) << 8));
    const std::uint16_t DescriptorPointer = static_cast<std::uint16_t>(Data[0x00]
        | (static_cast<std::uint16_t>(Data[0x01]) << 8));
    if (const std::size_t DescriptorOffset = GetTownPointerOffset(DescriptorPointer, Data.size());
        DescriptorOffset + 4 < Data.size())
    {
        Output.TownPatternGroupId = Data[DescriptorOffset + 4];
    }

    if (const std::size_t NpcPatrolBoundariesOffset = GetTownPointerOffset(NpcPatrolBoundariesPointer, Data.size());
        NpcPatrolBoundariesOffset + NpcPatrolBoundsByteCount <= Data.size())
    {
        Output.NpcPatrolBoundaries.MinimumX = static_cast<std::uint16_t>(Data[NpcPatrolBoundariesOffset]
            | (static_cast<std::uint16_t>(Data[NpcPatrolBoundariesOffset + 1]) << 8));
        Output.NpcPatrolBoundaries.MaximumX = static_cast<std::uint16_t>(Data[NpcPatrolBoundariesOffset + 2]
            | (static_cast<std::uint16_t>(Data[NpcPatrolBoundariesOffset + 3]) << 8));
        Output.HasNpcPatrolBoundaries = true;
    }

    ParseTownTransitionData(Data, Output.TransitionTablePointer, DoorsPointer, Output);
    ParseTownNameRenderingInfo(Data, Output);
    const std::uint16_t NpcConversationsPointer = ReadTownWord(Data, TownNpcConversationsPointerOffset);
    if (!ParseTownNpcConversations(Data, NpcConversationsPointer, Output, ErrorMessage))
    {
        return false;
    }
    ParseTownEntityMarkers(Data, DoorsPointer, NpcPointer, Output);

    ErrorMessage.clear();
    return true;
}
}
