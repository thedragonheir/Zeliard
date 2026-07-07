# Zeliard C++ Port

Unofficial C++ port/reimplementation of **Zeliard**, focused on faithfully recreating the original DOS behavior, rendering, data formats and gameplay systems using the original game assets.

This project is a preservation-focused C++23 + SDL3 port of the 1989 DOS game **Zeliard**. The goal is not to modernize the game randomly, but to understand how the original works and rebuild it cleanly with accurate behavior.

## Status

Work in progress.

Current focus:

- SDL3 startup and rendering
- 320x200 internal logical resolution
- 960x600 window output
- Original GRP decoding
- Palette handling
- SAR/archive support
- Town rendering and movement behavior
- Documentation of original data formats and engine behavior

## Goals

- Recreate the original DOS gameplay behavior as faithfully as possible
- Decode and use the original `.SAR` and `.GRP` data formats
- Keep the code small, readable and project-owned
- Use C++23 and SDL3 only, no large game engine
- Document findings while reverse engineering the original data and assembly

## Project structure

```text
asm/        Original assembly sources and reverse engineering references
assets/     Extracted or converted game assets
docs/       Project notes and format documentation
game/       Original game data and binaries used for analysis
src/        C++23 source code
tools/      Python tools for inspecting and extracting game data
out/        Generated CMake build output
```

## Build

Configure debug build:

```cmd
cmake --preset x64-debug
```

Build debug:

```cmd
cmake --build --preset x64-debug
```

Run:

```cmd
out\build\x64-debug\Zeliard.exe
```

Configure release build:

```cmd
cmake --preset x64-release
```

## Requirements

- C++23 compatible compiler
- CMake
- SDL3
- Windows development environment

## Original assets

This port uses original Zeliard game assets and data files for compatibility, preservation, research and faithful reimplementation purposes.

Original Zeliard assets, data files, binaries, graphics, music, sound, `.SAR` files, `.GRP` files, names and trademarks remain the property of their respective rights holders.

## License

The project-owned source code, tools and documentation are licensed under the MIT License.

See [`LICENSE`](LICENSE) for details.
