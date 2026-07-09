# Zeliard C++ Port

Unofficial C++23 + SDL3 port/reimplementation of **Zeliard**.

The project focuses on faithfully recreating the original DOS behavior, rendering, data formats and gameplay systems using the original game assets. The goal is preservation and understanding first, not modernization for its own sake.

## Status

The current build focuses on the town flow. It boots through SDL3, loads the original data files, decodes town GRP/MDT content, renders at a 320x200 internal resolution, and runs the Muralla town flow with assembly-backed movement, scrolling, town transitions, NPC behavior and HUD rendering.

The game is presented in a fixed 4:3 corrected desktop layout at 960x720, matching the intended DOS/CRT proportions instead of stretching to widescreen.

The port is still incomplete. Dialogs, shops, buildings, dungeons, combat, save/load, music and sound are not implemented yet.

## Website Preview

An experimental WebAssembly preview is available at:

https://thedragonheir.github.io/Zeliard/

This preview is work in progress and does not represent a complete game.

## Goals

- Recreate the original DOS behavior as accurately as possible
- Decode and use the original `.SAR`, `.GRP`, `.MDT` and related data formats
- Keep the code small, readable and project-owned
- Use C++23 and SDL3, without a large game engine
- Document reverse-engineering findings while rebuilding the game
- Prefer accuracy first, polish later

## Project Layout

```text
AGENTS.md   Repo workflow and contribution guidance
asm/        Original assembly sources and reverse-engineering references
assets/     Converted music and sound assets
docs/       Project notes and format documentation
game/       Original game data and binaries used for analysis
src/        C++23 source code
tools/      Python tools for inspecting and extracting game data
web/        Browser shell used by the WebAssembly build
out/        Generated CMake build output
