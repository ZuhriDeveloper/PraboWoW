# PraboWoW playerbot module.
#
# This tree lives outside the core submodule (CLAUDE.md rule 2 keeps core edits to
# labelled atomic commits), so core/src/server/CMakeLists.txt adds it with an explicit
# binary directory. Directory properties are inherited from that call site, which is how
# the Windows platform defines and TRINITY_PRABOBOTS reach these sources.
#
# Note CollectSourceFiles has no CONFIGURE_DEPENDS: a newly added .cpp is only picked up
# on the next CMake configure. tools/build-core.ps1 always reconfigures, so the normal
# workflow is safe.

CollectSourceFiles(${CMAKE_CURRENT_SOURCE_DIR} PRIVATE_SOURCES)
CollectIncludeDirectories(${CMAKE_CURRENT_SOURCE_DIR} PUBLIC_INCLUDES)

GroupSources(${CMAKE_CURRENT_SOURCE_DIR})

add_library(prabobots STATIC ${PRIVATE_SOURCES})

target_include_directories(prabobots
  PUBLIC
    ${PUBLIC_INCLUDES})

# trinity-core-interface carries /permissive-, /W3, /bigobj, /MP, the CRT defines and
# cxx_std_20, so this module compiles under exactly the same rules as the core does.
# game is linked rather than game-interface because we call real symbols.
target_link_libraries(prabobots
  PRIVATE
    trinity-core-interface
  PUBLIC
    game)

set_target_properties(prabobots
  PROPERTIES
    FOLDER
      "server")

# No PCH and no unity build on purpose: the core PCH is private to the game target, and at
# this file count neither would pay for itself. Revisit when the AI port lands.
