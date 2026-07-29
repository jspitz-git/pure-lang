foreach (required_variable
    PURE_EXECUTABLE PURE_PREFIX SOURCE_DIR BRIDGE_DIR TEST_SCRIPT OCTAVE_ROOT
    EXPECTED_OUTPUT)
  if (NOT DEFINED ${required_variable} OR "${${required_variable}}" STREQUAL "")
    message(FATAL_ERROR
      "${required_variable} is required to run the Pure/Octave test.")
  endif ()
endforeach ()

set(ENV{PATH} "${PURE_PREFIX}/bin;C:/Windows/System32;C:/Windows")
set(ENV{PURE_OCTAVE_ROOT} "${OCTAVE_ROOT}")
unset(ENV{PURELIB})
unset(ENV{OCTAVE_HOME})
unset(ENV{OCTAVE_EXEC_HOME})
unset(ENV{OCTAVE_PATH})
unset(ENV{OCTAVE_EXEC_PATH})

execute_process(
  COMMAND "${PURE_EXECUTABLE}" -q --norc
    -I "${SOURCE_DIR}" -L "${BRIDGE_DIR}" -x "${TEST_SCRIPT}"
  WORKING_DIRECTORY "${SOURCE_DIR}"
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
