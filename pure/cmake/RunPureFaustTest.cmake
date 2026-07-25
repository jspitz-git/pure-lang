if(NOT DEFINED PURE_SH_EXECUTABLE OR
   NOT DEFINED PURE_RUN_TEST OR
   NOT DEFINED PURE_FIXTURE_DIR OR
   NOT DEFINED PURE_SCRIPT)
  message(FATAL_ERROR "Missing Pure Faust test driver arguments")
endif()

file(
  COPY_FILE
  "${PURE_FIXTURE_DIR}/reload-a.bc"
  "${PURE_FIXTURE_DIR}/reload.bc"
)

execute_process(
  COMMAND
    "${PURE_SH_EXECUTABLE}" "${PURE_RUN_TEST}" -L "${PURE_FIXTURE_DIR}"
  INPUT_FILE "${PURE_SCRIPT}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)

message("${output}")
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Pure Faust test exited with status ${result}")
endif()
