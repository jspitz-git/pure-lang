foreach (required_variable
    CMAKE_COMMAND AUDIT_SCRIPT OBJDUMP LOADER IMPLEMENTATION PURE_LIBRARY
    PURE_RUNTIME_DIR OCTAVE_RUNTIME_DIR EXPECTED_DIAGNOSTIC)
  if (NOT DEFINED ${required_variable} OR "${${required_variable}}" STREQUAL "")
    message(FATAL_ERROR
      "${required_variable} is required for the runtime ownership mutation.")
  endif ()
endforeach ()

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DOBJDUMP=${OBJDUMP}"
    "-DLOADER=${LOADER}"
    "-DIMPLEMENTATION=${IMPLEMENTATION}"
    "-DPURE_LIBRARY=${PURE_LIBRARY}"
    "-DPURE_RUNTIME_DIR=${PURE_RUNTIME_DIR}"
    "-DOCTAVE_RUNTIME_DIR=${OCTAVE_RUNTIME_DIR}"
    -P "${AUDIT_SCRIPT}"
  RESULT_VARIABLE audit_result
  OUTPUT_VARIABLE audit_stdout
  ERROR_VARIABLE audit_stderr)
set(audit_output "${audit_stdout}${audit_stderr}")

if (audit_result EQUAL 0)
  message(FATAL_ERROR
    "Runtime ownership audit accepted a foreign Pure runtime library.")
endif ()

string(FIND "${audit_output}" "${EXPECTED_DIAGNOSTIC}" diagnostic_position)
if (diagnostic_position EQUAL -1)
  message(FATAL_ERROR
    "Runtime ownership audit failed for the wrong reason; expected "
    "'${EXPECTED_DIAGNOSTIC}':\n${audit_output}")
endif ()
