if(NOT DEFINED PURE_SH_EXECUTABLE OR NOT DEFINED PURE_REGRESSION_HARNESS OR
   NOT DEFINED PURE_RUN_TEST OR NOT DEFINED PURE_SOURCE_DIR)
  message(FATAL_ERROR "Missing regression harness contract arguments")
endif()

set(fixture "${CMAKE_CURRENT_BINARY_DIR}/regression-harness-contract")
file(REMOVE_RECURSE "${fixture}")
file(MAKE_DIRECTORY "${fixture}/test")

get_filename_component(shell_directory "${PURE_SH_EXECUTABLE}" DIRECTORY)
set(ENV{PATH} "${shell_directory};$ENV{PATH}")

set(test_name "test001")
set(test_file "${PURE_SOURCE_DIR}/test/${test_name}.pure")
set(golden_file "${PURE_SOURCE_DIR}/test/${test_name}.log")
foreach(required_file IN ITEMS
    "${PURE_REGRESSION_HARNESS}" "${PURE_RUN_TEST}" "${test_file}"
    "${golden_file}")
  if(NOT EXISTS "${required_file}")
    message(FATAL_ERROR "Regression harness fixture is missing ${required_file}")
  endif()
endforeach()

file(COPY_FILE "${PURE_RUN_TEST}" "${fixture}/run-test")
file(WRITE "${fixture}/pure" "#!/bin/sh\ncat '${golden_file}'\nexit 23\n")

execute_process(
  COMMAND "${PURE_SH_EXECUTABLE}" "${PURE_REGRESSION_HARNESS}" -j 1 -v
          "${test_file}"
  WORKING_DIRECTORY "${fixture}"
  RESULT_VARIABLE harness_result
  OUTPUT_VARIABLE harness_output
  ERROR_VARIABLE harness_error
)

file(REMOVE_RECURSE "${fixture}")
message("${harness_output}${harness_error}")
if(harness_result EQUAL 0)
  message(FATAL_ERROR
    "Regression harness accepted a fake interpreter that emitted golden output and exited 23"
  )
endif()
string(FIND "${harness_output}${harness_error}"
       "interpreter exited with status 23" interpreter_failure_position)
if(interpreter_failure_position EQUAL -1)
  message(FATAL_ERROR "Regression harness did not report the fake interpreter status")
endif()
