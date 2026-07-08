#include "mcga_palette.h"

#include <cctype>
#include <cstdint>
#include <fstream>
#include <initializer_list>
#include <iostream>
#include <sstream>
#include <vector>

namespace
{
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

std::filesystem::path ResolveFirstExistingPath(
    std::initializer_list<std::filesystem::path> CandidatePaths)
{
    for (const std::filesystem::path& CandidatePath : CandidatePaths)
    {
        if (!CandidatePath.empty() && std::filesystem::exists(CandidatePath))
        {
            return CandidatePath;
        }
    }

    if (CandidatePaths.size() == 0)
    {
        return {};
    }

    return *CandidatePaths.begin();
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
}

namespace Mcga
{
bool LoadMain64Palette(const std::filesystem::path& ProjectRoot, Main64Palette& Palette,
    std::string& ErrorMessage)
{
    const std::filesystem::path PalettePath = ResolveFirstExistingPath({
        ProjectRoot / "assets" / "grpviewer" / "v15" / "PALETTE.json",
        ProjectRoot / "tools" / "grpviewer" / "v15" / "PALETTE.json"
    });
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
        while (Cursor < ArrayEnd
            && (CleanText[Cursor] == ',' || std::isspace(static_cast<unsigned char>(CleanText[Cursor]))))
        {
            ++Cursor;
        }

        if (Cursor >= ArrayEnd)
        {
            break;
        }

        if (CleanText[Cursor] != '"')
        {
            ErrorMessage = "main_64 palette contains unexpected text before color "
                + std::to_string(PaletteIndex);
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
            ErrorMessage = "main_64 palette color " + std::to_string(PaletteIndex)
                + " is not a #RRGGBB value";
            return false;
        }

        SDL_Color Color{};
        if (!ParseHexByte(ColorText, 1, Color.r) || !ParseHexByte(ColorText, 3, Color.g)
            || !ParseHexByte(ColorText, 5, Color.b))
        {
            ErrorMessage = "main_64 palette color " + std::to_string(PaletteIndex)
                + " contains invalid hex digits";
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
        ErrorMessage = "main_64 palette contains " + std::to_string(PaletteIndex)
            + " colors instead of 64";
        return false;
    }

    ErrorMessage.clear();
    std::cout << "cpat.grp palette loaded from " << PalettePath.string() << " main_64." << '\n';
    return true;
}
}
