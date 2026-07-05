#include "mdt_map.h"

#include <algorithm>

namespace Mdt
{
namespace
{
constexpr std::size_t TownHeaderSize = 0x17;
constexpr std::uint16_t TownHeight = 8;
constexpr std::size_t TownDoorEntrySize = 3;
constexpr std::size_t TownNpcEntrySize = 8;
constexpr std::uint16_t TownEntityHeadLevelRow = 5;

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
        Marker.NpcId = Data[Offset + 7];
        Output.EntityMarkers.push_back(Marker);
    }
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

    Output.EntityMarkers.clear();
    ParseTownEntityMarkers(Data, static_cast<std::uint16_t>(Data[0x09] | (static_cast<std::uint16_t>(Data[0x0A]) << 8)),
        static_cast<std::uint16_t>(Data[0x0F] | (static_cast<std::uint16_t>(Data[0x10]) << 8)), Output);

    ErrorMessage.clear();
    return true;
}
}
