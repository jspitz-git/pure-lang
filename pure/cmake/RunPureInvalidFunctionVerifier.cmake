if(NOT DEFINED PURE_EXECUTABLE OR NOT DEFINED PURE_SCRIPT)
  message(FATAL_ERROR "Missing Pure invalid-function verifier test arguments")
endif()

execute_process(
  COMMAND
    "${CMAKE_COMMAND}" -E env PURE_TEST_INVALID_FUNCTION_IR=1
    "${PURE_EXECUTABLE}" --norc --noprelude -q "${PURE_SCRIPT}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)

if(NOT output MATCHES
   "LLVM verifier failed before optimization of 'invalid_function_ir'")
  message(FATAL_ERROR
    "Invalid function IR lacked the pre-optimization verifier diagnostic "
    "(status ${result}):\n${output}")
endif()

message(STATUS "Release pre-optimization verifier rejected invalid function IR")
