# Zeliard C++ Port

Unofficial C++23 + SDL3 port/reimplementation of **Zeliard**, focused on faithfully recreating the original DOS behavior, rendering, data formats and gameplay systems using the original game assets.

This project is preservation-focused. The goal is not to modernize the game randomly, but to understand how the original works and rebuild it cleanly with accurate behavior.

## Current State

The current runtime is a town-first SDL3 build. The app boots, loads the original data files, decodes town GRP/MDT content, renders the town viewport at a 320x200 logical resolution, and drives the Muralla town flow with assembly-backed horizontal movement, scrolling, edge transitions, and NPC behavior.

The native entry point is [`src/zeliard.cpp`](src/zeliard.cpp), with the town scene split across `src/town/`, MDT parsing in `src/mdt/`, GRP handling in `src/grp/`, and HUD / MCGA helpers in `src/hud/` and `src/mcga/`.

Implemented or partially implemented:

- SDL3 startup and rendering
- 320x200 internal logical resolution
- 960x600 desktop output in the default square-pixel mode
- Experimental 960x720 desktop mode for 4:3-style presentation
- Original GRP decoding
- Palette handling
- Town pattern-bank decoding for `cpat.grp`, `mpat.grp` and `dpat.grp`
- Active pattern-bank passability using original special tile lists
- Muralla town rendering from MDT data
- Muralla CMAP.MDT to MRMP.MDT right-edge transition
- Muralla MRMP.MDT to CMAP.MDT left-edge transition
- Transition-specific hero and scroll reset behavior
- Muralla NPC runtime rebuild after town transitions
- Muralla NPC animation, movement and blocking behavior based on parsed MDT data and original assembly behavior
- HUD / border rendering backed by the original data files
- Documentation of original data formats, town rendering and town engine behavior
- Experimental WebAssembly build and GitHub Pages preview

Not implemented yet:

- Dialogs
- Shops
- Buildings
- Dungeons
- Combat
- Full gameplay loop
- Save/load behavior
- Music and sound integration

## Live Web Preview

An experimental C++23 + SDL3 WebAssembly build is available at:

https://thedragonheir.github.io/Zeliard/

The preview is part of the work-in-progress port and does not represent a complete game.

## Goals

- Recreate the original DOS gameplay behavior as faithfully as possible
- Decode and use the original `.SAR`, `.GRP`, `.MDT` and related data formats
- Keep the code small, readable and project-owned
- Use C++23 and SDL3 only, no large game engine
- Document findings while reverse engineering the original data and assembly
- Prefer accuracy first, polish later

## Project Structure

```text
AGENTS.md   Repo workflow and documentation guidance
asm/        Original assembly sources and reverse engineering references
assets/     Converted music and sound assets
docs/       Project notes and format documentation
game/       Original game data and binaries used for analysis
src/        C++23 source code
tools/      Python tools for inspecting and extracting game data
web/        Browser shell used by the WebAssembly build
out/        Generated CMake build output
```

`out/` is generated build output and should not be edited manually.

## Build

### Windows desktop

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

Build release:

```cmd
cmake --build --preset x64-release
```

The checked-in presets also include `x86-debug`, `x86-release`, `linux-debug`, `macos-debug`, and `web-debug`.

### Web build

```cmd
emcmake cmake --preset web-debug
cmake --build --preset web-debug
```

The generated browser build lands under `out/build/web-debug/` and uses the shell in `web/zeliard_shell.html`.

## Requirements

- C++23 compatible compiler
- CMake
- SDL3
- Windows development environment for the main desktop preset
- Emscripten for the web build

## Development Notes

The port is intentionally built in small verified steps. Original assembly and original data files are used as references before behavior is recreated in C++.

Current high-value references:

- `asm/town.asm`
- `asm/stick.asm`
- `asm/gtmcga.asm`
- `asm/ympd.asm`
- `docs/town_engine_and_town_graphics.md`
- `docs/town_fidelity_audit.md`
- `docs/runtime_architecture_and_build.md`
- `docs/web_build.md`

## Original Assets

This port uses original Zeliard game assets and data files for compatibility, preservation, research and faithful reimplementation purposes.

Original Zeliard assets, data files, binaries, graphics, music, sound, `.SAR` files, `.GRP` files, names and trademarks remain the property of their respective rights holders.

## License

The project-owned source code, tools and documentation are licensed under the MIT License.

See [`LICENSE`](LICENSE) for details.
