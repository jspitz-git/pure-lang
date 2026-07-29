foreach (required_variable MKOCTFILE PROBE_SOURCE PROBE_BINARY OCTAVE_RUNTIME_DIR)
  if (NOT DEFINED ${required_variable} OR "${${required_variable}}" STREQUAL "")
    message(FATAL_ERROR "${required_variable} is required to run the embedding probe.")
  endif ()
endforeach ()

set(ENV{PATH} "${OCTAVE_RUNTIME_DIR};C:/Windows/System32;C:/Windows")
unset(ENV{OCTAVE_HOME})
unset(ENV{OCTAVE_PATH})
unset(ENV{OCTAVE_EXEC_PATH})

get_filename_component(PROBE_BINARY_DIR "${PROBE_BINARY}" DIRECTORY)
get_filename_component(PROBE_BINARY_NAME "${PROBE_BINARY}" NAME)

execute_process(
  COMMAND "${MKOCTFILE}" --link-stand-alone -o "${PROBE_BINARY_NAME}" "${PROBE_SOURCE}"
  RESULT_VARIABLE build_result
  WORKING_DIRECTORY "${PROBE_BINARY_DIR}"
  OUTPUT_VARIABLE build_stdout
  ERROR_VARIABLE build_stderr)
if (NOT build_result EQUAL 0)
  message(FATAL_ERROR "mkoctfile failed (${build_result}):\n${build_stdout}${build_stderr}")
endif ()

execute_process(
  COMMAND "${PROBE_BINARY}"
  RESULT_VARIABLE probe_result
  OUTPUT_VARIABLE probe_stdout
  ERROR_VARIABLE probe_stderr)
if (NOT probe_result EQUAL 0)
  message(FATAL_ERROR "Embedding probe failed (${probe_result}):\n${probe_stdout}${probe_stderr}")
endif ()
if (NOT probe_stdout MATCHES "PURE_OCTAVE_EMBED_PROBE_OK:5")
  message(FATAL_ERROR "Embedding probe did not report success:\n${probe_stdout}${probe_stderr}")
endif ()
