foreach (required_variable
    CMAKE_COMMAND PURE_EXECUTABLE PURE_PREFIX SOURCE_DIR BRIDGE_DIR TEST_SCRIPT
    OCTAVE_ROOT RUN_PURE_TEST WORK_ROOT EXPECTED_OUTPUT EXPECTED_DIAGNOSTIC)
  if (NOT DEFINED ${required_variable} OR "${${required_variable}}" STREQUAL "")
    message(FATAL_ERROR
      "${required_variable} is required for the write audit regression.")
  endif ()
endforeach ()

set(allowed_root "${WORK_ROOT}/allowed")
set(outside_root "${WORK_ROOT}/outside")
set(poison_path "${outside_root}/poison.txt")
file(REMOVE_RECURSE "${WORK_ROOT}")
file(MAKE_DIRECTORY "${allowed_root}" "${outside_root}")

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
    "-DPOISON_MARKER=${poison_path}"
    "-DEXPECTED_OUTPUT=${EXPECTED_OUTPUT}"
    "-DREQUIRE_CLEAN_OUTPUT=ON"
    "-DWRITE_AUDIT_ROOT=${WORK_ROOT}"
    "-DALLOWED_WRITE_ROOT=${allowed_root}"
    -P "${RUN_PURE_TEST}"
  RESULT_VARIABLE test_result
  OUTPUT_VARIABLE test_stdout
  ERROR_VARIABLE test_stderr)
set(test_output "${test_stdout}${test_stderr}")

if (test_result EQUAL 0)
  if (EXISTS "${poison_path}")
    set(poison_detail " and left ${poison_path}")
  else ()
    set(poison_detail "")
  endif ()
  file(REMOVE_RECURSE "${WORK_ROOT}")
  message(FATAL_ERROR
    "RunPureTest accepted a write outside its controlled work directory"
    "${poison_detail}.")
endif ()
if (NOT test_output MATCHES "${EXPECTED_DIAGNOSTIC}")
  file(REMOVE_RECURSE "${WORK_ROOT}")
  message(FATAL_ERROR
    "Write audit rejection omitted '${EXPECTED_DIAGNOSTIC}':\n${test_output}")
endif ()
if (NOT EXISTS "${poison_path}")
  file(REMOVE_RECURSE "${WORK_ROOT}")
  message(FATAL_ERROR
    "Poison script did not create its outside-write fixture:\n${test_output}")
endif ()

file(REMOVE_RECURSE "${WORK_ROOT}")
if (EXISTS "${WORK_ROOT}")
  message(FATAL_ERROR "Write audit regression fixture cleanup failed.")
endif ()
