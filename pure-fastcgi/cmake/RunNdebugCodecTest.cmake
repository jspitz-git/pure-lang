if(NOT DEFINED PROGRAM OR PROGRAM STREQUAL "")
  message(FATAL_ERROR "PROGRAM is required")
endif()

if(NOT EXISTS "${PROGRAM}")
  message(FATAL_ERROR "NDEBUG codec test executable does not exist: ${PROGRAM}")
endif()

execute_process(
  COMMAND "${PROGRAM}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE stdout
  ERROR_VARIABLE stderr)

if(NOT result MATCHES "^[0-9]+$" OR NOT result EQUAL 1)
  message(FATAL_ERROR
    "NDEBUG codec test returned ${result}, expected 1\nstdout:\n${stdout}\nstderr:\n${stderr}")
endif()

set(expected_marker "codec checks must remain active under NDEBUG")
string(CONCAT output "${stdout}" "${stderr}")
string(FIND "${output}" "${expected_marker}" marker_offset)
if(marker_offset EQUAL -1)
  message(FATAL_ERROR
    "NDEBUG codec test did not emit its check marker\nstdout:\n${stdout}\nstderr:\n${stderr}")
endif()

message(STATUS "NDEBUG codec checks remained active")
