# Web build

This repository has an experimental Emscripten/WebAssembly path for the Zeliard C++ build.
It compiles the app for the browser and bundles `game/` and `assets/` into `Zeliard.data`.

## Local setup

1. Install Emscripten and activate its environment.
2. Configure the web build:
   ```bash
   emcmake cmake --preset web-debug
   ```
3. Build it:
   ```bash
   cmake --build --preset web-debug
   ```
4. Open the generated `out/build/web-debug/Zeliard.html` through a local static server if you want to inspect the browser wrapper and `Zeliard.data`.

## GitHub Pages

1. Push the branch that contains `.github/workflows/web.yml`.
2. In GitHub, open `Settings > Pages`.
3. Under `Source`, select `GitHub Actions`.
4. The workflow will publish the Pages artifact with `index.html` at the root.
5. The Pages workflow intentionally pins Emscripten `5.0.1` to avoid the current `TextDecoder` resizable-`ArrayBuffer` crash seen with newer output.

## Notes

- The web build uses the same 320x200 logical rendering path.
- Desktop x64 debug and release presets are unchanged.
- The browser package bundles the original game data in `Zeliard.data`.
- Runtime data that the browser build loads must live under `game/` or `assets/`, not `tools/`.
- The web build uses a larger stack because the default 64 KB Emscripten stack overflows during startup.
- The web build uses fixed WebAssembly memory so browser file-path decoding does not hit resizable-`ArrayBuffer` `TextDecoder` issues.
