cmake_minimum_required(VERSION 3.25)

foreach(_required IN ITEMS
    PURE_REDUCE_SOURCE_DIR PURE_REDUCE_UPSTREAM_MODULE
    PURE_REDUCE_MSYS2_BASH PURE_REDUCE_MAKE)
  if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
    message(FATAL_ERROR "${_required} is required")
  endif()
endforeach()

set(_fixture "${CMAKE_CURRENT_BINARY_DIR}/pure-reduce-revalidation-fixture")
file(REMOVE_RECURSE "${_fixture}")
file(MAKE_DIRECTORY "${_fixture}")
file(MAKE_DIRECTORY "${_fixture}/source")
execute_process(
  COMMAND git -C "${PURE_REDUCE_SOURCE_DIR}" rev-parse --git-common-dir
  RESULT_VARIABLE _common_result OUTPUT_VARIABLE _common_dir
  ERROR_VARIABLE _common_error OUTPUT_STRIP_TRAILING_WHITESPACE)
if(NOT _common_result EQUAL 0)
  message(FATAL_ERROR "could not locate pinned object store: ${_common_error}")
endif()
get_filename_component(_common_dir "${_common_dir}" ABSOLUTE
  BASE_DIR "${PURE_REDUCE_SOURCE_DIR}")
file(TO_CMAKE_PATH "${_common_dir}/objects" _objects)
execute_process(
  COMMAND git -C "${_fixture}/source" init
  RESULT_VARIABLE _init_result ERROR_VARIABLE _init_error)
file(MAKE_DIRECTORY "${_fixture}/source/.git/objects/info")
file(WRITE "${_fixture}/source/.git/objects/info/alternates" "${_objects}")
execute_process(
  COMMAND git -C "${_fixture}/source" sparse-checkout init --no-cone
  RESULT_VARIABLE _sparse_init_result ERROR_VARIABLE _sparse_init_error)
execute_process(
  COMMAND git -C "${_fixture}/source" sparse-checkout set --no-cone
    /csl/cslbase/winsupport.cpp
  RESULT_VARIABLE _sparse_result ERROR_VARIABLE _sparse_error)
execute_process(
  COMMAND git -C "${_fixture}/source" checkout --detach
    7efba90661139ae9c73c99fddd55f3fb2fabf69a
  RESULT_VARIABLE _checkout_result ERROR_VARIABLE _checkout_error)
if(NOT _init_result EQUAL 0 OR NOT _sparse_init_result EQUAL 0 OR
   NOT _sparse_result EQUAL 0 OR NOT _checkout_result EQUAL 0)
  message(FATAL_ERROR
    "could not prepare sparse pinned fixture: "
    "${_init_error}${_sparse_init_error}${_sparse_error}${_checkout_error}")
endif()

file(TO_CMAKE_PATH "${PURE_REDUCE_UPSTREAM_MODULE}" _module)
file(TO_CMAKE_PATH "${_fixture}/source" _source)
file(TO_CMAKE_PATH "${_fixture}/upstream" _upstream)
file(TO_CMAKE_PATH "${PURE_REDUCE_MSYS2_BASH}" _bash)
file(TO_CMAKE_PATH "${PURE_REDUCE_MAKE}" _make)
file(WRITE "${_fixture}/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.25)
project(revalidation-fixture LANGUAGES NONE)
include("@MODULE@")
set(PURE_REDUCE_SOURCE_DIR "@SOURCE@")
set(PURE_REDUCE_UPSTREAM_BINARY_DIR "@UPSTREAM@")
set(PURE_REDUCE_MSYS2_BASH "@BASH@")
set(PURE_REDUCE_MAKE "@MAKE@")
set(PURE_REDUCE_VERIFIED_COMMIT
  "7efba90661139ae9c73c99fddd55f3fb2fabf69a")
set(PURE_REDUCE_SOURCE_TREE_SHA256
  "134a68fdb10403d3a4c69051eb4e133803ff2659784f2d38ac4d94c7ee9f86d8")
pure_reduce_define_upstream_build()
]=])
file(READ "${_fixture}/CMakeLists.txt" _project)
string(REPLACE "@MODULE@" "${_module}" _project "${_project}")
string(REPLACE "@SOURCE@" "${_source}" _project "${_project}")
string(REPLACE "@UPSTREAM@" "${_upstream}" _project "${_project}")
string(REPLACE "@BASH@" "${_bash}" _project "${_project}")
string(REPLACE "@MAKE@" "${_make}" _project "${_project}")
file(WRITE "${_fixture}/CMakeLists.txt" "${_project}")

execute_process(
  COMMAND "${CMAKE_COMMAND}" -S "${_fixture}" -B "${_fixture}/build" -G Ninja
  RESULT_VARIABLE _configure_result
  OUTPUT_VARIABLE _configure_output ERROR_VARIABLE _configure_error)
if(NOT _configure_result EQUAL 0)
  message(FATAL_ERROR
    "could not configure revalidation fixture:\n${_configure_output}${_configure_error}")
endif()

file(MAKE_DIRECTORY
  "${_fixture}/upstream/artifacts/link"
  "${_fixture}/upstream/artifacts/runtime/reduce.resources"
  "${_fixture}/upstream/artifacts/runtime/reduce.fonts")
foreach(_artifact IN ITEMS
    pure-reduce-upstream.stamp reduce-upstream-metrics.json
    artifacts/reduce.img
    artifacts/link/libreduce-csl.a artifacts/link/libcrlibm.a
    artifacts/link/libffi.a
    artifacts/runtime/reduce.resources.manifest
    artifacts/runtime/reduce.fonts.manifest)
  file(WRITE "${_fixture}/upstream/${_artifact}" "fixture\n")
endforeach()
file(APPEND "${_fixture}/source/csl/cslbase/winsupport.cpp"
  "\n// deliberately dirty\n")

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    -DPURE_REDUCE_RUN_SOURCE_VERIFICATION=ON
    "-DPURE_REDUCE_SOURCE_DIR=${_fixture}/source"
    -DPURE_REDUCE_VERIFIED_COMMIT=7efba90661139ae9c73c99fddd55f3fb2fabf69a
    -DPURE_REDUCE_SOURCE_TREE_SHA256=134a68fdb10403d3a4c69051eb4e133803ff2659784f2d38ac4d94c7ee9f86d8
    -P "${PURE_REDUCE_UPSTREAM_MODULE}"
  RESULT_VARIABLE _build_result
  OUTPUT_VARIABLE _build_output ERROR_VARIABLE _build_error)
file(READ "${_fixture}/build/build.ninja" _build_graph)
file(REMOVE_RECURSE "${_fixture}")
if(_build_result EQUAL 0)
  message(FATAL_ERROR
    "up-to-date artifact stamp accepted a dirty verified source tree")
endif()
if(NOT _build_graph MATCHES
    "build pure-reduce-upstream: phony[^\n]*pure-reduce-upstream-runtime-ensure" OR
   NOT _build_graph MATCHES
    "build pure-reduce-upstream-runtime-ensure: phony[^\n]*pure-reduce-upstream-build-ensure" OR
   NOT _build_graph MATCHES
    "build pure-reduce-upstream-build-ensure: phony[^\n]*pure-reduce-upstream-source-verify")
  message(FATAL_ERROR
    "upstream target does not depend on the always-run source verifier")
endif()
set(_combined "${_build_output}${_build_error}")
if(NOT _combined MATCHES "REDUCE source tree is dirty")
  message(FATAL_ERROR
    "dirty-source build failed for the wrong reason:\n${_combined}")
endif()

message(STATUS "pure-reduce upstream revalidation passed")
