# Web build

This repository has an experimental Emscripten/WebAssembly path for the Zeliard C++ build.
GitHub Pages publishes the generated WebAssembly package at:

https://thedragonheir.github.io/Zeliard/

The browser package bundles `game/` and `assets/` into `Zeliard.data`. Runtime data
needed by the web build must live under one of those directories, not under `tools/`.

## Local setup

1. Install Emscripten and activate its environment.
2. Configure the web build:
   ```bash
   emcmake cmake --preset "Web Debug"
   ```
3. Build it:
   ```bash
   cmake --build --preset "Web Debug"
   ```
4. Open the generated `out/build/web-debug/Zeliard.html` through a local static server if you want to inspect the browser wrapper and `Zeliard.data`.

## GitHub Pages

1. Push the branch that contains `.github/workflows/web.yml` with `git push`.
2. In GitHub, open `Settings > Pages`.
3. Under `Source`, select `GitHub Actions`.
4. The workflow will publish the Pages artifact with `index.html` at the root.
5. The Pages workflow intentionally pins Emscripten `5.0.1` to avoid the current `TextDecoder` resizable-`ArrayBuffer` crash seen with newer output.

## Manual deployment check

1. Run `git push`.
2. Run `RunWeb.bat` if the local helper is available.
3. Open https://thedragonheir.github.io/Zeliard/.
4. Hard refresh the page with `Ctrl+F5`.

`RunWeb.bat` is a local helper only and should not be committed. Keep local helper
scripts under `.local/` where practical.

## Notes

- The web build uses the same 320x200 logical rendering path.
- Desktop x64 debug and release presets are unchanged.
- The browser package bundles `game/` and `assets/` into `Zeliard.data`.
- Runtime data that the browser build loads must live under `game/` or `assets/`, not `tools/`.
- The web build uses a 4 MB Emscripten stack.
- Initial WebAssembly memory is fixed at 256 MB.
- Memory growth is disabled to avoid browser `TextDecoder` issues with resizable `ArrayBuffer` instances.
