cmake_minimum_required(VERSION 3.25)
project(PureReduce LANGUAGES NONE)

set(PURE_REDUCE_SOURCE_DIR "" CACHE PATH
  "Existing checkout of pinned REDUCE sources")
set(PURE_REDUCE_UPSTREAM_COMMIT
  "7efba90661139ae9c73c99fddd55f3fb2fabf69a")

include("${CMAKE_CURRENT_LIST_DIR}/cmake/ReduceSource.cmake")

include(CTest)
if(BUILD_TESTING)
  add_test(
    NAME pure-reduce-source-contract
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_REDUCE_SOURCE_DIR=${PURE_REDUCE_SOURCE_DIR}"
      -P "${CMAKE_CURRENT_LIST_DIR}/tests/source-contract.cmake")
  set_tests_properties(pure-reduce-source-contract PROPERTIES LABELS "reduce")
endif()
