cmake_minimum_required(VERSION 3.29)

set(contract_helper "${CMAKE_CURRENT_LIST_DIR}/ContractTestRoot.cmake")
if(NOT EXISTS "${contract_helper}")
  message(FATAL_ERROR "Contract root helper is missing: ${contract_helper}")
endif()
include("${contract_helper}")

if(DEFINED ROOT_PROBE_MODE)
  foreach(required IN ITEMS BINARY_DIR EXPECTED_LEAF)
    if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
      message(FATAL_ERROR "${required} is required")
    endif()
  endforeach()
  if(ROOT_PROBE_MODE STREQUAL "validate")
    pure_odbc_validate_contract_test_root("${EXPECTED_LEAF}" unused_root)
  elseif(ROOT_PROBE_MODE STREQUAL "reset")
    pure_odbc_reset_contract_test_root("${EXPECTED_LEAF}")
  else()
    message(FATAL_ERROR "Unknown root probe mode: ${ROOT_PROBE_MODE}")
  endif()
  message(FATAL_ERROR
    "ROOT_SAFETY_PROBE accepted unsafe ${ROOT_PROBE_MODE} input")
endif()

function(expect_root_rejected label mode leaf candidate expected)
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DBINARY_DIR=${candidate}"
      "-DEXPECTED_LEAF=${leaf}"
      "-DROOT_PROBE_MODE=${mode}"
      -P "${CMAKE_CURRENT_LIST_FILE}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8
  )
  set(diagnostics "${output}\n${error}")
  if(result EQUAL 0)
    message(FATAL_ERROR
      "Root-safety probe accepted unsafe ${label}: ${candidate}")
  endif()
  if(diagnostics MATCHES "ROOT_SAFETY_PROBE accepted unsafe")
    message(FATAL_ERROR
      "Root-safety probe accepted unsafe ${label}: ${candidate}\n${diagnostics}")
  endif()
  if(NOT diagnostics MATCHES "${expected}")
    message(FATAL_ERROR
      "Unsafe ${label} produced the wrong diagnostic\n${diagnostics}")
  endif()
endfunction()

function(expect_runner_rejected label expected)
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env
      "PATH=C:/ambient-msys2/bin;C:/ambient-tools"
      "PURELIB=C:/ambient-purelib"
      "${CMAKE_COMMAND}" ${ARGN}
      -P "${SOURCE_DIR}/cmake/RunPureTest.cmake"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8
  )
  set(diagnostics "${output}\n${error}")
  if(result EQUAL 0)
    message(FATAL_ERROR "Runner accepted ${label}")
  endif()
  if(NOT diagnostics MATCHES "${expected}")
    message(FATAL_ERROR
      "Runner rejected ${label} for the wrong reason\n${diagnostics}")
  endif()
endfunction()

pure_odbc_validate_contract_test_root("runner" initial_test_root)
pure_odbc_reset_contract_test_root("runner")

expect_root_rejected(
  "source descendant" validate runner "${SOURCE_DIR}/tests"
  "inside canonical SOURCE_DIR")
string(TOUPPER "${SOURCE_DIR}/tests" case_alias)
expect_root_rejected(
  "case-only source descendant" validate runner "${case_alias}"
  "inside canonical SOURCE_DIR")
expect_root_rejected(
  "unknown fixed leaf" validate arbitrary "${BINARY_DIR}"
  "Unknown pure-odbc contract leaf")

set(junction "${TEST_ROOT}/binary-reparse-alias")
set(powershell
  "$ENV{SystemRoot}/System32/WindowsPowerShell/v1.0/powershell.exe")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    "PURE_ODBC_JUNCTION_PATH=${junction}"
    "PURE_ODBC_JUNCTION_TARGET=${BINARY_DIR}"
    "${powershell}" -NoProfile -NonInteractive -ExecutionPolicy Bypass
    -Command
    "$ErrorActionPreference='Stop'; New-Item -ItemType Junction -Path $env:PURE_ODBC_JUNCTION_PATH -Target $env:PURE_ODBC_JUNCTION_TARGET | Out-Null"
  RESULT_VARIABLE junction_result
  OUTPUT_VARIABLE junction_output
  ERROR_VARIABLE junction_error
  ENCODING UTF-8
)
if(NOT junction_result EQUAL 0)
  message(FATAL_ERROR
    "Unable to create junction probe (${junction_result})\n"
    "${junction_output}${junction_error}")
endif()
execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DBINARY_DIR=${junction}"
    -DEXPECTED_LEAF=runner
    -DROOT_PROBE_MODE=validate
    -P "${CMAKE_CURRENT_LIST_FILE}"
  RESULT_VARIABLE reparse_result
  OUTPUT_VARIABLE reparse_output
  ERROR_VARIABLE reparse_error
  ENCODING UTF-8
)
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    "PURE_ODBC_JUNCTION_PATH=${junction}"
    "${powershell}" -NoProfile -NonInteractive -ExecutionPolicy Bypass
    -Command
    "$ErrorActionPreference='Stop'; $item=Get-Item -LiteralPath $env:PURE_ODBC_JUNCTION_PATH -Force; if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { throw 'not a reparse point' }; [IO.Directory]::Delete($env:PURE_ODBC_JUNCTION_PATH, $false)"
  RESULT_VARIABLE junction_cleanup_result
  OUTPUT_VARIABLE junction_cleanup_output
  ERROR_VARIABLE junction_cleanup_error
  ENCODING UTF-8
)
if(NOT junction_cleanup_result EQUAL 0)
  message(FATAL_ERROR
    "Unable to remove junction probe (${junction_cleanup_result})\n"
    "${junction_cleanup_output}${junction_cleanup_error}")
endif()
set(reparse_diagnostics "${reparse_output}\n${reparse_error}")
if(reparse_result EQUAL 0 OR
    reparse_diagnostics MATCHES "ROOT_SAFETY_PROBE accepted unsafe" OR
    NOT reparse_diagnostics MATCHES "[Rr]eparse")
  message(FATAL_ERROR
    "Reparse BINARY_DIR was not rejected safely\n${reparse_diagnostics}")
endif()

set(wrong_cache "${TEST_ROOT}/wrong-build-cache")
file(MAKE_DIRECTORY "${wrong_cache}")
file(WRITE "${wrong_cache}/CMakeCache.txt"
  "CMAKE_HOME_DIRECTORY:INTERNAL=${SOURCE_DIR}\n"
  "CMAKE_CACHEFILE_DIR:INTERNAL=${wrong_cache}\n"
  "CMAKE_PROJECT_NAME:STATIC=not-pure-odbc\n")
expect_root_rejected(
  "wrong build cache" validate runner "${wrong_cache}"
  "belongs to project 'not-pure-odbc'")

set(owner_sentinel "${TEST_ROOT}/.pure-odbc-contract-owner")
pure_odbc_contract_sentinel_content("runner" expected_sentinel)
file(WRITE "${TEST_ROOT}/unowned.guard" "must survive rejected reset\n")
file(REMOVE "${owner_sentinel}")
expect_root_rejected(
  "existing unowned directory" reset runner "${BINARY_DIR}"
  "without ownership sentinel")
if(NOT EXISTS "${TEST_ROOT}/unowned.guard")
  message(FATAL_ERROR "Rejected unowned directory reset removed its guard")
endif()
file(WRITE "${owner_sentinel}" "${expected_sentinel}")
pure_odbc_reset_contract_test_root("runner")

file(WRITE "${TEST_ROOT}/damaged.guard" "must survive rejected reset\n")
file(WRITE "${owner_sentinel}" "damaged ownership\n")
expect_root_rejected(
  "damaged ownership sentinel" reset runner "${BINARY_DIR}"
  "invalid ownership sentinel")
if(NOT EXISTS "${TEST_ROOT}/damaged.guard")
  message(FATAL_ERROR "Rejected damaged-sentinel reset removed its guard")
endif()
file(WRITE "${owner_sentinel}" "${expected_sentinel}")
pure_odbc_reset_contract_test_root("runner")

file(MAKE_DIRECTORY
  "${TEST_ROOT}/pure/bin"
  "${TEST_ROOT}/module"
  "${TEST_ROOT}/work")
file(WRITE "${TEST_ROOT}/pure/bin/pure.cmd"
  "@echo off\r\n"
  "echo RUNNER_STDOUT_SENTINEL\r\n"
  "echo EFFECTIVE_CWD=%CD%\r\n"
  "echo EFFECTIVE_PATH=%PATH%\r\n"
  "if defined PURELIB echo EFFECTIVE_PURELIB=SET\r\n"
  "if not defined PURELIB echo EFFECTIVE_PURELIB=UNSET\r\n"
  "echo EFFECTIVE_ARGS=%*\r\n"
  "exit /b 0\r\n")
file(WRITE "${TEST_ROOT}/pure/bin/stderr-pure.cmd"
  "@echo off\r\n"
  "echo ZERO_EXIT_STDERR_SENTINEL 1>&2\r\n"
  "exit /b 0\r\n")
file(WRITE "${TEST_ROOT}/pure/bin/exit-pure.cmd"
  "@echo off\r\n"
  "echo EXIT_STDOUT_SENTINEL\r\n"
  "exit /b 37\r\n")
file(WRITE "${TEST_ROOT}/test.pure" "// runner contract fixture\n")
file(WRITE "${TEST_ROOT}/not-a-directory" "fixture\n")

set(all_args
  "-DPURE_EXECUTABLE=${TEST_ROOT}/pure/bin/pure.cmd"
  "-DPURE_SOURCE_DIR=${SOURCE_DIR}"
  "-DMODULE_DIR=${TEST_ROOT}/module"
  "-DSCRIPT=${TEST_ROOT}/test.pure"
  "-DWORK_DIRECTORY=${TEST_ROOT}/work")

foreach(missing IN ITEMS
    PURE_EXECUTABLE PURE_SOURCE_DIR MODULE_DIR SCRIPT WORK_DIRECTORY)
  set(args ${all_args})
  list(FILTER args EXCLUDE REGEX "^-D${missing}=")
  expect_runner_rejected(
    "a missing ${missing}" "${missing} is required" ${args})
endforeach()

foreach(file_input IN ITEMS PURE_EXECUTABLE SCRIPT)
  set(args ${all_args})
  list(FILTER args EXCLUDE REGEX "^-D${file_input}=")
  list(PREPEND args "-D${file_input}=${TEST_ROOT}/missing-input")
  expect_runner_rejected(
    "a nonexistent ${file_input}"
    "${file_input} must be an existing file" ${args})
  set(args ${all_args})
  list(FILTER args EXCLUDE REGEX "^-D${file_input}=")
  list(PREPEND args "-D${file_input}=${TEST_ROOT}/module")
  expect_runner_rejected(
    "a directory ${file_input}"
    "${file_input} must be an existing file" ${args})
endforeach()

foreach(directory_input IN ITEMS PURE_SOURCE_DIR MODULE_DIR WORK_DIRECTORY)
  set(args ${all_args})
  list(FILTER args EXCLUDE REGEX "^-D${directory_input}=")
  list(PREPEND args "-D${directory_input}=${TEST_ROOT}/missing-input")
  expect_runner_rejected(
    "a nonexistent ${directory_input}"
    "${directory_input} must be an existing directory" ${args})
  set(args ${all_args})
  list(FILTER args EXCLUDE REGEX "^-D${directory_input}=")
  list(PREPEND args "-D${directory_input}=${TEST_ROOT}/not-a-directory")
  expect_runner_rejected(
    "a file ${directory_input}"
    "${directory_input} must be an existing directory" ${args})
endforeach()

execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    "PATH=C:/ambient-msys2/bin;C:/ambient-tools"
    "PURELIB=C:/ambient-purelib"
    "${CMAKE_COMMAND}" ${all_args}
    -P "${SOURCE_DIR}/cmake/RunPureTest.cmake"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
  ENCODING UTF-8
)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Runner probe failed\n${output}${error}")
endif()
if(NOT error STREQUAL "")
  message(FATAL_ERROR "Successful runner emitted stderr\n${output}${error}")
endif()
if(NOT output MATCHES "RUNNER_STDOUT_SENTINEL")
  message(FATAL_ERROR "Runner discarded child stdout\n${output}")
endif()
if(NOT output MATCHES "EFFECTIVE_PURELIB=UNSET" OR
    output MATCHES "EFFECTIVE_PURELIB=SET")
  message(FATAL_ERROR "Runner did not unset PURELIB\n${output}")
endif()
string(REGEX MATCH "EFFECTIVE_PATH=([^\r\n]+)" unused "${output}")
set(actual_path "${CMAKE_MATCH_1}")
set(expected_path
  "${TEST_ROOT}/module;${TEST_ROOT}/pure/bin;$ENV{SystemRoot}/System32;$ENV{SystemRoot}")
string(REPLACE "\\" "/" actual_path "${actual_path}")
string(REPLACE "\\" "/" expected_path "${expected_path}")
string(TOLOWER "${actual_path}" actual_path)
string(TOLOWER "${expected_path}" expected_path)
if(NOT actual_path STREQUAL expected_path)
  message(FATAL_ERROR
    "Runner leaked or omitted a PATH entry. Expected '${expected_path}', "
    "got '${actual_path}'")
endif()
string(REGEX MATCH "EFFECTIVE_CWD=([^\r\n]+)" unused "${output}")
set(actual_work_directory "${CMAKE_MATCH_1}")
_pure_odbc_fold_path("${actual_work_directory}" actual_work_directory)
_pure_odbc_fold_path("${TEST_ROOT}/work" expected_work_directory)
if(NOT actual_work_directory STREQUAL expected_work_directory)
  message(FATAL_ERROR
    "Runner used '${actual_work_directory}', expected '${expected_work_directory}'")
endif()

set(stderr_args ${all_args})
list(FILTER stderr_args EXCLUDE REGEX "^-DPURE_EXECUTABLE=")
list(PREPEND stderr_args
  "-DPURE_EXECUTABLE=${TEST_ROOT}/pure/bin/stderr-pure.cmd")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    "PATH=C:/ambient-msys2/bin;C:/ambient-tools"
    "PURELIB=C:/ambient-purelib"
    "${CMAKE_COMMAND}" ${stderr_args}
    -P "${SOURCE_DIR}/cmake/RunPureTest.cmake"
  RESULT_VARIABLE stderr_result
  OUTPUT_VARIABLE stderr_output
  ERROR_VARIABLE stderr_error
  ENCODING UTF-8
)
set(stderr_diagnostics "${stderr_output}\n${stderr_error}")
if(NOT stderr_result EQUAL 1 OR
    NOT stderr_diagnostics MATCHES "emitted stderr" OR
    NOT stderr_diagnostics MATCHES "ZERO_EXIT_STDERR_SENTINEL")
  message(FATAL_ERROR
    "Runner did not reject zero-exit stderr correctly\n${stderr_diagnostics}")
endif()

set(exit_args ${all_args})
list(FILTER exit_args EXCLUDE REGEX "^-DPURE_EXECUTABLE=")
list(PREPEND exit_args
  "-DPURE_EXECUTABLE=${TEST_ROOT}/pure/bin/exit-pure.cmd")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    "PATH=C:/ambient-msys2/bin;C:/ambient-tools"
    "PURELIB=C:/ambient-purelib"
    "${CMAKE_COMMAND}" ${exit_args}
    -P "${SOURCE_DIR}/cmake/RunPureTest.cmake"
  RESULT_VARIABLE exit_result
  OUTPUT_VARIABLE exit_output
  ERROR_VARIABLE exit_error
  ENCODING UTF-8
)
if(NOT exit_result EQUAL 37)
  message(FATAL_ERROR
    "Runner did not propagate child exit 37 (got ${exit_result})\n"
    "${exit_output}${exit_error}")
endif()
if(NOT "${exit_output}\n${exit_error}" MATCHES "EXIT_STDOUT_SENTINEL")
  message(FATAL_ERROR
    "Runner discarded stdout from failed child\n${exit_output}${exit_error}")
endif()

message(STATUS "pure-odbc runner and root-safety contracts passed")
