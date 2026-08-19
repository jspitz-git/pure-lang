cmake_minimum_required(VERSION 3.25)

if(NOT DEFINED RUNNER OR NOT IS_ABSOLUTE "${RUNNER}" OR
   NOT EXISTS "${RUNNER}")
  message(FATAL_ERROR "RUNNER must be an absolute existing path")
endif()
if(NOT DEFINED SMOKE_OUTER_TIMEOUT_SECONDS OR
   NOT "${SMOKE_OUTER_TIMEOUT_SECONDS}" MATCHES "^[1-9][0-9]*$")
  message(FATAL_ERROR
    "SMOKE_OUTER_TIMEOUT_SECONDS must be a positive integer")
endif()

math(EXPR exhausted_reserve_seconds
  "${SMOKE_OUTER_TIMEOUT_SECONDS} - 3 - 20")
if(exhausted_reserve_seconds LESS 1)
  message(FATAL_ERROR "Outer timeout is too small for the contract fixtures")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    -DSMOKE_OUTER_TIMEOUT_SECONDS=${SMOKE_OUTER_TIMEOUT_SECONDS}
    -DSMOKE_PORT_PROBE_TIMEOUT_SECONDS=3
    -DSMOKE_PURE_CHILD_TIMEOUT_SECONDS=20
    -DSMOKE_SETUP_CLEANUP_RESERVE_SECONDS=${exhausted_reserve_seconds}
    -DSMOKE_BUDGET_CHECK_ONLY=ON
    -P "${RUNNER}"
  RESULT_VARIABLE exhausted_result
  OUTPUT_VARIABLE exhausted_output
  ERROR_VARIABLE exhausted_error)
if(exhausted_result STREQUAL "0")
  message(FATAL_ERROR
    "Runner accepted timeout budgets that consume the outer timeout")
endif()
if(NOT exhausted_error MATCHES "Smoke timeout budget invariant")
  message(FATAL_ERROR
    "Runner rejected the exhausted budget for the wrong reason. "
    "stdout=[${exhausted_output}] stderr=[${exhausted_error}]")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    -DSMOKE_OUTER_TIMEOUT_SECONDS=${SMOKE_OUTER_TIMEOUT_SECONDS}
    -DSMOKE_BUDGET_CHECK_ONLY=ON
    -P "${RUNNER}"
  RESULT_VARIABLE valid_result
  OUTPUT_VARIABLE valid_output
  ERROR_VARIABLE valid_error)
if(NOT valid_result STREQUAL "0")
  message(FATAL_ERROR
    "Runner's default budgets leave no cleanup margin. exit=${valid_result} "
    "stdout=[${valid_output}] stderr=[${valid_error}]")
endif()
