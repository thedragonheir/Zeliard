# Web build

This repository has an experimental Emscripten/WebAssembly path for the Zeliard C++ build.
It compiles the app for the browser, but it does not bundle the original game data files into the public Pages artifact.

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
4. Open the generated `out/build/web-debug/Zeliard.html` through a local static server if you want to inspect the browser wrapper.

## GitHub Pages

1. Push the branch that contains `.github/workflows/web.yml`.
2. In GitHub, open `Settings > Pages`.
3. Under `Source`, select `GitHub Actions`.
4. The workflow will publish the Pages artifact with `index.html` at the root.

## Notes

- The web build uses the same 320x200 logical rendering path.
- Desktop x64 debug and release presets are unchanged.
- If you want the browser build to load the game data, you will need to provide those files separately outside the public Pages artifact.
