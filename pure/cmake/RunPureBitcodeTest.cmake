if(NOT DEFINED PURE_SH_EXECUTABLE OR
   NOT DEFINED PURE_RUN_TEST OR
   NOT DEFINED PURE_FIXTURE_DIR OR
   NOT DEFINED PURE_SCRIPT)
  message(FATAL_ERROR "Missing Pure bitcode test driver arguments")
endif()

if(DEFINED PURE_C_SOURCE OR DEFINED PURE_BITCODE_OUTPUT OR
   DEFINED PURE_SECOND_C_SOURCE OR DEFINED PURE_SECOND_BITCODE_OUTPUT)
  if(NOT DEFINED PURE_C_COMPILER OR
     NOT DEFINED PURE_C_SOURCE OR NOT DEFINED PURE_BITCODE_OUTPUT OR
     NOT DEFINED PURE_SECOND_C_SOURCE OR
     NOT DEFINED PURE_SECOND_BITCODE_OUTPUT)
    message(FATAL_ERROR "Incomplete Pure bitcode fixture compiler arguments")
  endif()
  execute_process(
    COMMAND
      "${PURE_C_COMPILER}" -O0 -emit-llvm -c "${PURE_C_SOURCE}"
      -o "${PURE_BITCODE_OUTPUT}"
    RESULT_VARIABLE compile_result
    OUTPUT_VARIABLE compile_output
    ERROR_VARIABLE compile_output
  )
  if(NOT compile_result EQUAL 0)
    message(FATAL_ERROR
      "First Pure bitcode fixture compilation exited with status ${compile_result}: ${compile_output}"
    )
  endif()
  execute_process(
    COMMAND
      "${PURE_C_COMPILER}" -O0 -emit-llvm -c "${PURE_SECOND_C_SOURCE}"
      -o "${PURE_SECOND_BITCODE_OUTPUT}"
    RESULT_VARIABLE second_compile_result
    OUTPUT_VARIABLE second_compile_output
    ERROR_VARIABLE second_compile_output
  )
  if(NOT second_compile_result EQUAL 0)
    message(FATAL_ERROR
      "Second Pure bitcode fixture compilation exited with status ${second_compile_result}: ${second_compile_output}"
    )
  endif()
endif()

if(DEFINED PURE_BATCH_OBJECT OR DEFINED PURE_BATCH_EXECUTABLE)
  if(NOT DEFINED PURE_BATCH_OBJECT OR NOT DEFINED PURE_BATCH_EXECUTABLE OR
     NOT DEFINED PURE_CXX_COMPILER OR NOT DEFINED PURE_MAIN_OBJECT OR
     NOT DEFINED PURE_RUNTIME_DIR OR NOT DEFINED PURE_LD_LIB_PATH)
    message(FATAL_ERROR "Missing Pure bitcode batch recovery arguments")
  endif()
  file(REMOVE "${PURE_BATCH_OBJECT}" "${PURE_BATCH_EXECUTABLE}")
  execute_process(
    COMMAND
      "${PURE_SH_EXECUTABLE}" "${PURE_RUN_TEST}" -L "${PURE_FIXTURE_DIR}"
      --noprelude -c "${PURE_SCRIPT}" -o "${PURE_BATCH_OBJECT}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE output
  )
  message("${output}")
  if(NOT result EQUAL 0 OR NOT EXISTS "${PURE_BATCH_OBJECT}")
    message(FATAL_ERROR
      "Pure bitcode batch compilation exited with status ${result}"
    )
  endif()
  set(batch_link_options)
  if(CMAKE_HOST_UNIX AND NOT CMAKE_HOST_APPLE)
    list(APPEND batch_link_options -no-pie -Wl,--no-as-needed)
  endif()
  if(DEFINED PURE_SANITIZERS AND NOT "${PURE_SANITIZERS}" STREQUAL "")
    list(APPEND batch_link_options "-fsanitize=${PURE_SANITIZERS}")
  endif()
  execute_process(
    COMMAND
      "${PURE_CXX_COMPILER}" -o "${PURE_BATCH_EXECUTABLE}"
      "${PURE_MAIN_OBJECT}" "${PURE_BATCH_OBJECT}"
      ${batch_link_options} "-L${PURE_RUNTIME_DIR}" -lpure
    RESULT_VARIABLE link_result
    OUTPUT_VARIABLE link_output
    ERROR_VARIABLE link_output
  )
  message("${link_output}")
  if(NOT link_result EQUAL 0 OR NOT EXISTS "${PURE_BATCH_EXECUTABLE}")
    message(FATAL_ERROR
      "Pure bitcode batch executable link exited with status ${link_result}"
    )
  endif()
  set(loader_path "${PURE_RUNTIME_DIR}")
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
      "${PURE_BATCH_EXECUTABLE}"
    RESULT_VARIABLE run_result
    OUTPUT_VARIABLE run_output
    ERROR_VARIABLE run_error
  )
  message("${run_output}${run_error}")
  if(NOT run_result EQUAL 0)
    message(FATAL_ERROR
      "Pure bitcode batch executable exited with status ${run_result}"
    )
  endif()
  if(NOT "${run_output}" STREQUAL "42\n")
    message(FATAL_ERROR
      "Pure bitcode batch executable did not print the expected literal"
    )
  endif()
  return()
endif()

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
  message(FATAL_ERROR "Pure bitcode test exited with status ${result}")
endif()
