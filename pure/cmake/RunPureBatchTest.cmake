if(NOT DEFINED PURE_EXECUTABLE OR NOT DEFINED PURE_SOURCE_DIR OR
   NOT DEFINED PURE_BUILD_DIR OR NOT DEFINED PURE_LD_LIB_PATH)
  message(FATAL_ERROR "Missing Pure batch test driver arguments")
endif()

if(NOT DEFINED PURE_SCRIPT)
  set(PURE_SCRIPT "${PURE_SOURCE_DIR}/test/batch-smoke.pure")
endif()
if(NOT DEFINED PURE_OUTPUT_NAME)
  set(PURE_OUTPUT_NAME "pure-batch-smoke.o")
endif()

if(DEFINED PURE_FIXTURE_SOURCE OR DEFINED PURE_FIXTURE_DESTINATION)
  if(NOT DEFINED PURE_FIXTURE_SOURCE OR
     NOT DEFINED PURE_FIXTURE_DESTINATION)
    message(FATAL_ERROR "Incomplete Pure batch fixture copy arguments")
  endif()
  file(COPY_FILE "${PURE_FIXTURE_SOURCE}" "${PURE_FIXTURE_DESTINATION}")
endif()

set(output "${PURE_BUILD_DIR}/test/${PURE_OUTPUT_NAME}")
file(REMOVE "${output}")

execute_process(
  COMMAND
    "${CMAKE_COMMAND}" -E env
    "${PURE_LD_LIB_PATH}=${PURE_BUILD_DIR}"
    "PURELIB=${PURE_SOURCE_DIR}/lib"
    "${PURE_EXECUTABLE}" --norc --noprelude -c
    "${PURE_SCRIPT}" -o "${output}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE command_output
  ERROR_VARIABLE command_output
)

message("${command_output}")
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Pure batch compilation exited with status ${result}")
endif()
if(NOT EXISTS "${output}")
  message(FATAL_ERROR "Pure batch compilation did not create ${output}")
endif()
file(SIZE "${output}" output_size)
if(output_size EQUAL 0)
  message(FATAL_ERROR "Pure batch compilation created an empty object")
endif()
