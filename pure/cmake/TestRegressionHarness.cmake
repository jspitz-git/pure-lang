if(NOT DEFINED PURE_SH_EXECUTABLE OR NOT DEFINED PURE_REGRESSION_HARNESS OR
   NOT DEFINED PURE_RUN_TEST OR NOT DEFINED PURE_SOURCE_DIR OR
   NOT DEFINED PURE_PATH_LIST_MODULE OR
   NOT DEFINED PURE_CONFIGURED_TEST_JOBS)
  message(FATAL_ERROR "Missing regression harness contract arguments")
endif()

include("${PURE_PATH_LIST_MODULE}")

set(fixture "${CMAKE_CURRENT_BINARY_DIR}/regression-harness-contract")
file(REMOVE_RECURSE "${fixture}")
file(MAKE_DIRECTORY "${fixture}/test")

get_filename_component(shell_directory "${PURE_SH_EXECUTABLE}" DIRECTORY)
pure_prepend_path(harness_path "${shell_directory}" "$ENV{PATH}" "${WIN32}")
set(ENV{PATH} "${harness_path}")

pure_prepend_path(posix_contract "/opt/Pure Tools/bin"
  "/usr/local/bin:/usr/bin:/bin" FALSE)
if(NOT posix_contract STREQUAL
    "/opt/Pure Tools/bin:/usr/local/bin:/usr/bin:/bin")
  message(FATAL_ERROR
    "POSIX regression PATH construction used the wrong separator: "
    "[${posix_contract}]")
endif()

if(WIN32 AND NOT PURE_CONFIGURED_TEST_JOBS STREQUAL "1")
  message(FATAL_ERROR
    "Windows nested regression is configured with TEST_JOBS="
    "${PURE_CONFIGURED_TEST_JOBS}, expected 1")
endif()

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
set(emitted_golden "${fixture}/golden-emitted.log")
file(WRITE "${fixture}/pure"
  "#!/bin/sh\ncat '${golden_file}'\ncp '${golden_file}' '${emitted_golden}'\nexit 23\n")
file(CHMOD "${fixture}/run-test" "${fixture}/pure"
  PERMISSIONS
    OWNER_READ OWNER_WRITE OWNER_EXECUTE
    GROUP_READ GROUP_EXECUTE
    WORLD_READ WORLD_EXECUTE)

if(WIN32)
  set(harness_command "${PURE_SH_EXECUTABLE}" "${PURE_REGRESSION_HARNESS}")
else()
  set(harness_command "${PURE_REGRESSION_HARNESS}")
endif()
execute_process(
  COMMAND ${harness_command} -j 1 -v "${test_file}"
  WORKING_DIRECTORY "${fixture}"
  RESULT_VARIABLE harness_result
  OUTPUT_VARIABLE harness_output
  ERROR_VARIABLE harness_error
)

set(golden_emission_error "")
if(NOT EXISTS "${emitted_golden}")
  set(golden_emission_error
    "Regression fake interpreter did not emit the golden output")
else()
  file(READ "${golden_file}" expected_golden)
  file(READ "${emitted_golden}" actual_golden)
  if(NOT actual_golden STREQUAL expected_golden)
    set(golden_emission_error
      "Regression fake interpreter emitted output other than the golden log")
  endif()
endif()
file(REMOVE_RECURSE "${fixture}")
message("${harness_output}${harness_error}")
if(golden_emission_error)
  message(FATAL_ERROR "${golden_emission_error}")
endif()
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
