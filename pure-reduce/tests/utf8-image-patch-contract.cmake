foreach(_required IN ITEMS PURE_REDUCE_SOURCE_DIR PURE_REDUCE_SOURCE_TREE_SHA256)
  if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
    message(FATAL_ERROR "${_required} is required")
  endif()
endforeach()

include("${CMAKE_CURRENT_LIST_DIR}/../cmake/ReduceUpstream.cmake")

_pure_reduce_expected_upstream_stamp("commit" "tree" _stamp)
string(CONCAT _expected_stamp
  "commit\ntree\n"
  "2d88d6d4a842ccb4574b60b0bd7e3af91896cea76708551a6e54489792e91d08\n"
  "ad89f9581eefaaf4191b65af1b769a18883e865ee2740e4e6f053d1c5615d0e9\n"
  "ec94278f24718963e68aeac737a168c704c81cc72f48af903c4675770f3518df\n"
  "0863ce92c9cd6d89b74f7605bb216c3734e3b95902643239bf890de70d49612f\n")
if(NOT _stamp STREQUAL _expected_stamp OR _stamp MATCHES ";")
  message(FATAL_ERROR
    "upstream stamp must be six newline-delimited identity fields")
endif()

# Applying a private-source patch must not depend on whether the scratch tree
# happens to live below an unrelated enclosing Git worktree. The production
# scratch is outside this repository, while upstream-contract fixtures live in
# the build tree, so exercise the latter placement explicitly.
set(_enclosing_fixture
  "${CMAKE_CURRENT_BINARY_DIR}/pure-reduce-enclosing-repository-patch-fixture")
file(REMOVE_RECURSE "${_enclosing_fixture}")
_pure_reduce_checkout_pinned_files(
  "${PURE_REDUCE_SOURCE_DIR}" "${_enclosing_fixture}"
  csl/cslbase/winsupport.cpp)
_pure_reduce_apply_private_source_patch(
  "${_enclosing_fixture}"
  "${CMAKE_CURRENT_LIST_DIR}/../patches/0001-csl-winsupport-define-nil.patch"
  "${PURE_REDUCE_SOURCE_TREE_SHA256}"
  "${_enclosing_fixture}/patches.log"
  _enclosing_nil_patch_json)
file(REMOVE_RECURSE "${_enclosing_fixture}")

string(SHA256 _fixture_key "${CMAKE_CURRENT_BINARY_DIR}")
file(TO_CMAKE_PATH
  "$ENV{TEMP}/pure-reduce-utf8-image-patch-${_fixture_key}" _fixture)
file(REMOVE_RECURSE "${_fixture}")
_pure_reduce_checkout_pinned_files(
  "${PURE_REDUCE_SOURCE_DIR}" "${_fixture}"
  csl/cslbase/preserve.cpp
  csl/cslbase/proc.h
  csl/cslbase/csl.cpp
  csl/cslbase/winsupport.cpp
  csl/cslbase/winsupport.h
  configure
  configure.ac)

_pure_reduce_apply_private_source_patch(
  "${_fixture}"
  "${CMAKE_CURRENT_LIST_DIR}/../patches/0001-csl-winsupport-define-nil.patch"
  "${PURE_REDUCE_SOURCE_TREE_SHA256}"
  "${_fixture}/patches.log"
  _nil_patch_json)
_pure_reduce_apply_private_source_patch(
  "${_fixture}"
  "${CMAKE_CURRENT_LIST_DIR}/../patches/0002-csl-windows-utf8-image-open.patch"
  "${PURE_REDUCE_SOURCE_TREE_SHA256}"
  "${_fixture}/patches.log"
  _utf8_patch_json)
_pure_reduce_apply_private_source_patch(
  "${_fixture}"
  "${CMAKE_CURRENT_LIST_DIR}/../patches/0004-csl-procedural-raw-cons.patch"
  "${PURE_REDUCE_SOURCE_TREE_SHA256}"
  "${_fixture}/patches.log"
  _raw_cons_patch_json)
_pure_reduce_apply_private_source_patch(
  "${_fixture}"
  "${CMAKE_CURRENT_LIST_DIR}/../patches/0003-configure-quote-source-paths.patch"
  "${PURE_REDUCE_SOURCE_TREE_SHA256}"
  "${_fixture}/patches.log"
  _configure_paths_patch_json)

string(JSON _configure_target_count LENGTH
  "${_configure_paths_patch_json}" targets)
if(NOT _configure_target_count EQUAL 2)
  message(FATAL_ERROR
    "configure path patch provenance must cover exactly two targets")
endif()
string(JSON _raw_cons_target_count LENGTH "${_raw_cons_patch_json}" targets)
if(NOT _raw_cons_target_count EQUAL 2)
  message(FATAL_ERROR
    "raw-cons patch provenance must cover exactly two targets")
endif()
string(JSON _target_count LENGTH "${_utf8_patch_json}" targets)
if(NOT _target_count EQUAL 3)
  message(FATAL_ERROR
    "UTF-8 image patch provenance must cover exactly three targets")
endif()
set(_actual_targets)
foreach(_index RANGE 0 2)
  string(JSON _target GET "${_utf8_patch_json}" targets ${_index} path)
  list(APPEND _actual_targets "${_target}")
endforeach()
set(_expected_targets
  csl/cslbase/preserve.cpp
  csl/cslbase/winsupport.cpp
  csl/cslbase/winsupport.h)
list(SORT _actual_targets)
list(SORT _expected_targets)
if(NOT _actual_targets STREQUAL _expected_targets)
  message(FATAL_ERROR
    "UTF-8 image patch provenance names wrong targets: ${_actual_targets}")
endif()

file(READ "${_fixture}/csl/cslbase/preserve.cpp" _preserve)
file(READ "${_fixture}/csl/cslbase/proc.h" _proc_h)
file(READ "${_fixture}/csl/cslbase/csl.cpp" _csl_cpp)
file(READ "${_fixture}/csl/cslbase/winsupport.cpp" _winsupport_cpp)
file(READ "${_fixture}/csl/cslbase/winsupport.h" _winsupport_h)
file(READ "${_fixture}/configure" _configure)
file(READ "${_fixture}/configure.ac" _configure_ac)
if(NOT _preserve MATCHES "windowsFopenUtf8" OR
   NOT _preserve MATCHES "windowsFileStatusUtf8" OR
   NOT _winsupport_cpp MATCHES "MultiByteToWideChar\\(CP_UTF8" OR
   NOT _winsupport_cpp MATCHES "_wfopen" OR
   NOT _winsupport_h MATCHES "windowsFopenUtf8" OR
   NOT _winsupport_h MATCHES "windowsFileStatusUtf8")
  message(FATAL_ERROR
    "UTF-8 image patch does not route the Windows image-open boundary")
endif()
if(NOT _proc_h MATCHES "extern int PROC_make_raw_cons\\(\\)" OR
   NOT _csl_cpp MATCHES "int PROC_make_raw_cons\\(\\)" OR
   NOT _csl_cpp MATCHES "procstack = w1")
  message(FATAL_ERROR
    "raw-cons patch does not expose and implement the private stack primitive")
endif()
foreach(_configure_source IN ITEMS _configure _configure_ac)
  if(NOT "${${_configure_source}}" MATCHES
      "libraries/libffi/configure[^\n]*--disable-symvers")
    message(FATAL_ERROR
      "configure path patch does not disable libffi symbol version scripts in ${_configure_source}")
  endif()
endforeach()

file(REMOVE_RECURSE "${_fixture}")

# The recipe marker invalidates cached closures when build flags change without
# changing the public six-field source/patch identity stamp.
set(PURE_REDUCE_VERIFIED_COMMIT "commit")
string(SHA256 _recipe_fixture_key "${CMAKE_CURRENT_BINARY_DIR}")
file(TO_CMAKE_PATH
  "$ENV{TEMP}/pure-reduce-recipe-stamp-contract-${_recipe_fixture_key}"
  _recipe_fixture)
set(PURE_REDUCE_UPSTREAM_BINARY_DIR "${_recipe_fixture}")
set(PURE_REDUCE_MSYS2_BASH "fixture-bash")
set(PURE_REDUCE_MAKE "fixture-make")
file(REMOVE_RECURSE "${_recipe_fixture}")
file(MAKE_DIRECTORY
  "${_recipe_fixture}/artifacts/include"
  "${_recipe_fixture}/artifacts/install-inputs/csl/cslbase/cm-unicode"
  "${_recipe_fixture}/artifacts/install-inputs/libraries/crlibm"
  "${_recipe_fixture}/artifacts/install-inputs/libraries/libffi"
  "${_recipe_fixture}/artifacts/link"
  "${_recipe_fixture}/artifacts/runtime/reduce.resources"
  "${_recipe_fixture}/artifacts/runtime/reduce.fonts"
  "${_recipe_fixture}/logs")
foreach(_artifact IN ITEMS
    artifacts/reduce.img
    artifacts/include/proc.h
    artifacts/install-inputs/csl/cslbase/COPYING
    artifacts/install-inputs/csl/cslbase/cm-unicode/LICENSE
    artifacts/install-inputs/libraries/crlibm/COPYING
    artifacts/install-inputs/libraries/crlibm/COPYING.LIB
    artifacts/install-inputs/libraries/libffi/LICENSE
    artifacts/link/libreduce-csl.a
    artifacts/link/libcrlibm.a
    artifacts/link/libffi.a
    artifacts/runtime/reduce.resources/mma.awk
    artifacts/runtime/reduce.fonts/fonts.dir
    toolchain-packages.tsv
    reduce-upstream-metrics.json
    logs/artifact-contract-probe.exe
    logs/artifact-contract.log)
  file(WRITE "${_recipe_fixture}/${_artifact}"
    "fixture artifact bytes for recipe contract\n")
endforeach()
_pure_reduce_write_directory_manifest(
  "${_recipe_fixture}/artifacts/runtime/reduce.resources"
  "${_recipe_fixture}/artifacts/runtime/reduce.resources.manifest")
_pure_reduce_write_directory_manifest(
  "${_recipe_fixture}/artifacts/runtime/reduce.fonts"
  "${_recipe_fixture}/artifacts/runtime/reduce.fonts.manifest")
_pure_reduce_expected_upstream_stamp(
  "${PURE_REDUCE_VERIFIED_COMMIT}"
  "${PURE_REDUCE_SOURCE_TREE_SHA256}"
  _recipe_expected_stamp)
file(WRITE "${_recipe_fixture}/pure-reduce-upstream.stamp"
  "${_recipe_expected_stamp}")
file(WRITE "${_recipe_fixture}/pure-reduce-upstream.recipe"
  "${_PURE_REDUCE_BUILD_RECIPE_VERSION}\n")
set(PURE_REDUCE_TOOLCHAIN_PROVENANCE_TEST_OVERRIDE
  "${_recipe_fixture}/toolchain-packages.fixture-live.tsv")
file(COPY_FILE "${_recipe_fixture}/toolchain-packages.tsv"
  "${PURE_REDUCE_TOOLCHAIN_PROVENANCE_TEST_OVERRIDE}")
_pure_reduce_write_upstream_identity("${_recipe_fixture}")

function(_pure_reduce_run_upstream_build)
  set_property(GLOBAL PROPERTY PURE_REDUCE_RECIPE_REBUILD_CALLED ON)
  file(WRITE "${PURE_REDUCE_UPSTREAM_BINARY_DIR}/pure-reduce-upstream.recipe"
    "${_PURE_REDUCE_BUILD_RECIPE_VERSION}\n")
  _pure_reduce_write_upstream_identity("${PURE_REDUCE_UPSTREAM_BINARY_DIR}")
endfunction()

foreach(_recipe_case IN ITEMS missing stale current)
  set_property(GLOBAL PROPERTY PURE_REDUCE_RECIPE_REBUILD_CALLED OFF)
  if(_recipe_case STREQUAL "missing")
    file(REMOVE "${_recipe_fixture}/pure-reduce-upstream.recipe")
  elseif(_recipe_case STREQUAL "stale")
    file(WRITE "${_recipe_fixture}/pure-reduce-upstream.recipe"
      "stale recipe identity with enough bytes\n")
  else()
    file(WRITE "${_recipe_fixture}/pure-reduce-upstream.recipe"
      "${_PURE_REDUCE_BUILD_RECIPE_VERSION}\n")
  endif()
  _pure_reduce_run_upstream_build_ensure()
  get_property(_rebuild_called GLOBAL
    PROPERTY PURE_REDUCE_RECIPE_REBUILD_CALLED)
  if(_recipe_case STREQUAL "current")
    if(_rebuild_called)
      message(FATAL_ERROR "current upstream recipe marker forced regeneration")
    endif()
  elseif(NOT _rebuild_called)
    message(FATAL_ERROR
      "${_recipe_case} upstream recipe marker did not force regeneration")
  endif()
endforeach()
file(REMOVE_RECURSE "${_recipe_fixture}")
