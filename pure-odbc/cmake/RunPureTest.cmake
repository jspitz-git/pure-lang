cmake_minimum_required(VERSION 3.25)

include("${CMAKE_CURRENT_LIST_DIR}/../tests/ContractTestRoot.cmake")

foreach(required IN ITEMS
    PURE_EXECUTABLE PURE_SOURCE_DIR MODULE_DIR SCRIPT WORK_DIRECTORY)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()
if(WIN32 AND
    (NOT DEFINED PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY OR
     "${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}" STREQUAL ""))
  message(FATAL_ERROR
    "PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY is required")
endif()
foreach(path_input IN ITEMS PURE_EXECUTABLE PURE_SOURCE_DIR MODULE_DIR SCRIPT)
  cmake_path(ABSOLUTE_PATH ${path_input} NORMALIZE OUTPUT_VARIABLE normalized)
  set(${path_input} "${normalized}")
endforeach()

foreach(directory_input IN ITEMS PURE_SOURCE_DIR MODULE_DIR)
  if(NOT IS_DIRECTORY "${${directory_input}}")
    message(FATAL_ERROR
      "${directory_input} must be an existing directory: ${${directory_input}}")
  endif()
endforeach()

if(WIN32)
  cmake_path(ABSOLUTE_PATH PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY
    NORMALIZE OUTPUT_VARIABLE PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY)
  if(NOT IS_DIRECTORY "${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}")
    message(FATAL_ERROR
      "PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY must be an existing "
      "directory: ${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}")
  endif()
  _pure_odbc_require_no_reparse(
    "${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}"
    "configure-time OS Windows directory" FALSE)
  file(REAL_PATH "${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}"
    configure_windows_directory)
  _pure_odbc_require_no_reparse("${MODULE_DIR}" "MODULE_DIR" FALSE)
  file(REAL_PATH "${MODULE_DIR}" canonical_module_directory)
  set(expected_runner "${canonical_module_directory}/run_pure_test.exe")
  set(runner "${MODULE_DIR}/run_pure_test.exe")
  if(NOT EXISTS "${runner}" OR IS_DIRECTORY "${runner}")
    message(FATAL_ERROR
      "Native test runner must be an existing file: ${runner}")
  endif()
  _pure_odbc_require_no_reparse("${runner}" "native test runner" FALSE)
  file(REAL_PATH "${runner}" canonical_runner)
  _pure_odbc_fold_path("${expected_runner}" folded_expected_runner)
  _pure_odbc_fold_path("${canonical_runner}" folded_canonical_runner)
  if(NOT folded_canonical_runner STREQUAL folded_expected_runner)
    message(FATAL_ERROR
      "Native test runner must be exactly MODULE_DIR/run_pure_test.exe\n"
      "expected: ${expected_runner}\nactual: ${canonical_runner}")
  endif()
  set(MODULE_DIR "${canonical_module_directory}")
  set(runner "${canonical_runner}")
  execute_process(
    COMMAND "${runner}" --print-windows-directory
    RESULT_VARIABLE windows_directory_result
    OUTPUT_VARIABLE windows_directory_output
    ERROR_VARIABLE windows_directory_error
    ENCODING UTF-8
  )
  string(STRIP "${windows_directory_output}" windows_directory)
  if(NOT windows_directory_result EQUAL 0 OR
      NOT windows_directory_error STREQUAL "" OR
      NOT IS_DIRECTORY "${windows_directory}")
    message(FATAL_ERROR
      "Native test runner did not return the OS Windows directory\n"
      "stdout:\n${windows_directory_output}\n"
      "stderr:\n${windows_directory_error}")
  endif()
  cmake_path(ABSOLUTE_PATH windows_directory NORMALIZE
    OUTPUT_VARIABLE windows_directory)
  file(REAL_PATH "${windows_directory}" windows_directory)
  _pure_odbc_fold_path(
    "${configure_windows_directory}" folded_configure_windows_directory)
  _pure_odbc_fold_path(
    "${windows_directory}" folded_runtime_windows_directory)
  if(NOT folded_runtime_windows_directory STREQUAL
      folded_configure_windows_directory)
    message(FATAL_ERROR
      "Runtime OS Windows directory does not match configure-time authority\n"
      "configure: ${configure_windows_directory}\n"
      "runtime: ${windows_directory}")
  endif()
  cmake_path(ABSOLUTE_PATH WORK_DIRECTORY NORMALIZE
    OUTPUT_VARIABLE WORK_DIRECTORY)
else()
  cmake_path(ABSOLUTE_PATH WORK_DIRECTORY NORMALIZE
    OUTPUT_VARIABLE WORK_DIRECTORY)
endif()

foreach(file_input IN ITEMS PURE_EXECUTABLE SCRIPT)
  if(NOT EXISTS "${${file_input}}" OR IS_DIRECTORY "${${file_input}}")
    message(FATAL_ERROR
      "${file_input} must be an existing file: ${${file_input}}")
  endif()
  _pure_odbc_require_no_reparse(
    "${${file_input}}" "${file_input}" FALSE)
endforeach()
if(NOT IS_DIRECTORY "${WORK_DIRECTORY}")
  message(FATAL_ERROR
    "WORK_DIRECTORY must be an existing directory: ${WORK_DIRECTORY}")
endif()
if(WIN32)
  pure_odbc_require_owned_or_neutral_work_directory(
    "${WORK_DIRECTORY}" "${windows_directory}" validated_work_directory)
  set(WORK_DIRECTORY "${validated_work_directory}")
endif()

if(WIN32)
  set(command
    "${runner}" "${PURE_EXECUTABLE}" "${PURE_SOURCE_DIR}" "${MODULE_DIR}"
    "${SCRIPT}" "${WORK_DIRECTORY}")
else()
  cmake_path(GET PURE_EXECUTABLE PARENT_PATH pure_bin)
  unset(ENV{PURELIB})
  set(ENV{PATH} "${MODULE_DIR}:${pure_bin}:/usr/bin:/bin")
  set(command
    "${PURE_EXECUTABLE}" --norc -I "${PURE_SOURCE_DIR}"
    -L "${MODULE_DIR}" -x "${SCRIPT}")
endif()

execute_process(
  COMMAND ${command}
  WORKING_DIRECTORY "${WORK_DIRECTORY}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
  ENCODING UTF-8
)

if(NOT error STREQUAL "")
  message(FATAL_ERROR
    "pure-odbc test emitted stderr\nstdout:\n${output}\nstderr:\n${error}")
endif()
if(NOT result EQUAL 0)
  message(FATAL_ERROR
    "pure-odbc test failed (${result})\nstdout:\n${output}\nstderr:\n${error}")
endif()
message(STATUS "${output}")
