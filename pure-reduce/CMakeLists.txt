cmake_minimum_required(VERSION 3.25)
project(PureReduce LANGUAGES NONE)

set(PURE_REDUCE_SOURCE_DIR "" CACHE PATH
  "Existing checkout of pinned REDUCE sources")
set(PURE_REDUCE_UPSTREAM_COMMIT
  "7efba90661139ae9c73c99fddd55f3fb2fabf69a")
set(PURE_REDUCE_MSYS2_BASH "C:/msys64/usr/bin/bash.exe" CACHE FILEPATH
  "MSYS2 bash used only to build the pinned REDUCE dependency")
set(PURE_REDUCE_MAKE "C:/msys64/usr/bin/make.exe" CACHE FILEPATH
  "GNU make used only to build the pinned REDUCE dependency")
set(PURE_REDUCE_UPSTREAM_BINARY_DIR
  "${CMAKE_CURRENT_BINARY_DIR}/reduce-upstream" CACHE PATH
  "Private binary root for the complete pinned REDUCE build")

include("${CMAKE_CURRENT_LIST_DIR}/cmake/ReduceSource.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/cmake/ReduceUpstream.cmake")

if(PURE_REDUCE_SOURCE_DIR)
  pure_reduce_verify_source(
    "${PURE_REDUCE_SOURCE_DIR}"
    PURE_REDUCE_VERIFIED_COMMIT
    PURE_REDUCE_SOURCE_TREE_SHA256)
  pure_reduce_define_upstream_build()
endif()

include(CTest)
if(BUILD_TESTING)
  add_test(
    NAME pure-reduce-source-contract
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_REDUCE_SOURCE_DIR=${PURE_REDUCE_SOURCE_DIR}"
      -P "${CMAKE_CURRENT_LIST_DIR}/tests/source-contract.cmake")
  set_tests_properties(pure-reduce-source-contract PROPERTIES LABELS "reduce")
  if(PURE_REDUCE_SOURCE_DIR)
    add_test(
      NAME pure-reduce-upstream-contract
      COMMAND "${CMAKE_COMMAND}"
        "-DPURE_REDUCE_SOURCE_DIR=${PURE_REDUCE_SOURCE_DIR}"
        "-DPURE_REDUCE_UPSTREAM_BINARY_DIR=${PURE_REDUCE_UPSTREAM_BINARY_DIR}"
        "-DPURE_REDUCE_MSYS2_BASH=${PURE_REDUCE_MSYS2_BASH}"
        "-DPURE_REDUCE_MAKE=${PURE_REDUCE_MAKE}"
        -P "${CMAKE_CURRENT_LIST_DIR}/tests/upstream-contract.cmake")
    set_tests_properties(pure-reduce-upstream-contract PROPERTIES
      LABELS "reduce")
    add_test(
      NAME pure-reduce-upstream-revalidation
      COMMAND "${CMAKE_COMMAND}"
        "-DPURE_REDUCE_SOURCE_DIR=${PURE_REDUCE_SOURCE_DIR}"
        "-DPURE_REDUCE_UPSTREAM_MODULE=${CMAKE_CURRENT_LIST_DIR}/cmake/ReduceUpstream.cmake"
        "-DPURE_REDUCE_MSYS2_BASH=${PURE_REDUCE_MSYS2_BASH}"
        "-DPURE_REDUCE_MAKE=${PURE_REDUCE_MAKE}"
        -P "${CMAKE_CURRENT_LIST_DIR}/tests/upstream-revalidation.cmake")
    set_tests_properties(pure-reduce-upstream-revalidation PROPERTIES
      LABELS "reduce")
  endif()
endif()
