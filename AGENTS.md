# Repository Guidelines

## Project Structure & Module Organization
This repository is a C++23 + SDL3 port of Zeliard. Keep game code in `src/`, with features split by domain such as `src/town/`, `src/mdt/`, `src/grp/`, `src/mcga/`, and `src/hud/`. Original assembly and reverse-engineering references live in `asm/`. Use `docs/` for analysis notes and format documentation, `game/` for original data files, `assets/` for converted audio, and `tools/` for Python utilities and extractors. `web/` contains the WebAssembly shell.

## Build, Test, and Development Commands
Use the CMake presets from the repo root:

- `cmake --preset Debug` configures a native debug build in `out/build/Debug`.
- `cmake --build --preset Debug` builds the desktop executable.
- `out\build\Debug\Zeliard.exe` runs the native build.
- `cmake --preset Website` and `cmake --build --preset Website` build the browser target.

There is no automated test suite yet. Validate changes by building the affected preset and launching the game or tool you touched.

## Coding Style & Naming Conventions
Prefer clear, project-owned names over terse abbreviations. Use PascalCase for project-owned constants and constant-like identifiers, even where other codebases would use uppercase. Do not rename external API symbols, enum values, or library constants. Keep comments focused on why code exists, especially for reverse-engineered behavior, fragile timing, or data-format quirks. Match the surrounding formatting and keep edits narrow.

## Testing Guidelines
Testing is mostly manual. For gameplay changes, run the native executable and verify the affected scene or flow. For tools in `tools/`, run the script against representative files from `game/` and confirm the output or extracted data looks correct. If a change affects rendering or layout, verify it on screen and note any remaining visual differences.

## Commit & Pull Request Guidelines
Recent commits are short, imperative, and specific, for example: `Fix startup hero idle frame` or `Add selectable display aspect mode`. Keep commit messages similarly focused. Pull requests should describe the behavior change, list the files or systems touched, and include screenshots or short notes for visible changes. Mention any validation performed and any known gaps.

## Agent Notes
For Zeliard work, inspect the relevant assembly, docs, and source before changing behavior. Avoid broad refactors, unrelated renames, and speculative modernization. Preserve original data formats and only change what the task requires.
