foreach (required_variable
    CMAKE_COMMAND PURE_EXECUTABLE PURE_PREFIX SOURCE_DIR BRIDGE_DIR
    TEST_SCRIPT OCTAVE_ROOT RUN_PURE_TEST WORK_ROOT)
  if (NOT DEFINED ${required_variable} OR "${${required_variable}}" STREQUAL "")
    message(FATAL_ERROR
      "${required_variable} is required for the poison init test.")
  endif ()
endforeach ()

set(test_home "${WORK_ROOT}/poison-home")
set(init_file "${test_home}/.octaverc")
set(poison_marker "${WORK_ROOT}/poison-init.marker")
set(history_file "${WORK_ROOT}/poison-history")
file(MAKE_DIRECTORY "${test_home}")
file(REMOVE "${init_file}" "${poison_marker}" "${history_file}")
file(WRITE "${init_file}" [=[
PURE_OCTAVE_POISONED = 1;
marker = getenv ("PURE_OCTAVE_POISON_MARKER");
fid = fopen (marker, "wt");
if (fid >= 0)
  fprintf (fid, "POISON_INIT_EXECUTED\n");
  fclose (fid);
endif
]=])
if (NOT EXISTS "${init_file}")
  message(FATAL_ERROR "Poison user init fixture was not created.")
endif ()

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
    "-DPURE_PREFIX=${PURE_PREFIX}"
    "-DSOURCE_DIR=${SOURCE_DIR}"
    "-DBRIDGE_DIR=${BRIDGE_DIR}"
    "-DTEST_SCRIPT=${TEST_SCRIPT}"
    "-DOCTAVE_ROOT=${OCTAVE_ROOT}"
    "-DEXPECTED_OUTPUT=PURE_OCTAVE_POISON_INIT_OK"
    "-DTEST_HOME=${test_home}"
    "-DTEST_WORKING_DIRECTORY=${test_home}"
    "-DPOISON_MARKER=${poison_marker}"
    "-DPOISON_INIT_FILE=${init_file}"
    "-DPOISON_HISTORY_FILE=${history_file}"
    "-DREQUIRE_CLEAN_OUTPUT=ON"
    -P "${RUN_PURE_TEST}"
  RESULT_VARIABLE pure_result
  OUTPUT_VARIABLE pure_stdout
  ERROR_VARIABLE pure_stderr)

if (EXISTS "${history_file}")
  file(REMOVE "${history_file}")
  message(FATAL_ERROR
    "Embedded Octave created a history artifact:\n"
    "${pure_stdout}${pure_stderr}")
endif ()

if (NOT EXISTS "${init_file}")
  message(FATAL_ERROR "Poison user init fixture disappeared during the test.")
endif ()
if (EXISTS "${poison_marker}")
  file(READ "${poison_marker}" marker_contents)
  file(REMOVE "${poison_marker}")
  message(FATAL_ERROR
    "Poison user init was evaluated: ${marker_contents}\n"
    "${pure_stdout}${pure_stderr}")
endif ()
if (NOT pure_result EQUAL 0)
  message(FATAL_ERROR
    "Poison init Pure test failed (${pure_result}):\n"
    "${pure_stdout}${pure_stderr}")
endif ()
