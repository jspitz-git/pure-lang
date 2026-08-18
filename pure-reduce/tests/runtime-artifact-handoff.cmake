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
  "${_root}/source/csl/cslbase/cm-unicode"
  "${_root}/source/libraries/crlibm"
  "${_root}/source/libraries/libffi"
  "${_producer}/reduce.resources"
  "${_producer}/reduce.fonts")
file(WRITE "${_root}/source/csl/cslbase/proc.h" "fixture proc header\n")
foreach(_license IN ITEMS
    csl/cslbase/COPYING
    csl/cslbase/cm-unicode/LICENSE
    libraries/crlibm/COPYING
    libraries/crlibm/COPYING.LIB
    libraries/libffi/LICENSE)
  file(WRITE "${_root}/source/${_license}" "fixture ${_license}\n")
endforeach()
file(WRITE "${_configuration}/Makefile" "all:\n")
file(WRITE "${_producer}/config.h" "/* #undef RAW_CYGWIN */\n")
file(WRITE "${_producer}/reduce.img" "fixture image payload\n")
file(WRITE "${_producer}/reduce.resources/data" "resource\n")
file(WRITE "${_producer}/reduce.fonts/font" "font\n")

set(PURE_REDUCE_UPSTREAM_BINARY_DIR "${_root}")
_pure_reduce_stage_public_headers(
  "${_root}/source" "${_root}/artifacts/include")
_pure_reduce_stage_install_inputs(
  "${_root}/source" "${_root}/artifacts/install-inputs")
_pure_reduce_run_runtime_artifact_refresh()
file(COPY_FILE
  "${_producer}/reduce.img" "${_root}/artifacts/reduce.img")
file(MAKE_DIRECTORY "${_root}/artifacts/link")
foreach(_library IN ITEMS libreduce-csl.a libcrlibm.a libffi.a)
  file(WRITE "${_root}/artifacts/link/${_library}"
    "fixture ${_library} payload\n")
endforeach()
file(MAKE_DIRECTORY "${_root}/logs")
file(WRITE "${_root}/logs/artifact-contract-probe.exe"
  "fixture artifact probe payload\n")
file(WRITE "${_root}/logs/artifact-contract.log"
  "fixture artifact contract log\n")
file(WRITE "${_root}/reduce-upstream-metrics.json"
  "{\"fixture\":\"runtime handoff\"}\n")
file(WRITE "${_root}/pure-reduce-upstream.recipe"
  "${_PURE_REDUCE_BUILD_RECIPE_VERSION}\n")
set(PURE_REDUCE_SOURCE_DIR "${_root}/source")
set(PURE_REDUCE_MSYS2_BASH "fixture-bash")
set(PURE_REDUCE_MAKE "fixture-make")
set(PURE_REDUCE_VERIFIED_COMMIT "fixture-commit")
set(PURE_REDUCE_SOURCE_TREE_SHA256 "fixture-tree")
_pure_reduce_expected_upstream_stamp(
  "${PURE_REDUCE_VERIFIED_COMMIT}"
  "${PURE_REDUCE_SOURCE_TREE_SHA256}" _fixture_stamp)
file(WRITE "${_root}/pure-reduce-upstream.stamp" "${_fixture_stamp}")

# A full rebuild is intentionally replaced by a deterministic local producer:
# the real upstream build is the slow external boundary, while all completeness
# decisions and published runtime effects below remain production behavior.
set(_recovery_producer "${_root}/recovery-producer")
file(COPY "${_producer}/reduce.resources" DESTINATION "${_recovery_producer}")
file(COPY "${_producer}/reduce.fonts" DESTINATION "${_recovery_producer}")
set(_rebuild_log "${_root}/rebuilds.log")
function(_pure_reduce_run_upstream_build)
  file(APPEND "${_rebuild_log}" "rebuild\n")
  _pure_reduce_stage_runtime_artifacts(
    "${_recovery_producer}" "${_root}/artifacts/runtime")
endfunction()
foreach(_manifest IN ITEMS reduce.resources.manifest reduce.fonts.manifest)
  file(SHA256 "${_root}/artifacts/runtime/${_manifest}"
    "_before_${_manifest}")
endforeach()

# A successful private build removes its no-space producer source. Complete
# published runtime artifacts must remain independently refreshable after that
# handoff rather than forcing a lookup below the deleted source tree.
file(REMOVE_RECURSE "${_root}/source")
_pure_reduce_run_runtime_artifact_refresh()

# Build completeness must include the staged runtime closure. Each corruption
# below occurs after the private producer source was removed, so recovery must
# select a full rebuild rather than attempt to refresh from `${_root}/source`.
file(REMOVE_RECURSE "${_root}/artifacts/runtime/reduce.resources")
_pure_reduce_run_upstream_build_ensure()
_pure_reduce_run_runtime_artifact_refresh()
if(NOT EXISTS "${_root}/artifacts/runtime/reduce.resources/data")
  message(FATAL_ERROR
    "missing staged runtime directory did not trigger full rebuild recovery")
endif()

file(REMOVE "${_root}/artifacts/runtime/reduce.fonts.manifest")
_pure_reduce_run_upstream_build_ensure()
_pure_reduce_run_runtime_artifact_refresh()
if(NOT EXISTS "${_root}/artifacts/runtime/reduce.fonts.manifest")
  message(FATAL_ERROR
    "missing staged runtime manifest did not trigger full rebuild recovery")
endif()

# Leave the old manifest in place while removing one file from its directory.
# A directory+manifest existence check cannot detect this incomplete closure.
file(REMOVE "${_root}/artifacts/runtime/reduce.resources/data")
_pure_reduce_run_upstream_build_ensure()
_pure_reduce_run_runtime_artifact_refresh()
if(NOT EXISTS "${_root}/artifacts/runtime/reduce.resources/data")
  message(FATAL_ERROR
    "stale runtime manifest did not trigger full rebuild recovery")
endif()

file(STRINGS "${_rebuild_log}" _rebuilds)
list(LENGTH _rebuilds _rebuild_count)
if(NOT _rebuild_count EQUAL 3)
  message(FATAL_ERROR
    "expected three runtime recovery rebuilds; found ${_rebuild_count}")
endif()

if(NOT EXISTS "${_root}/artifacts/include/proc.h")
  message(FATAL_ERROR "staged CSL public header did not survive source handoff")
endif()
foreach(_license IN ITEMS
    csl/cslbase/COPYING
    csl/cslbase/cm-unicode/LICENSE
    libraries/crlibm/COPYING
    libraries/crlibm/COPYING.LIB
    libraries/libffi/LICENSE)
  if(NOT EXISTS "${_root}/artifacts/install-inputs/${_license}")
    message(FATAL_ERROR
      "staged installation input did not survive source handoff: ${_license}")
  endif()
endforeach()

foreach(_manifest IN ITEMS reduce.resources.manifest reduce.fonts.manifest)
  file(SHA256 "${_root}/artifacts/runtime/${_manifest}"
    "_after_${_manifest}")
  if(NOT "${_before_${_manifest}}" STREQUAL "${_after_${_manifest}}")
    message(FATAL_ERROR
      "complete runtime artifact handoff changed ${_manifest}")
  endif()
endforeach()

file(REMOVE_RECURSE "${_root}")
