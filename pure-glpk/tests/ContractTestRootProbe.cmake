cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS BINARY_DIR EXPECTED_LEAF ROOT_SAFETY_PROBE)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

include("${CMAKE_CURRENT_LIST_DIR}/ContractTestRoot.cmake")
pure_glpk_validate_contract_test_root("${EXPECTED_LEAF}" unused_test_root)
message(FATAL_ERROR "ROOT_SAFETY_PROBE accepted unsafe BINARY_DIR")
