foreach(required IN ITEMS PURE_EXECUTABLE PURE_SOURCE_DIR MODULE_DIR TEST_KIND)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

set(ENV{PATH} "${MODULE_DIR};$ENV{PATH}")
set(pure_arguments
  --norc
  -I "${PURE_SOURCE_DIR}"
  -I "${PURE_SOURCE_DIR}/pure-stlvec"
  -I "${PURE_SOURCE_DIR}/pure-stlmap"
  -L "${MODULE_DIR}"
)

if(TEST_KIND STREQUAL "stlvec")
  set(test_directory "${PURE_SOURCE_DIR}/pure-stlvec/ut")
  list(APPEND pure_arguments -x "${test_directory}/ut_all.pure")
  set(success_marker "PASSED STLVEC UNIT TESTS")
elseif(TEST_KIND STREQUAL "stlmap")
  set(test_directory "${PURE_SOURCE_DIR}/pure-stlmap/uts")
  file(GLOB map_tests "${test_directory}/uts_*.pure")
  list(SORT map_tests)
  list(APPEND pure_arguments -x "${test_directory}/check_uts.pure")
  list(APPEND pure_arguments ${map_tests})
  set(success_marker "PASSED STLMAP UTS TESTS")
else()
  message(FATAL_ERROR "Unknown TEST_KIND: ${TEST_KIND}")
endif()

execute_process(
  COMMAND "${PURE_EXECUTABLE}" ${pure_arguments}
  WORKING_DIRECTORY "${test_directory}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
  ENCODING UTF-8
)

if(NOT result EQUAL 0)
  message(FATAL_ERROR
    "pure-stllib ${TEST_KIND} tests failed (${result})\nstdout:\n${output}\nstderr:\n${error}")
endif()
if(NOT output MATCHES "${success_marker}")
  message(FATAL_ERROR
    "pure-stllib ${TEST_KIND} success marker missing\nstdout:\n${output}\nstderr:\n${error}")
endif()
message(STATUS "${output}")
