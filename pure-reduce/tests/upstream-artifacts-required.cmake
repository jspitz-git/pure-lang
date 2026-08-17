cmake_minimum_required(VERSION 3.25)

foreach(_required IN ITEMS PURE_REDUCE_SOURCE_DIR PURE_REDUCE_UPSTREAM_CONTRACT
    PURE_REDUCE_MSYS2_BASH PURE_REDUCE_MAKE)
  if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
    message(FATAL_ERROR "${_required} is required")
  endif()
endforeach()

set(_empty_root
  "${CMAKE_CURRENT_BINARY_DIR}/pure-reduce-missing-upstream-artifacts")
file(REMOVE_RECURSE "${_empty_root}")
file(MAKE_DIRECTORY "${_empty_root}")
execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DPURE_REDUCE_SOURCE_DIR=${PURE_REDUCE_SOURCE_DIR}"
    "-DPURE_REDUCE_UPSTREAM_BINARY_DIR=${_empty_root}"
    "-DPURE_REDUCE_MSYS2_BASH=${PURE_REDUCE_MSYS2_BASH}"
    "-DPURE_REDUCE_MAKE=${PURE_REDUCE_MAKE}"
    -P "${PURE_REDUCE_UPSTREAM_CONTRACT}"
  RESULT_VARIABLE _contract_result
  OUTPUT_VARIABLE _contract_output
  ERROR_VARIABLE _contract_error)
file(REMOVE_RECURSE "${_empty_root}")

if(_contract_result EQUAL 0)
  message(FATAL_ERROR
    "direct upstream contract passed without real upstream artifacts")
endif()
set(_combined "${_contract_output}${_contract_error}")
if(NOT _combined MATCHES
    "upstream artifacts must be built before running the contract")
  message(FATAL_ERROR
    "missing-artifact contract failed for the wrong reason:\n${_combined}")
endif()

message(STATUS "pure-reduce upstream artifact prerequisite passed")
