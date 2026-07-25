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

set(loader_path "${PURE_BUILD_DIR}")
if(DEFINED ENV{${PURE_LD_LIB_PATH}} AND
   NOT "$ENV{${PURE_LD_LIB_PATH}}" STREQUAL "")
  if(CMAKE_HOST_WIN32)
    string(APPEND loader_path ";$ENV{${PURE_LD_LIB_PATH}}")
  else()
    string(APPEND loader_path ":$ENV{${PURE_LD_LIB_PATH}}")
  endif()
endif()

execute_process(
  COMMAND
    "${CMAKE_COMMAND}" -E env
    "${PURE_LD_LIB_PATH}=${loader_path}"
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

if(PURE_RUN_EXECUTABLE)
  if(NOT DEFINED PURE_EXECUTABLE_SUFFIX OR
     NOT DEFINED PURE_EXPECTED_CXX_COMPILER OR
     NOT DEFINED PURE_MAIN_OBJECT)
    message(FATAL_ERROR "Missing Pure batch executable arguments")
  endif()
  file(COPY_FILE "${PURE_MAIN_OBJECT}" "${PURE_BUILD_DIR}/test/pure_main.o")
  set(executable "${PURE_BUILD_DIR}/test/pure-batch-program${PURE_EXECUTABLE_SUFFIX}")
  file(REMOVE "${executable}")
  if(PURE_SANITIZERS)
    set(
      compiler_environment
      "CXX=${PURE_EXPECTED_CXX_COMPILER} -fsanitize=${PURE_SANITIZERS}"
    )
  else()
    set(compiler_environment --unset=CC --unset=CXX)
  endif()
  execute_process(
    COMMAND
      "${CMAKE_COMMAND}" -E env ${compiler_environment}
      "${PURE_LD_LIB_PATH}=${loader_path}"
      "PURELIB=${PURE_BUILD_DIR}/test"
      "${PURE_EXECUTABLE}" --norc --noprelude -v0100 -c
      "${PURE_SCRIPT}" -o "${executable}"
    RESULT_VARIABLE link_result
    OUTPUT_VARIABLE link_output
    ERROR_VARIABLE link_output
  )
  message("${link_output}")
  if(NOT link_result EQUAL 0 OR NOT EXISTS "${executable}")
    message(FATAL_ERROR "Pure batch executable link failed with status ${link_result}")
  endif()
  set(normalized_link_output "${link_output}")
  set(normalized_expected_cxx "${PURE_EXPECTED_CXX_COMPILER}")
  string(REPLACE "\\" "/" normalized_link_output "${normalized_link_output}")
  string(REPLACE "\\" "/" normalized_expected_cxx "${normalized_expected_cxx}")
  string(FIND "${normalized_link_output}" "${normalized_expected_cxx}" compiler_position)
  if(compiler_position EQUAL -1)
    message(FATAL_ERROR
      "Pure batch executable did not use ${PURE_EXPECTED_CXX_COMPILER}"
    )
  endif()
  execute_process(
    COMMAND
      "${CMAKE_COMMAND}" -E env
      "${PURE_LD_LIB_PATH}=${loader_path}"
      "${executable}"
    RESULT_VARIABLE run_result
    OUTPUT_VARIABLE run_output
    ERROR_VARIABLE run_output
  )
  message("${run_output}")
  if(NOT run_result EQUAL 0)
    message(FATAL_ERROR "Pure batch executable exited with status ${run_result}")
  endif()
endif()
