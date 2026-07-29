foreach (required_variable
    PURE_EXECUTABLE PURE_PREFIX SOURCE_DIR BRIDGE_DIR TEST_SCRIPT OCTAVE_ROOT
    EXPECTED_OUTPUT)
  if (NOT DEFINED ${required_variable} OR "${${required_variable}}" STREQUAL "")
    message(FATAL_ERROR
      "${required_variable} is required to run the Pure/Octave test.")
  endif ()
endforeach ()

set(pure_working_directory "${SOURCE_DIR}")
if (DEFINED TEST_WORKING_DIRECTORY AND
    NOT "${TEST_WORKING_DIRECTORY}" STREQUAL "")
  set(pure_working_directory "${TEST_WORKING_DIRECTORY}")
endif ()
set(ENV{PATH} "${PURE_PREFIX}/bin;C:/Windows/System32;C:/Windows")
set(ENV{PURE_OCTAVE_ROOT} "${OCTAVE_ROOT}")
unset(ENV{PURELIB})
unset(ENV{OCTAVE_HOME})
unset(ENV{OCTAVE_EXEC_HOME})
unset(ENV{OCTAVE_PATH})
unset(ENV{OCTAVE_EXEC_PATH})

if (DEFINED TEST_HOME AND NOT "${TEST_HOME}" STREQUAL "")
  set(ENV{HOME} "${TEST_HOME}")
  set(ENV{USERPROFILE} "${TEST_HOME}")
endif ()
if (DEFINED POISON_MARKER AND NOT "${POISON_MARKER}" STREQUAL "")
  set(ENV{PURE_OCTAVE_POISON_MARKER} "${POISON_MARKER}")
else ()
  unset(ENV{PURE_OCTAVE_POISON_MARKER})
endif ()

if (DEFINED POISON_INIT_FILE AND NOT "${POISON_INIT_FILE}" STREQUAL "")
  set(ENV{OCTAVE_INITFILE} "${POISON_INIT_FILE}")
else ()
  unset(ENV{OCTAVE_INITFILE})
endif ()

if (DEFINED POISON_HISTORY_FILE AND
    NOT "${POISON_HISTORY_FILE}" STREQUAL "")
  set(ENV{OCTAVE_HISTFILE} "${POISON_HISTORY_FILE}")
else ()
  unset(ENV{OCTAVE_HISTFILE})
endif ()
execute_process(
  COMMAND "${PURE_EXECUTABLE}" -q --norc
    -I "${SOURCE_DIR}" -L "${BRIDGE_DIR}" -x "${TEST_SCRIPT}"
  WORKING_DIRECTORY "${pure_working_directory}"
  RESULT_VARIABLE pure_result
  OUTPUT_VARIABLE pure_stdout
  ERROR_VARIABLE pure_stderr)
if (NOT pure_result EQUAL 0)
  message(FATAL_ERROR
    "Pure/Octave test failed (${pure_result}):\n${pure_stdout}${pure_stderr}")
endif ()
if (NOT pure_stdout MATCHES "${EXPECTED_OUTPUT}")
  message(FATAL_ERROR
    "Pure/Octave test omitted '${EXPECTED_OUTPUT}':\n${pure_stdout}${pure_stderr}")
endif ()
if (REQUIRE_CLEAN_OUTPUT)
  string(STRIP "${pure_stdout}" stripped_stdout)
  string(STRIP "${pure_stderr}" stripped_stderr)
  if (NOT stripped_stdout STREQUAL EXPECTED_OUTPUT)
    message(FATAL_ERROR
      "Pure/Octave test emitted unexpected stdout:\n${pure_stdout}")
  endif ()
  if (NOT stripped_stderr STREQUAL "")
    message(FATAL_ERROR
      "Pure/Octave test emitted stderr:\n${pure_stderr}")
  endif ()
endif ()
