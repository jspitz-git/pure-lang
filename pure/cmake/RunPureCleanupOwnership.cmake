if(NOT DEFINED PURE_EXECUTABLE OR NOT DEFINED PURE_SCRIPT OR
   NOT DEFINED PURE_FAILURE_MODE OR NOT DEFINED PURE_EXPECTED_DIAGNOSTIC)
  message(FATAL_ERROR "Missing Pure cleanup ownership test arguments")
endif()

execute_process(
  COMMAND
    "${CMAKE_COMMAND}" -E env
    "PURE_TEST_ORC_FAILURE=${PURE_FAILURE_MODE}"
    PURE_TEST_CLEAN_SHUTDOWN=1
    "${PURE_EXECUTABLE}" --norc --noprelude -q
  INPUT_FILE "${PURE_SCRIPT}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE stdout
  ERROR_VARIABLE stderr
  TIMEOUT 60
)
set(output "${stdout}${stderr}")
message("${output}")
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Pure cleanup ownership child exited with ${result}")
endif()
if(NOT output MATCHES "${PURE_EXPECTED_DIAGNOSTIC}")
  message(FATAL_ERROR "Pure cleanup ownership diagnostic was missing")
endif()
if(NOT output MATCHES "(^|[\r\n])42([\r\n]|$)")
  message(FATAL_ERROR "Pure cleanup ownership child did not recover")
endif()
if(output MATCHES "failed to remove ORC compilation unit")
  message(FATAL_ERROR "Pure cleanup owner was lost before shutdown retry")
endif()
