cmake_minimum_required(VERSION 3.25)

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
  if(ROOT_PROBE_MODE STREQUAL "validate" OR
      ROOT_PROBE_MODE STREQUAL "validate-positive")
    pure_odbc_validate_contract_test_root("${EXPECTED_LEAF}" unused_root)
  elseif(ROOT_PROBE_MODE STREQUAL "reset")
    pure_odbc_reset_contract_test_root("${EXPECTED_LEAF}")
  else()
    message(FATAL_ERROR "Unknown root probe mode: ${ROOT_PROBE_MODE}")
  endif()
  if(ROOT_PROBE_MODE STREQUAL "validate-positive")
    message(STATUS "ROOT_SAFETY_PROBE accepted expected safe input")
    return()
  endif()
  message(FATAL_ERROR "ROOT_SAFETY_PROBE accepted unsafe input")
endif()

if(DEFINED WINDOWS_DIRECTORY_PROBE_MODE)
  foreach(required IN ITEMS PROBE_WORK_DIRECTORY PROBE_WINDOWS_DIRECTORY)
    if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
      message(FATAL_ERROR "${required} is required")
    endif()
  endforeach()
  pure_odbc_require_owned_or_neutral_work_directory(
    "${PROBE_WORK_DIRECTORY}" "${PROBE_WINDOWS_DIRECTORY}"
    validated_probe_work_directory)
  if(WINDOWS_DIRECTORY_PROBE_MODE STREQUAL "validate-positive")
    _pure_odbc_fold_path(
      "${validated_probe_work_directory}" folded_probe_work_directory)
    _pure_odbc_fold_path(
      "${PROBE_WINDOWS_DIRECTORY}" folded_probe_windows_directory)
    if(NOT folded_probe_work_directory STREQUAL folded_probe_windows_directory)
      message(FATAL_ERROR
        "Windows-directory helper returned a different canonical identity")
    endif()
    message(STATUS
      "WINDOWS_DIRECTORY_PROBE accepted authoritative case-only identity")
    return()
  endif()
  message(FATAL_ERROR "WINDOWS_DIRECTORY_PROBE accepted unsafe input")
endif()

function(expect_root_rejected label mode leaf candidate expected)
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DBINARY_DIR=${candidate}"
      "-DEXPECTED_LEAF=${leaf}"
      "-DROOT_PROBE_MODE=${mode}"
      "-DPURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY=${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}"
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

function(expect_root_accepted label leaf candidate)
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DBINARY_DIR=${candidate}"
      "-DEXPECTED_LEAF=${leaf}"
      -DROOT_PROBE_MODE=validate-positive
      "-DPURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY=${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}"
      -P "${CMAKE_CURRENT_LIST_FILE}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8
  )
  if(NOT result EQUAL 0)
    message(FATAL_ERROR
      "Root-safety probe rejected safe ${label}: ${candidate}\n${output}${error}")
  endif()
endfunction()

function(expect_windows_directory_accepted work_directory windows_directory)
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      -DWINDOWS_DIRECTORY_PROBE_MODE=validate-positive
      "-DPROBE_WORK_DIRECTORY=${work_directory}"
      "-DPROBE_WINDOWS_DIRECTORY=${windows_directory}"
      "-DPURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY=${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}"
      -P "${CMAKE_CURRENT_LIST_FILE}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8
  )
  if(NOT result EQUAL 0 OR
      NOT output MATCHES "authoritative case-only identity")
    message(FATAL_ERROR
      "Windows-directory helper rejected an authoritative case-only "
      "identity\n${output}${error}")
  endif()
endfunction()

function(expect_windows_directory_rejected work_directory windows_directory)
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      -DWINDOWS_DIRECTORY_PROBE_MODE=validate-negative
      "-DPROBE_WORK_DIRECTORY=${work_directory}"
      "-DPROBE_WINDOWS_DIRECTORY=${windows_directory}"
      "-DPURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY=${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}"
      -P "${CMAKE_CURRENT_LIST_FILE}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8
  )
  if(result EQUAL 0 OR
      NOT "${output}\n${error}" MATCHES
        "WORK_DIRECTORY must be the OS Windows directory")
    message(FATAL_ERROR
      "Windows-directory helper accepted a non-authoritative identity\n"
      "${output}${error}")
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

function(expect_runner_link_rejected label link_kind link_path link_target
    linked_input input_path link_is_directory)
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env
      "PURE_ODBC_LINK_KIND=${link_kind}"
      "PURE_ODBC_LINK_PATH=${link_path}"
      "PURE_ODBC_LINK_TARGET=${link_target}"
      "${powershell}" -NoProfile -NonInteractive -ExecutionPolicy Bypass
      -Command
      "$ErrorActionPreference='Stop'; New-Item -ItemType $env:PURE_ODBC_LINK_KIND -Path $env:PURE_ODBC_LINK_PATH -Target $env:PURE_ODBC_LINK_TARGET | Out-Null"
    RESULT_VARIABLE create_result
    OUTPUT_VARIABLE create_output
    ERROR_VARIABLE create_error
    ENCODING UTF-8
  )
  if(NOT create_result EQUAL 0)
    message(FATAL_ERROR
      "Unable to create ${label} (${create_result})\n"
      "${create_output}${create_error}")
  endif()

  set(args ${all_args})
  list(FILTER args EXCLUDE REGEX "^-D${linked_input}=")
  list(PREPEND args "-D${linked_input}=${input_path}")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env
      "PATH=C:/ambient-msys2/bin;C:/ambient-tools"
      "PURELIB=C:/ambient-purelib"
      "${CMAKE_COMMAND}" ${args}
      -P "${SOURCE_DIR}/cmake/RunPureTest.cmake"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8
  )

  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env
      "PURE_ODBC_LINK_PATH=${link_path}"
      "PURE_ODBC_LINK_IS_DIRECTORY=${link_is_directory}"
      "${powershell}" -NoProfile -NonInteractive -ExecutionPolicy Bypass
      -Command
      "$ErrorActionPreference='Stop'; $item=Get-Item -LiteralPath $env:PURE_ODBC_LINK_PATH -Force; if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { throw 'not a reparse point' }; if ($env:PURE_ODBC_LINK_IS_DIRECTORY -eq 'TRUE') { [IO.Directory]::Delete($env:PURE_ODBC_LINK_PATH, $false) } else { [IO.File]::Delete($env:PURE_ODBC_LINK_PATH) }"
    RESULT_VARIABLE cleanup_result
    OUTPUT_VARIABLE cleanup_output
    ERROR_VARIABLE cleanup_error
    ENCODING UTF-8
  )
  if(NOT cleanup_result EQUAL 0)
    message(FATAL_ERROR
      "Unable to remove ${label} (${cleanup_result})\n"
      "${cleanup_output}${cleanup_error}")
  endif()

  set(diagnostics "${output}\n${error}")
  if(result EQUAL 0)
    message(FATAL_ERROR "Runner accepted ${label}")
  endif()
  if(NOT diagnostics MATCHES "${linked_input}.*[Rr]eparse")
    message(FATAL_ERROR
      "Runner rejected ${label} for the wrong reason\n${diagnostics}")
  endif()
endfunction()

foreach(required IN ITEMS RUN_PURE_TEST_EXECUTABLE ACTUAL_PURE_EXECUTABLE
    ALTERNATE_RUN_PURE_TEST_EXECUTABLE ACTUAL_MODULE_DIR ACCESS_SCRIPT
    ACCESS_WORK_DIRECTORY
    PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()
if(NOT IS_DIRECTORY "${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}")
  message(FATAL_ERROR
    "PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY must be an existing directory: "
    "${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}")
endif()
foreach(file_input IN ITEMS RUN_PURE_TEST_EXECUTABLE
    ALTERNATE_RUN_PURE_TEST_EXECUTABLE ACTUAL_PURE_EXECUTABLE ACCESS_SCRIPT)
  if(NOT EXISTS "${${file_input}}" OR IS_DIRECTORY "${${file_input}}")
    message(FATAL_ERROR
      "${file_input} must be an existing file: ${${file_input}}")
  endif()
endforeach()
foreach(directory_input IN ITEMS ACTUAL_MODULE_DIR ACCESS_WORK_DIRECTORY)
  if(NOT IS_DIRECTORY "${${directory_input}}")
    message(FATAL_ERROR
      "${directory_input} must be an existing directory: "
      "${${directory_input}}")
  endif()
endforeach()

execute_process(
  COMMAND "${RUN_PURE_TEST_EXECUTABLE}" --print-windows-directory
  RESULT_VARIABLE windows_query_result
  OUTPUT_VARIABLE windows_query_output
  ERROR_VARIABLE windows_query_error
  ENCODING UTF-8
)
string(STRIP "${windows_query_output}" OS_WINDOWS_DIRECTORY)
if(NOT windows_query_result EQUAL 0 OR
    NOT windows_query_error STREQUAL "" OR
    NOT IS_DIRECTORY "${OS_WINDOWS_DIRECTORY}")
  message(FATAL_ERROR
    "Native runner did not return the OS-authoritative Windows directory\n"
    "${windows_query_output}${windows_query_error}")
endif()
set(oracle_powershell
  "${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}/System32/WindowsPowerShell/v1.0/powershell.exe")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    "SystemRoot=${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}"
    "windir=${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}"
    "${oracle_powershell}" -NoProfile -NonInteractive -ExecutionPolicy Bypass
    -Command "[Environment]::SystemDirectory"
  RESULT_VARIABLE windows_oracle_result
  OUTPUT_VARIABLE windows_oracle_output
  ERROR_VARIABLE windows_oracle_error
  ENCODING UTF-8
)
string(STRIP "${windows_oracle_output}" windows_oracle_system_directory)
if(NOT windows_oracle_result EQUAL 0 OR
    NOT windows_oracle_error STREQUAL "" OR
    NOT IS_DIRECTORY "${windows_oracle_system_directory}")
  message(FATAL_ERROR
    "Independent SystemDirectory oracle failed\n"
    "${windows_oracle_output}${windows_oracle_error}")
endif()
cmake_path(GET windows_oracle_system_directory PARENT_PATH
  OS_WINDOWS_DIRECTORY_ORACLE)
file(REAL_PATH "${OS_WINDOWS_DIRECTORY_ORACLE}"
  OS_WINDOWS_DIRECTORY_ORACLE)
_pure_odbc_fold_path(
  "${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}"
  folded_configure_windows_directory)
_pure_odbc_fold_path(
  "${OS_WINDOWS_DIRECTORY}" folded_queried_windows_directory)
_pure_odbc_fold_path(
  "${OS_WINDOWS_DIRECTORY_ORACLE}" folded_oracle_windows_directory)
if(NOT folded_configure_windows_directory STREQUAL
      folded_oracle_windows_directory OR
    NOT folded_queried_windows_directory STREQUAL
      folded_oracle_windows_directory)
  message(FATAL_ERROR
    "Configure-time, runtime, and independent Windows directories disagree\n"
    "configure: ${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}\n"
    "runtime: ${OS_WINDOWS_DIRECTORY}\n"
    "oracle: ${OS_WINDOWS_DIRECTORY_ORACLE}")
endif()

pure_odbc_validate_contract_test_root("runner" initial_test_root)
pure_odbc_reset_contract_test_root("runner")

set(alternate_windows_directory "${TEST_ROOT}/alternate-windows")
set(non_windows_directory "${TEST_ROOT}/not-windows")
file(MAKE_DIRECTORY
  "${alternate_windows_directory}" "${non_windows_directory}")
string(TOUPPER "${alternate_windows_directory}"
  case_only_alternate_windows_directory)
expect_windows_directory_accepted(
  "${case_only_alternate_windows_directory}"
  "${alternate_windows_directory}")
expect_windows_directory_rejected(
  "${non_windows_directory}" "${alternate_windows_directory}")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    "PURE_ODBC_TEST_WINDOWS_DIRECTORY=${alternate_windows_directory}"
    "${ALTERNATE_RUN_PURE_TEST_EXECUTABLE}" --print-windows-directory
  RESULT_VARIABLE alternate_query_result
  OUTPUT_VARIABLE alternate_query_output
  ERROR_VARIABLE alternate_query_error
  ENCODING UTF-8
)
string(STRIP "${alternate_query_output}" alternate_query_directory)
_pure_odbc_fold_path(
  "${alternate_query_directory}" folded_alternate_query_directory)
_pure_odbc_fold_path(
  "${alternate_windows_directory}" folded_alternate_windows_directory)
if(NOT alternate_query_result EQUAL 0 OR
    NOT alternate_query_error STREQUAL "" OR
    NOT folded_alternate_query_directory STREQUAL
      folded_alternate_windows_directory)
  message(FATAL_ERROR
    "Test-seam launcher did not use its controlled alternate Windows "
    "directory\n${alternate_query_output}${alternate_query_error}")
endif()
set(production_seam_marker
  "${TEST_ROOT}/production-seam-must-stay-disabled.marker")
file(REMOVE "${production_seam_marker}")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    "PURE_ODBC_TEST_WINDOWS_DIRECTORY=${alternate_windows_directory}"
    "PURE_ODBC_TEST_QUERY_MARKER=${production_seam_marker}"
    "${RUN_PURE_TEST_EXECUTABLE}" --print-windows-directory
  RESULT_VARIABLE production_query_result
  OUTPUT_VARIABLE production_query_output
  ERROR_VARIABLE production_query_error
  ENCODING UTF-8
)
string(STRIP "${production_query_output}" production_query_directory)
_pure_odbc_fold_path(
  "${production_query_directory}" folded_production_query_directory)
if(NOT production_query_result EQUAL 0 OR
    NOT production_query_error STREQUAL "" OR
    EXISTS "${production_seam_marker}" OR
    NOT folded_production_query_directory STREQUAL
      folded_oracle_windows_directory)
  message(FATAL_ERROR
    "Production native launcher enabled a test-only authority seam\n"
    "${production_query_output}${production_query_error}")
endif()

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
  "${OS_WINDOWS_DIRECTORY}/System32/WindowsPowerShell/v1.0/powershell.exe")
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
    "-DPURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY=${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}"
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

set(case_cache "${TEST_ROOT}/case-project-cache")
file(MAKE_DIRECTORY "${case_cache}")
string(TOUPPER "${SOURCE_DIR}" case_cache_source)
string(TOUPPER "${case_cache}" case_cache_binary)
file(WRITE "${case_cache}/CMakeCache.txt"
  "CMAKE_HOME_DIRECTORY:INTERNAL=${case_cache_source}\n"
  "CMAKE_CACHEFILE_DIR:INTERNAL=${case_cache_binary}\n"
  "CMAKE_PROJECT_NAME:STATIC=PURE-ODBC\n")
expect_root_accepted(
  "case-only project/cache identity" runner "${case_cache}")

set(case_wrong_cache "${TEST_ROOT}/case-wrong-project-cache")
file(MAKE_DIRECTORY "${case_wrong_cache}")
file(WRITE "${case_wrong_cache}/CMakeCache.txt"
  "CMAKE_HOME_DIRECTORY:INTERNAL=${case_cache_source}\n"
  "CMAKE_CACHEFILE_DIR:INTERNAL=${case_wrong_cache}\n"
  "CMAKE_PROJECT_NAME:STATIC=PURE-ODBC-WRONG\n")
expect_root_rejected(
  "case-folded wrong project identity" validate runner "${case_wrong_cache}"
  "belongs to project 'PURE-ODBC-WRONG'")

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
  "${TEST_ROOT}/work"
  "${TEST_ROOT}/alternate-windows")
file(COPY_FILE
  "${RUN_PURE_TEST_EXECUTABLE}" "${TEST_ROOT}/module/run_pure_test.exe")
foreach(fake_name IN ITEMS
    fake-success fake-stderr fake-exit37 fake-exit77 fake-hang)
  file(COPY_FILE
    "${RUN_PURE_TEST_EXECUTABLE}"
    "${TEST_ROOT}/pure/bin/${fake_name}.exe")
endforeach()
file(WRITE "${TEST_ROOT}/test.pure" "// runner contract fixture\n")
file(WRITE "${TEST_ROOT}/not-a-directory" "fixture\n")

set(all_args
  "-DPURE_EXECUTABLE=${TEST_ROOT}/pure/bin/fake-success.exe"
  "-DPURE_SOURCE_DIR=${SOURCE_DIR}"
  "-DMODULE_DIR=${TEST_ROOT}/module"
  "-DSCRIPT=${TEST_ROOT}/test.pure"
  "-DWORK_DIRECTORY=${TEST_ROOT}"
  "-DPURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY=${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}")

foreach(missing IN ITEMS
    PURE_EXECUTABLE PURE_SOURCE_DIR MODULE_DIR SCRIPT WORK_DIRECTORY
    PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY)
  set(args ${all_args})
  list(FILTER args EXCLUDE REGEX "^-D${missing}=")
  expect_runner_rejected(
    "a missing ${missing}" "${missing} is required" ${args})
endforeach()

set(marker_target_module "${TEST_ROOT}/marker-target-module")
set(marker_module_junction "${TEST_ROOT}/marker-module-junction")
set(query_execution_marker "${TEST_ROOT}/untrusted-runner-executed.marker")
file(MAKE_DIRECTORY "${marker_target_module}")
file(COPY_FILE
  "${ALTERNATE_RUN_PURE_TEST_EXECUTABLE}"
  "${marker_target_module}/run_pure_test.exe")
file(REMOVE "${query_execution_marker}")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    "PURE_ODBC_LINK_PATH=${marker_module_junction}"
    "PURE_ODBC_LINK_TARGET=${marker_target_module}"
    "${powershell}" -NoProfile -NonInteractive -ExecutionPolicy Bypass
    -Command
    "$ErrorActionPreference='Stop'; New-Item -ItemType Junction -Path $env:PURE_ODBC_LINK_PATH -Target $env:PURE_ODBC_LINK_TARGET | Out-Null"
  RESULT_VARIABLE marker_junction_result
  OUTPUT_VARIABLE marker_junction_output
  ERROR_VARIABLE marker_junction_error
  ENCODING UTF-8
)
if(NOT marker_junction_result EQUAL 0)
  message(FATAL_ERROR
    "Unable to create runner-execution junction probe\n"
    "${marker_junction_output}${marker_junction_error}")
endif()
set(marker_args ${all_args})
list(FILTER marker_args EXCLUDE REGEX "^-DMODULE_DIR=")
list(PREPEND marker_args "-DMODULE_DIR=${marker_module_junction}")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    "PURE_ODBC_TEST_QUERY_MARKER=${query_execution_marker}"
    "${CMAKE_COMMAND}" ${marker_args}
    -P "${SOURCE_DIR}/cmake/RunPureTest.cmake"
  RESULT_VARIABLE marker_probe_result
  OUTPUT_VARIABLE marker_probe_output
  ERROR_VARIABLE marker_probe_error
  ENCODING UTF-8
)
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    "PURE_ODBC_LINK_PATH=${marker_module_junction}"
    "${powershell}" -NoProfile -NonInteractive -ExecutionPolicy Bypass
    -Command
    "$ErrorActionPreference='Stop'; $item=Get-Item -LiteralPath $env:PURE_ODBC_LINK_PATH -Force; if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { throw 'not a reparse point' }; [IO.Directory]::Delete($env:PURE_ODBC_LINK_PATH, $false)"
  RESULT_VARIABLE marker_cleanup_result
  OUTPUT_VARIABLE marker_cleanup_output
  ERROR_VARIABLE marker_cleanup_error
  ENCODING UTF-8
)
if(NOT marker_cleanup_result EQUAL 0)
  message(FATAL_ERROR
    "Unable to remove runner-execution junction probe\n"
    "${marker_cleanup_output}${marker_cleanup_error}")
endif()
set(marker_probe_diagnostics "${marker_probe_output}\n${marker_probe_error}")
if(EXISTS "${query_execution_marker}")
  message(FATAL_ERROR
    "RunPureTest executed an untrusted junction-path runner before validation\n"
    "${marker_probe_diagnostics}")
endif()
if(marker_probe_result EQUAL 0 OR
    NOT marker_probe_diagnostics MATCHES "MODULE_DIR.*[Rr]eparse")
  message(FATAL_ERROR
    "RunPureTest did not reject a junction-path runner before execution\n"
    "${marker_probe_diagnostics}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    "PURE_ODBC_TEST_WINDOWS_DIRECTORY=${TEST_ROOT}/alternate-windows"
    "${ALTERNATE_RUN_PURE_TEST_EXECUTABLE}"
    "${TEST_ROOT}/pure/bin/fake-success.exe"
    "${SOURCE_DIR}"
    "${TEST_ROOT}/module"
    "${TEST_ROOT}/test.pure"
    "${TEST_ROOT}/alternate-windows"
  RESULT_VARIABLE alternate_launch_result
  OUTPUT_VARIABLE alternate_launch_output
  ERROR_VARIABLE alternate_launch_error
  ENCODING UTF-8
)
if(NOT alternate_launch_result EQUAL 0 OR
    NOT alternate_launch_error STREQUAL "")
  message(FATAL_ERROR
    "Alternate-authority native launcher failed\n"
    "${alternate_launch_output}${alternate_launch_error}")
endif()

set(partial_thread_marker "${TEST_ROOT}/partial-thread-cleanup.events")
file(REMOVE "${partial_thread_marker}")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    "PURE_ODBC_TEST_WINDOWS_DIRECTORY=${TEST_ROOT}/alternate-windows"
    "PURE_ODBC_TEST_CREATE_THREAD_FAILURE=2"
    "PURE_ODBC_TEST_CLEANUP_MARKER=${partial_thread_marker}"
    "${ALTERNATE_RUN_PURE_TEST_EXECUTABLE}"
    "${TEST_ROOT}/pure/bin/fake-hang.exe"
    "${SOURCE_DIR}"
    "${TEST_ROOT}/module"
    "${TEST_ROOT}/test.pure"
    "${TEST_ROOT}/alternate-windows"
  RESULT_VARIABLE partial_thread_result
  OUTPUT_VARIABLE partial_thread_output
  ERROR_VARIABLE partial_thread_error
  TIMEOUT 10
  ENCODING UTF-8
)
if(NOT partial_thread_result EQUAL 1)
  message(FATAL_ERROR
    "Partial capture-thread failure did not fail promptly and exactly\n"
    "${partial_thread_output}${partial_thread_error}")
endif()
if(NOT EXISTS "${partial_thread_marker}")
  message(FATAL_ERROR "Partial capture-thread failure emitted no cleanup trace")
endif()
file(READ "${partial_thread_marker}" partial_thread_events)
if(NOT partial_thread_events MATCHES
    "terminate-process.*close-write-ends.*wait-process.*wait-stdout-thread.*close-stdout-thread.*close-stdout-read")
  message(FATAL_ERROR
    "Partial capture-thread cleanup ordering is unsafe\n${partial_thread_events}")
endif()
string(REGEX MATCH "EFFECTIVE_CWD=([^\r\n]+)" unused
  "${alternate_launch_output}")
_pure_odbc_fold_path("${CMAKE_MATCH_1}" folded_alternate_launch_cwd)
_pure_odbc_fold_path(
  "${TEST_ROOT}/alternate-windows" folded_alternate_windows_directory)
if(NOT folded_alternate_launch_cwd STREQUAL
    folded_alternate_windows_directory)
  message(FATAL_ERROR
    "Alternate-authority launcher ignored its controlled CWD\n"
    "${alternate_launch_output}")
endif()
string(REGEX MATCH "EFFECTIVE_PATH=([^\r\n]+)" unused
  "${alternate_launch_output}")
set(alternate_actual_path "${CMAKE_MATCH_1}")
set(alternate_expected_path
  "${TEST_ROOT}/module;${TEST_ROOT}/pure/bin"
  "${TEST_ROOT}/alternate-windows/System32"
  "${TEST_ROOT}/alternate-windows")
_pure_odbc_fold_path("${alternate_actual_path}" alternate_actual_path)
_pure_odbc_fold_path("${alternate_expected_path}" alternate_expected_path)
if(NOT alternate_actual_path STREQUAL alternate_expected_path)
  message(FATAL_ERROR
    "Alternate-authority launcher ignored its controlled PATH\n"
    "expected: ${alternate_expected_path}\n"
    "actual: ${alternate_actual_path}")
endif()

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

expect_runner_link_rejected(
  "a junction-component PURE_EXECUTABLE"
  Junction "${TEST_ROOT}/pure-directory-link"
  "${TEST_ROOT}/pure/bin" PURE_EXECUTABLE
  "${TEST_ROOT}/pure-directory-link/fake-success.exe" TRUE)
expect_runner_link_rejected(
  "a junction-component SCRIPT"
  Junction "${TEST_ROOT}/script-directory-link"
  "${TEST_ROOT}" SCRIPT "${TEST_ROOT}/script-directory-link/test.pure" TRUE)

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

set(arbitrary_work_args ${all_args})
list(FILTER arbitrary_work_args EXCLUDE REGEX "^-DWORK_DIRECTORY=")
list(PREPEND arbitrary_work_args "-DWORK_DIRECTORY=${TEST_ROOT}/work")
expect_runner_rejected(
  "an arbitrary existing WORK_DIRECTORY"
  "WORK_DIRECTORY must be the OS Windows directory"
  ${arbitrary_work_args})

set(os_windows_args ${all_args})
list(FILTER os_windows_args EXCLUDE REGEX "^-DWORK_DIRECTORY=")
list(PREPEND os_windows_args "-DWORK_DIRECTORY=${OS_WINDOWS_DIRECTORY}")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    "PATH=C:/ambient-msys2/bin;C:/ambient-tools"
    "PURELIB=C:/ambient-purelib"
    "SystemRoot=C:/controlled-untrusted-system-root"
    "${CMAKE_COMMAND}" ${os_windows_args}
    -P "${SOURCE_DIR}/cmake/RunPureTest.cmake"
  RESULT_VARIABLE os_windows_result
  OUTPUT_VARIABLE os_windows_output
  ERROR_VARIABLE os_windows_error
  ENCODING UTF-8
)
if(NOT os_windows_result EQUAL 0 OR NOT os_windows_error STREQUAL "")
  message(FATAL_ERROR
    "RunPureTest did not use the native OS Windows directory\n"
    "${os_windows_output}${os_windows_error}")
endif()
string(REGEX MATCH "EFFECTIVE_CWD=([^\r\n]+)" unused "${os_windows_output}")
_pure_odbc_fold_path("${CMAKE_MATCH_1}" folded_os_windows_cwd)
_pure_odbc_fold_path("${OS_WINDOWS_DIRECTORY}" folded_os_windows_directory)
if(NOT folded_os_windows_cwd STREQUAL folded_os_windows_directory)
  message(FATAL_ERROR
    "RunPureTest CWD disagrees with the native OS Windows directory\n"
    "${os_windows_output}")
endif()
string(REGEX MATCH "EFFECTIVE_PATH=([^\r\n]+)" unused "${os_windows_output}")
set(os_windows_actual_path "${CMAKE_MATCH_1}")
set(os_windows_expected_path
  "${TEST_ROOT}/module;${TEST_ROOT}/pure/bin"
  "${OS_WINDOWS_DIRECTORY}/System32;${OS_WINDOWS_DIRECTORY}")
_pure_odbc_fold_path("${os_windows_actual_path}" os_windows_actual_path)
_pure_odbc_fold_path("${os_windows_expected_path}" os_windows_expected_path)
if(NOT os_windows_actual_path STREQUAL os_windows_expected_path)
  message(FATAL_ERROR
    "RunPureTest PATH disagrees with the native OS Windows directory\n"
    "expected: ${os_windows_expected_path}\n"
    "actual: ${os_windows_actual_path}")
endif()

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
foreach(expected_arg IN ITEMS
    "EFFECTIVE_ARG_1=--norc"
    "EFFECTIVE_ARG_2=-I"
    "EFFECTIVE_ARG_3=${SOURCE_DIR}"
    "EFFECTIVE_ARG_4=-L"
    "EFFECTIVE_ARG_5=${TEST_ROOT}/module"
    "EFFECTIVE_ARG_6=-x"
    "EFFECTIVE_ARG_7=${TEST_ROOT}/test.pure")
  string(REPLACE "/" "[/\\\\]" expected_arg_pattern "${expected_arg}")
  if(NOT output MATCHES "${expected_arg_pattern}")
    message(FATAL_ERROR
      "Runner did not use the exact Pure command; missing "
      "'${expected_arg}'\n${output}")
  endif()
endforeach()
if(NOT output MATCHES "EFFECTIVE_PURELIB=UNSET" OR
    output MATCHES "EFFECTIVE_PURELIB=SET")
  message(FATAL_ERROR "Runner did not unset PURELIB\n${output}")
endif()
string(REGEX MATCH "EFFECTIVE_PATH=([^\r\n]+)" unused "${output}")
set(actual_path "${CMAKE_MATCH_1}")
set(expected_path
  "${TEST_ROOT}/module;${TEST_ROOT}/pure/bin"
  "${OS_WINDOWS_DIRECTORY}/System32;${OS_WINDOWS_DIRECTORY}")
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
_pure_odbc_fold_path("${TEST_ROOT}" expected_work_directory)
if(NOT actual_work_directory STREQUAL expected_work_directory)
  message(FATAL_ERROR
    "Runner used '${actual_work_directory}', expected '${expected_work_directory}'")
endif()

set(stderr_args ${all_args})
list(FILTER stderr_args EXCLUDE REGEX "^-DPURE_EXECUTABLE=")
list(PREPEND stderr_args
  "-DPURE_EXECUTABLE=${TEST_ROOT}/pure/bin/fake-stderr.exe")
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

execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    "PATH=C:/ambient-msys2/bin;C:/ambient-tools"
    "PURELIB=C:/ambient-purelib"
    "${RUN_PURE_TEST_EXECUTABLE}"
    "${TEST_ROOT}/pure/bin/fake-exit37.exe"
    "${SOURCE_DIR}"
    "${TEST_ROOT}/module"
    "${TEST_ROOT}/test.pure"
    "${TEST_ROOT}"
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

execute_process(
  COMMAND "${RUN_PURE_TEST_EXECUTABLE}"
    "${TEST_ROOT}/pure/bin/fake-exit77.exe"
    "${SOURCE_DIR}"
    "${TEST_ROOT}/module"
    "${TEST_ROOT}/test.pure"
    "${TEST_ROOT}"
  RESULT_VARIABLE skip_result
  OUTPUT_VARIABLE skip_output
  ERROR_VARIABLE skip_error
  ENCODING UTF-8
)
if(NOT skip_result EQUAL 77 OR NOT skip_error STREQUAL "" OR
    NOT skip_output MATCHES "SKIP_STDOUT_SENTINEL")
  message(FATAL_ERROR
    "Native runner did not preserve child exit 77\n"
    "${skip_output}${skip_error}")
endif()
if(NOT "${exit_output}\n${exit_error}" MATCHES "EXIT_STDOUT_SENTINEL")
  message(FATAL_ERROR
    "Runner discarded stdout from failed child\n${exit_output}${exit_error}")
endif()

file(READ "${ACCESS_SCRIPT}" access_source)
function(run_access_variant label driver_expression expected_result
    expected_diagnostic)
  string(REPLACE
    "drivers = odbc::drivers;"
    "drivers = ${driver_expression};"
    variant_source "${access_source}")
  if(variant_source STREQUAL access_source)
    message(FATAL_ERROR
      "Access ${label} probe could not replace the driver enumeration")
  endif()
  set(variant "${TEST_ROOT}/access-${label}.pure")
  file(WRITE "${variant}" "${variant_source}")
  execute_process(
    COMMAND "${RUN_PURE_TEST_EXECUTABLE}"
      "${ACTUAL_PURE_EXECUTABLE}"
      "${SOURCE_DIR}"
      "${ACTUAL_MODULE_DIR}"
      "${variant}"
      "${ACCESS_WORK_DIRECTORY}"
    RESULT_VARIABLE variant_result
    OUTPUT_VARIABLE variant_output
    ERROR_VARIABLE variant_error
    ENCODING UTF-8
  )
  set(variant_diagnostics "${variant_output}\n${variant_error}")
  if(NOT variant_result EQUAL expected_result OR
      NOT variant_diagnostics MATCHES "${expected_diagnostic}")
    message(FATAL_ERROR
      "Access ${label} contract failed (expected ${expected_result}, "
      "got ${variant_result})\n${variant_diagnostics}")
  endif()
endfunction()

run_access_variant(
  "driver-absent" "[]" 77 "PURE_ODBC_TEXT_DRIVER_SKIPPED")
run_access_variant(
  "malformed-before-exact"
  "[(\"malformed\",42),(text_driver,[])]" 1 "driver record shape")
run_access_variant(
  "malformed-after-exact"
  "[(text_driver,[]),(\"malformed\",42)]" 1 "driver record shape")

set(skip_ctest_directory "${TEST_ROOT}/absence-skip-ctest")
file(MAKE_DIRECTORY "${skip_ctest_directory}")
file(WRITE "${skip_ctest_directory}/CTestTestfile.cmake"
  "add_test(pure-odbc-access-absence-contract "
  "\"${RUN_PURE_TEST_EXECUTABLE}\" "
  "\"${ACTUAL_PURE_EXECUTABLE}\" "
  "\"${SOURCE_DIR}\" "
  "\"${ACTUAL_MODULE_DIR}\" "
  "\"${TEST_ROOT}/access-driver-absent.pure\" "
  "\"${ACCESS_WORK_DIRECTORY}\")\n"
  "set_tests_properties(pure-odbc-access-absence-contract PROPERTIES "
  "SKIP_RETURN_CODE 77)\n")
cmake_path(GET CMAKE_COMMAND PARENT_PATH cmake_bin)
set(ctest_executable "${cmake_bin}/ctest.exe")
if(NOT EXISTS "${ctest_executable}" OR IS_DIRECTORY "${ctest_executable}")
  message(FATAL_ERROR "CTest executable is missing: ${ctest_executable}")
endif()
execute_process(
  COMMAND "${ctest_executable}"
    --test-dir "${skip_ctest_directory}" --output-on-failure
  RESULT_VARIABLE skip_ctest_result
  OUTPUT_VARIABLE skip_ctest_output
  ERROR_VARIABLE skip_ctest_error
  ENCODING UTF-8
)
if(NOT skip_ctest_result EQUAL 0 OR
    NOT skip_ctest_output MATCHES "[*][*][*]Skipped" OR
    NOT skip_ctest_output MATCHES "100% tests passed")
  message(FATAL_ERROR
    "CTest did not classify exact-driver absence as an explicit skip\n"
    "${skip_ctest_output}${skip_ctest_error}")
endif()

message(STATUS "pure-odbc runner and root-safety contracts passed")
