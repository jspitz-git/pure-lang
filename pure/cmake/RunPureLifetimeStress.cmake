if(NOT DEFINED PURE_EXECUTABLE OR
   NOT DEFINED PURE_SCRIPT OR
   NOT DEFINED PURE_EXPECTED)
  message(FATAL_ERROR "Missing Pure lifetime stress test driver arguments")
endif()

execute_process(
  COMMAND "${PURE_EXECUTABLE}" --norc --noprelude -q
  INPUT_FILE "${PURE_SCRIPT}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)

message("${output}")
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Pure lifetime stress test exited with status ${result}")
endif()

file(READ "${PURE_EXPECTED}" expected)
string(STRIP "${output}" output)
string(STRIP "${expected}" expected)
if(NOT output STREQUAL expected)
  message(FATAL_ERROR "Pure lifetime stress test output did not match")
endif()
