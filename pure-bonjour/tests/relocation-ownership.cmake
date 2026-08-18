cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS
    CMAKE_COMMAND BUILD_DIR VERIFIER SOURCE_PREFIX PURE_PREFIX TEST_ROOT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH BUILD_DIR NORMALIZE OUTPUT_VARIABLE build_dir)
cmake_path(ABSOLUTE_PATH SOURCE_PREFIX NORMALIZE OUTPUT_VARIABLE source_prefix)
cmake_path(ABSOLUTE_PATH PURE_PREFIX NORMALIZE OUTPUT_VARIABLE pure_prefix)
cmake_path(ABSOLUTE_PATH TEST_ROOT NORMALIZE OUTPUT_VARIABLE test_root)
set(oracle "${build_dir}/PureBonjourExpected.sha256")
set(inventory_relative
  "share/doc/pure-bonjour/PureBonjourInventory.tsv")

file(REMOVE_RECURSE "${test_root}")
file(MAKE_DIRECTORY "${test_root}")

execute_process(
  COMMAND "${CMAKE_COMMAND}" --build "${build_dir}"
  RESULT_VARIABLE build_result
  OUTPUT_VARIABLE build_output
  ERROR_VARIABLE build_error
  ENCODING UTF-8)
if(NOT build_result EQUAL 0)
  message(FATAL_ERROR
    "PureBonjour build failed (${build_result})\n${build_output}${build_error}")
endif()
if(NOT EXISTS "${oracle}")
  message(FATAL_ERROR "external expected-hash oracle is missing: ${oracle}")
endif()

function(verify_prefix prefix label)
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DSTAGE_PREFIX=${prefix}"
      "-DSOURCE_PREFIX=${source_prefix}"
      "-DBUILD_PREFIX=${build_dir}"
      "-DPURE_PREFIX=${prefix}"
      -P "${VERIFIER}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8)
  if(NOT result EQUAL 0)
    message(FATAL_ERROR
      "${label} verification failed (${result})\n${output}${error}")
  endif()
endfunction()

function(install_component prefix)
  execute_process(
    COMMAND "${CMAKE_COMMAND}" --install "${build_dir}"
      --prefix "${prefix}" --component PureBonjour
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8)
  if(NOT result EQUAL 0)
    message(FATAL_ERROR
      "component install failed (${result})\n${output}${error}")
  endif()
endfunction()

# Pure 0.68 uses the active Windows narrow code page for script paths.  Czech
# non-ASCII characters exercise Unicode filesystem relocation while remaining
# representable on the supported local runtime used by this Windows build.
set(first_prefix "${test_root}/Installed Pure Č")
set(relocated_prefix "${test_root}/Relocated Pure Ž")
file(MAKE_DIRECTORY "${first_prefix}")
file(COPY "${pure_prefix}/" DESTINATION "${first_prefix}")
file(MAKE_DIRECTORY
  "${first_prefix}/share/unrelated-owner"
  "${first_prefix}/share/keep-empty")
file(WRITE "${first_prefix}/lib/pure/unrelated-sentinel.bin"
  "shared library sentinel\n")
file(WRITE "${first_prefix}/share/unrelated-owner/sentinel.bin"
  "shared documentation sentinel\n")
file(SHA256 "${first_prefix}/lib/pure/unrelated-sentinel.bin"
  library_sentinel_sha)
file(SHA256 "${first_prefix}/share/unrelated-owner/sentinel.bin"
  documentation_sentinel_sha)

install_component("${first_prefix}")
verify_prefix("${first_prefix}" "installed Unicode/space prefix")

file(MAKE_DIRECTORY "${relocated_prefix}")
file(COPY "${first_prefix}/" DESTINATION "${relocated_prefix}")
verify_prefix("${relocated_prefix}" "relocated prefix")

# Same-version overlay must neither alter nor remove unrelated shared-prefix
# state, and the resulting component remains independently verifiable.
install_component("${relocated_prefix}")
verify_prefix("${relocated_prefix}" "same-version overlay")
foreach(sentinel IN ITEMS
    "lib/pure/unrelated-sentinel.bin"
    "share/unrelated-owner/sentinel.bin")
  file(SHA256 "${first_prefix}/${sentinel}" first_sha)
  file(SHA256 "${relocated_prefix}/${sentinel}" relocated_sha)
  if(sentinel MATCHES "^lib/")
    set(expected_sha "${library_sentinel_sha}")
  else()
    set(expected_sha "${documentation_sentinel_sha}")
  endif()
  if(NOT first_sha STREQUAL expected_sha OR
      NOT relocated_sha STREQUAL expected_sha)
    message(FATAL_ERROR "overlay changed unrelated sentinel: ${sentinel}")
  endif()
endforeach()

set(expected_owned_paths
  lib/pure/bonjour.dll
  lib/pure/bonjour.pure
  share/doc/pure-bonjour/COPYING
  share/doc/pure-bonjour/COPYING.LESSER
  share/doc/pure-bonjour/PureBonjourInventory.tsv
  share/doc/pure-bonjour/README
  share/doc/pure-bonjour/WINDOWS.md
  share/doc/pure-bonjour/examples/bonjour_examp.pure)
list(SORT expected_owned_paths)

function(validate_owned_path relative normalized_output)
  if(relative STREQUAL "" OR IS_ABSOLUTE "${relative}" OR
      relative MATCHES "^[A-Za-z]:" OR relative MATCHES "^[/\\\\]" OR
      relative MATCHES "(^|[/\\\\])\\.\\.([/\\\\]|$)" OR
      relative MATCHES "(^|[/\\\\])\\.([/\\\\]|$)" OR
      relative MATCHES "\\\\|:|[*?]")
    message(FATAL_ERROR "trusted oracle contains unsafe path: ${relative}")
  endif()
  cmake_path(NORMAL_PATH relative OUTPUT_VARIABLE normalized)
  string(TOLOWER "${normalized}" identity)
  set(${normalized_output} "${normalized}|${identity}" PARENT_SCOPE)
endfunction()

# This is intentionally an oracle-only remover.  It parses and validates the
# complete external authority before deleting anything and never reads the
# installed inventory for ownership decisions.
function(remove_component prefix)
  file(STRINGS "${oracle}" oracle_lines ENCODING UTF-8)
  set(paths)
  set(identities)
  foreach(line IN LISTS oracle_lines)
    string(LENGTH "${line}" line_length)
    if(line_length LESS 67)
      message(FATAL_ERROR "trusted oracle has malformed row: ${line}")
    endif()
    string(SUBSTRING "${line}" 0 64 sha)
    string(SUBSTRING "${line}" 64 2 separator)
    string(SUBSTRING "${line}" 66 -1 relative)
    string(LENGTH "${sha}" sha_length)
    if(NOT sha_length EQUAL 64 OR NOT sha MATCHES "^[0-9A-Fa-f]+$" OR
        NOT separator STREQUAL "  ")
      message(FATAL_ERROR "trusted oracle has malformed row: ${line}")
    endif()
    validate_owned_path("${relative}" validated)
    string(REPLACE "|" ";" validated_fields "${validated}")
    list(GET validated_fields 0 normalized)
    list(GET validated_fields 1 identity)
    if(identity IN_LIST identities)
      message(FATAL_ERROR "trusted oracle repeats owned path: ${relative}")
    endif()
    list(APPEND paths "${normalized}")
    list(APPEND identities "${identity}")
  endforeach()
  set(sorted_paths "${paths}")
  list(SORT sorted_paths)
  if(NOT sorted_paths STREQUAL expected_owned_paths)
    message(FATAL_ERROR
      "trusted oracle has unexpected ownership set: ${sorted_paths}")
  endif()

  foreach(relative IN LISTS paths)
    set(target "${prefix}/${relative}")
    if(EXISTS "${target}" OR IS_SYMLINK "${target}")
      file(REMOVE "${target}")
    endif()
  endforeach()
  foreach(directory IN ITEMS
      "${prefix}/share/doc/pure-bonjour/examples"
      "${prefix}/share/doc/pure-bonjour")
    if(IS_DIRECTORY "${directory}")
      file(GLOB remaining LIST_DIRECTORIES TRUE "${directory}/*")
      if(remaining)
        message(FATAL_ERROR
          "PureBonjour-specific directory is not empty after exact removal: "
          "${directory}: ${remaining}")
      endif()
      file(REMOVE_RECURSE "${directory}")
    endif()
  endforeach()
endfunction()

function(assert_removed_and_preserved prefix label)
  foreach(relative IN LISTS expected_owned_paths)
    if(EXISTS "${prefix}/${relative}" OR IS_SYMLINK "${prefix}/${relative}")
      message(FATAL_ERROR "${label} retained owned path: ${relative}")
    endif()
  endforeach()
  if(EXISTS "${prefix}/share/doc/pure-bonjour")
    message(FATAL_ERROR "${label} retained PureBonjour-specific directory")
  endif()
  foreach(sentinel IN ITEMS
      "lib/pure/unrelated-sentinel.bin"
      "share/unrelated-owner/sentinel.bin")
    if(NOT EXISTS "${prefix}/${sentinel}")
      message(FATAL_ERROR "${label} removed unrelated sentinel: ${sentinel}")
    endif()
    file(SHA256 "${prefix}/${sentinel}" actual_sha)
    if(sentinel MATCHES "^lib/")
      set(expected_sha "${library_sentinel_sha}")
    else()
      set(expected_sha "${documentation_sentinel_sha}")
    endif()
    if(NOT actual_sha STREQUAL expected_sha)
      message(FATAL_ERROR "${label} changed unrelated sentinel: ${sentinel}")
    endif()
  endforeach()
  if(NOT IS_DIRECTORY "${prefix}/share/keep-empty")
    message(FATAL_ERROR "${label} removed unrelated empty directory")
  endif()
endfunction()

remove_component("${relocated_prefix}")
assert_removed_and_preserved("${relocated_prefix}" "normal removal")

# A forged installed inventory naming an unrelated file must have no influence
# on deletion.  This is a fresh copy and the external oracle remains outside it.
set(forged_prefix "${test_root}/Forged Inventory Removal")
file(MAKE_DIRECTORY "${forged_prefix}")
file(COPY "${first_prefix}/" DESTINATION "${forged_prefix}")
file(APPEND "${forged_prefix}/${inventory_relative}"
  "lib/pure/unrelated-sentinel.bin\tforged\tforged\t0\t"
  "0000000000000000000000000000000000000000000000000000000000000000\t0\n")
remove_component("${forged_prefix}")
assert_removed_and_preserved("${forged_prefix}" "forged-inventory removal")
