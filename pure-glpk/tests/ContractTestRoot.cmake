include_guard(GLOBAL)

set(_pure_glpk_contract_helper_dir "${CMAKE_CURRENT_LIST_DIR}")
cmake_path(ABSOLUTE_PATH _pure_glpk_contract_helper_dir NORMALIZE
  OUTPUT_VARIABLE _pure_glpk_contract_helper_dir)
set(_pure_glpk_source_lexical "${_pure_glpk_contract_helper_dir}/..")
cmake_path(NORMAL_PATH _pure_glpk_source_lexical
  OUTPUT_VARIABLE _pure_glpk_source_lexical)

function(_pure_glpk_fold_path input output)
  cmake_path(CONVERT "${input}" TO_CMAKE_PATH_LIST folded NORMALIZE)
  string(TOLOWER "${folded}" folded)
  string(REGEX REPLACE "/+$" "" folded "${folded}")
  set(${output} "${folded}" PARENT_SCOPE)
endfunction()

function(_pure_glpk_require_no_reparse path label scan_descendants)
  if(NOT WIN32)
    if(IS_SYMLINK "${path}")
      message(FATAL_ERROR "Unsafe ${label} symlink: ${path}")
    endif()
    return()
  endif()
  set(powershell
    "$ENV{SystemRoot}/System32/WindowsPowerShell/v1.0/powershell.exe")
  if(NOT EXISTS "${powershell}" OR IS_DIRECTORY "${powershell}")
    message(FATAL_ERROR
      "Cannot inspect ${label} for Windows reparse points: ${powershell}")
  endif()
  set(check_script [=[
$ErrorActionPreference = 'Stop'
$target = [IO.Path]::GetFullPath($env:PURE_GLPK_CHECK_PATH)
$scanDescendants = $env:PURE_GLPK_SCAN_DESCENDANTS -eq 'TRUE'
$root = [IO.Path]::GetPathRoot($target)
$current = $root
$parts = $target.Substring($root.Length).Split(
  [char[]]@('\', '/'), [StringSplitOptions]::RemoveEmptyEntries)
foreach ($part in $parts) {
  $current = [IO.Path]::Combine($current, $part)
  if (-not (Test-Path -LiteralPath $current)) { break }
  $item = Get-Item -LiteralPath $current -Force
  if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    [Console]::Error.WriteLine("reparse component: $($item.FullName)")
    exit 17
  }
}
if ($scanDescendants -and (Test-Path -LiteralPath $target)) {
  foreach ($item in Get-ChildItem -LiteralPath $target -Force -Recurse) {
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      [Console]::Error.WriteLine("reparse descendant: $($item.FullName)")
      exit 18
    }
  }
}
]=])
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env
      "PURE_GLPK_CHECK_PATH=${path}"
      "PURE_GLPK_SCAN_DESCENDANTS=${scan_descendants}"
      "${powershell}" -NoProfile -NonInteractive -ExecutionPolicy Bypass
      -Command "${check_script}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8
  )
  if(NOT result EQUAL 0)
    message(FATAL_ERROR
      "Unsafe ${label}; reparse-point inspection failed (${result})\n"
      "path: ${path}\n${output}${error}")
  endif()
endfunction()

function(_pure_glpk_cache_value cache_file name output)
  file(STRINGS "${cache_file}" lines
    REGEX "^${name}:[^=]*=" LIMIT_COUNT 1)
  list(LENGTH lines count)
  if(NOT count EQUAL 1)
    message(FATAL_ERROR "${cache_file} has no unique ${name} entry")
  endif()
  list(GET lines 0 value)
  string(REGEX REPLACE "^[^=]*=" "" value "${value}")
  set(${output} "${value}" PARENT_SCOPE)
endfunction()

function(pure_glpk_validate_contract_test_root leaf output_test_root)
  if(NOT leaf MATCHES
      "^(runner|configure|install|runtime-verifier|source-dist)$")
    message(FATAL_ERROR "Unknown pure-glpk contract leaf: ${leaf}")
  endif()
  if(NOT DEFINED BINARY_DIR OR "${BINARY_DIR}" STREQUAL "")
    message(FATAL_ERROR "BINARY_DIR is required")
  endif()

  _pure_glpk_require_no_reparse(
    "${_pure_glpk_source_lexical}" "canonical SOURCE_DIR" FALSE)
  file(REAL_PATH "${_pure_glpk_source_lexical}" canonical_source)
  cmake_path(ABSOLUTE_PATH BINARY_DIR NORMALIZE OUTPUT_VARIABLE binary_dir)
  if(NOT IS_DIRECTORY "${binary_dir}")
    message(FATAL_ERROR "BINARY_DIR must be an existing directory: ${binary_dir}")
  endif()
  _pure_glpk_require_no_reparse("${binary_dir}" "BINARY_DIR" FALSE)
  file(REAL_PATH "${binary_dir}" canonical_binary)

  _pure_glpk_fold_path("${canonical_source}" folded_source)
  _pure_glpk_fold_path("${canonical_binary}" folded_binary)
  string(FIND "${folded_binary}/" "${folded_source}/" source_prefix)
  if(source_prefix EQUAL 0 OR folded_binary STREQUAL folded_source)
    message(FATAL_ERROR
      "Unsafe BINARY_DIR is inside canonical SOURCE_DIR\n"
      "BINARY_DIR: ${binary_dir}\nSOURCE_DIR: ${canonical_source}")
  endif()

  set(cache_file "${canonical_binary}/CMakeCache.txt")
  if(NOT EXISTS "${cache_file}" OR IS_DIRECTORY "${cache_file}" OR
      IS_SYMLINK "${cache_file}")
    message(FATAL_ERROR
      "BINARY_DIR has no regular CMakeCache.txt: ${canonical_binary}")
  endif()
  _pure_glpk_require_no_reparse("${cache_file}" "CMakeCache.txt" FALSE)
  _pure_glpk_cache_value("${cache_file}" CMAKE_HOME_DIRECTORY cache_source)
  _pure_glpk_cache_value("${cache_file}" CMAKE_CACHEFILE_DIR cache_binary)
  _pure_glpk_cache_value("${cache_file}" CMAKE_PROJECT_NAME cache_project)
  cmake_path(ABSOLUTE_PATH cache_source NORMALIZE OUTPUT_VARIABLE cache_source)
  cmake_path(ABSOLUTE_PATH cache_binary NORMALIZE OUTPUT_VARIABLE cache_binary)
  _pure_glpk_require_no_reparse("${cache_source}" "cached source" FALSE)
  _pure_glpk_require_no_reparse("${cache_binary}" "cached binary" FALSE)
  file(REAL_PATH "${cache_source}" cache_source)
  file(REAL_PATH "${cache_binary}" cache_binary)
  _pure_glpk_fold_path("${cache_source}" folded_cache_source)
  _pure_glpk_fold_path("${cache_binary}" folded_cache_binary)
  if(NOT folded_cache_source STREQUAL folded_source)
    message(FATAL_ERROR
      "BINARY_DIR cache belongs to another source tree: ${cache_source}")
  endif()
  if(NOT folded_cache_binary STREQUAL folded_binary)
    message(FATAL_ERROR
      "BINARY_DIR cache identity mismatch: ${cache_binary}")
  endif()
  if(NOT cache_project STREQUAL "pure-glpk")
    message(FATAL_ERROR
      "BINARY_DIR cache belongs to project '${cache_project}', not pure-glpk")
  endif()

  set(contract_root "${canonical_binary}/pure-glpk-contract")
  set(test_root "${contract_root}/${leaf}")
  _pure_glpk_require_no_reparse("${contract_root}" "CONTRACT_ROOT" FALSE)
  _pure_glpk_require_no_reparse("${test_root}" "TEST_ROOT" FALSE)

  set(SOURCE_DIR "${canonical_source}" PARENT_SCOPE)
  set(BINARY_DIR "${canonical_binary}" PARENT_SCOPE)
  set(CONTRACT_ROOT "${contract_root}" PARENT_SCOPE)
  set(TEST_ROOT "${test_root}" PARENT_SCOPE)
  set(${output_test_root} "${test_root}" PARENT_SCOPE)
endfunction()

function(pure_glpk_reset_contract_test_root leaf)
  pure_glpk_validate_contract_test_root("${leaf}" validated_test_root)
  _pure_glpk_fold_path("${SOURCE_DIR}" folded_source)
  _pure_glpk_fold_path("${BINARY_DIR}" folded_binary)
  set(sentinel "${validated_test_root}/.pure-glpk-contract-owner")
  set(expected_sentinel
    "pure-glpk-contract-v1\nleaf=${leaf}\nsource=${folded_source}\nbinary=${folded_binary}\n")

  if(EXISTS "${validated_test_root}" OR IS_SYMLINK "${validated_test_root}")
    if(NOT IS_DIRECTORY "${validated_test_root}" OR
        IS_SYMLINK "${validated_test_root}")
      message(FATAL_ERROR
        "Refusing cleanup of non-directory TEST_ROOT: ${validated_test_root}")
    endif()
    _pure_glpk_require_no_reparse(
      "${validated_test_root}" "owned TEST_ROOT" TRUE)
    if(NOT EXISTS "${sentinel}" OR IS_DIRECTORY "${sentinel}" OR
        IS_SYMLINK "${sentinel}")
      message(FATAL_ERROR
        "Refusing cleanup without ownership sentinel: ${validated_test_root}")
    endif()
    file(READ "${sentinel}" actual_sentinel)
    if(NOT actual_sentinel STREQUAL expected_sentinel)
      message(FATAL_ERROR
        "Refusing cleanup with invalid ownership sentinel: ${sentinel}")
    endif()
    file(REMOVE_RECURSE "${validated_test_root}")
    if(EXISTS "${validated_test_root}" OR IS_SYMLINK "${validated_test_root}")
      message(FATAL_ERROR "Unable to reset TEST_ROOT: ${validated_test_root}")
    endif()
  endif()
  file(MAKE_DIRECTORY "${validated_test_root}")
  file(WRITE "${sentinel}" "${expected_sentinel}")

  set(SOURCE_DIR "${SOURCE_DIR}" PARENT_SCOPE)
  set(BINARY_DIR "${BINARY_DIR}" PARENT_SCOPE)
  set(CONTRACT_ROOT "${CONTRACT_ROOT}" PARENT_SCOPE)
  set(TEST_ROOT "${validated_test_root}" PARENT_SCOPE)
endfunction()

function(_pure_glpk_expect_binary_rejected label leaf candidate expected)
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DBINARY_DIR=${candidate}"
      "-DEXPECTED_LEAF=${leaf}"
      -DROOT_SAFETY_PROBE=ON
      -P "${_pure_glpk_contract_helper_dir}/ContractTestRootProbe.cmake"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8
  )
  if(result EQUAL 0)
    message(FATAL_ERROR
      "Root-safety probe accepted unsafe ${label} BINARY_DIR: ${candidate}")
  endif()
  if(NOT "${output}\n${error}" MATCHES "${expected}")
    message(FATAL_ERROR
      "Unsafe ${label} BINARY_DIR produced the wrong diagnostic\n"
      "${output}\n${error}")
  endif()
endfunction()

function(pure_glpk_run_root_safety_probes leaf)
  pure_glpk_validate_contract_test_root("${leaf}" unused_test_root)
  _pure_glpk_expect_binary_rejected("protected descendant" "${leaf}"
    "${SOURCE_DIR}/tests" "inside canonical SOURCE_DIR")
  string(TOUPPER "${SOURCE_DIR}/tests" case_alias)
  _pure_glpk_expect_binary_rejected("case-only protected descendant" "${leaf}"
    "${case_alias}" "inside canonical SOURCE_DIR")

  set(junction "${BINARY_DIR}/pure-glpk-reparse-probe-${leaf}")
  if(EXISTS "${junction}" OR IS_SYMLINK "${junction}")
    message(FATAL_ERROR "Refusing to replace existing reparse probe: ${junction}")
  endif()
  set(powershell
    "$ENV{SystemRoot}/System32/WindowsPowerShell/v1.0/powershell.exe")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env
      "PURE_GLPK_JUNCTION_PATH=${junction}"
      "PURE_GLPK_JUNCTION_TARGET=${BINARY_DIR}"
      "${powershell}" -NoProfile -NonInteractive -ExecutionPolicy Bypass
      -Command
      "$ErrorActionPreference='Stop'; New-Item -ItemType Junction -Path $env:PURE_GLPK_JUNCTION_PATH -Target $env:PURE_GLPK_JUNCTION_TARGET | Out-Null"
    RESULT_VARIABLE junction_result
    OUTPUT_VARIABLE junction_output
    ERROR_VARIABLE junction_error
    ENCODING UTF-8
  )
  if(NOT junction_result EQUAL 0)
    message(FATAL_ERROR
      "Unable to create safe junction root-safety probe (${junction_result})\n"
      "${junction_output}${junction_error}")
  endif()
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DBINARY_DIR=${junction}"
      "-DEXPECTED_LEAF=${leaf}"
      -DROOT_SAFETY_PROBE=ON
      -P "${_pure_glpk_contract_helper_dir}/ContractTestRootProbe.cmake"
    RESULT_VARIABLE reparse_result
    OUTPUT_VARIABLE reparse_output
    ERROR_VARIABLE reparse_error
    ENCODING UTF-8
  )
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env
      "PURE_GLPK_JUNCTION_PATH=${junction}"
      "${powershell}" -NoProfile -NonInteractive -ExecutionPolicy Bypass
      -Command
      "$ErrorActionPreference='Stop'; $item=Get-Item -LiteralPath $env:PURE_GLPK_JUNCTION_PATH -Force; if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { throw 'not a reparse point' }; [IO.Directory]::Delete($env:PURE_GLPK_JUNCTION_PATH, $false)"
    RESULT_VARIABLE cleanup_result
    OUTPUT_VARIABLE cleanup_output
    ERROR_VARIABLE cleanup_error
    ENCODING UTF-8
  )
  if(NOT cleanup_result EQUAL 0)
    message(FATAL_ERROR
      "Unable to remove junction root-safety probe (${cleanup_result})\n"
      "${cleanup_output}${cleanup_error}")
  endif()
  if(reparse_result EQUAL 0)
    message(FATAL_ERROR
      "Root-safety probe accepted reparse BINARY_DIR: ${junction}")
  endif()
  if(NOT "${reparse_output}\n${reparse_error}" MATCHES "[Rr]eparse")
    message(FATAL_ERROR
      "Reparse BINARY_DIR produced the wrong diagnostic\n"
      "${reparse_output}\n${reparse_error}")
  endif()
endfunction()
