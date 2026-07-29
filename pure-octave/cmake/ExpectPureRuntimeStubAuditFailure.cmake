foreach (required_variable AUDIT_SCRIPT OBJDUMP IMPLEMENTATION PURE_RUNTIME_STUB
    EXPECTED_DIAGNOSTIC)
  if (NOT DEFINED ${required_variable} OR "${${required_variable}}" STREQUAL "")
    message(FATAL_ERROR
      "${required_variable} is required for the stub mutation test.")
  endif ()
endforeach ()

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DOBJDUMP=${OBJDUMP}"
    "-DIMPLEMENTATION=${IMPLEMENTATION}"
    "-DPURE_RUNTIME_STUB=${PURE_RUNTIME_STUB}"
    -P "${AUDIT_SCRIPT}"
  RESULT_VARIABLE audit_result
  OUTPUT_VARIABLE audit_stdout
  ERROR_VARIABLE audit_stderr)
set(audit_output "${audit_stdout}${audit_stderr}")
if (audit_result EQUAL 0)
  message(FATAL_ERROR "Mutated Pure runtime stub unexpectedly passed the audit.")
endif ()
if (NOT audit_output MATCHES "${EXPECTED_DIAGNOSTIC}")
  message(FATAL_ERROR
    "Expected mutation diagnostic '${EXPECTED_DIAGNOSTIC}', got:\n"
    "${audit_output}")
endif ()
