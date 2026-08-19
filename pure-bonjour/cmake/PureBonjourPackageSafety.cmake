cmake_minimum_required(VERSION 3.25)

set(pure_bonjour_filesystem_safety
  "${CMAKE_CURRENT_LIST_DIR}/PureBonjourFilesystemSafety.ps1")
set(pure_bonjour_expected_paths
  lib/pure/bonjour.dll
  lib/pure/bonjour.pure
  share/doc/pure-bonjour/COPYING
  share/doc/pure-bonjour/COPYING.LESSER
  share/doc/pure-bonjour/PureBonjourInventory.tsv
  share/doc/pure-bonjour/README
  share/doc/pure-bonjour/WINDOWS.md
  share/doc/pure-bonjour/examples/bonjour_examp.pure)
list(SORT pure_bonjour_expected_paths)

function(pure_bonjour_safety_fail token detail)
  message(FATAL_ERROR "${token}: ${detail}")
endfunction()
function(pure_bonjour_fs_action mode path root token)
  set(powershell
    "$ENV{SystemRoot}/System32/WindowsPowerShell/v1.0/powershell.exe")
  execute_process(
    COMMAND "${powershell}" -NoLogo -NoProfile -NonInteractive
      -File "${pure_bonjour_filesystem_safety}"
      -Mode "${mode}" -Path "${path}" -Root "${root}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8)
  if(NOT result EQUAL 0)
    pure_bonjour_safety_fail("${token}"
      "filesystem safety check failed for ${path}: ${output}${error}")
  endif()
endfunction()

function(pure_bonjour_try_unlink_reparse path removed_output detail_output)
  set(powershell
    "$ENV{SystemRoot}/System32/WindowsPowerShell/v1.0/powershell.exe")
  execute_process(
    COMMAND "${powershell}" -NoLogo -NoProfile -NonInteractive
      -File "${pure_bonjour_filesystem_safety}"
      -Mode unlink-reparse -Path "${path}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8)
  if(result EQUAL 0)
    set(${removed_output} TRUE PARENT_SCOPE)
  else()
    set(${removed_output} FALSE PARENT_SCOPE)
  endif()
  set(${detail_output} "${output}${error}" PARENT_SCOPE)
endfunction()

function(pure_bonjour_validate_relative_path relative context path_output
    identity_output)
  if(relative STREQUAL "" OR IS_ABSOLUTE "${relative}" OR
      relative MATCHES "^[A-Za-z]:" OR relative MATCHES "^[/\\\\]" OR
      relative MATCHES "(^|[/\\\\])\\.\\.([/\\\\]|$)" OR
      relative MATCHES "(^|[/\\\\])\\.([/\\\\]|$)" OR
      relative MATCHES "//|\\\\|:|[*?]" OR
      NOT relative MATCHES "^[A-Za-z0-9._/+ -]+$")
    pure_bonjour_safety_fail(PACKAGE_INVENTORY
      "${context} contains unsafe relative path: ${relative}")
  endif()
  set(normalized "${relative}")
  cmake_path(NORMAL_PATH normalized)
  if(NOT normalized STREQUAL relative)
    pure_bonjour_safety_fail(PACKAGE_INVENTORY
      "${context} path is not canonical: ${relative}")
  endif()
  string(TOLOWER "${normalized}" identity)
  set(${path_output} "${normalized}" PARENT_SCOPE)
  set(${identity_output} "${identity}" PARENT_SCOPE)
endfunction()

function(pure_bonjour_parse_external_oracle oracle_input protected_prefix
    canonical_output paths_output identities_output hashes_output)
  if(NOT IS_ABSOLUTE "${oracle_input}" OR NOT EXISTS "${oracle_input}" OR
      IS_DIRECTORY "${oracle_input}")
    pure_bonjour_safety_fail(PACKAGE_INVENTORY
      "external expected-hash oracle is missing or not a file: ${oracle_input}")
  endif()
  pure_bonjour_fs_action(inspect-file "${oracle_input}" ""
    PACKAGE_INVENTORY)
  file(REAL_PATH "${oracle_input}" canonical_oracle)
  file(REAL_PATH "${protected_prefix}" canonical_protected)
  cmake_path(IS_PREFIX canonical_protected "${canonical_oracle}" NORMALIZE
    oracle_inside_prefix)
  if(oracle_inside_prefix)
    pure_bonjour_safety_fail(PACKAGE_INVENTORY
      "external oracle must remain outside the protected prefix: "
      "${canonical_oracle}")
  endif()

  file(STRINGS "${canonical_oracle}" oracle_lines ENCODING UTF-8)
  list(LENGTH oracle_lines oracle_line_count)
  if(NOT oracle_line_count EQUAL 8)
    pure_bonjour_safety_fail(PACKAGE_INVENTORY
      "external expected-hash oracle must contain exactly eight rows")
  endif()
  set(paths)
  set(identities)
  set(hashes)
  foreach(line IN LISTS oracle_lines)
    string(LENGTH "${line}" line_length)
    if(line_length LESS 67)
      pure_bonjour_safety_fail(PACKAGE_INVENTORY
        "external expected-hash oracle row is malformed: ${line}")
    endif()
    string(SUBSTRING "${line}" 0 64 expected_sha)
    string(SUBSTRING "${line}" 64 2 separator)
    string(SUBSTRING "${line}" 66 -1 relative)
    string(LENGTH "${expected_sha}" sha_length)
    if(NOT sha_length EQUAL 64 OR
        NOT expected_sha MATCHES "^[0-9A-Fa-f]+$" OR
        NOT separator STREQUAL "  ")
      pure_bonjour_safety_fail(PACKAGE_INVENTORY
        "external expected-hash oracle row is malformed: ${line}")
    endif()
    pure_bonjour_validate_relative_path(
      "${relative}" "external expected-hash oracle" normalized identity)
    if(identity IN_LIST identities)
      pure_bonjour_safety_fail(PACKAGE_INVENTORY
        "external expected-hash oracle repeats a case-folded path: ${relative}")
    endif()
    string(TOLOWER "${expected_sha}" expected_sha)
    list(APPEND paths "${normalized}")
    list(APPEND identities "${identity}")
    list(APPEND hashes "${expected_sha}")
  endforeach()
  set(sorted_paths "${paths}")
  list(SORT sorted_paths)
  if(NOT sorted_paths STREQUAL pure_bonjour_expected_paths)
    pure_bonjour_safety_fail(PACKAGE_SET
      "external oracle ownership set differs from the exact eight paths: "
      "${sorted_paths}")
  endif()
  set(${canonical_output} "${canonical_oracle}" PARENT_SCOPE)
  set(${paths_output} "${paths}" PARENT_SCOPE)
  set(${identities_output} "${identities}" PARENT_SCOPE)
  set(${hashes_output} "${hashes}" PARENT_SCOPE)
endfunction()
