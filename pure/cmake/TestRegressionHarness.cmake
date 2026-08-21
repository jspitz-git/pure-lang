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

if(NOT PURE_CONFIGURED_TEST_JOBS MATCHES "^[1-9][0-9]*$")
  message(FATAL_ERROR
    "Configured regression TEST_JOBS is not a positive integer: "
    "${PURE_CONFIGURED_TEST_JOBS}")
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

file(MAKE_DIRECTORY "${fixture}/bin" "${fixture}/lib" "${fixture}/test")
file(COPY_FILE "${PURE_RUN_TEST}" "${fixture}/run-test")
file(READ "${PURE_REGRESSION_HARNESS}" scheduler_harness)
string(REGEX REPLACE "srcdir=[^\n]*" "srcdir=\"${fixture}\""
  scheduler_harness "${scheduler_harness}")
file(WRITE "${fixture}/run-tests" "${scheduler_harness}")
file(WRITE "${fixture}/lib/prelude.pure" "1:prelude\n")
file(WRITE "${fixture}/test/prelude.log" "prelude\n")
file(WRITE "${fixture}/test/test001.pure" "1:slow\n")
file(WRITE "${fixture}/test/test001.log" "slow\n")
file(WRITE "${fixture}/test/test002.pure" "1:fast\n")
file(WRITE "${fixture}/test/test002.log" "fast\n")
file(WRITE "${fixture}/bin/find" [=[#!/bin/sh
printf '%s\n' '@FIXTURE@/test\test001.pure' '@FIXTURE@/test\test002.pure'
]=])
file(WRITE "${fixture}/pure" [=[#!/bin/sh
IFS=: read delay payload
if mkdir '@FIXTURE@/active' 2>/dev/null; then
  owns_active=1
else
  : > '@FIXTURE@/overlap'
  owns_active=0
fi
sleep "$delay"
test "$owns_active" -eq 0 || rmdir '@FIXTURE@/active'
printf '%s\n' "$payload"
]=])
file(READ "${fixture}/pure" scheduler_interpreter)
string(REPLACE "@FIXTURE@" "${fixture}"
  scheduler_interpreter "${scheduler_interpreter}")
file(WRITE "${fixture}/pure" "${scheduler_interpreter}")
file(READ "${fixture}/bin/find" scheduler_find)
string(REPLACE "@FIXTURE@" "${fixture}" scheduler_find "${scheduler_find}")
file(WRITE "${fixture}/bin/find" "${scheduler_find}")
file(CHMOD
  "${fixture}/bin/find" "${fixture}/run-test" "${fixture}/run-tests"
  "${fixture}/pure"
  PERMISSIONS
    OWNER_READ OWNER_WRITE OWNER_EXECUTE
    GROUP_READ GROUP_EXECUTE
    WORLD_READ WORLD_EXECUTE)
if(WIN32)
  set(scheduler_harness_command
    "${PURE_SH_EXECUTABLE}" "${fixture}/run-tests")
else()
  set(scheduler_harness_command "${fixture}/run-tests")
endif()
pure_prepend_path(scheduler_path "${fixture}/bin" "$ENV{PATH}" "${WIN32}")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env "PATH=${scheduler_path}"
    ${scheduler_harness_command} -j 2
  WORKING_DIRECTORY "${fixture}"
  RESULT_VARIABLE scheduler_result
  OUTPUT_VARIABLE scheduler_output
  ERROR_VARIABLE scheduler_error
)
set(scheduler_combined "${scheduler_output}${scheduler_error}")
if(NOT scheduler_result EQUAL 0)
  file(REMOVE_RECURSE "${fixture}")
  message(FATAL_ERROR
    "Two-worker regression fixture failed:\n${scheduler_combined}")
endif()
if(NOT EXISTS "${fixture}/overlap")
  file(REMOVE_RECURSE "${fixture}")
  message(FATAL_ERROR
    "Two-worker regression fixture did not execute concurrently")
endif()
string(FIND "${scheduler_combined}" "prelude.pure: passed"
  prelude_position)
string(FIND "${scheduler_combined}" "test001.pure: passed"
  slow_position)
string(FIND "${scheduler_combined}" "test002.pure: passed"
  fast_position)
file(REMOVE_RECURSE "${fixture}")
if(prelude_position EQUAL -1 OR slow_position EQUAL -1 OR
   fast_position EQUAL -1 OR NOT prelude_position LESS slow_position OR
   NOT slow_position LESS fast_position)
  message(FATAL_ERROR
    "Parallel regression results were not published in argument order:\n"
    "${scheduler_combined}")
endif()
