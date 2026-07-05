#include "mdt_map.h"

#include <algorithm>

namespace Mdt
{
namespace
{
constexpr std::size_t TownHeaderSize = 0x17;
constexpr std::uint16_t TownHeight = 8;
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

    ErrorMessage.clear();
    return true;
}
}
