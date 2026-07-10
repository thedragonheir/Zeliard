#include "grp_unpack.hpp"

#include <cstddef>
#include <fstream>

namespace Grp
{
namespace
{
bool ReadWholeFile(const std::filesystem::path& Path, std::vector<std::uint8_t>& Output, std::string& ErrorMessage)
{
    std::ifstream Input(Path, std::ios::binary | std::ios::ate);
    if (!Input)
    {
        ErrorMessage = "failed to open " + Path.string();
        return false;
    }

    const std::streamsize FileSize = Input.tellg();
    if (FileSize < 0)
    {
        ErrorMessage = "failed to determine size of " + Path.string();
        return false;
    }

    Output.resize(static_cast<std::size_t>(FileSize));
    Input.seekg(0, std::ios::beg);
    if (FileSize > 0 && !Input.read(reinterpret_cast<char*>(Output.data()), FileSize))
    {
        ErrorMessage = "failed to read " + Path.string();
        return false;
    }

    return true;
}

bool UnpackBytes(const std::vector<std::uint8_t>& Source, std::vector<std::uint8_t>& Output, std::string& ErrorMessage)
{
    Output.clear();

    if (Source.empty())
    {
        return true;
    }

    std::size_t ReadIndex = 0;
    const std::size_t InputSize = Source.size();

    auto ReadByte = [&](std::uint8_t& Value) -> bool
    {
        if (ReadIndex >= InputSize)
        {
            ErrorMessage = "unexpected end of compressed data";
            return false;
        }

        Value = Source[ReadIndex++];
        return true;
    };

    auto ReadWord = [&](std::uint16_t& Value) -> bool
    {
        std::uint8_t Low = 0;
        std::uint8_t High = 0;
        if (!ReadByte(Low) || !ReadByte(High))
        {
            return false;
        }

        Value = static_cast<std::uint16_t>(Low | (static_cast<std::uint16_t>(High) << 8));
        return true;
    };

    auto WriteRepeatedByte = [&](std::uint8_t Value, std::size_t Count)
    {
        Output.insert(Output.end(), Count, Value);
    };

    std::uint8_t MethodByte = 0;
    if (!ReadByte(MethodByte))
    {
        return false;
    }

    const std::uint8_t Method = MethodByte & 0x07;

    switch (Method)
    {
    case 0:
        Output.insert(Output.end(), Source.begin() + static_cast<std::ptrdiff_t>(ReadIndex), Source.end());
        return true;

    case 1:
    {
        const std::size_t TableIndex = ReadIndex;

        std::uint8_t Terminator = 0;
        do
        {
            if (!ReadByte(Terminator))
            {
                return false;
            }
        }
        while (Terminator != 0xFF);

        while (ReadIndex < InputSize)
        {
            std::uint8_t Value = 0;
            if (!ReadByte(Value))
            {
                return false;
            }

            const std::uint8_t HighNibble = static_cast<std::uint8_t>(Value & 0xF0);
            std::size_t RepeatCount = 1;
            std::size_t TableReadIndex = TableIndex;

            while (true)
            {
                if (TableReadIndex + 1 >= InputSize)
                {
                    ErrorMessage = "malformed method 1 table";
                    return false;
                }

                const std::uint8_t EntryKey = Source[TableReadIndex];
                if ((EntryKey & 0x0F) != 0)
                {
                    break;
                }

                if (HighNibble == EntryKey)
                {
                    RepeatCount = static_cast<std::size_t>(Value & 0x0F) + 2;
                    Value = Source[TableReadIndex + 1];
                    break;
                }

                TableReadIndex += 2;
            }

            WriteRepeatedByte(Value, RepeatCount);
        }

        return true;
    }

    case 2:
    {
        std::uint8_t Marker = 0;
        if (!ReadByte(Marker))
        {
            return false;
        }

        while (ReadIndex < InputSize)
        {
            std::uint8_t Value = 0;
            if (!ReadByte(Value))
            {
                return false;
            }

            std::size_t RepeatCount = 1;
            if ((Value & 0xF0) == Marker)
            {
                RepeatCount = static_cast<std::size_t>(Value & 0x0F) + 3;
                if (!ReadByte(Value))
                {
                    return false;
                }
            }

            WriteRepeatedByte(Value, RepeatCount);
        }

        return true;
    }

    case 3:
    {
        const std::size_t TableIndex = ReadIndex;

        std::uint8_t Terminator = 0;
        do
        {
            if (!ReadByte(Terminator))
            {
                return false;
            }
        }
        while (Terminator != 0xFF);

        while (ReadIndex < InputSize)
        {
            std::uint8_t Value = 0;
            if (!ReadByte(Value))
            {
                return false;
            }

            const std::uint8_t LowNibble = static_cast<std::uint8_t>(Value & 0x0F);
            std::size_t RepeatCount = 1;
            std::size_t TableReadIndex = TableIndex;

            while (true)
            {
                if (TableReadIndex + 1 >= InputSize)
                {
                    ErrorMessage = "malformed method 3 table";
                    return false;
                }

                const std::uint8_t EntryKey = Source[TableReadIndex];
                if ((EntryKey & 0xF0) != 0)
                {
                    break;
                }

                if (LowNibble == EntryKey)
                {
                    RepeatCount = static_cast<std::size_t>(Value >> 4) + 2;
                    Value = Source[TableReadIndex + 1];
                    break;
                }

                TableReadIndex += 2;
            }

            WriteRepeatedByte(Value, RepeatCount);
        }

        return true;
    }

    case 4:
    {
        std::uint8_t Marker = 0;
        if (!ReadByte(Marker))
        {
            return false;
        }

        while (ReadIndex < InputSize)
        {
            std::uint8_t Value = 0;
            if (!ReadByte(Value))
            {
                return false;
            }

            std::size_t RepeatCount = 1;
            if ((Value & 0x0F) == Marker)
            {
                RepeatCount = static_cast<std::size_t>(Value >> 4) + 3;
                if (!ReadByte(Value))
                {
                    return false;
                }
            }

            WriteRepeatedByte(Value, RepeatCount);
        }

        return true;
    }

    case 5:
        while (ReadIndex < InputSize)
        {
            std::uint8_t Value = 0;
            if (!ReadByte(Value))
            {
                return false;
            }

            std::size_t RepeatCount = 1;
            if (ReadIndex + 1 < InputSize && Source[ReadIndex] == Value)
            {
                RepeatCount = static_cast<std::size_t>(Source[ReadIndex + 1]) + 2;
                ReadIndex += 2;
            }

            WriteRepeatedByte(Value, RepeatCount);
        }

        return true;

    case 6:
    {
        const std::size_t TableIndex = ReadIndex;

        std::uint16_t Terminator = 0;
        do
        {
            if (!ReadWord(Terminator))
            {
                return false;
            }
        }
        while (Terminator != 0xFFFF);

        while (ReadIndex < InputSize)
        {
            std::uint8_t Value = 0;
            if (!ReadByte(Value))
            {
                return false;
            }

            std::size_t RepeatCount = 1;
            std::size_t TableReadIndex = TableIndex;

            while (true)
            {
                if (TableReadIndex + 1 >= InputSize)
                {
                    ErrorMessage = "malformed method 6 table";
                    return false;
                }

                const std::uint8_t Low = Source[TableReadIndex];
                const std::uint8_t High = Source[TableReadIndex + 1];
                if (Low == 0xFF && High == 0xFF)
                {
                    break;
                }

                if (Low == Value)
                {
                    if (!ReadByte(Value))
                    {
                        return false;
                    }

                    RepeatCount = static_cast<std::size_t>(Value) + 2;
                    Value = High;
                    break;
                }

                TableReadIndex += 2;
            }

            WriteRepeatedByte(Value, RepeatCount);
        }

        return true;
    }

    case 7:
    {
        std::uint8_t Marker = 0;
        if (!ReadByte(Marker))
        {
            return false;
        }

        while (ReadIndex < InputSize)
        {
            std::uint8_t Value = 0;
            if (!ReadByte(Value))
            {
                return false;
            }

            std::size_t RepeatCount = 1;
            if (Value == Marker)
            {
                if (!ReadByte(Value))
                {
                    return false;
                }

                std::uint8_t RepeatByte = 0;
                if (!ReadByte(RepeatByte))
                {
                    return false;
                }

                RepeatCount = static_cast<std::size_t>(RepeatByte) + 3;
            }

            WriteRepeatedByte(Value, RepeatCount);
        }

        return true;
    }

    default:
        ErrorMessage = "unsupported compression method";
        return false;
    }
}
}

bool UnpackFile(const std::filesystem::path& Path, std::vector<std::uint8_t>& Output, std::string& ErrorMessage)
{
    std::vector<std::uint8_t> Raw;
    if (!ReadWholeFile(Path, Raw, ErrorMessage))
    {
        return false;
    }

    if (Raw.empty())
    {
        ErrorMessage = "empty file";
        return false;
    }

    std::vector<std::uint8_t> Payload;
    std::size_t HeaderLength = 0;
    bool HasHeaderLength = false;

    if (Raw[0] == 0)
    {
        Payload.assign(Raw.begin() + 1, Raw.end());
    }
    else
    {
        if (Raw.size() < 5)
        {
            ErrorMessage = "file is too small to contain a GRP header";
            return false;
        }

        const std::uint16_t Skip = static_cast<std::uint16_t>(Raw[1] | (static_cast<std::uint16_t>(Raw[2]) << 8));
        HeaderLength = static_cast<std::size_t>(Raw[3] | (static_cast<std::uint16_t>(Raw[4]) << 8));
        HasHeaderLength = true;

        const std::size_t PayloadOffset = 5 + Skip;
        if (PayloadOffset > Raw.size())
        {
            ErrorMessage = "GRP payload offset is past the end of the file";
            return false;
        }

        Payload.assign(Raw.begin() + static_cast<std::ptrdiff_t>(PayloadOffset), Raw.end());
    }

    if (HasHeaderLength && Payload.size() != HeaderLength)
    {
        ErrorMessage = "expected " + std::to_string(HeaderLength) + " compressed bytes, got " + std::to_string(Payload.size());
        return false;
    }

    if (!UnpackBytes(Payload, Output, ErrorMessage))
    {
        return false;
    }

    return true;
}
}
