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

namespace
{
const std::filesystem::path ProjectRoot = ZELIARD_PROJECT_ROOT;
constexpr std::size_t TownMapTileSize = 8;
constexpr std::size_t TownMapVisibleColumns = 320 / TownMapTileSize;
constexpr std::size_t TownMapViewportWidth = 320;
constexpr std::size_t SpriteFrameCount = 40;
constexpr std::size_t SpriteFrameMaximumIndex = SpriteFrameCount - 1;
constexpr std::size_t TownMapActorAnimationFrameDelay = 8;
constexpr std::size_t TownMapActorAnimationPhaseCount = 4;
constexpr std::size_t TownMapActorFramesPerBlock = 8;
constexpr std::size_t TownMapActorIdleBlockIndex = 1;
// The repo notes confirm the five 8-frame families, but not the exact
// direction order. Keep the block mapping isolated here until that is firmed up.
constexpr std::size_t TownMapActorRightBlockIndex = 0;
constexpr std::size_t TownMapActorLeftBlockIndex = 2;
constexpr std::size_t TownMapActorUpBlockIndex = 3;
constexpr std::size_t TownMapActorDownBlockIndex = 4;
constexpr std::size_t TownMapActorInitialMapPixelX = 160;
constexpr std::size_t TownMapActorInitialMapPixelY = 40;

enum class TownMapActorFacingDirection
{
    Right,
    Left,
    Up,
    Down
};

enum class ViewMode
{
    Font,
    Cpat,
    TownMap,
    Sprite
};

using Main64Palette = std::array<SDL_Color, 64>;

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
        std::cout << "active view mode: mman.grp sprite test" << '\n';
        break;
    }
}

const char* GetTownMapActorFacingDirectionName(TownMapActorFacingDirection FacingDirection)
{
    switch (FacingDirection)
    {
    case TownMapActorFacingDirection::Right:
        return "RIGHT";

    case TownMapActorFacingDirection::Left:
        return "LEFT";

    case TownMapActorFacingDirection::Up:
        return "UP";

    case TownMapActorFacingDirection::Down:
        return "DOWN";
    }

    return "UNKNOWN";
}

const char* GetTownMapCameraFollowModeName(bool CameraFollowEnabled)
{
    return CameraFollowEnabled ? "AUTO" : "MANUAL";
}

std::size_t GetTownMapActorAnimationBlockIndex(TownMapActorFacingDirection FacingDirection)
{
    switch (FacingDirection)
    {
    case TownMapActorFacingDirection::Right:
        return TownMapActorRightBlockIndex;

    case TownMapActorFacingDirection::Left:
        return TownMapActorLeftBlockIndex;

    case TownMapActorFacingDirection::Up:
        return TownMapActorUpBlockIndex;

    case TownMapActorFacingDirection::Down:
        return TownMapActorDownBlockIndex;
    }

    return TownMapActorIdleBlockIndex;
}

std::size_t GetTownMapActorFrameIndex(TownMapActorFacingDirection FacingDirection, bool ActorIsMoving, std::size_t AnimationPhase)
{
    const std::size_t BlockIndex = GetTownMapActorAnimationBlockIndex(FacingDirection);
    const std::size_t FramePhase = ActorIsMoving ? (AnimationPhase % TownMapActorAnimationPhaseCount) : 0;
    return BlockIndex * TownMapActorFramesPerBlock + FramePhase;
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

bool LoadNpcSpriteFrameForView(const std::filesystem::path& GrpPath, std::size_t FrameIndex, Grp::NpcSpriteFrame& SpriteFrame, std::string& ErrorMessage)
{
    return Grp::LoadNpcSpriteFrame(GrpPath, FrameIndex, SpriteFrame, ErrorMessage);
}

bool LoadTownMap(Mdt::TownMapInfo& TownMap)
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

const Grp::PatternTile& GetFallbackPatternTile()
{
    static const Grp::PatternTile FallbackTile = []
    {
        Grp::PatternTile Tile{};
        for (std::size_t Row = 0; Row < 8; ++Row)
        {
            for (std::size_t Column = 0; Column < 8; ++Column)
            {
                const bool IsBright = ((Row + Column) % 2) == 0;
                Tile.Pixels[Row * 8 + Column] = IsBright ? 63 : 0;
            }
        }
        return Tile;
    }();

    return FallbackTile;
}

void DrawPatternTile(SDL_Renderer* Renderer, const Grp::PatternTile& Tile, const Main64Palette& Palette, float TileX, float TileY, float PixelSize)
{
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

void DrawNpcSpriteFrameOnTownMap(SDL_Renderer* Renderer, const Grp::NpcSpriteFrame& SpriteFrame, const Main64Palette& Palette, float MapPixelX, float MapPixelY, std::size_t ScrollOffsetPixels)
{
    constexpr float SpritePixelSize = 1.0f;
    const float ScreenX = MapPixelX - static_cast<float>(ScrollOffsetPixels);

    for (std::size_t Row = 0; Row < Grp::NpcSpriteFrame::FrameHeight; ++Row)
    {
        for (std::size_t Column = 0; Column < Grp::NpcSpriteFrame::FrameWidth; ++Column)
        {
            const std::uint8_t PaletteIndex = SpriteFrame.Pixels[Row * Grp::NpcSpriteFrame::FrameWidth + Column];
            if (PaletteIndex == 0)
            {
                continue;
            }

            const SDL_Color& Color = Palette[PaletteIndex];
            SDL_SetRenderDrawColor(Renderer, Color.r, Color.g, Color.b, Color.a);

            const SDL_FRect PixelRect{
                ScreenX + static_cast<float>(Column) * SpritePixelSize,
                MapPixelY + static_cast<float>(Row) * SpritePixelSize,
                SpritePixelSize,
                SpritePixelSize
            };
            SDL_RenderFillRect(Renderer, &PixelRect);
        }
    }
}

void DrawNpcSpriteFrameView(SDL_Renderer* Renderer, const Grp::NpcSpriteFrame& SpriteFrame, std::size_t SpriteFrameIndex, const Main64Palette& Palette, const Grp::FontGroup* DebugFontGroup, bool DebugOverlayEnabled)
{
    constexpr float SpritePixelSize = 5.0f;
    const float SpriteWidthPixels = static_cast<float>(Grp::NpcSpriteFrame::FrameWidth) * SpritePixelSize;
    const float SpriteHeightPixels = static_cast<float>(Grp::NpcSpriteFrame::FrameHeight) * SpritePixelSize;
    const float StartX = (320.0f - SpriteWidthPixels) * 0.5f;
    const float StartY = (200.0f - SpriteHeightPixels) * 0.5f;

    for (std::size_t Row = 0; Row < Grp::NpcSpriteFrame::FrameHeight; ++Row)
    {
        for (std::size_t Column = 0; Column < Grp::NpcSpriteFrame::FrameWidth; ++Column)
        {
            const std::uint8_t PaletteIndex = SpriteFrame.Pixels[Row * Grp::NpcSpriteFrame::FrameWidth + Column];
            if (PaletteIndex == 0)
            {
                continue;
            }

            const SDL_Color& Color = Palette[PaletteIndex];
            SDL_SetRenderDrawColor(Renderer, Color.r, Color.g, Color.b, Color.a);

            const SDL_FRect PixelRect{
                StartX + static_cast<float>(Column) * SpritePixelSize,
                StartY + static_cast<float>(Row) * SpritePixelSize,
                SpritePixelSize,
                SpritePixelSize
            };
            SDL_RenderFillRect(Renderer, &PixelRect);
        }
    }

    if (DebugOverlayEnabled && DebugFontGroup != nullptr)
    {
        constexpr float TextScale = 1.0f;
        constexpr float TextStartX = 8.0f;
        constexpr float TextStartY = 8.0f;
        constexpr float LineSpacing = 10.0f;

        DrawFontText(Renderer, *DebugFontGroup, TextStartX, TextStartY, TextScale, "SPR MMAN");
        DrawFontText(Renderer, *DebugFontGroup, TextStartX, TextStartY + LineSpacing, TextScale,
            "FRAME " + std::to_string(SpriteFrameIndex) + " / " + std::to_string(SpriteFrameMaximumIndex));
        DrawFontText(Renderer, *DebugFontGroup, TextStartX, TextStartY + LineSpacing * 2.0f, TextScale, "W 16 H 24");
    }
}

std::size_t GetTownMapMaximumScrollOffset(const Mdt::TownMapInfo& TownMap)
{
    const std::size_t MapWidthPixels = static_cast<std::size_t>(TownMap.Width) * TownMapTileSize;
    return MapWidthPixels > TownMapViewportWidth ? MapWidthPixels - TownMapViewportWidth : 0;
}

std::size_t GetTownMapCameraFollowScrollOffset(const Mdt::TownMapInfo& TownMap, std::size_t ActorMapPixelX)
{
    const std::size_t MaximumScrollOffset = GetTownMapMaximumScrollOffset(TownMap);
    const std::size_t ActorCenterPixelX = ActorMapPixelX + (Grp::NpcSpriteFrame::FrameWidth / 2);
    const std::size_t ViewportCenterPixelX = TownMapViewportWidth / 2;
    const std::size_t DesiredScrollOffset = ActorCenterPixelX > ViewportCenterPixelX ? ActorCenterPixelX - ViewportCenterPixelX : 0;
    return std::min<std::size_t>(DesiredScrollOffset, MaximumScrollOffset);
}

std::size_t GetTownMapMaximumActorMapPixelX(const Mdt::TownMapInfo& TownMap)
{
    const std::size_t MapWidthPixels = static_cast<std::size_t>(TownMap.Width) * TownMapTileSize;
    const std::size_t ActorWidthPixels = Grp::NpcSpriteFrame::FrameWidth;
    return MapWidthPixels > ActorWidthPixels ? MapWidthPixels - ActorWidthPixels : 0;
}

std::size_t GetTownMapMaximumActorMapPixelY(const Mdt::TownMapInfo& TownMap)
{
    const std::size_t MapHeightPixels = static_cast<std::size_t>(TownMap.Height) * TownMapTileSize;
    const std::size_t ActorHeightPixels = Grp::NpcSpriteFrame::FrameHeight;
    return MapHeightPixels > ActorHeightPixels ? MapHeightPixels - ActorHeightPixels : 0;
}

void ClampTownMapActorPosition(const Mdt::TownMapInfo& TownMap, std::size_t& ActorMapPixelX, std::size_t& ActorMapPixelY)
{
    ActorMapPixelX = std::clamp(ActorMapPixelX, std::size_t{0}, GetTownMapMaximumActorMapPixelX(TownMap));
    ActorMapPixelY = std::clamp(ActorMapPixelY, std::size_t{0}, GetTownMapMaximumActorMapPixelY(TownMap));
}

bool MoveTownMapActorPosition(const Mdt::TownMapInfo& TownMap, std::size_t& ActorMapPixelX, std::size_t& ActorMapPixelY,
    const bool* KeyboardState, TownMapActorFacingDirection& ActorFacingDirection)
{
    if (KeyboardState == nullptr)
    {
        return false;
    }

    constexpr std::size_t ActorMoveSpeedPixels = 2;
    const std::size_t MaximumActorMapPixelX = GetTownMapMaximumActorMapPixelX(TownMap);
    const std::size_t MaximumActorMapPixelY = GetTownMapMaximumActorMapPixelY(TownMap);
    bool ActorMoved = false;

    if (KeyboardState[SDL_SCANCODE_J] && !KeyboardState[SDL_SCANCODE_L])
    {
        const std::size_t PreviousActorMapPixelX = ActorMapPixelX;
        ActorMapPixelX = ActorMapPixelX > ActorMoveSpeedPixels ? ActorMapPixelX - ActorMoveSpeedPixels : 0;
        if (ActorMapPixelX != PreviousActorMapPixelX)
        {
            ActorFacingDirection = TownMapActorFacingDirection::Left;
            ActorMoved = true;
        }
    }
    else if (KeyboardState[SDL_SCANCODE_L] && !KeyboardState[SDL_SCANCODE_J])
    {
        const std::size_t PreviousActorMapPixelX = ActorMapPixelX;
        ActorMapPixelX = std::min<std::size_t>(ActorMapPixelX + ActorMoveSpeedPixels, MaximumActorMapPixelX);
        if (ActorMapPixelX != PreviousActorMapPixelX)
        {
            ActorFacingDirection = TownMapActorFacingDirection::Right;
            ActorMoved = true;
        }
    }

    if (KeyboardState[SDL_SCANCODE_I] && !KeyboardState[SDL_SCANCODE_K])
    {
        const std::size_t PreviousActorMapPixelY = ActorMapPixelY;
        ActorMapPixelY = ActorMapPixelY > ActorMoveSpeedPixels ? ActorMapPixelY - ActorMoveSpeedPixels : 0;
        if (ActorMapPixelY != PreviousActorMapPixelY)
        {
            ActorFacingDirection = TownMapActorFacingDirection::Up;
            ActorMoved = true;
        }
    }
    else if (KeyboardState[SDL_SCANCODE_K] && !KeyboardState[SDL_SCANCODE_I])
    {
        const std::size_t PreviousActorMapPixelY = ActorMapPixelY;
        ActorMapPixelY = std::min<std::size_t>(ActorMapPixelY + ActorMoveSpeedPixels, MaximumActorMapPixelY);
        if (ActorMapPixelY != PreviousActorMapPixelY)
        {
            ActorFacingDirection = TownMapActorFacingDirection::Down;
            ActorMoved = true;
        }
    }

    ClampTownMapActorPosition(TownMap, ActorMapPixelX, ActorMapPixelY);
    return ActorMoved;
}

bool UpdateTownMapActorFrame(const std::filesystem::path& SpriteGrpPath, std::size_t DesiredActorFrameIndex,
    std::size_t& ActorFrameIndex, std::size_t& ActorAnimationTickCount, Grp::NpcSpriteFrame& ActorFrame)
{
    if (DesiredActorFrameIndex == ActorFrameIndex)
    {
        return true;
    }

    Grp::NpcSpriteFrame RequestedActorFrame;
    std::string RequestedActorFrameErrorMessage;
    if (!LoadNpcSpriteFrameForView(SpriteGrpPath, DesiredActorFrameIndex, RequestedActorFrame, RequestedActorFrameErrorMessage))
    {
        return false;
    }

    ActorFrameIndex = DesiredActorFrameIndex;
    ActorFrame = std::move(RequestedActorFrame);
    ActorAnimationTickCount = 0;
    return true;
}

void DrawTownMapView(SDL_Renderer* Renderer, const Mdt::TownMapInfo& TownMap, const Grp::PatternBank& PatternBank,
    const Main64Palette& Palette, bool& FallbackWarningPrinted, std::size_t ScrollOffsetPixels,
    const Grp::NpcSpriteFrame* ActorFrame, std::size_t ActorFrameIndex, TownMapActorFacingDirection ActorFacingDirection,
    std::size_t ActorMapPixelX, std::size_t ActorMapPixelY, const Grp::FontGroup* DebugFontGroup, bool DebugOverlayEnabled,
    bool CameraFollowEnabled)
{
    constexpr std::size_t TileSize = TownMapTileSize;
    constexpr std::size_t VisibleColumns = TownMapVisibleColumns;
    const std::size_t MaximumScrollOffset = GetTownMapMaximumScrollOffset(TownMap);
    const std::size_t ClampedScrollOffset = std::min<std::size_t>(ScrollOffsetPixels, MaximumScrollOffset);
    const std::size_t FirstColumn = ClampedScrollOffset / TileSize;
    const std::size_t ColumnPixelOffset = ClampedScrollOffset % TileSize;
    const std::size_t ColumnsAvailable = TownMap.Width > FirstColumn ? TownMap.Width - FirstColumn : 0;
    const std::size_t ColumnsToRender = std::min<std::size_t>(ColumnsAvailable, VisibleColumns + (ColumnPixelOffset != 0 ? 1 : 0));
    const std::size_t RowsToRender = TownMap.Height;
    const Grp::PatternTile& FallbackTile = GetFallbackPatternTile();

    for (std::size_t Column = 0; Column < ColumnsToRender; ++Column)
    {
        const std::size_t MapColumn = FirstColumn + Column;
        const float TileX = static_cast<float>(Column * TileSize) - static_cast<float>(ColumnPixelOffset);
        for (std::size_t Row = 0; Row < RowsToRender; ++Row)
        {
            const std::size_t CellIndex = MapColumn * TownMap.Height + Row;
            if (CellIndex >= TownMap.Cells.size())
            {
                continue;
            }

            const std::uint8_t TileIndex = TownMap.Cells[CellIndex];
            const Grp::PatternTile* Tile = nullptr;
            if (TileIndex < PatternBank.Tiles.size())
            {
                Tile = &PatternBank.Tiles[TileIndex];
            }
            else
            {
                if (!FallbackWarningPrinted)
                {
                    std::cerr << "cmap.mdt tile at column " << MapColumn << ", row " << Row
                              << " uses tile index " << static_cast<int>(TileIndex)
                              << " outside the cpat.grp pattern bank; drawing fallback tiles." << '\n';
                    FallbackWarningPrinted = true;
                }

                Tile = &FallbackTile;
            }

            DrawPatternTile(Renderer, *Tile, Palette, TileX, static_cast<float>(Row * TileSize), 1.0f);
        }
    }

    if (ActorFrame != nullptr)
    {
        DrawNpcSpriteFrameOnTownMap(Renderer, *ActorFrame, Palette, static_cast<float>(ActorMapPixelX),
            static_cast<float>(ActorMapPixelY), ClampedScrollOffset);
    }

    if (DebugOverlayEnabled && DebugFontGroup != nullptr)
    {
        constexpr float TextScale = 2.0f;
        constexpr float StartX = 8.0f;
        constexpr float StartY = 72.0f;
        constexpr float LineSpacing = 16.0f;

        DrawFontText(Renderer, *DebugFontGroup, StartX, StartY, TextScale, "ACTOR MMAN");
        DrawFontText(Renderer, *DebugFontGroup, StartX, StartY + LineSpacing, TextScale,
            "FRAME " + std::to_string(ActorFrameIndex) + " / " + std::to_string(SpriteFrameMaximumIndex));
        DrawFontText(Renderer, *DebugFontGroup, StartX, StartY + LineSpacing * 2.0f, TextScale,
            "DIR " + std::string(GetTownMapActorFacingDirectionName(ActorFacingDirection)));
        DrawFontText(Renderer, *DebugFontGroup, StartX, StartY + LineSpacing * 3.0f, TextScale,
            "CAM " + std::string(GetTownMapCameraFollowModeName(CameraFollowEnabled)));
        DrawFontText(Renderer, *DebugFontGroup, StartX, StartY + LineSpacing * 4.0f, TextScale,
            "X " + std::to_string(ClampedScrollOffset) + " / " + std::to_string(MaximumScrollOffset));
        DrawFontText(Renderer, *DebugFontGroup, StartX, StartY + LineSpacing * 5.0f, TextScale,
            "AX " + std::to_string(ActorMapPixelX) + " AY " + std::to_string(ActorMapPixelY));
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
    const bool TownMapLoaded = LoadTownMap(TownMap);
    if (!TownMapLoaded)
    {
        std::cerr << "cmap.mdt parse validation failed; continuing anyway." << '\n';
    }

    Grp::PatternBank PatternBank;
    const bool PatternBankLoaded = LoadPatternBank(PatternBank);

    Grp::SpriteSheetSummary SpriteSheet;
    const bool SpriteSheetLoaded = LoadNpcSpriteSheetSummary(SpriteSheet);
    if (!SpriteSheetLoaded)
    {
        std::cerr << "mman.grp sprite validation failed; continuing anyway." << '\n';
    }

    const std::filesystem::path SpriteGrpPath = ProjectRoot / "tools" / "grpviewer" / "mman.grp";
    Grp::NpcSpriteFrame CurrentSpriteFrame;
    std::size_t CurrentSpriteFrameIndex = 0;
    std::string SpriteFrameLoadErrorMessage;
    const bool SpriteFrameLoaded = LoadNpcSpriteFrameForView(SpriteGrpPath, CurrentSpriteFrameIndex, CurrentSpriteFrame, SpriteFrameLoadErrorMessage);
    if (!SpriteFrameLoaded)
    {
        std::cerr << "mman.grp sprite frame 0 load failed: " << SpriteFrameLoadErrorMessage << '\n';
    }
    else
    {
        std::cout << "mman.grp sprite frame 0 loaded: source " << SpriteGrpPath.string()
                  << ", frame " << Grp::NpcSpriteFrame::FrameWidth << "x"
                  << Grp::NpcSpriteFrame::FrameHeight << "." << '\n';
    }
    TownMapActorFacingDirection TownMapActorFacingDirectionState = TownMapActorFacingDirection::Right;
    std::size_t TownMapActorAnimationPhase = 0;
    Grp::NpcSpriteFrame TownMapActorFrame;
    std::size_t TownMapActorFrameIndex = GetTownMapActorFrameIndex(TownMapActorFacingDirectionState, false, TownMapActorAnimationPhase);
    std::string TownMapActorFrameLoadErrorMessage;
    const bool TownMapActorFrameLoaded = LoadNpcSpriteFrameForView(SpriteGrpPath, TownMapActorFrameIndex, TownMapActorFrame, TownMapActorFrameLoadErrorMessage);
    if (!TownMapActorFrameLoaded)
    {
        std::cerr << "mman.grp town-map actor frame " << TownMapActorFrameIndex
                  << " load failed: " << TownMapActorFrameLoadErrorMessage << '\n';
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

    const bool CpatViewAvailable = PatternBankLoaded && PaletteLoaded;
    const bool TownMapViewAvailable = TownMapLoaded && PatternBankLoaded && PaletteLoaded;
    const bool SpriteViewAvailable = SpriteFrameLoaded && PaletteLoaded;
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
    if (!SpriteFrameLoaded)
    {
        SpriteViewUnavailableMessage = SpriteFrameLoadErrorMessage.empty() ? "sprite frame load failed" : SpriteFrameLoadErrorMessage;
    }
    else if (!PaletteLoaded)
    {
        SpriteViewUnavailableMessage = PaletteErrorMessage;
    }

    std::array<Grp::FontGroup, 3> FontGroups{};
    std::array<bool, 3> FontGroupAvailable{};
    const bool FontLoaded = LoadFontGroups(FontGroups, FontGroupAvailable);
    std::size_t ActiveFontGroupIndex = 0;
    ViewMode ActiveViewMode = ViewMode::Font;
    std::size_t TownMapScrollOffsetPixels = 0;
    bool TownMapFallbackWarningPrinted = false;
    bool DebugOverlayEnabled = true;
    bool TownMapCameraFollowEnabled = true;
    std::size_t TownMapActorAnimationTickCount = 0;

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

    std::size_t TownMapActorMapPixelX = TownMapActorInitialMapPixelX;
    std::size_t TownMapActorMapPixelY = TownMapActorInitialMapPixelY;
    ClampTownMapActorPosition(TownMap, TownMapActorMapPixelX, TownMapActorMapPixelY);

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
                else if (Event.key.key == SDLK_A && ActiveViewMode == ViewMode::TownMap)
                {
                    TownMapCameraFollowEnabled = !TownMapCameraFollowEnabled;
                    std::cout << "town map camera follow " << (TownMapCameraFollowEnabled ? "on" : "off") << '\n';
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
                        std::cerr << "mman.grp sprite test unavailable: " << SpriteViewUnavailableMessage << '\n';
                    }
                }
                else if (ActiveViewMode == ViewMode::Sprite)
                {
                    if (Event.key.key == SDLK_LEFT || Event.key.key == SDLK_RIGHT)
                    {
                        std::size_t RequestedSpriteFrameIndex = CurrentSpriteFrameIndex;
                        if (Event.key.key == SDLK_LEFT)
                        {
                            RequestedSpriteFrameIndex = RequestedSpriteFrameIndex == 0 ? SpriteFrameMaximumIndex : RequestedSpriteFrameIndex - 1;
                        }
                        else
                        {
                            RequestedSpriteFrameIndex = RequestedSpriteFrameIndex == SpriteFrameMaximumIndex ? 0 : RequestedSpriteFrameIndex + 1;
                        }

                        Grp::NpcSpriteFrame RequestedSpriteFrame;
                        std::string RequestedSpriteFrameErrorMessage;
                        if (LoadNpcSpriteFrameForView(SpriteGrpPath, RequestedSpriteFrameIndex, RequestedSpriteFrame, RequestedSpriteFrameErrorMessage))
                        {
                            CurrentSpriteFrameIndex = RequestedSpriteFrameIndex;
                            CurrentSpriteFrame = std::move(RequestedSpriteFrame);
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

        if (ActiveViewMode == ViewMode::TownMap)
        {
            const bool* KeyboardState = SDL_GetKeyboardState(nullptr);
            if (KeyboardState != nullptr)
            {
                constexpr std::size_t ScrollSpeedPixels = 2;
                const std::size_t MaximumScrollOffset = GetTownMapMaximumScrollOffset(TownMap);

                if (TownMapCameraFollowEnabled)
                {
                    TownMapScrollOffsetPixels = GetTownMapCameraFollowScrollOffset(TownMap, TownMapActorMapPixelX);
                }
                else if (KeyboardState[SDL_SCANCODE_LEFT] && !KeyboardState[SDL_SCANCODE_RIGHT])
                {
                    TownMapScrollOffsetPixels = TownMapScrollOffsetPixels > ScrollSpeedPixels ? TownMapScrollOffsetPixels - ScrollSpeedPixels : 0;
                }
                else if (KeyboardState[SDL_SCANCODE_RIGHT] && !KeyboardState[SDL_SCANCODE_LEFT])
                {
                    TownMapScrollOffsetPixels = std::min<std::size_t>(TownMapScrollOffsetPixels + ScrollSpeedPixels, MaximumScrollOffset);
                }

                const TownMapActorFacingDirection PreviousTownMapActorFacingDirection = TownMapActorFacingDirectionState;
                const bool TownMapActorMoved = MoveTownMapActorPosition(TownMap, TownMapActorMapPixelX, TownMapActorMapPixelY,
                    KeyboardState, TownMapActorFacingDirectionState);

                if (TownMapActorMoved)
                {
                    if (TownMapActorFacingDirectionState != PreviousTownMapActorFacingDirection)
                    {
                        TownMapActorAnimationPhase = 0;
                        TownMapActorAnimationTickCount = 0;
                    }
                    else
                    {
                        ++TownMapActorAnimationTickCount;
                        if (TownMapActorAnimationTickCount >= TownMapActorAnimationFrameDelay)
                        {
                            TownMapActorAnimationTickCount = 0;
                            TownMapActorAnimationPhase = (TownMapActorAnimationPhase + 1) % TownMapActorAnimationPhaseCount;
                        }
                    }
                }
                else
                {
                    TownMapActorAnimationTickCount = 0;
                    TownMapActorAnimationPhase = 0;
                }

                const std::size_t DesiredTownMapActorFrameIndex = GetTownMapActorFrameIndex(TownMapActorFacingDirectionState,
                    TownMapActorMoved, TownMapActorAnimationPhase);
                if (TownMapActorFrameLoaded)
                {
                    (void)UpdateTownMapActorFrame(SpriteGrpPath, DesiredTownMapActorFrameIndex, TownMapActorFrameIndex,
                        TownMapActorAnimationTickCount, TownMapActorFrame);
                }
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

                DrawTownMapView(Renderer, TownMap, PatternBank, Palette, TownMapFallbackWarningPrinted,
                    TownMapScrollOffsetPixels, TownMapActorFrameLoaded ? &TownMapActorFrame : nullptr, TownMapActorFrameIndex,
                    TownMapActorFacingDirectionState, TownMapActorMapPixelX, TownMapActorMapPixelY, DebugFontGroup,
                    DebugOverlayEnabled, TownMapCameraFollowEnabled);
            }
        }
        else if (ActiveViewMode == ViewMode::Sprite)
        {
            if (SpriteViewAvailable)
            {
                const Grp::FontGroup* DebugFontGroup = FontLoaded ? GetDebugFontGroup(FontGroups, FontGroupAvailable) : nullptr;

                DrawNpcSpriteFrameView(Renderer, CurrentSpriteFrame, CurrentSpriteFrameIndex, Palette, DebugFontGroup, DebugOverlayEnabled);
            }
        }
        else if (CpatViewAvailable)
        {
            DrawPatternBankGrid(Renderer, PatternBank, Palette);
        }

        SDL_RenderPresent(Renderer);
        SDL_Delay(16);
    }

    SDL_DestroyRenderer(Renderer);
    SDL_DestroyWindow(Window);
    SDL_Quit();
    return 0;
}
