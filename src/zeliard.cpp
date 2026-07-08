#include <SDL3/SDL.h>

#include "grp/font_grp.h"
#include "grp/pat_grp.h"
#include "grp/man_grp.h"
#include "grp/grp_unpack.h"
#include "mdt/town_mdt.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <optional>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif

#include "town/town.h"

namespace
{
const std::filesystem::path ProjectRoot = ZELIARD_PROJECT_ROOT;
constexpr std::uint64_t SpriteAnimationFrameDelayMs = 160;

enum class SpriteBankKind
{
    Npc,
    TownHero,
    DungeonHero
};

enum class SpriteFrameLoadState
{
    Ok,
    Miss,
    Empty
};

struct SpriteBankDefinition
{
    const char* FileName = "";
    SpriteBankKind Kind = SpriteBankKind::Npc;
    std::size_t FrameCount = 0;
    std::size_t FrameWidth = 0;
    std::size_t FrameHeight = 0;
};

struct SpriteViewFrame
{
    std::size_t Width = 0;
    std::size_t Height = 0;
    std::vector<std::uint8_t> Pixels;
    std::vector<std::uint8_t> DrawModes;
    std::vector<std::uint8_t> VisiblePixels;
};

const std::array<SpriteBankDefinition, 4> SpriteBankDefinitions{{
    { "mman.grp", SpriteBankKind::Npc, 40, Grp::NpcSpriteFrame::FrameWidth, Grp::NpcSpriteFrame::FrameHeight },
    { "cman.grp", SpriteBankKind::Npc, 40, Grp::NpcSpriteFrame::FrameWidth, Grp::NpcSpriteFrame::FrameHeight },
    { "tman.grp", SpriteBankKind::TownHero, 10, Grp::NpcSpriteFrame::FrameWidth, Grp::NpcSpriteFrame::FrameHeight },
    { "fman.grp", SpriteBankKind::DungeonHero, 91, Grp::DungeonHeroSpriteFrame::FrameWidth, Grp::DungeonHeroSpriteFrame::FrameHeight }
}};

enum class ViewMode
{
    Font,
    Cpat,
    TownMap,
    Sprite
};

bool ReadWholeFile(const std::filesystem::path& Path, std::vector<std::uint8_t>& Output)
{
    std::ifstream Input(Path, std::ios::binary | std::ios::ate);
    if (!Input)
    {
        return false;
    }

    const std::streamsize FileSize = Input.tellg();
    if (FileSize < 0)
    {
        return false;
    }

    Output.resize(static_cast<std::size_t>(FileSize));
    Input.seekg(0, std::ios::beg);
    if (FileSize > 0 && !Input.read(reinterpret_cast<char*>(Output.data()), FileSize))
    {
        return false;
    }

    return true;
}

bool ParseHexByte(const std::string& Text, std::size_t Offset, std::uint8_t& Value)
{
    auto HexDigit = [](char Ch) -> int
    {
        if (Ch >= '0' && Ch <= '9')
        {
            return Ch - '0';
        }

        if (Ch >= 'a' && Ch <= 'f')
        {
            return 10 + (Ch - 'a');
        }

        if (Ch >= 'A' && Ch <= 'F')
        {
            return 10 + (Ch - 'A');
        }

        return -1;
    };

    const int High = HexDigit(Text[Offset]);
    const int Low = HexDigit(Text[Offset + 1]);
    if (High < 0 || Low < 0)
    {
        return false;
    }

    Value = static_cast<std::uint8_t>((High << 4) | Low);
    return true;
}

std::string StripJsonLineComments(const std::string& Text)
{
    std::istringstream Input(Text);
    std::string Line;
    std::string Output;
    Output.reserve(Text.size());

    while (std::getline(Input, Line))
    {
        const std::size_t CommentPos = Line.find("//");
        if (CommentPos != std::string::npos)
        {
            Line.erase(CommentPos);
        }

        Output += Line;
        Output.push_back('\n');
    }

    return Output;
}

bool LoadMain64Palette(Main64Palette& Palette, std::string& ErrorMessage)
{
    const std::filesystem::path PalettePath = ProjectRoot / "tools" / "grpviewer" / "v15" / "PALETTE.json";
    std::vector<std::uint8_t> FileBytes;
    if (!ReadWholeFile(PalettePath, FileBytes))
    {
        ErrorMessage = "failed to open " + PalettePath.string();
        return false;
    }

    const std::string CleanText = StripJsonLineComments(std::string(FileBytes.begin(), FileBytes.end()));
    const std::string PaletteKey = "\"main_64\"";
    const std::size_t PaletteKeyPos = CleanText.find(PaletteKey);
    if (PaletteKeyPos == std::string::npos)
    {
        ErrorMessage = "main_64 palette section was not found in " + PalettePath.string();
        return false;
    }

    const std::size_t ArrayStart = CleanText.find('[', PaletteKeyPos + PaletteKey.size());
    if (ArrayStart == std::string::npos)
    {
        ErrorMessage = "main_64 palette array is missing an opening bracket";
        return false;
    }

    const std::size_t ArrayEnd = CleanText.find(']', ArrayStart);
    if (ArrayEnd == std::string::npos)
    {
        ErrorMessage = "main_64 palette array is missing a closing bracket";
        return false;
    }

    std::size_t Cursor = ArrayStart + 1;
    std::size_t PaletteIndex = 0;
    while (Cursor < ArrayEnd)
    {
        while (Cursor < ArrayEnd && (CleanText[Cursor] == ',' || std::isspace(static_cast<unsigned char>(CleanText[Cursor]))))
        {
            ++Cursor;
        }

        if (Cursor >= ArrayEnd)
        {
            break;
        }

        if (CleanText[Cursor] != '"')
        {
            ErrorMessage = "main_64 palette contains unexpected text before color " + std::to_string(PaletteIndex);
            return false;
        }

        const std::size_t ColorStart = Cursor + 1;
        const std::size_t ColorEnd = CleanText.find('"', ColorStart);
        if (ColorEnd == std::string::npos || ColorEnd > ArrayEnd)
        {
            ErrorMessage = "main_64 palette contains an unterminated color string";
            return false;
        }

        const std::string ColorText = CleanText.substr(ColorStart, ColorEnd - ColorStart);
        if (ColorText.size() != 7 || ColorText[0] != '#')
        {
            ErrorMessage = "main_64 palette color " + std::to_string(PaletteIndex) + " is not a #RRGGBB value";
            return false;
        }

        SDL_Color Color{};
        if (!ParseHexByte(ColorText, 1, Color.r) || !ParseHexByte(ColorText, 3, Color.g) || !ParseHexByte(ColorText, 5, Color.b))
        {
            ErrorMessage = "main_64 palette color " + std::to_string(PaletteIndex) + " contains invalid hex digits";
            return false;
        }

        Color.a = 255;
        if (PaletteIndex >= Palette.size())
        {
            ErrorMessage = "main_64 palette contains more than 64 colors";
            return false;
        }

        Palette[PaletteIndex] = Color;
        ++PaletteIndex;
        Cursor = ColorEnd + 1;
    }

    if (PaletteIndex != Palette.size())
    {
        ErrorMessage = "main_64 palette contains " + std::to_string(PaletteIndex) + " colors instead of 64";
        return false;
    }

    ErrorMessage.clear();
    return true;
}

void PrintActiveViewMode(ViewMode ActiveViewMode)
{
    switch (ActiveViewMode)
    {
    case ViewMode::Font:
        std::cout << "active view mode: font.grp" << '\n';
        break;

    case ViewMode::Cpat:
        std::cout << "active view mode: cpat.grp tile grid" << '\n';
        break;

    case ViewMode::TownMap:
        std::cout << "active view mode: town map" << '\n';
        break;

    case ViewMode::Sprite:
        std::cout << "active view mode: sprite viewer" << '\n';
        break;
    }
}

const char* GetSpriteFrameLoadStateName(SpriteFrameLoadState LoadState)
{
    switch (LoadState)
    {
    case SpriteFrameLoadState::Ok:
        return "OK";

    case SpriteFrameLoadState::Miss:
        return "MISS";

    case SpriteFrameLoadState::Empty:
        return "EMPTY";
    }

    return "MISS";
}

std::filesystem::path GetSpriteBankPath(const SpriteBankDefinition& SpriteBank)
{
    return ProjectRoot / "tools" / "grpviewer" / SpriteBank.FileName;
}

void ResetSpriteViewFrame(SpriteViewFrame& SpriteFrame, std::size_t Width, std::size_t Height)
{
    SpriteFrame.Width = Width;
    SpriteFrame.Height = Height;
    SpriteFrame.Pixels.assign(Width * Height, 0);
    SpriteFrame.DrawModes.assign(Width * Height, Grp::TransparentDrawMode);
    SpriteFrame.VisiblePixels.assign(Width * Height, 0);
}

void CopyNpcSpriteFrameForView(const Grp::NpcSpriteFrame& SourceFrame, SpriteViewFrame& SpriteFrame)
{
    ResetSpriteViewFrame(SpriteFrame, Grp::NpcSpriteFrame::FrameWidth, Grp::NpcSpriteFrame::FrameHeight);

    for (std::size_t PixelIndex = 0; PixelIndex < SourceFrame.Pixels.size(); ++PixelIndex)
    {
        const std::uint8_t PaletteIndex = SourceFrame.Pixels[PixelIndex];
        SpriteFrame.Pixels[PixelIndex] = PaletteIndex;
        SpriteFrame.DrawModes[PixelIndex] = SourceFrame.DrawModes[PixelIndex];
        SpriteFrame.VisiblePixels[PixelIndex] = SourceFrame.DrawModes[PixelIndex] == Grp::TransparentDrawMode ? 0 : 1;
    }
}

void CopyDungeonHeroSpriteFrameForView(const Grp::DungeonHeroSpriteFrame& SourceFrame, SpriteViewFrame& SpriteFrame)
{
    ResetSpriteViewFrame(SpriteFrame, Grp::DungeonHeroSpriteFrame::FrameWidth, Grp::DungeonHeroSpriteFrame::FrameHeight);
    std::copy(SourceFrame.Pixels.begin(), SourceFrame.Pixels.end(), SpriteFrame.Pixels.begin());
    std::copy(SourceFrame.VisiblePixels.begin(), SourceFrame.VisiblePixels.end(), SpriteFrame.VisiblePixels.begin());
    std::transform(SourceFrame.VisiblePixels.begin(), SourceFrame.VisiblePixels.end(), SpriteFrame.DrawModes.begin(),
        [](std::uint8_t IsVisible)
        {
            return IsVisible != 0 ? Grp::ColorDrawMode : Grp::TransparentDrawMode;
        });
}

bool HasVisibleSpritePixels(const SpriteViewFrame& SpriteFrame)
{
    return std::any_of(SpriteFrame.DrawModes.begin(), SpriteFrame.DrawModes.end(),
        [](std::uint8_t DrawMode)
        {
            return DrawMode != Grp::TransparentDrawMode;
        });
}

void LoadSpriteFrameForView(const SpriteBankDefinition& SpriteBank, std::size_t FrameIndex,
    SpriteViewFrame& SpriteFrame, SpriteFrameLoadState& LoadState, std::string& ErrorMessage)
{
    ResetSpriteViewFrame(SpriteFrame, SpriteBank.FrameWidth, SpriteBank.FrameHeight);

    if (FrameIndex >= SpriteBank.FrameCount)
    {
        LoadState = SpriteFrameLoadState::Miss;
        ErrorMessage = std::string(SpriteBank.FileName) + " frame index " + std::to_string(FrameIndex)
            + " is outside the " + std::to_string(SpriteBank.FrameCount) + "-frame sheet";
        return;
    }

    const std::filesystem::path SpriteBankPath = GetSpriteBankPath(SpriteBank);
    bool FrameLoaded = false;

    switch (SpriteBank.Kind)
    {
    case SpriteBankKind::Npc:
    {
        Grp::NpcSpriteFrame LoadedFrame;
        FrameLoaded = Grp::LoadNpcSpriteFrame(SpriteBankPath, FrameIndex, LoadedFrame, ErrorMessage);
        if (FrameLoaded)
        {
            CopyNpcSpriteFrameForView(LoadedFrame, SpriteFrame);
        }
        break;
    }

    case SpriteBankKind::TownHero:
    {
        Grp::NpcSpriteFrame LoadedFrame;
        FrameLoaded = Grp::LoadTownHeroSpriteFrame(SpriteBankPath, FrameIndex, LoadedFrame, ErrorMessage);
        if (FrameLoaded)
        {
            CopyNpcSpriteFrameForView(LoadedFrame, SpriteFrame);
        }
        break;
    }

    case SpriteBankKind::DungeonHero:
    {
        Grp::DungeonHeroSpriteFrame LoadedFrame;
        FrameLoaded = Grp::LoadDungeonHeroSpriteFrame(SpriteBankPath, FrameIndex, LoadedFrame, ErrorMessage);
        if (FrameLoaded)
        {
            CopyDungeonHeroSpriteFrameForView(LoadedFrame, SpriteFrame);
        }
        break;
    }
    }

    if (!FrameLoaded)
    {
        LoadState = SpriteFrameLoadState::Miss;
        return;
    }

    LoadState = HasVisibleSpritePixels(SpriteFrame) ? SpriteFrameLoadState::Ok : SpriteFrameLoadState::Empty;
    ErrorMessage.clear();
}

void PrintActiveSpriteBank(const SpriteBankDefinition& SpriteBank)
{
    std::cout << "active sprite bank: " << SpriteBank.FileName
              << " (" << SpriteBank.FrameCount << " frames)" << '\n';
}

void PrintSpriteAnimationState(bool SpriteAnimationEnabled)
{
    std::cout << "sprite animation " << (SpriteAnimationEnabled ? "on" : "off") << '\n';
}

bool ValidateGrpUnpack()
{
    std::vector<std::uint8_t> Unpacked;
    std::vector<std::uint8_t> Expected;
    std::string ErrorMessage;
    const std::filesystem::path GrpPath = ProjectRoot / "tools" / "grpviewer" / "cpat.grp";
    const std::filesystem::path UnpPath = ProjectRoot / "tools" / "grpviewer" / "cpat.grp.unp";

    if (!Grp::UnpackFile(GrpPath, Unpacked, ErrorMessage))
    {
        std::cerr << "GRP validation mismatch: " << ErrorMessage << '\n';
        return false;
    }

    if (!ReadWholeFile(UnpPath, Expected))
    {
        std::cerr << "GRP validation mismatch: failed to open " << UnpPath.string() << '\n';
        return false;
    }

    if (Unpacked == Expected)
    {
        std::cout << "GRP validation match: " << GrpPath.string() << " matches " << UnpPath.string()
                  << " (" << Unpacked.size() << " bytes)." << '\n';
        return true;
    }

    std::cout << "GRP validation mismatch: " << GrpPath.string() << " unpacked to " << Unpacked.size()
              << " bytes, expected " << Expected.size() << " bytes." << '\n';
    return false;
}

bool LoadFontGroups(std::array<Grp::FontGroup, 3>& FontGroups, std::array<bool, 3>& FontGroupAvailable)
{
    std::vector<std::uint8_t> Unpacked;
    std::string ErrorMessage;
    const std::filesystem::path GrpPath = ProjectRoot / "tools" / "grpviewer" / "font.grp";

    if (!Grp::UnpackFile(GrpPath, Unpacked, ErrorMessage))
    {
        std::cerr << "font.grp load failed: " << ErrorMessage << '\n';
        return false;
    }

    bool AnyGroupLoaded = false;
    for (std::size_t GroupIndex = 0; GroupIndex < FontGroups.size(); ++GroupIndex)
    {
        std::string WarningMessage;
        if (Grp::DecodeFontGroup(Unpacked, GroupIndex, FontGroups[GroupIndex], ErrorMessage, &WarningMessage))
        {
            FontGroupAvailable[GroupIndex] = true;
            AnyGroupLoaded = true;
            if (!WarningMessage.empty())
            {
                std::cerr << WarningMessage << '\n';
            }
        }
        else
        {
            FontGroupAvailable[GroupIndex] = false;
            std::cerr << "font.grp parse skipped for group " << GroupIndex << ": " << ErrorMessage << '\n';
        }
    }

    if (!AnyGroupLoaded)
    {
        std::cerr << "font.grp parse failed: no usable font groups were found" << '\n';
        return false;
    }

    std::size_t AvailableGroupCount = 0;
    for (bool IsAvailable : FontGroupAvailable)
    {
        if (IsAvailable)
        {
            ++AvailableGroupCount;
        }
    }

    std::cout << "font.grp loaded: " << AvailableGroupCount << " font groups available ("
              << Unpacked.size() << " unpacked bytes)." << '\n';
    return true;
}

bool LoadPatternBank(Grp::PatternBank& PatternBank)
{
    std::vector<std::uint8_t> Unpacked;
    std::string ErrorMessage;
    const std::filesystem::path GrpPath = ProjectRoot / "tools" / "grpviewer" / "cpat.grp";

    if (!Grp::UnpackFile(GrpPath, Unpacked, ErrorMessage))
    {
        std::cerr << "cpat.grp load failed: " << ErrorMessage << '\n';
        return false;
    }

    if (!Grp::DecodePatternBank(Unpacked, PatternBank, ErrorMessage))
    {
        std::cerr << "cpat.grp pattern decode failed: " << ErrorMessage << '\n';
        return false;
    }

    std::cout << "cpat.grp pattern bank loaded: " << PatternBank.Tiles.size() << " patterns, "
              << Unpacked.size() << " source bytes, "
              << (PatternBank.Tiles.size() * 64) << " decoded pixels, "
              << "palette indices " << static_cast<int>(PatternBank.MinimumPaletteIndex) << ".."
              << static_cast<int>(PatternBank.MaximumPaletteIndex) << "." << '\n';
    return true;
}

std::filesystem::path GetTownPatternBankPath(std::uint8_t PatternGroupId)
{
    switch (PatternGroupId)
    {
    case 0:
        return ProjectRoot / "tools" / "grpviewer" / "cpat.grp";

    case 1:
        return ProjectRoot / "tools" / "grpviewer" / "mpat.grp";

    case 2:
        return ProjectRoot / "tools" / "grpviewer" / "dpat.grp";
    }

    return {};
}

bool LoadTownPatternBank(std::uint8_t PatternGroupId, Grp::PatternBank& PatternBank)
{
    std::vector<std::uint8_t> Unpacked;
    std::string ErrorMessage;
    const std::filesystem::path GrpPath = GetTownPatternBankPath(PatternGroupId);
    if (GrpPath.empty())
    {
        std::cerr << "invalid town pattern group id: " << static_cast<unsigned int>(PatternGroupId) << '\n';
        return false;
    }

    if (!Grp::UnpackFile(GrpPath, Unpacked, ErrorMessage))
    {
        std::cerr << GrpPath.filename().string() << " load failed: " << ErrorMessage << '\n';
        return false;
    }

    if (!Grp::DecodePatternBank(Unpacked, PatternBank, ErrorMessage))
    {
        std::cerr << GrpPath.filename().string() << " pattern decode failed: " << ErrorMessage << '\n';
        return false;
    }

    std::ostringstream SpecialTileStream;
    SpecialTileStream << std::uppercase << std::hex << std::setfill('0');
    for (std::size_t TileIndex = 0; TileIndex < PatternBank.SpecialTileIndices.size(); ++TileIndex)
    {
        if (TileIndex > 0)
        {
            SpecialTileStream << ' ';
        }

        SpecialTileStream << std::setw(2)
            << static_cast<unsigned int>(PatternBank.SpecialTileIndices[TileIndex]);
    }

    std::cout << GrpPath.filename().string() << " pattern bank loaded: " << PatternBank.Tiles.size()
              << " patterns, " << Unpacked.size() << " source bytes, "
              << (PatternBank.Tiles.size() * 64) << " decoded pixels, "
              << "palette indices " << static_cast<int>(PatternBank.MinimumPaletteIndex) << ".."
              << static_cast<int>(PatternBank.MaximumPaletteIndex)
              << ", special tiles "
              << (PatternBank.SpecialTileIndices.empty() ? "none" : SpecialTileStream.str()) << "." << '\n';
    return true;
}

bool LoadNpcSpriteSheetSummary(Grp::SpriteSheetSummary& SpriteSheet)
{
    std::string ErrorMessage;
    const std::filesystem::path GrpPath = ProjectRoot / "tools" / "grpviewer" / "mman.grp";

    if (!Grp::LoadNpcSpriteSheet(GrpPath, SpriteSheet, ErrorMessage))
    {
        std::cerr << "mman.grp sprite validation failed: " << ErrorMessage << '\n';
        return false;
    }

    std::cout << "mman.grp sprite validation: source " << GrpPath.string()
              << ", unpacked " << SpriteSheet.UnpackedByteCount << " bytes, "
              << SpriteSheet.FrameCount << " frames, frame "
              << SpriteSheet.FrameWidth << "x" << SpriteSheet.FrameHeight
              << ", decoded " << SpriteSheet.DecodedPixelCount << " pixels, palette indices "
              << static_cast<int>(SpriteSheet.MinimumPaletteIndex) << ".."
              << static_cast<int>(SpriteSheet.MaximumPaletteIndex) << "." << '\n';
    return true;
}

std::filesystem::path GetTownNpcSpriteGrpPath(const std::vector<std::uint8_t>& FileBytes)
{
    constexpr std::uint16_t TownDescriptorAddress = 0xC000;
    constexpr std::size_t TownNpcBankSelectorOffset = 1;
    const std::string NpcGrpName = [&FileBytes]() -> std::string
    {
        if (FileBytes.size() < 2)
        {
            return "mman.grp";
        }

        const std::uint16_t DescriptorPointer = static_cast<std::uint16_t>(
            FileBytes[0] | (static_cast<std::uint16_t>(FileBytes[1]) << 8));
        if (DescriptorPointer < TownDescriptorAddress)
        {
            return "mman.grp";
        }

        const std::size_t DescriptorOffset = static_cast<std::size_t>(DescriptorPointer - TownDescriptorAddress);
        if (DescriptorOffset + TownNpcBankSelectorOffset >= FileBytes.size())
        {
            return "mman.grp";
        }

        return FileBytes[DescriptorOffset + TownNpcBankSelectorOffset] != 0 ? "cman.grp" : "mman.grp";
    }();

    return ProjectRoot / "game" / "0" / NpcGrpName;
}

std::filesystem::path GetTownMdtPath(std::uint8_t TownId)
{
    switch (TownId)
    {
    case 0:
        return ProjectRoot / "game" / "0" / "cmap.mdt";

    case 1:
        return ProjectRoot / "game" / "0" / "mrmp.mdt";

    case 2:
        return ProjectRoot / "game" / "0" / "stmp.mdt";

    case 3:
        return ProjectRoot / "game" / "0" / "bsmp.mdt";

    case 4:
        return ProjectRoot / "game" / "0" / "hlmp.mdt";

    case 5:
        return ProjectRoot / "game" / "0" / "tmmp.mdt";

    case 6:
        return ProjectRoot / "game" / "0" / "drmp.mdt";

    case 7:
        return ProjectRoot / "game" / "0" / "llmp.mdt";

    case 8:
        return ProjectRoot / "game" / "0" / "prmp.mdt";

    case 9:
        return ProjectRoot / "game" / "0" / "esmp.mdt";
    }

    return {};
}

std::string FormatTownTransitionRecordBytes(const Mdt::TownTransitionData& TownTransition)
{
    std::ostringstream Stream;
    Stream << std::uppercase << std::hex << std::setfill('0')
           << std::setw(2) << static_cast<unsigned int>(TownTransition.Flags) << ' '
           << std::setw(2) << static_cast<unsigned int>(TownTransition.DestinationMapId) << ' '
           << std::setw(2) << static_cast<unsigned int>(TownTransition.NpcSpriteGroupId) << ' '
           << std::setw(2) << static_cast<unsigned int>(TownTransition.PatternGroupId);
    return Stream.str();
}

bool LoadTownMap(std::uint8_t TownId, Mdt::TownMapInfo& TownMap, std::filesystem::path& TownNpcSpriteGrpPath)
{
    const std::filesystem::path MdtPath = GetTownMdtPath(TownId);
    if (MdtPath.empty())
    {
        std::cerr << "invalid town id: " << static_cast<unsigned int>(TownId) << '\n';
        return false;
    }

    std::vector<std::uint8_t> FileBytes;
    std::string ErrorMessage;
    if (!ReadWholeFile(MdtPath, FileBytes))
    {
        std::cerr << MdtPath.filename().string() << " load failed: failed to open " << MdtPath.string() << std::endl;
        return false;
    }

    Mdt::TownMapInfo MapInfo;
    if (!Mdt::ParseTownMap(FileBytes, MapInfo, ErrorMessage))
    {
        std::cerr << MdtPath.filename().string() << " parse failed: " << ErrorMessage << std::endl;
        return false;
    }

    std::cout << MdtPath.filename().string() << " parsed: " << MdtPath.string() << ", width " << MapInfo.Width
              << ", height " << MapInfo.Height << ", cells " << MapInfo.CellCount
              << ", tile indices " << static_cast<int>(MapInfo.MinimumTileIndex) << ".."
              << static_cast<int>(MapInfo.MaximumTileIndex) << "." << std::endl;
    TownNpcSpriteGrpPath = GetTownNpcSpriteGrpPath(FileBytes);
    TownMap = std::move(MapInfo);
    return true;
}

void PrintActiveFontGroup(std::size_t GroupIndex, const Grp::FontGroup& FontGroup)
{
    std::cout << "font.grp active group " << GroupIndex << " has " << FontGroup.Glyphs.size()
              << " 8x8 glyphs." << '\n';
}

const Grp::FontGroup* GetDebugFontGroup(const std::array<Grp::FontGroup, 3>& FontGroups, const std::array<bool, 3>& FontGroupAvailable)
{
    if (!FontGroupAvailable[0])
    {
        return nullptr;
    }

    return &FontGroups[0];
}

void PrintDebugOverlayState(bool DebugOverlayEnabled)
{
    std::cout << "debug overlay " << (DebugOverlayEnabled ? "on" : "off") << '\n';
}

void PrintTownMapBlockedTileOverlayState(bool BlockedTileOverlayEnabled)
{
    std::cout << "town map collision overlay " << (BlockedTileOverlayEnabled ? "on" : "off") << '\n';
}

void PrintTownMapEntityMarkerState(bool EntityMarkersEnabled)
{
    std::cout << "town map object markers " << (EntityMarkersEnabled ? "on" : "off") << '\n';
}

void PrintTownTearsOverlayDebugOverrideState(bool DebugOverrideEnabled)
{
    std::cout << "town tears overlay debug override " << (DebugOverrideEnabled ? "on" : "off") << '\n';
}

void DrawFontGlyphGrid(SDL_Renderer* Renderer, const Grp::FontGroup& FontGroup)
{
    constexpr int Columns = 16;
    constexpr float StartX = 16.0f;
    constexpr float StartY = 16.0f;
    constexpr float PixelSize = 2.0f;
    constexpr float GlyphStep = 18.0f;

    SDL_SetRenderDrawColor(Renderer, 255, 255, 255, 255);

    for (std::size_t GlyphIndex = 0; GlyphIndex < FontGroup.Glyphs.size(); ++GlyphIndex)
    {
        const int GlyphColumn = static_cast<int>(GlyphIndex % Columns);
        const int GlyphRow = static_cast<int>(GlyphIndex / Columns);
        const float GlyphX = StartX + static_cast<float>(GlyphColumn) * GlyphStep;
        const float GlyphY = StartY + static_cast<float>(GlyphRow) * GlyphStep;

        for (std::size_t Row = 0; Row < 8; ++Row)
        {
            const std::uint8_t Bits = FontGroup.Glyphs[GlyphIndex].Rows[Row];
            for (std::size_t Column = 0; Column < 8; ++Column)
            {
                if (((Bits >> (7 - Column)) & 1) == 0)
                {
                    continue;
                }

                const SDL_FRect PixelRect{
                    GlyphX + static_cast<float>(Column) * PixelSize,
                    GlyphY + static_cast<float>(Row) * PixelSize,
                    PixelSize,
                    PixelSize
                };
                SDL_RenderFillRect(Renderer, &PixelRect);
            }
        }
    }
}

void DrawFontText(SDL_Renderer* Renderer, const Grp::FontGroup& FontGroup, float StartX, float StartY, float Scale, const std::string& Text)
{
    constexpr std::size_t GlyphWidth = 8;
    constexpr std::size_t GlyphHeight = 8;

    SDL_SetRenderDrawColor(Renderer, 255, 255, 255, 255);

    float CursorX = StartX;
    float CursorY = StartY;
    const float GlyphAdvance = static_cast<float>(GlyphWidth) * Scale;
    const float LineAdvance = static_cast<float>(GlyphHeight) * Scale;

    for (char Ch : Text)
    {
        if (Ch == '\n')
        {
            CursorX = StartX;
            CursorY += LineAdvance;
            continue;
        }

        const unsigned char Character = static_cast<unsigned char>(Ch);
        if (Character < 32)
        {
            CursorX += GlyphAdvance;
            continue;
        }

        const std::size_t GlyphIndex = static_cast<std::size_t>(Character - 32);
        if (GlyphIndex >= FontGroup.Glyphs.size())
        {
            CursorX += GlyphAdvance;
            continue;
        }

        const Grp::FontGlyph& Glyph = FontGroup.Glyphs[GlyphIndex];
        for (std::size_t Row = 0; Row < GlyphHeight; ++Row)
        {
            const std::uint8_t Bits = Glyph.Rows[Row];
            for (std::size_t Column = 0; Column < GlyphWidth; ++Column)
            {
                if (((Bits >> (7 - Column)) & 1) == 0)
                {
                    continue;
                }

                const SDL_FRect PixelRect{
                    CursorX + static_cast<float>(Column) * Scale,
                    CursorY + static_cast<float>(Row) * Scale,
                    Scale,
                    Scale
                };
                SDL_RenderFillRect(Renderer, &PixelRect);
            }
        }

        CursorX += GlyphAdvance;
    }
}

void DrawPatternBankGrid(SDL_Renderer* Renderer, const Grp::PatternBank& PatternBank, const Main64Palette& Palette)
{
    constexpr int Columns = 16;
    constexpr float StartX = 17.0f;
    constexpr float StartY = 11.0f;
    constexpr float PixelSize = 2.0f;
    constexpr float TileStep = 18.0f;

    for (std::size_t PatternIndex = 0; PatternIndex < PatternBank.Tiles.size(); ++PatternIndex)
    {
        const int TileColumn = static_cast<int>(PatternIndex % Columns);
        const int TileRow = static_cast<int>(PatternIndex / Columns);
        const float TileX = StartX + static_cast<float>(TileColumn) * TileStep;
        const float TileY = StartY + static_cast<float>(TileRow) * TileStep;

        const Grp::PatternTile& Tile = PatternBank.Tiles[PatternIndex];
        for (std::size_t Row = 0; Row < 8; ++Row)
        {
            for (std::size_t Column = 0; Column < 8; ++Column)
            {
                const std::uint8_t PaletteIndex = Tile.Pixels[Row * 8 + Column];
                const SDL_Color& Color = Palette[PaletteIndex];
                SDL_SetRenderDrawColor(Renderer, Color.r, Color.g, Color.b, Color.a);

                const SDL_FRect PixelRect{
                    TileX + static_cast<float>(Column) * PixelSize,
                    TileY + static_cast<float>(Row) * PixelSize,
                    PixelSize,
                    PixelSize
                };
                SDL_RenderFillRect(Renderer, &PixelRect);
            }
        }
    }
}

void DrawSpriteFrameView(SDL_Renderer* Renderer, const SpriteBankDefinition& SpriteBank, const SpriteViewFrame& SpriteFrame,
    std::size_t SpriteFrameIndex, SpriteFrameLoadState LoadState, bool SpriteAnimationEnabled,
    const Main64Palette& Palette, const Grp::FontGroup* DebugFontGroup, bool DebugOverlayEnabled)
{
    if (LoadState != SpriteFrameLoadState::Miss && SpriteFrame.Width > 0 && SpriteFrame.Height > 0
        && SpriteFrame.Pixels.size() == SpriteFrame.DrawModes.size())
    {
        constexpr float MaximumSpriteViewSize = 120.0f;
        const float SpritePixelSize = std::min(5.0f,
            MaximumSpriteViewSize / static_cast<float>(std::max(SpriteFrame.Width, SpriteFrame.Height)));
        const float SpriteWidthPixels = static_cast<float>(SpriteFrame.Width) * SpritePixelSize;
        const float SpriteHeightPixels = static_cast<float>(SpriteFrame.Height) * SpritePixelSize;
        const float StartX = (320.0f - SpriteWidthPixels) * 0.5f;
        const float StartY = (200.0f - SpriteHeightPixels) * 0.5f;

        for (std::size_t Row = 0; Row < SpriteFrame.Height; ++Row)
        {
            for (std::size_t Column = 0; Column < SpriteFrame.Width; ++Column)
            {
                const std::size_t PixelIndex = Row * SpriteFrame.Width + Column;
                const std::uint8_t DrawMode = SpriteFrame.DrawModes[PixelIndex];
                if (DrawMode == Grp::TransparentDrawMode)
                {
                    continue;
                }

                if (DrawMode == Grp::BlackDrawMode)
                {
                    SDL_SetRenderDrawColor(Renderer, 0, 0, 0, 255);
                }
                else
                {
                    const std::uint8_t PaletteIndex = SpriteFrame.Pixels[PixelIndex];
                    if (PaletteIndex >= Palette.size())
                    {
                        continue;
                    }

                    const SDL_Color& Color = Palette[PaletteIndex];
                    SDL_SetRenderDrawColor(Renderer, Color.r, Color.g, Color.b, Color.a);
                }

                const SDL_FRect PixelRect{
                    StartX + static_cast<float>(Column) * SpritePixelSize,
                    StartY + static_cast<float>(Row) * SpritePixelSize,
                    SpritePixelSize,
                    SpritePixelSize
                };
                SDL_RenderFillRect(Renderer, &PixelRect);
            }
        }
    }

    if (DebugOverlayEnabled && DebugFontGroup != nullptr)
    {
        constexpr float TextScale = 1.0f;
        constexpr float TextStartX = 8.0f;
        constexpr float TextStartY = 8.0f;
        constexpr float LineSpacing = 10.0f;

        DrawFontText(Renderer, *DebugFontGroup, TextStartX, TextStartY, TextScale,
            "GRP " + std::string(SpriteBank.FileName));
        DrawFontText(Renderer, *DebugFontGroup, TextStartX, TextStartY + LineSpacing, TextScale,
            "FRAME " + std::to_string(SpriteFrameIndex) + " / " + std::to_string(SpriteBank.FrameCount));
        DrawFontText(Renderer, *DebugFontGroup, TextStartX, TextStartY + LineSpacing * 2.0f, TextScale,
            "ANIM " + std::string(SpriteAnimationEnabled ? "ON" : "OFF"));
        DrawFontText(Renderer, *DebugFontGroup, TextStartX, TextStartY + LineSpacing * 3.0f, TextScale,
            "STATE " + std::string(GetSpriteFrameLoadStateName(LoadState)));
    }
}

struct ZeliardApp
{
    Mdt::TownMapInfo TownMap;
    std::filesystem::path TownNpcSpriteGrpPath;
    std::filesystem::path TownActorSpriteGrpPath;
    Grp::PatternBank TownPatternBank;
    Main64Palette Palette{};
    std::optional<TownScene> TownMapScene;
    SDL_Window* Window = nullptr;
    SDL_Renderer* Renderer = nullptr;
    bool TownMapLoaded = false;
    bool TownPatternBankLoaded = false;
    bool PaletteLoaded = false;
    bool TownReady = false;
    bool Running = false;
    std::uint64_t TownMapTimingLastTicksNs = 0;
    std::uint64_t TownMapTimingAccumulatorNs = 0;
};

void LoadZeliardContent(ZeliardApp& App)
{
    App.TownNpcSpriteGrpPath = ProjectRoot / "game" / "0" / "mman.grp";
    constexpr std::uint8_t StartingTownId = 0;
    App.TownMapLoaded = LoadTownMap(StartingTownId, App.TownMap, App.TownNpcSpriteGrpPath);
    if (!App.TownMapLoaded)
    {
        std::cerr << "town MDT parse validation failed; continuing anyway." << '\n';
    }
    else
    {
        std::cout << "town NPC sprite group selected: " << App.TownNpcSpriteGrpPath.filename().string() << '\n';
    }

    App.TownPatternBankLoaded = App.TownMapLoaded
        && LoadTownPatternBank(App.TownMap.TownPatternGroupId, App.TownPatternBank);
    if (!App.TownPatternBankLoaded)
    {
        std::cerr << "town pattern bank decode failed; continuing anyway." << '\n';
    }

    std::string PaletteErrorMessage;
    App.PaletteLoaded = LoadMain64Palette(App.Palette, PaletteErrorMessage);
    if (!App.PaletteLoaded)
    {
        std::cerr << "cpat.grp palette load failed: " << PaletteErrorMessage << '\n';
    }
    else
    {
        std::cout << "cpat.grp palette loaded from tools/grpviewer/v15/PALETTE.json main_64." << '\n';
    }

    App.TownActorSpriteGrpPath = ProjectRoot / "game" / "0" / "tman.grp";
    App.TownMapScene.emplace(App.TownActorSpriteGrpPath, App.TownNpcSpriteGrpPath, App.TownMap, App.TownPatternBank, App.Palette);
    App.TownReady = App.TownMapLoaded && App.TownPatternBankLoaded && App.PaletteLoaded;
}

bool InitializeZeliardApp(ZeliardApp& App)
{
    LoadZeliardContent(App);

    if (!SDL_Init(SDL_INIT_VIDEO))
    {
        std::cerr << "SDL_Init failed: " << SDL_GetError() << '\n';
        return false;
    }

    App.Window = SDL_CreateWindow("Zeliard", 960, 600, 0);
    if (!App.Window)
    {
        std::cerr << "SDL_CreateWindow failed: " << SDL_GetError() << '\n';
        return false;
    }

    App.Renderer = SDL_CreateRenderer(App.Window, nullptr);
    if (!App.Renderer)
    {
        std::cerr << "SDL_CreateRenderer failed: " << SDL_GetError() << '\n';
        return false;
    }

    if (!SDL_SetRenderLogicalPresentation(App.Renderer, 320, 200, SDL_LOGICAL_PRESENTATION_LETTERBOX))
    {
        std::cerr << "SDL_SetRenderLogicalPresentation failed: " << SDL_GetError() << '\n';
        return false;
    }

    App.Running = true;
    return true;
}

bool RunZeliardFrame(ZeliardApp& App)
{
    SDL_Event Event;
    while (SDL_PollEvent(&Event))
    {
        if (Event.type == SDL_EVENT_QUIT)
        {
            App.Running = false;
        }
        else if (Event.type == SDL_EVENT_KEY_DOWN && Event.key.key == SDLK_ESCAPE)
        {
            App.Running = false;
        }
    }

    const std::uint64_t CurrentTicksNs = SDL_GetTicksNS();
    if (App.TownReady && App.TownMapScene.has_value())
    {
        const bool* KeyboardState = SDL_GetKeyboardState(nullptr);
        if (App.TownMapTimingLastTicksNs == 0)
        {
            App.TownMapTimingLastTicksNs = CurrentTicksNs;
            App.TownMapTimingAccumulatorNs = TownScene::TownDosTownLoopIntervalNanoseconds;
        }
        else
        {
            App.TownMapTimingAccumulatorNs += CurrentTicksNs - App.TownMapTimingLastTicksNs;
            App.TownMapTimingLastTicksNs = CurrentTicksNs;
        }

        while (App.TownMapTimingAccumulatorNs >= TownScene::TownDosTownLoopIntervalNanoseconds)
        {
            if (const std::optional<Mdt::TownTransitionData> TownTransition = App.TownMapScene->Update(KeyboardState))
            {
                const bool IsLeftEdgeTransition = (TownTransition->Flags & 1) != 0;
                Mdt::TownMapInfo DestinationTownMap;
                std::filesystem::path DestinationTownNpcSpriteGrpPath = App.TownNpcSpriteGrpPath;
                Grp::PatternBank DestinationTownPatternBank;
                if (LoadTownMap(TownTransition->DestinationMapId, DestinationTownMap, DestinationTownNpcSpriteGrpPath)
                    && LoadTownPatternBank(TownTransition->PatternGroupId, DestinationTownPatternBank))
                {
                    App.TownMap = std::move(DestinationTownMap);
                    App.TownNpcSpriteGrpPath = std::move(DestinationTownNpcSpriteGrpPath);
                    App.TownPatternBank = std::move(DestinationTownPatternBank);
                    if (IsLeftEdgeTransition)
                    {
                        App.TownMapScene->ReloadTownStateAfterLeftEdgeTransition();
                    }
                    else
                    {
                        App.TownMapScene->ReloadTownStateAfterRightEdgeTransition();
                    }

                    App.TownMapTimingAccumulatorNs = 0;
                    App.TownMapTimingLastTicksNs = CurrentTicksNs;
                }
                else
                {
                    std::cerr << "town transition reload failed; staying on the current town." << '\n';
                }

                break;
            }

            App.TownMapTimingAccumulatorNs -= TownScene::TownDosTownLoopIntervalNanoseconds;
        }
    }

    SDL_SetRenderDrawColor(App.Renderer, 12, 18, 12, 255);
    SDL_RenderClear(App.Renderer);

    if (App.TownReady && App.TownMapScene.has_value())
    {
        App.TownMapScene->Draw(App.Renderer);
    }

    SDL_RenderPresent(App.Renderer);
#ifndef __EMSCRIPTEN__
    SDL_Delay(1);
#endif
    return App.Running;
}

void ShutdownZeliardApp(ZeliardApp& App)
{
    if (App.Renderer != nullptr)
    {
        SDL_DestroyRenderer(App.Renderer);
        App.Renderer = nullptr;
    }

    if (App.Window != nullptr)
    {
        SDL_DestroyWindow(App.Window);
        App.Window = nullptr;
    }

    SDL_Quit();
}

#ifdef __EMSCRIPTEN__
void RunZeliardMainLoop(void* UserData)
{
    auto* App = static_cast<ZeliardApp*>(UserData);
    if (App == nullptr || !RunZeliardFrame(*App))
    {
        emscripten_cancel_main_loop();
    }
}
#endif
}

int main()
{
    ZeliardApp App;
    if (!InitializeZeliardApp(App))
    {
        ShutdownZeliardApp(App);
        return 1;
    }

#ifdef __EMSCRIPTEN__
    emscripten_set_main_loop_arg(RunZeliardMainLoop, &App, 0, true);
    return 0;
#else
    while (App.Running)
    {
        if (!RunZeliardFrame(App))
        {
            break;
        }
    }
#endif

    ShutdownZeliardApp(App);
    return 0;
}
