# CMakeList.txt : CMake project for Zeliard, include source and define
# project specific logic here.
#
cmake_minimum_required(VERSION 3.20)

# Enable Hot Reload for MSVC compilers if supported.
if (POLICY CMP0141)
  cmake_policy(SET CMP0141 NEW)
  set(CMAKE_MSVC_DEBUG_INFORMATION_FORMAT "$<IF:$<AND:$<C_COMPILER_ID:MSVC>,$<CXX_COMPILER_ID:MSVC>>,$<$<CONFIG:Debug,RelWithDebInfo>:EditAndContinue>,$<$<CONFIG:Debug,RelWithDebInfo>:ProgramDatabase>>")
endif()

project(Zeliard LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(SDL_OPENGL OFF CACHE BOOL "" FORCE)
set(SDL_OPENGLES OFF CACHE BOOL "" FORCE)
set(SDL_JOYSTICK OFF CACHE BOOL "" FORCE)
set(SDL_HAPTIC OFF CACHE BOOL "" FORCE)
set(SDL_HIDAPI OFF CACHE BOOL "" FORCE)

include(FetchContent)

FetchContent_Declare(
  SDL3
  GIT_REPOSITORY https://github.com/libsdl-org/SDL.git
  GIT_TAG release-3.4.12
  GIT_SHALLOW TRUE
)

FetchContent_MakeAvailable(SDL3)

add_executable(Zeliard
  src/zeliard.cpp
  src/hud/mole_panels.cpp
  src/hud/tears.cpp
  src/mcga/mcga_draw.cpp
  src/mcga/mcga_palette.cpp
  src/town/town_actors.cpp
  src/town/town.cpp
  src/town/town_dialog.cpp
  src/town/town_npc.cpp
  src/town/town_render.cpp
  src/town/town_transitions.cpp
  src/mdt/town_mdt.cpp
  src/grp/font_grp.cpp
  src/grp/man_grp.cpp
  src/grp/pat_grp.cpp
  src/grp/grp_unpack.cpp
)
if (EMSCRIPTEN)
  target_compile_definitions(Zeliard PRIVATE
    ZELIARD_PROJECT_ROOT="."
  )
else()
  target_compile_definitions(Zeliard PRIVATE
    ZELIARD_PROJECT_ROOT="${CMAKE_SOURCE_DIR}"
  )
endif()
target_compile_options(Zeliard PRIVATE
  $<$<CXX_COMPILER_ID:MSVC>:/EHsc>
)
target_link_libraries(Zeliard PRIVATE SDL3::SDL3)

if (EMSCRIPTEN)
  set(ZeliardWebStackSize 4194304)
  set(ZeliardWebInitialMemory 268435456)
  set_target_properties(Zeliard PROPERTIES SUFFIX ".html")
  target_link_options(Zeliard PRIVATE
    "SHELL:--shell-file=\"${CMAKE_SOURCE_DIR}/web/zeliard_shell.html\""
    "SHELL:--preload-file \"${CMAKE_SOURCE_DIR}/game@/game\""
    "SHELL:--preload-file \"${CMAKE_SOURCE_DIR}/assets@/assets\""
    "SHELL:-sSTACK_SIZE=${ZeliardWebStackSize}"
    "SHELL:-sINITIAL_MEMORY=${ZeliardWebInitialMemory}"
    "SHELL:-sALLOW_MEMORY_GROWTH=0"
  )
endif()

if (WIN32)
  add_custom_command(TARGET Zeliard POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            $<TARGET_FILE:SDL3::SDL3>
            $<TARGET_FILE_DIR:Zeliard>
  )
endif()

# TODO: Add tests and install targets if needed.
