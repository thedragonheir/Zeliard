#include <SDL3/SDL.h>

#include "grp/grp_font.h"
#include "grp/grp_pattern_bank.h"
#include "grp/grp_sprite_sheet.h"
#include "grp/grp_unpacker.h"
#include "mdt/mdt_map.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#include "town/town_scene.h"

namespace
{
const std::filesystem::path ProjectRoot = ZELIARD_PROJECT_ROOT;
constexpr std::uint64_t SpriteAnimationFrameDelayMs = 160;
constexpr std::size_t TownMapMaxCatchUpSteps = 4;

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
        std::cout << "active view mode: cmap.mdt town map" << '\n';
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

bool LoadTownMap(Mdt::TownMapInfo& TownMap, std::filesystem::path& TownNpcSpriteGrpPath)
{
    const std::filesystem::path MdtPath = ProjectRoot / "tools" / "cmap.mdt";
    std::vector<std::uint8_t> FileBytes;
    std::string ErrorMessage;
    if (!ReadWholeFile(MdtPath, FileBytes))
    {
        std::cerr << "cmap.mdt load failed: failed to open " << MdtPath.string() << std::endl;
        return false;
    }

    Mdt::TownMapInfo MapInfo;
    if (!Mdt::ParseTownMap(FileBytes, MapInfo, ErrorMessage))
    {
        std::cerr << "cmap.mdt parse failed: " << ErrorMessage << std::endl;
        return false;
    }

    std::cout << "cmap.mdt parsed: " << MdtPath.string() << ", width " << MapInfo.Width
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
}

int main()
{
    const bool ValidationMatch = ValidateGrpUnpack();
    if (!ValidationMatch)
    {
        std::cerr << "cpat.grp unpack validation failed; continuing anyway." << '\n';
    }

    Mdt::TownMapInfo TownMap;
    std::filesystem::path TownNpcSpriteGrpPath = ProjectRoot / "game" / "0" / "mman.grp";
    const bool TownMapLoaded = LoadTownMap(TownMap, TownNpcSpriteGrpPath);
    if (!TownMapLoaded)
    {
        std::cerr << "cmap.mdt parse validation failed; continuing anyway." << '\n';
    }
    else
    {
        std::cout << "cmap.mdt town NPC sprite group selected: " << TownNpcSpriteGrpPath.filename().string() << '\n';
    }

    Grp::PatternBank PatternBank;
    const bool PatternBankLoaded = LoadPatternBank(PatternBank);

    Grp::SpriteSheetSummary SpriteSheet;
    const bool SpriteSheetLoaded = LoadNpcSpriteSheetSummary(SpriteSheet);
    if (!SpriteSheetLoaded)
    {
        std::cerr << "mman.grp sprite validation failed; continuing anyway." << '\n';
    }

    const std::filesystem::path TownActorSpriteGrpPath = ProjectRoot / "game" / "0" / "tman.grp";
    std::size_t ActiveSpriteBankIndex = 0;
    SpriteViewFrame CurrentSpriteFrame;
    std::size_t CurrentSpriteFrameIndex = 0;
    SpriteFrameLoadState CurrentSpriteFrameLoadState = SpriteFrameLoadState::Miss;
    std::string SpriteFrameLoadErrorMessage;
    LoadSpriteFrameForView(SpriteBankDefinitions[ActiveSpriteBankIndex], CurrentSpriteFrameIndex,
        CurrentSpriteFrame, CurrentSpriteFrameLoadState, SpriteFrameLoadErrorMessage);
    if (CurrentSpriteFrameLoadState == SpriteFrameLoadState::Miss)
    {
        std::cerr << SpriteBankDefinitions[ActiveSpriteBankIndex].FileName << " sprite frame 0 load failed: "
                  << SpriteFrameLoadErrorMessage << '\n';
    }
    else
    {
        std::cout << SpriteBankDefinitions[ActiveSpriteBankIndex].FileName
                  << " sprite frame 0 loaded: frame " << CurrentSpriteFrame.Width << "x"
                  << CurrentSpriteFrame.Height << ", state "
                  << GetSpriteFrameLoadStateName(CurrentSpriteFrameLoadState) << "." << '\n';
    }
    Main64Palette Palette{};
    std::string PaletteErrorMessage;
    const bool PaletteLoaded = LoadMain64Palette(Palette, PaletteErrorMessage);
    if (!PaletteLoaded)
    {
        std::cerr << "cpat.grp palette load failed: " << PaletteErrorMessage << '\n';
    }
    else
    {
        std::cout << "cpat.grp palette loaded from tools/grpviewer/v15/PALETTE.json main_64." << '\n';
    }

    TownScene TownMapScene(TownActorSpriteGrpPath, TownNpcSpriteGrpPath, TownMap, PatternBank, Palette);

    const bool CpatViewAvailable = PatternBankLoaded && PaletteLoaded;
    const bool TownMapViewAvailable = TownMapLoaded && PatternBankLoaded && PaletteLoaded;
    const bool SpriteViewAvailable = PaletteLoaded;
    std::string CpatViewUnavailableMessage;
    if (!PatternBankLoaded)
    {
        CpatViewUnavailableMessage = "pattern bank decode failed";
    }
    else if (!PaletteLoaded)
    {
        CpatViewUnavailableMessage = PaletteErrorMessage;
    }

    std::string TownMapViewUnavailableMessage;
    if (!TownMapLoaded)
    {
        TownMapViewUnavailableMessage = "town map parse failed";
    }
    else if (!PatternBankLoaded)
    {
        TownMapViewUnavailableMessage = "pattern bank decode failed";
    }
    else if (!PaletteLoaded)
    {
        TownMapViewUnavailableMessage = PaletteErrorMessage;
    }

    std::string SpriteViewUnavailableMessage;
    if (!PaletteLoaded)
    {
        SpriteViewUnavailableMessage = PaletteErrorMessage;
    }

    std::array<Grp::FontGroup, 3> FontGroups{};
    std::array<bool, 3> FontGroupAvailable{};
    const bool FontLoaded = LoadFontGroups(FontGroups, FontGroupAvailable);
    std::size_t ActiveFontGroupIndex = 0;
    ViewMode ActiveViewMode = ViewMode::Font;
    bool DebugOverlayEnabled = true;
    bool SpriteAnimationEnabled = false;
    std::uint64_t LastSpriteAnimationTick = 0;
    ViewMode LastTownViewMode = ActiveViewMode;
    std::uint64_t TownMapTimingLastTicksNs = 0;
    std::uint64_t TownMapTimingAccumulatorNs = 0;

    if (FontLoaded && !FontGroupAvailable[ActiveFontGroupIndex])
    {
        for (std::size_t GroupIndex = 0; GroupIndex < FontGroupAvailable.size(); ++GroupIndex)
        {
            if (FontGroupAvailable[GroupIndex])
            {
                ActiveFontGroupIndex = GroupIndex;
                break;
            }
        }
    }

    if (!SDL_Init(SDL_INIT_VIDEO))
    {
        std::cerr << "SDL_Init failed: " << SDL_GetError() << '\n';
        return 1;
    }

    SDL_Window* Window = SDL_CreateWindow("Zeliard", 960, 600, 0);
    if (!Window)
    {
        std::cerr << "SDL_CreateWindow failed: " << SDL_GetError() << '\n';
        SDL_Quit();
        return 1;
    }

    SDL_Renderer* Renderer = SDL_CreateRenderer(Window, nullptr);
    if (!Renderer)
    {
        std::cerr << "SDL_CreateRenderer failed: " << SDL_GetError() << '\n';
        SDL_DestroyWindow(Window);
        SDL_Quit();
        return 1;
    }

    if (!SDL_SetRenderLogicalPresentation(Renderer, 320, 200, SDL_LOGICAL_PRESENTATION_LETTERBOX))
    {
        std::cerr << "SDL_SetRenderLogicalPresentation failed: " << SDL_GetError() << '\n';
        SDL_DestroyRenderer(Renderer);
        SDL_DestroyWindow(Window);
        SDL_Quit();
        return 1;
    }

    bool Running = true;
    while (Running)
    {
        SDL_Event Event;
        while (SDL_PollEvent(&Event))
        {
            if (Event.type == SDL_EVENT_QUIT)
            {
                Running = false;
            }
            else if (Event.type == SDL_EVENT_KEY_DOWN && Event.key.key == SDLK_ESCAPE)
            {
                Running = false;
            }
            else if (Event.type == SDL_EVENT_KEY_DOWN && !Event.key.repeat)
            {
                if (Event.key.key == SDLK_F)
                {
                    if (ActiveViewMode != ViewMode::Font)
                    {
                        ActiveViewMode = ViewMode::Font;
                        PrintActiveViewMode(ActiveViewMode);
                        if (FontLoaded && ActiveFontGroupIndex < FontGroupAvailable.size() && FontGroupAvailable[ActiveFontGroupIndex])
                        {
                            PrintActiveFontGroup(ActiveFontGroupIndex, FontGroups[ActiveFontGroupIndex]);
                        }
                    }
                }
                else if (Event.key.key == SDLK_D)
                {
                    DebugOverlayEnabled = !DebugOverlayEnabled;
                    PrintDebugOverlayState(DebugOverlayEnabled);
                }
                else if (Event.key.key == SDLK_T && ActiveViewMode == ViewMode::TownMap)
                {
                    TownMapScene.ToggleBlockedTileOverlay();
                    PrintTownMapBlockedTileOverlayState(TownMapScene.IsBlockedTileOverlayEnabled());
                }
                else if (Event.key.key == SDLK_O && ActiveViewMode == ViewMode::TownMap)
                {
                    TownMapScene.ToggleTownEntityMarkers();
                    PrintTownMapEntityMarkerState(TownMapScene.IsTownEntityMarkersEnabled());
                }
                else if (Event.key.key == SDLK_Y && ActiveViewMode == ViewMode::TownMap)
                {
                    TownMapScene.ToggleTearsOverlayDebugOverride();
                    PrintTownTearsOverlayDebugOverrideState(TownMapScene.IsTearsOverlayDebugOverrideEnabled());
                }
                else if (Event.key.key == SDLK_C)
                {
                    if (CpatViewAvailable)
                    {
                        if (ActiveViewMode != ViewMode::Cpat)
                        {
                            ActiveViewMode = ViewMode::Cpat;
                            PrintActiveViewMode(ActiveViewMode);
                        }
                    }
                    else
                    {
                        std::cerr << "cpat.grp tile grid unavailable: " << CpatViewUnavailableMessage << '\n';
                    }
                }
                else if (Event.key.key == SDLK_M)
                {
                    if (TownMapViewAvailable)
                    {
                        if (ActiveViewMode != ViewMode::TownMap)
                        {
                            ActiveViewMode = ViewMode::TownMap;
                            PrintActiveViewMode(ActiveViewMode);
                        }
                    }
                    else
                    {
                        std::cerr << "cmap.mdt town map unavailable: " << TownMapViewUnavailableMessage << '\n';
                    }
                }
                else if (Event.key.key == SDLK_S)
                {
                    if (SpriteViewAvailable)
                    {
                        if (ActiveViewMode != ViewMode::Sprite)
                        {
                            ActiveViewMode = ViewMode::Sprite;
                            PrintActiveViewMode(ActiveViewMode);
                        }
                    }
                    else
                    {
                        std::cerr << "sprite viewer unavailable: " << SpriteViewUnavailableMessage << '\n';
                    }
                }
                else if (ActiveViewMode == ViewMode::Sprite)
                {
                    if (Event.key.key == SDLK_G)
                    {
                        ActiveSpriteBankIndex = (ActiveSpriteBankIndex + 1) % SpriteBankDefinitions.size();
                        CurrentSpriteFrameIndex = 0;
                        LoadSpriteFrameForView(SpriteBankDefinitions[ActiveSpriteBankIndex], CurrentSpriteFrameIndex,
                            CurrentSpriteFrame, CurrentSpriteFrameLoadState, SpriteFrameLoadErrorMessage);
                        LastSpriteAnimationTick = SDL_GetTicks();
                        PrintActiveSpriteBank(SpriteBankDefinitions[ActiveSpriteBankIndex]);
                        if (CurrentSpriteFrameLoadState == SpriteFrameLoadState::Miss)
                        {
                            std::cerr << SpriteBankDefinitions[ActiveSpriteBankIndex].FileName
                                      << " sprite frame " << CurrentSpriteFrameIndex
                                      << " load failed: " << SpriteFrameLoadErrorMessage << '\n';
                        }
                    }
                    else if (Event.key.key == SDLK_SPACE)
                    {
                        SpriteAnimationEnabled = !SpriteAnimationEnabled;
                        LastSpriteAnimationTick = SDL_GetTicks();
                        PrintSpriteAnimationState(SpriteAnimationEnabled);
                    }
                    else if (Event.key.key == SDLK_LEFT || Event.key.key == SDLK_RIGHT)
                    {
                        const SpriteBankDefinition& ActiveSpriteBank = SpriteBankDefinitions[ActiveSpriteBankIndex];
                        std::size_t RequestedSpriteFrameIndex = CurrentSpriteFrameIndex;
                        if (Event.key.key == SDLK_LEFT)
                        {
                            RequestedSpriteFrameIndex = RequestedSpriteFrameIndex == 0
                                ? ActiveSpriteBank.FrameCount - 1
                                : RequestedSpriteFrameIndex - 1;
                        }
                        else
                        {
                            RequestedSpriteFrameIndex = RequestedSpriteFrameIndex + 1 >= ActiveSpriteBank.FrameCount
                                ? 0
                                : RequestedSpriteFrameIndex + 1;
                        }

                        CurrentSpriteFrameIndex = RequestedSpriteFrameIndex;
                        LoadSpriteFrameForView(ActiveSpriteBank, CurrentSpriteFrameIndex,
                            CurrentSpriteFrame, CurrentSpriteFrameLoadState, SpriteFrameLoadErrorMessage);
                        LastSpriteAnimationTick = SDL_GetTicks();
                        if (CurrentSpriteFrameLoadState == SpriteFrameLoadState::Miss)
                        {
                            std::cerr << ActiveSpriteBank.FileName
                                      << " sprite frame " << CurrentSpriteFrameIndex
                                      << " load failed: " << SpriteFrameLoadErrorMessage << '\n';
                        }
                    }
                }
                else if (ActiveViewMode == ViewMode::Font)
                {
                    std::size_t RequestedGroupIndex = 0;
                    bool HasSelection = true;

                    if (Event.key.key == SDLK_1)
                    {
                        RequestedGroupIndex = 0;
                    }
                    else if (Event.key.key == SDLK_2)
                    {
                        RequestedGroupIndex = 1;
                    }
                    else if (Event.key.key == SDLK_3)
                    {
                        RequestedGroupIndex = 2;
                    }
                    else
                    {
                        HasSelection = false;
                    }

                    if (HasSelection && RequestedGroupIndex < FontGroupAvailable.size() && FontGroupAvailable[RequestedGroupIndex] && RequestedGroupIndex != ActiveFontGroupIndex)
                    {
                        ActiveFontGroupIndex = RequestedGroupIndex;
                        PrintActiveFontGroup(ActiveFontGroupIndex, FontGroups[ActiveFontGroupIndex]);
                    }
                }
            }
        }

        const std::uint64_t CurrentTicksNs = SDL_GetTicksNS();
        if (ActiveViewMode != LastTownViewMode)
        {
            if (ActiveViewMode == ViewMode::TownMap)
            {
                TownMapTimingLastTicksNs = CurrentTicksNs;
                TownMapTimingAccumulatorNs = TownScene::TownDosTownLoopIntervalNanoseconds;
            }
            else if (LastTownViewMode == ViewMode::TownMap)
            {
                TownMapTimingLastTicksNs = 0;
                TownMapTimingAccumulatorNs = 0;
            }

            LastTownViewMode = ActiveViewMode;
        }

        if (ActiveViewMode == ViewMode::TownMap)
        {
            if (TownMapViewAvailable)
            {
                const bool* KeyboardState = SDL_GetKeyboardState(nullptr);
                if (TownMapTimingLastTicksNs == 0)
                {
                    TownMapTimingLastTicksNs = CurrentTicksNs;
                    TownMapTimingAccumulatorNs = TownScene::TownDosTownLoopIntervalNanoseconds;
                }
                else
                {
                    TownMapTimingAccumulatorNs += CurrentTicksNs - TownMapTimingLastTicksNs;
                    TownMapTimingLastTicksNs = CurrentTicksNs;
                }

                // Advance town gameplay on the DOS cadence while still redrawing every frame.
                std::size_t TownMapUpdatesThisFrame = 0;
                while (TownMapTimingAccumulatorNs >= TownScene::TownDosTownLoopIntervalNanoseconds
                    && TownMapUpdatesThisFrame < TownMapMaxCatchUpSteps)
                {
                    TownMapScene.Update(KeyboardState);
                    TownMapTimingAccumulatorNs -= TownScene::TownDosTownLoopIntervalNanoseconds;
                    ++TownMapUpdatesThisFrame;
                }

                if (TownMapUpdatesThisFrame == TownMapMaxCatchUpSteps
                    && TownMapTimingAccumulatorNs >= TownScene::TownDosTownLoopIntervalNanoseconds)
                {
                    TownMapTimingAccumulatorNs = 0;
                }
            }
        }
        else if (ActiveViewMode == ViewMode::Sprite && SpriteAnimationEnabled)
        {
            const std::uint64_t CurrentTick = SDL_GetTicks();
            if (LastSpriteAnimationTick == 0)
            {
                LastSpriteAnimationTick = CurrentTick;
            }

            const std::uint64_t ElapsedTicks = CurrentTick - LastSpriteAnimationTick;
            if (ElapsedTicks >= SpriteAnimationFrameDelayMs)
            {
                const SpriteBankDefinition& ActiveSpriteBank = SpriteBankDefinitions[ActiveSpriteBankIndex];
                const std::size_t FrameStep = static_cast<std::size_t>(ElapsedTicks / SpriteAnimationFrameDelayMs);
                CurrentSpriteFrameIndex = (CurrentSpriteFrameIndex + FrameStep) % ActiveSpriteBank.FrameCount;
                LastSpriteAnimationTick += static_cast<std::uint64_t>(FrameStep) * SpriteAnimationFrameDelayMs;
                LoadSpriteFrameForView(ActiveSpriteBank, CurrentSpriteFrameIndex,
                    CurrentSpriteFrame, CurrentSpriteFrameLoadState, SpriteFrameLoadErrorMessage);
            }
        }

        if (ActiveViewMode == ViewMode::Font)
        {
            if (FontLoaded)
            {
                SDL_SetRenderDrawColor(Renderer, 16, 24, 32, 255);
            }
            else
            {
                SDL_SetRenderDrawColor(Renderer, 48, 16, 16, 255);
            }
        }
        else if (ActiveViewMode == ViewMode::TownMap)
        {
            SDL_SetRenderDrawColor(Renderer, 10, 14, 18, 255);
        }
        else if (ActiveViewMode == ViewMode::Sprite)
        {
            SDL_SetRenderDrawColor(Renderer, 16, 14, 20, 255);
        }
        else
        {
            SDL_SetRenderDrawColor(Renderer, 12, 18, 12, 255);
        }
        SDL_RenderClear(Renderer);

        if (ActiveViewMode == ViewMode::Font)
        {
            if (FontLoaded && ActiveFontGroupIndex < FontGroupAvailable.size() && FontGroupAvailable[ActiveFontGroupIndex])
            {
                DrawFontGlyphGrid(Renderer, FontGroups[ActiveFontGroupIndex]);
            }
        }
        else if (ActiveViewMode == ViewMode::TownMap)
        {
            if (TownMapViewAvailable)
            {
                const Grp::FontGroup* DebugFontGroup = FontLoaded ? GetDebugFontGroup(FontGroups, FontGroupAvailable) : nullptr;

                TownMapScene.Draw(Renderer, DebugFontGroup, DebugOverlayEnabled);
            }
        }
        else if (ActiveViewMode == ViewMode::Sprite)
        {
            if (SpriteViewAvailable)
            {
                const Grp::FontGroup* DebugFontGroup = FontLoaded ? GetDebugFontGroup(FontGroups, FontGroupAvailable) : nullptr;

                DrawSpriteFrameView(Renderer, SpriteBankDefinitions[ActiveSpriteBankIndex], CurrentSpriteFrame,
                    CurrentSpriteFrameIndex, CurrentSpriteFrameLoadState, SpriteAnimationEnabled,
                    Palette, DebugFontGroup, DebugOverlayEnabled);
            }
        }
        else if (CpatViewAvailable)
        {
            DrawPatternBankGrid(Renderer, PatternBank, Palette);
        }

        SDL_RenderPresent(Renderer);
        SDL_Delay(1);
    }

    SDL_DestroyRenderer(Renderer);
    SDL_DestroyWindow(Window);
    SDL_Quit();
    return 0;
}
