foreach(required_variable IN ITEMS
    HARNESS MODULE MODULE_SOURCE WORKER TRUNCATED_WORKER TRUNCATED_WRONG_WORKER
    HANG_WORKER PURE_EXECUTABLE PURE_RUNTIME_DIR TEST_ROOT)
  if(NOT DEFINED ${required_variable} OR "${${required_variable}}" STREQUAL "")
    message(FATAL_ERROR "${required_variable} is required")
  endif()
endforeach()

foreach(required_file IN ITEMS
    HARNESS MODULE MODULE_SOURCE WORKER TRUNCATED_WORKER TRUNCATED_WRONG_WORKER
    HANG_WORKER PURE_EXECUTABLE)
  if(NOT EXISTS "${${required_file}}")
    message(FATAL_ERROR "${required_file} does not exist: ${${required_file}}")
  endif()
endforeach()

file(REMOVE_RECURSE "${TEST_ROOT}")
file(MAKE_DIRECTORY "${TEST_ROOT}")
get_filename_component(module_name "${MODULE}" NAME)
get_filename_component(module_source_name "${MODULE_SOURCE}" NAME)
get_filename_component(worker_name "${WORKER}" NAME)
get_filename_component(truncated_worker_name "${TRUNCATED_WORKER}" NAME)
get_filename_component(truncated_wrong_worker_name "${TRUNCATED_WRONG_WORKER}" NAME)
get_filename_component(hang_worker_name "${HANG_WORKER}" NAME)
file(COPY_FILE "${MODULE}" "${TEST_ROOT}/${module_name}" ONLY_IF_DIFFERENT)
file(COPY_FILE "${MODULE_SOURCE}" "${TEST_ROOT}/${module_source_name}"
  ONLY_IF_DIFFERENT)
file(COPY_FILE "${WORKER}" "${TEST_ROOT}/${worker_name}" ONLY_IF_DIFFERENT)
file(COPY_FILE "${TRUNCATED_WORKER}" "${TEST_ROOT}/${truncated_worker_name}"
  ONLY_IF_DIFFERENT)
file(COPY_FILE "${TRUNCATED_WRONG_WORKER}"
  "${TEST_ROOT}/${truncated_wrong_worker_name}" ONLY_IF_DIFFERENT)
file(COPY_FILE "${HANG_WORKER}" "${TEST_ROOT}/${hang_worker_name}"
  ONLY_IF_DIFFERENT)

set(ENV{PATH}
  "${TEST_ROOT};${PURE_RUNTIME_DIR};$ENV{SystemRoot}\\System32;$ENV{SystemRoot};$ENV{SystemRoot}\\System32\\Wbem")
unset(ENV{PURELIB})

function(check_cleanup scenario expected_child_exited expected_pid)
  if(NOT EXISTS "${TEST_ROOT}/${scenario}.txt")
    message(FATAL_ERROR "${scenario} did not write a cleanup report")
  endif()
  file(READ "${TEST_ROOT}/${scenario}.txt" cleanup)
  string(REPLACE "\r\n" "\n" cleanup "${cleanup}")
  string(REPLACE "\n" ";" cleanup_lines "${cleanup}")
  set(child_pid_count 0)
  set(child_exited_count 0)
  set(pipe_closed_count 0)
  set(owned_handles_closed_count 0)
  set(elapsed_ms_count 0)
  foreach(line IN LISTS cleanup_lines)
    if(line STREQUAL "")
      continue()
    endif()
    if(NOT line MATCHES "^([A-Za-z_]+)=([^=]*)$")
      message(FATAL_ERROR "${scenario} cleanup is not ASCII key=value data: ${line}")
    endif()
    set(key "${CMAKE_MATCH_1}")
    set(value "${CMAKE_MATCH_2}")
    if(NOT key IN_LIST allowed_cleanup_keys)
      message(FATAL_ERROR "${scenario} cleanup has unexpected key ${key}")
    endif()
    math(EXPR ${key}_count "${${key}_count} + 1")
    if(${key}_count GREATER 1)
      message(FATAL_ERROR "${scenario} cleanup repeats ${key}")
    endif()
    set(${key}_value "${value}")
  endforeach()
  foreach(key IN LISTS allowed_cleanup_keys)
    if(NOT ${key}_count EQUAL 1)
      message(FATAL_ERROR "${scenario} cleanup is missing ${key}")
    endif()
  endforeach()
  if(expected_pid STREQUAL "positive" AND NOT child_pid_value MATCHES "^[1-9][0-9]*$")
    message(FATAL_ERROR "${scenario} cleanup child_pid is not positive: ${child_pid_value}")
  endif()
  if(expected_pid STREQUAL "zero" AND NOT child_pid_value STREQUAL "0")
    message(FATAL_ERROR "${scenario} cleanup child_pid is not zero: ${child_pid_value}")
  endif()
  foreach(key IN ITEMS child_exited pipe_closed owned_handles_closed)
    if(NOT ${key}_value MATCHES "^[01]$")
      message(FATAL_ERROR "${scenario} cleanup ${key} is not an exact boolean: ${${key}_value}")
    endif()
  endforeach()
  if(NOT child_exited_value STREQUAL "${expected_child_exited}" OR
      NOT pipe_closed_value STREQUAL "1" OR
      NOT owned_handles_closed_value STREQUAL "1")
    message(FATAL_ERROR "${scenario} cleanup has unexpected values:\n${cleanup}")
  endif()
  if(NOT elapsed_ms_value MATCHES "^[0-9]+$")
    message(FATAL_ERROR "${scenario} cleanup elapsed_ms is not numeric: ${elapsed_ms_value}")
  endif()
  if(elapsed_ms_value GREATER_EQUAL 10000)
    message(FATAL_ERROR "${scenario} took ${elapsed_ms_value} ms; expected under 10000")
  endif()
endfunction()

set(allowed_cleanup_keys child_pid child_exited pipe_closed
  owned_handles_closed elapsed_ms)

function(expect_failure scenario expected worker)
  execute_process(
    COMMAND "${HARNESS}" "${PURE_EXECUTABLE}" "${TEST_ROOT}"
      "${TEST_ROOT}/${worker}" --scenario "${scenario}"
      --cleanup-report "${TEST_ROOT}/${scenario}.txt"
    RESULT_VARIABLE result OUTPUT_VARIABLE out ERROR_VARIABLE err
    TIMEOUT 12)
  if(result EQUAL 0 OR NOT "${out}\n${err}" MATCHES "${expected}")
    message(FATAL_ERROR "${scenario} did not fail as ${expected}:\n${out}\n${err}")
  endif()
  check_cleanup("${scenario}" 1 positive)
endfunction()

function(expect_truncated_outcome_rejected)
  execute_process(
    COMMAND "${HARNESS}" "${PURE_EXECUTABLE}" "${TEST_ROOT}"
      "${TEST_ROOT}/${truncated_wrong_worker_name}" --scenario truncated
      --cleanup-report "${TEST_ROOT}/truncated-wrong.txt"
    RESULT_VARIABLE result OUTPUT_VARIABLE out ERROR_VARIABLE err
    TIMEOUT 12)
  if(result EQUAL 0 OR "${out}\n${err}" MATCHES "protocol error while reading PARAMS" OR
      NOT "${out}\n${err}" MATCHES "unexpected truncated sentinel status")
    message(FATAL_ERROR "wrong truncated worker outcome was accepted:\n${out}\n${err}")
  endif()
  check_cleanup("truncated-wrong" 1 positive)
endfunction()

function(expect_launch_failure)
  execute_process(
    COMMAND "${HARNESS}" "${TEST_ROOT}/missing-pure.exe" "${TEST_ROOT}"
      "${TEST_ROOT}/${worker_name}" --scenario success
      --cleanup-report "${TEST_ROOT}/launch-failure.txt"
    RESULT_VARIABLE result OUTPUT_VARIABLE out ERROR_VARIABLE err
    TIMEOUT 12)
  if(result EQUAL 0 OR NOT "${out}\n${err}" MATCHES "CreateProcessW failed")
    message(FATAL_ERROR "launch failure was not reported:\n${out}\n${err}")
  endif()
  check_cleanup("launch-failure" 0 zero)
endfunction()

expect_failure(truncated "protocol error while reading PARAMS"
  "${truncated_worker_name}")
expect_truncated_outcome_rejected()
expect_failure(timeout "deadline expired while waiting for END_REQUEST"
  "${hang_worker_name}")
expect_launch_failure()
