#pragma once

#include <cstdint>
#include <filesystem>
#include <string>
#include <vector>

namespace Grp
{
bool UnpackFile(const std::filesystem::path& Path, std::vector<std::uint8_t>& Output, std::string& ErrorMessage);
}
