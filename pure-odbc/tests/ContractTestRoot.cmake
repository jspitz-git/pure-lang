include_guard(GLOBAL)

set(_pure_odbc_contract_helper_dir "${CMAKE_CURRENT_LIST_DIR}")
cmake_path(ABSOLUTE_PATH _pure_odbc_contract_helper_dir NORMALIZE
  OUTPUT_VARIABLE _pure_odbc_contract_helper_dir)
set(_pure_odbc_source_lexical "${_pure_odbc_contract_helper_dir}/..")
cmake_path(NORMAL_PATH _pure_odbc_source_lexical
  OUTPUT_VARIABLE _pure_odbc_source_lexical)

function(_pure_odbc_fold_path input output)
  cmake_path(CONVERT "${input}" TO_CMAKE_PATH_LIST folded NORMALIZE)
  if(WIN32)
    string(TOLOWER "${folded}" folded)
  endif()
  string(REGEX REPLACE "/+$" "" folded "${folded}")
  set(${output} "${folded}" PARENT_SCOPE)
endfunction()

function(_pure_odbc_require_no_reparse path label scan_descendants)
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
$target = [IO.Path]::GetFullPath($env:PURE_ODBC_CHECK_PATH)
$scanDescendants = $env:PURE_ODBC_SCAN_DESCENDANTS -eq 'TRUE'
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
      "PURE_ODBC_CHECK_PATH=${path}"
      "PURE_ODBC_SCAN_DESCENDANTS=${scan_descendants}"
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

function(_pure_odbc_cache_value cache_file name output)
  file(STRINGS "${cache_file}" lines REGEX "^${name}:[^=]*=")
  list(LENGTH lines count)
  if(NOT count EQUAL 1)
    message(FATAL_ERROR
      "${cache_file} must have exactly one ${name} entry (found ${count})")
  endif()
  list(GET lines 0 value)
  string(REGEX REPLACE "^[^=]*=" "" value "${value}")
  set(${output} "${value}" PARENT_SCOPE)
endfunction()

function(_pure_odbc_validate_leaf leaf)
  if(NOT leaf MATCHES "^(runner|cleanup|access)$")
    message(FATAL_ERROR "Unknown pure-odbc contract leaf: ${leaf}")
  endif()
endfunction()

function(_pure_odbc_validate_source_and_binary source binary)
  _pure_odbc_require_no_reparse("${_pure_odbc_source_lexical}"
    "canonical SOURCE_DIR" FALSE)
  file(REAL_PATH "${_pure_odbc_source_lexical}" canonical_source)

  cmake_path(ABSOLUTE_PATH source NORMALIZE OUTPUT_VARIABLE candidate_source)
  if(NOT IS_DIRECTORY "${candidate_source}")
    message(FATAL_ERROR
      "SOURCE_DIR must be an existing directory: ${candidate_source}")
  endif()
  _pure_odbc_require_no_reparse("${candidate_source}" "SOURCE_DIR" FALSE)
  file(REAL_PATH "${candidate_source}" candidate_source)

  cmake_path(ABSOLUTE_PATH binary NORMALIZE OUTPUT_VARIABLE candidate_binary)
  if(NOT IS_DIRECTORY "${candidate_binary}")
    message(FATAL_ERROR
      "BINARY_DIR must be an existing directory: ${candidate_binary}")
  endif()
  _pure_odbc_require_no_reparse("${candidate_binary}" "BINARY_DIR" FALSE)
  file(REAL_PATH "${candidate_binary}" candidate_binary)

  _pure_odbc_fold_path("${canonical_source}" folded_canonical_source)
  _pure_odbc_fold_path("${candidate_source}" folded_candidate_source)
  _pure_odbc_fold_path("${candidate_binary}" folded_candidate_binary)
  if(NOT folded_candidate_source STREQUAL folded_canonical_source)
    message(FATAL_ERROR
      "SOURCE_DIR does not match helper-derived canonical source\n"
      "SOURCE_DIR: ${candidate_source}\n"
      "canonical source: ${canonical_source}")
  endif()
  string(FIND "${folded_candidate_binary}/"
    "${folded_canonical_source}/" source_prefix)
  if(source_prefix EQUAL 0 OR
      folded_candidate_binary STREQUAL folded_canonical_source)
    message(FATAL_ERROR
      "Unsafe BINARY_DIR is inside canonical SOURCE_DIR\n"
      "BINARY_DIR: ${candidate_binary}\nSOURCE_DIR: ${canonical_source}")
  endif()

  set(_validated_source "${canonical_source}" PARENT_SCOPE)
  set(_validated_binary "${candidate_binary}" PARENT_SCOPE)
endfunction()

function(_pure_odbc_sentinel_content leaf source binary output)
  _pure_odbc_fold_path("${source}" folded_source)
  _pure_odbc_fold_path("${binary}" folded_binary)
  set(content
    "pure-odbc-contract-v1\nleaf=${leaf}\nsource=${folded_source}\nbinary=${folded_binary}\n")
  set(${output} "${content}" PARENT_SCOPE)
endfunction()

function(pure_odbc_validate_contract_test_root leaf output_test_root)
  _pure_odbc_validate_leaf("${leaf}")
  if(NOT DEFINED BINARY_DIR OR "${BINARY_DIR}" STREQUAL "")
    message(FATAL_ERROR "BINARY_DIR is required")
  endif()

  _pure_odbc_validate_source_and_binary(
    "${_pure_odbc_source_lexical}" "${BINARY_DIR}")
  set(canonical_source "${_validated_source}")
  set(canonical_binary "${_validated_binary}")

  set(cache_file "${canonical_binary}/CMakeCache.txt")
  if(NOT EXISTS "${cache_file}" OR IS_DIRECTORY "${cache_file}" OR
      IS_SYMLINK "${cache_file}")
    message(FATAL_ERROR
      "BINARY_DIR has no regular CMakeCache.txt: ${canonical_binary}")
  endif()
  _pure_odbc_require_no_reparse("${cache_file}" "CMakeCache.txt" FALSE)
  _pure_odbc_cache_value(
    "${cache_file}" CMAKE_HOME_DIRECTORY cache_source)
  _pure_odbc_cache_value(
    "${cache_file}" CMAKE_CACHEFILE_DIR cache_binary)
  _pure_odbc_cache_value(
    "${cache_file}" CMAKE_PROJECT_NAME cache_project)

  cmake_path(ABSOLUTE_PATH cache_source NORMALIZE OUTPUT_VARIABLE cache_source)
  cmake_path(ABSOLUTE_PATH cache_binary NORMALIZE OUTPUT_VARIABLE cache_binary)
  if(NOT IS_DIRECTORY "${cache_source}" OR
      NOT IS_DIRECTORY "${cache_binary}")
    message(FATAL_ERROR "BINARY_DIR cache contains a nonexistent path")
  endif()
  _pure_odbc_require_no_reparse("${cache_source}" "cached source" FALSE)
  _pure_odbc_require_no_reparse("${cache_binary}" "cached binary" FALSE)
  file(REAL_PATH "${cache_source}" cache_source)
  file(REAL_PATH "${cache_binary}" cache_binary)
  _pure_odbc_fold_path("${canonical_source}" folded_source)
  _pure_odbc_fold_path("${canonical_binary}" folded_binary)
  _pure_odbc_fold_path("${cache_source}" folded_cache_source)
  _pure_odbc_fold_path("${cache_binary}" folded_cache_binary)
  if(NOT folded_cache_source STREQUAL folded_source)
    message(FATAL_ERROR
      "BINARY_DIR cache belongs to another source tree: ${cache_source}")
  endif()
  if(NOT folded_cache_binary STREQUAL folded_binary)
    message(FATAL_ERROR
      "BINARY_DIR cache identity mismatch: ${cache_binary}")
  endif()
  if(NOT cache_project STREQUAL "pure-odbc")
    message(FATAL_ERROR
      "BINARY_DIR cache belongs to project '${cache_project}', not pure-odbc")
  endif()

  set(contract_root "${canonical_binary}/pure-odbc-contract")
  set(test_root "${contract_root}/${leaf}")
  _pure_odbc_require_no_reparse("${contract_root}" "CONTRACT_ROOT" FALSE)
  _pure_odbc_require_no_reparse("${test_root}" "TEST_ROOT" FALSE)

  set(SOURCE_DIR "${canonical_source}" PARENT_SCOPE)
  set(BINARY_DIR "${canonical_binary}" PARENT_SCOPE)
  set(CONTRACT_ROOT "${contract_root}" PARENT_SCOPE)
  set(TEST_ROOT "${test_root}" PARENT_SCOPE)
  set(${output_test_root} "${test_root}" PARENT_SCOPE)
endfunction()

function(pure_odbc_contract_sentinel_content leaf output)
  _pure_odbc_validate_leaf("${leaf}")
  if(NOT DEFINED SOURCE_DIR OR NOT DEFINED BINARY_DIR)
    message(FATAL_ERROR
      "Contract root must be validated before requesting its sentinel")
  endif()
  _pure_odbc_sentinel_content(
    "${leaf}" "${SOURCE_DIR}" "${BINARY_DIR}" content)
  set(${output} "${content}" PARENT_SCOPE)
endfunction()

function(pure_odbc_reset_contract_test_root leaf)
  pure_odbc_validate_contract_test_root("${leaf}" validated_test_root)
  _pure_odbc_sentinel_content(
    "${leaf}" "${SOURCE_DIR}" "${BINARY_DIR}" expected_sentinel)
  set(sentinel "${validated_test_root}/.pure-odbc-contract-owner")

  if(EXISTS "${validated_test_root}" OR IS_SYMLINK "${validated_test_root}")
    if(NOT IS_DIRECTORY "${validated_test_root}" OR
        IS_SYMLINK "${validated_test_root}")
      message(FATAL_ERROR
        "Refusing cleanup of non-directory TEST_ROOT: ${validated_test_root}")
    endif()
    _pure_odbc_require_no_reparse(
      "${validated_test_root}" "owned TEST_ROOT" TRUE)
    if(NOT EXISTS "${sentinel}" OR IS_DIRECTORY "${sentinel}" OR
        IS_SYMLINK "${sentinel}")
      message(FATAL_ERROR
        "Refusing cleanup without ownership sentinel: ${validated_test_root}")
    endif()
    _pure_odbc_require_no_reparse(
      "${sentinel}" "ownership sentinel" FALSE)
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

function(pure_odbc_prepare_contract_test_root leaf configure_source
    configure_binary output_test_root)
  _pure_odbc_validate_leaf("${leaf}")
  _pure_odbc_validate_source_and_binary(
    "${configure_source}" "${configure_binary}")
  set(canonical_source "${_validated_source}")
  set(canonical_binary "${_validated_binary}")
  set(contract_root "${canonical_binary}/pure-odbc-contract")
  set(test_root "${contract_root}/${leaf}")
  set(sentinel "${test_root}/.pure-odbc-contract-owner")
  _pure_odbc_sentinel_content(
    "${leaf}" "${canonical_source}" "${canonical_binary}" expected_sentinel)

  _pure_odbc_require_no_reparse("${contract_root}" "CONTRACT_ROOT" FALSE)
  _pure_odbc_require_no_reparse("${test_root}" "TEST_ROOT" FALSE)
  if(EXISTS "${test_root}" OR IS_SYMLINK "${test_root}")
    if(NOT IS_DIRECTORY "${test_root}" OR IS_SYMLINK "${test_root}")
      message(FATAL_ERROR
        "Refusing to use non-directory TEST_ROOT: ${test_root}")
    endif()
    _pure_odbc_require_no_reparse("${test_root}" "owned TEST_ROOT" TRUE)
    if(NOT EXISTS "${sentinel}" OR IS_DIRECTORY "${sentinel}" OR
        IS_SYMLINK "${sentinel}")
      message(FATAL_ERROR
        "Refusing to use TEST_ROOT without ownership sentinel: ${test_root}")
    endif()
    file(READ "${sentinel}" actual_sentinel)
    if(NOT actual_sentinel STREQUAL expected_sentinel)
      message(FATAL_ERROR
        "Refusing to use TEST_ROOT with invalid ownership sentinel: ${sentinel}")
    endif()
  else()
    file(MAKE_DIRECTORY "${test_root}")
    file(WRITE "${sentinel}" "${expected_sentinel}")
  endif()
  set(${output_test_root} "${test_root}" PARENT_SCOPE)
endfunction()
