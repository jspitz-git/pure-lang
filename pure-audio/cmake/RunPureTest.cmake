# Reusable entry points for build-tree and installed-tree contract consumers.
# The native owner fixes the root next to itself and validates every operation.
function(pure_audio_create_leaf output)
  execute_process(COMMAND "${PURE_AUDIO_RUNNER}" --create-leaf
    RESULT_VARIABLE result OUTPUT_VARIABLE leaf ERROR_VARIABLE error
    OUTPUT_STRIP_TRAILING_WHITESPACE TIMEOUT 10)
  if(NOT result EQUAL 0)
    message(FATAL_ERROR "Cannot create owned Pure test leaf: ${result}\n${error}")
  endif()
  set(${output} "${leaf}" PARENT_SCOPE)
endfunction()

function(pure_audio_cleanup_leaf leaf)
  execute_process(COMMAND "${PURE_AUDIO_RUNNER}" --cleanup --cwd "${leaf}"
    RESULT_VARIABLE result ERROR_VARIABLE error TIMEOUT 15)
  if(NOT result EQUAL 0)
    message(FATAL_ERROR "Cannot clean owned Pure test leaf: ${result}\n${error}")
  endif()
endfunction()

function(pure_audio_run_fixture)
  foreach(required PURE_AUDIO_RUNNER PURE_EXECUTABLE PURE_SOURCE_DIR MODULE_DIR TEST_SCRIPT RUNTIME_DIRS)
    if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
      message(FATAL_ERROR "${required} is required")
    endif()
  endforeach()
  if(NOT DEFINED TEST_TIMEOUT)
    set(TEST_TIMEOUT 45000)
  endif()
  pure_audio_create_leaf(leaf)
  set(args --pure "${PURE_EXECUTABLE}" --script "${TEST_SCRIPT}"
    --token auto --timeout "${TEST_TIMEOUT}" --cwd "${leaf}"
    --module-dir "${MODULE_DIR}" --path-entry "${MODULE_DIR}")
  foreach(dir IN LISTS RUNTIME_DIRS)
    list(APPEND args --path-entry "${dir}")
  endforeach()
  foreach(dir IN ITEMS "${PURE_SOURCE_DIR}" "${PURE_SOURCE_DIR}/fftw"
      "${PURE_SOURCE_DIR}/samplerate" "${PURE_SOURCE_DIR}/sndfile"
      "${PURE_SOURCE_DIR}/realtime" "${PURE_SOURCE_DIR}/tests")
    # Installed trees may flatten all interfaces into one explicit directory.
    if(IS_DIRECTORY "${dir}")
      list(APPEND args --include "${dir}")
    endif()
  endforeach()
  foreach(line IN LISTS PURE_AUDIO_STDERR_ALLOWLIST)
    list(APPEND args --allow-stderr "${line}")
  endforeach()
  math(EXPR outer_timeout "${TEST_TIMEOUT}/1000+15")
  execute_process(COMMAND "${PURE_AUDIO_RUNNER}" ${args}
    RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error
    TIMEOUT "${outer_timeout}" ENCODING UTF-8)
  pure_audio_cleanup_leaf("${leaf}")
  if(NOT result EQUAL 0)
    message(FATAL_ERROR "Pure fixture failed (${result})\nstdout:\n${output}\nstderr:\n${error}")
  endif()
  message(STATUS "${output}")
endfunction()

if(NOT PURE_AUDIO_RUNNER_HELPERS_ONLY)
  pure_audio_run_fixture()
endif()
