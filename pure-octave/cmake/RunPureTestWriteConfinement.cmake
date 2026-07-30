foreach (required_variable
    CMAKE_COMMAND PURE_EXECUTABLE PURE_PREFIX SOURCE_DIR BRIDGE_DIR TEST_SCRIPT
    OCTAVE_ROOT RUN_PURE_TEST RESTRICTED_RUNNER WORK_ROOT OUTSIDE_POISON
    WRITE_AUDIT_CLEANUP_BASE EXPECTED_OUTPUT EXPECTED_RESULT)
  if (NOT DEFINED ${required_variable} OR "${${required_variable}}" STREQUAL "")
    message(FATAL_ERROR
      "${required_variable} is required for the write confinement regression.")
  endif ()
endforeach ()

set(audit_root "${WORK_ROOT}/audit")
set(allowed_root "${audit_root}/allowed")
file(REMOVE_RECURSE "${WORK_ROOT}")
file(REMOVE "${OUTSIDE_POISON}")
file(MAKE_DIRECTORY "${allowed_root}")

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
    "-DPURE_PREFIX=${PURE_PREFIX}"
    "-DSOURCE_DIR=${SOURCE_DIR}"
    "-DBRIDGE_DIR=${BRIDGE_DIR}"
    "-DTEST_SCRIPT=${TEST_SCRIPT}"
    "-DOCTAVE_ROOT=${OCTAVE_ROOT}"
    "-DTEST_WORKING_DIRECTORY=${allowed_root}"
    "-DTEST_HOME=${allowed_root}"
    "-DPOISON_MARKER=${OUTSIDE_POISON}"
    "-DEXPECTED_RESULT=${EXPECTED_RESULT}"
    "-DEXPECTED_OUTPUT=${EXPECTED_OUTPUT}"
    "-DREQUIRE_CLEAN_OUTPUT=ON"
    "-DWRITE_AUDIT_ROOT=${audit_root}"
    "-DALLOWED_WRITE_ROOT=${allowed_root}"
    "-DRESTRICT_WRITES=ON"
    "-DRESTRICTED_RUNNER=${RESTRICTED_RUNNER}"
    "-DCLEAN_WRITE_AUDIT_ROOT=ON"
    "-DWRITE_AUDIT_CLEANUP_BASE=${WRITE_AUDIT_CLEANUP_BASE}"
    -P "${RUN_PURE_TEST}"
  RESULT_VARIABLE test_result
  OUTPUT_VARIABLE test_stdout
  ERROR_VARIABLE test_stderr)
set(test_output "${test_stdout}${test_stderr}")

if (test_result EQUAL 0 AND EXISTS "${OUTSIDE_POISON}")
  file(REMOVE "${OUTSIDE_POISON}")
  file(REMOVE_RECURSE "${WORK_ROOT}")
  message(FATAL_ERROR
    "Restricted Pure process reported success after writing outside its "
    "controlled work directory.")
endif ()
if (NOT test_result EQUAL 0)
  if (EXISTS "${OUTSIDE_POISON}")
    set(poison_state "present")
    file(REMOVE "${OUTSIDE_POISON}")
  else ()
    set(poison_state "absent")
  endif ()
  file(REMOVE_RECURSE "${WORK_ROOT}")
  message(FATAL_ERROR
    "Restricted Pure process did not prove outside-write denial "
    "(outside marker ${poison_state}):\n${test_output}")
endif ()

file(REMOVE_RECURSE "${WORK_ROOT}")
if (EXISTS "${OUTSIDE_POISON}" OR EXISTS "${WORK_ROOT}")
  message(FATAL_ERROR "Write confinement regression fixture cleanup failed.")
endif ()
