foreach(required
    PURE_EXECUTABLE
    PURE_SCRIPT_TEMPLATE
    PURE_FAUST_EXECUTABLE
    PURE_C_COMPILER
    PURE_SOURCE_DIR
    PURE_WORK_ROOT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "Missing Pure inline Faust test argument ${required}")
  endif()
endforeach()

string(RANDOM LENGTH 12 ALPHABET 0123456789abcdef nonce)
set(work_dir "${PURE_WORK_ROOT}/inline Faust ${nonce}")
set(script "${work_dir}/inline DSP test.pure")
file(MAKE_DIRECTORY "${work_dir}")
configure_file("${PURE_SCRIPT_TEMPLATE}" "${script}" @ONLY)

if(WIN32)
  set(faust_command "\"${PURE_FAUST_EXECUTABLE}\"")
  set(clang_command "\"${PURE_C_COMPILER}\"")
else()
  set(faust_command "'${PURE_FAUST_EXECUTABLE}'")
  set(clang_command "'${PURE_C_COMPILER}'")
endif()

execute_process(
  COMMAND
    "${CMAKE_COMMAND}" -E env
    "PURE_FAUST=${faust_command}"
    "PURE_CC=${clang_command}"
    "PURELIB=${PURE_SOURCE_DIR}/lib"
    "PURE_INCLUDE=${PURE_SOURCE_DIR}/test"
    "srcdir=${PURE_SOURCE_DIR}"
    "LC_ALL=C"
    "${PURE_EXECUTABLE}" --norc -v0
  INPUT_FILE "${script}"
  WORKING_DIRECTORY "${work_dir}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error_output
)

string(REPLACE "\r\n" "\n" normalized_output "${output}")
set(expected_output "()\n()\n()\n1,1,42.0\n")
file(GLOB leftovers LIST_DIRECTORIES FALSE "${work_dir}/pure Faust *")
file(REMOVE_RECURSE "${work_dir}")

if(leftovers)
  message(FATAL_ERROR
    "Inline Faust left owned compiler artifacts: ${leftovers}\n${error_output}")
endif()
if(NOT result EQUAL 0)
  message(FATAL_ERROR
    "Pure inline Faust test exited with status ${result}\n"
    "stdout:\n${normalized_output}\n"
    "stderr:\n${error_output}")
endif()
if(NOT normalized_output STREQUAL expected_output)
  message(FATAL_ERROR
    "Pure inline Faust output mismatch\n"
    "expected: [${expected_output}]\n"
    "actual:   [${normalized_output}]\n"
    "stderr:\n${error_output}")
endif()
if(NOT error_output STREQUAL "")
  message(FATAL_ERROR
    "Pure inline Faust emitted unexpected diagnostics:\n${error_output}")
endif()
