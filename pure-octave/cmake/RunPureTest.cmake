foreach (required_variable
    PURE_EXECUTABLE PURE_PREFIX SOURCE_DIR BRIDGE_DIR TEST_SCRIPT OCTAVE_ROOT
    EXPECTED_OUTPUT)
  if (NOT DEFINED ${required_variable} OR "${${required_variable}}" STREQUAL "")
    message(FATAL_ERROR
      "${required_variable} is required to run the Pure/Octave test.")
  endif ()
endforeach ()

set(expected_result 0)
if (DEFINED EXPECTED_RESULT AND NOT "${EXPECTED_RESULT}" STREQUAL "")
  set(expected_result "${EXPECTED_RESULT}")
endif ()

set(pure_working_directory "${SOURCE_DIR}")
if (DEFINED TEST_WORKING_DIRECTORY AND
    NOT "${TEST_WORKING_DIRECTORY}" STREQUAL "")
  set(pure_working_directory "${TEST_WORKING_DIRECTORY}")
endif ()
file(MAKE_DIRECTORY "${pure_working_directory}")
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

set(write_audit_enabled FALSE)
if ((DEFINED WRITE_AUDIT_ROOT AND NOT "${WRITE_AUDIT_ROOT}" STREQUAL "") OR
    (DEFINED ALLOWED_WRITE_ROOT AND NOT "${ALLOWED_WRITE_ROOT}" STREQUAL ""))
  if (NOT DEFINED WRITE_AUDIT_ROOT OR "${WRITE_AUDIT_ROOT}" STREQUAL "" OR
      NOT DEFINED ALLOWED_WRITE_ROOT OR "${ALLOWED_WRITE_ROOT}" STREQUAL "")
    message(FATAL_ERROR
      "WRITE_AUDIT_ROOT and ALLOWED_WRITE_ROOT must be provided together.")
  endif ()
  include("${CMAKE_CURRENT_LIST_DIR}/FilesystemSnapshot.cmake")
  pure_octave_filesystem_snapshot(
    "${WRITE_AUDIT_ROOT}" "${ALLOWED_WRITE_ROOT}" filesystem_before)
  set(write_audit_enabled TRUE)
endif ()

set(pure_command
  "${PURE_EXECUTABLE}" -q --norc
  -I "${SOURCE_DIR}" -L "${BRIDGE_DIR}" -x "${TEST_SCRIPT}")
if (RESTRICT_WRITES)
  if (NOT DEFINED RESTRICTED_RUNNER OR
      "${RESTRICTED_RUNNER}" STREQUAL "" OR
      NOT EXISTS "${RESTRICTED_RUNNER}")
    message(FATAL_ERROR
      "RESTRICTED_RUNNER is required for write-confined Pure tests.")
  endif ()
  if (NOT DEFINED TEST_WORKING_DIRECTORY OR
      "${TEST_WORKING_DIRECTORY}" STREQUAL "")
    message(FATAL_ERROR
      "Write-confined Pure tests require TEST_WORKING_DIRECTORY.")
  endif ()
  set(ENV{TEMP} "${pure_working_directory}")
  set(ENV{TMP} "${pure_working_directory}")
  list(PREPEND pure_command
    "${RESTRICTED_RUNNER}" "${pure_working_directory}")
endif ()

execute_process(
  COMMAND ${pure_command}
  WORKING_DIRECTORY "${pure_working_directory}"
  RESULT_VARIABLE pure_result
  OUTPUT_VARIABLE pure_stdout
  ERROR_VARIABLE pure_stderr)
set(write_audit_violation FALSE)
if (write_audit_enabled)
  pure_octave_filesystem_snapshot(
    "${WRITE_AUDIT_ROOT}" "${ALLOWED_WRITE_ROOT}" filesystem_after)
  if (NOT filesystem_before STREQUAL filesystem_after)
    set(write_audit_violation TRUE)
  endif ()
endif ()

set(write_audit_cleanup_failed FALSE)
if (CLEAN_WRITE_AUDIT_ROOT)
  if (NOT write_audit_enabled OR
      NOT DEFINED WRITE_AUDIT_CLEANUP_BASE OR
      "${WRITE_AUDIT_CLEANUP_BASE}" STREQUAL "")
    message(FATAL_ERROR
      "Safe write-audit cleanup requires an enabled audit and cleanup base.")
  endif ()
  file(REAL_PATH "${WRITE_AUDIT_ROOT}" normalized_audit_root EXPAND_TILDE)
  file(REAL_PATH "${ALLOWED_WRITE_ROOT}" normalized_allowed_root EXPAND_TILDE)
  file(REAL_PATH "${WRITE_AUDIT_CLEANUP_BASE}" normalized_cleanup_base
    EXPAND_TILDE)
  set(audit_path "${normalized_audit_root}")
  set(cleanup_base_path "${normalized_cleanup_base}")
  cmake_path(IS_PREFIX audit_path "${normalized_allowed_root}" NORMALIZE
    allowed_is_below_audit)
  cmake_path(IS_PREFIX cleanup_base_path "${normalized_audit_root}" NORMALIZE
    audit_is_below_cleanup_base)
  cmake_path(COMPARE "${normalized_audit_root}" EQUAL
    "${normalized_allowed_root}" audit_equals_allowed)
  cmake_path(COMPARE "${normalized_cleanup_base}" EQUAL
    "${normalized_audit_root}" cleanup_base_equals_audit)
  if (NOT allowed_is_below_audit OR audit_equals_allowed OR
      NOT audit_is_below_cleanup_base OR cleanup_base_equals_audit)
    message(FATAL_ERROR
      "Refusing unsafe write-audit cleanup: audit=${normalized_audit_root}, "
      "allowed=${normalized_allowed_root}, base=${normalized_cleanup_base}")
  endif ()
  file(REMOVE_RECURSE "${normalized_audit_root}")
  if (EXISTS "${normalized_audit_root}")
    set(write_audit_cleanup_failed TRUE)
  endif ()
endif ()

if (write_audit_violation)
  message(FATAL_ERROR
    "Pure/Octave test wrote outside its controlled work directory "
    "${ALLOWED_WRITE_ROOT} within audit root ${WRITE_AUDIT_ROOT}.")
endif ()
if (write_audit_cleanup_failed)
  message(FATAL_ERROR
    "Pure/Octave write-audit fixture cleanup failed: ${WRITE_AUDIT_ROOT}")
endif ()
if (NOT pure_result EQUAL expected_result)
  message(FATAL_ERROR
    "Pure/Octave test failed (${pure_result}, expected ${expected_result}):\n${pure_stdout}${pure_stderr}")
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
