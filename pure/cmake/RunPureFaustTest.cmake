if(NOT DEFINED PURE_SH_EXECUTABLE OR
   NOT DEFINED PURE_RUN_TEST OR
   NOT DEFINED PURE_FIXTURE_DIR OR
   NOT DEFINED PURE_SCRIPT)
  message(FATAL_ERROR "Missing Pure Faust test driver arguments")
endif()

function(stage_faust_fixture source destination)
  file(COPY_FILE "${source}" "${destination}")
  file(TOUCH "${destination}")
endfunction()

stage_faust_fixture(
  "${PURE_FIXTURE_DIR}/reload-a.bc"
  "${PURE_FIXTURE_DIR}/lifecycle-a.bc")
file(COPY_FILE
  "${PURE_FIXTURE_DIR}/lifecycle-a.bc"
  "${PURE_FIXTURE_DIR}/lifecycle_reload.bc")
file(TOUCH "${PURE_FIXTURE_DIR}/lifecycle_reload.bc")
execute_process(COMMAND "${CMAKE_COMMAND}" -E sleep 1)
stage_faust_fixture(
  "${PURE_FIXTURE_DIR}/reload-unresolved.bc"
  "${PURE_FIXTURE_DIR}/lifecycle-b-unresolved.bc")
execute_process(COMMAND "${CMAKE_COMMAND}" -E sleep 1)
stage_faust_fixture(
  "${PURE_FIXTURE_DIR}/reload-b.bc"
  "${PURE_FIXTURE_DIR}/lifecycle-c.bc")
execute_process(COMMAND "${CMAKE_COMMAND}" -E sleep 1)
stage_faust_fixture(
  "${PURE_FIXTURE_DIR}/reload-float.bc"
  "${PURE_FIXTURE_DIR}/lifecycle-float.bc")

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
