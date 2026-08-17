cmake_minimum_required(VERSION 3.25)

if(NOT DEFINED REDUCE_UPSTREAM_MODULE OR
    "${REDUCE_UPSTREAM_MODULE}" STREQUAL "")
  message(FATAL_ERROR "REDUCE_UPSTREAM_MODULE is required")
endif()

include("${REDUCE_UPSTREAM_MODULE}")
string(SHA256 _fixture_key "${CMAKE_CURRENT_BINARY_DIR}")
file(TO_CMAKE_PATH
  "$ENV{TEMP}/pure reduce runtime handoff-${_fixture_key}" _root)
file(REMOVE_RECURSE "${_root}")

set(_configuration
  "${_root}/source/cslbuild/intel-pc-windows-nogui/win64")
set(_producer "${_configuration}/csl")
file(MAKE_DIRECTORY
  "${_root}/source/csl/cslbase"
  "${_producer}/reduce.resources"
  "${_producer}/reduce.fonts")
file(WRITE "${_root}/source/csl/cslbase/proc.h" "fixture proc header\n")
file(WRITE "${_configuration}/Makefile" "all:\n")
file(WRITE "${_producer}/config.h" "/* #undef RAW_CYGWIN */\n")
file(WRITE "${_producer}/reduce.img" "fixture image\n")
file(WRITE "${_producer}/reduce.resources/data" "resource\n")
file(WRITE "${_producer}/reduce.fonts/font" "font\n")

set(PURE_REDUCE_UPSTREAM_BINARY_DIR "${_root}")
_pure_reduce_stage_public_headers(
  "${_root}/source" "${_root}/artifacts/include")
_pure_reduce_run_runtime_artifact_refresh()
foreach(_manifest IN ITEMS reduce.resources.manifest reduce.fonts.manifest)
  file(SHA256 "${_root}/artifacts/runtime/${_manifest}"
    "_before_${_manifest}")
endforeach()

# A successful private build removes its no-space producer source. Complete
# published runtime artifacts must remain independently refreshable after that
# handoff rather than forcing a lookup below the deleted source tree.
file(REMOVE_RECURSE "${_root}/source")
_pure_reduce_run_runtime_artifact_refresh()

if(NOT EXISTS "${_root}/artifacts/include/proc.h")
  message(FATAL_ERROR "staged CSL public header did not survive source handoff")
endif()

foreach(_manifest IN ITEMS reduce.resources.manifest reduce.fonts.manifest)
  file(SHA256 "${_root}/artifacts/runtime/${_manifest}"
    "_after_${_manifest}")
  if(NOT "${_before_${_manifest}}" STREQUAL "${_after_${_manifest}}")
    message(FATAL_ERROR
      "complete runtime artifact handoff changed ${_manifest}")
  endif()
endforeach()

file(REMOVE_RECURSE "${_root}")
