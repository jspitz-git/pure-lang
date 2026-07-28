if(NOT DEFINED SOURCE_DIR OR "${SOURCE_DIR}" STREQUAL "")
  message(FATAL_ERROR "SOURCE_DIR is required")
endif()

set(world_source "${SOURCE_DIR}/src/world.c")
if(NOT EXISTS "${world_source}")
  message(FATAL_ERROR "Lilv world source not found: ${world_source}")
endif()

file(READ "${world_source}" source)
set(expected
"#ifdef LILV_DYN_MANIFEST
#  include \"dylib.h\"
#  include <lv2/dynmanifest/dynmanifest.h>
#endif")
set(patched
"#ifdef LILV_DYN_MANIFEST
#  include \"dylib.h\"
#  include \"node_skimmer.h\"
#  include <lv2/dynmanifest/dynmanifest.h>
#endif")

if(source MATCHES "#  include \"node_skimmer\\.h\"")
  message(STATUS "Lilv Dynamic Manifest include patch already present")
elseif(source MATCHES "#ifdef LILV_DYN_MANIFEST")
  string(FIND "${source}" "${expected}" expected_position)
  if(expected_position EQUAL -1)
    message(FATAL_ERROR
      "Lilv world.c does not match the expected 0.26.4 source")
  endif()
  string(REPLACE "${expected}" "${patched}" source "${source}")
  file(WRITE "${world_source}" "${source}")
  message(STATUS "Applied upstream Lilv Dynamic Manifest include fix")
else()
  message(FATAL_ERROR "Lilv world.c has no Dynamic Manifest block")
endif()
