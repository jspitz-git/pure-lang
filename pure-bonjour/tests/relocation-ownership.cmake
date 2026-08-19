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
set(remover "${source_prefix}/cmake/RemovePureBonjourPackage.cmake")

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

function(run_remover prefix authority expected_token label)
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DPREFIX=${prefix}"
      "-DBUILD_PREFIX=${authority}"
      -P "${remover}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8)
  set(log "${output}${error}")
  if(expected_token STREQUAL "")
    if(NOT result EQUAL 0)
      message(FATAL_ERROR "${label} removal failed (${result})\n${log}")
    endif()
  else()
    if(result EQUAL 0 OR NOT log MATCHES "${expected_token}")
      message(FATAL_ERROR
        "${label} was not rejected with ${expected_token}\n${log}")
    endif()
  endif()
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

# Removal-time parent replacement must be caught in a full preflight before any
# owned file is deleted.
set(removal_base "${test_root}/Removal Mutation Base")
install_component("${removal_base}")
file(MAKE_DIRECTORY "${removal_base}/share/unrelated-owner")
file(WRITE "${removal_base}/share/unrelated-owner/sentinel.bin"
  "removal sentinel\n")

set(lib_junction_prefix "${test_root}/Removal Lib Junction")
file(MAKE_DIRECTORY "${lib_junction_prefix}")
file(COPY "${removal_base}/" DESTINATION "${lib_junction_prefix}")
file(RENAME "${lib_junction_prefix}/lib/pure"
  "${lib_junction_prefix}/lib/pure-owned")
set(lib_junction_target "${test_root}/Unrelated Lib Target")
file(MAKE_DIRECTORY "${lib_junction_target}")
file(WRITE "${lib_junction_target}/bonjour.dll" "unrelated dll sentinel\n")
file(WRITE "${lib_junction_target}/bonjour.pure" "unrelated pure sentinel\n")
file(SHA256 "${lib_junction_target}/bonjour.dll" lib_target_sha)
file(SHA256 "${lib_junction_prefix}/share/doc/pure-bonjour/README"
  lib_prefix_owned_sha)
cmake_path(NATIVE_PATH lib_junction_target NORMALIZE lib_target_native)
set(lib_junction "${lib_junction_prefix}/lib/pure")
cmake_path(NATIVE_PATH lib_junction NORMALIZE lib_junction_native)
execute_process(COMMAND "$ENV{COMSPEC}" /d /c mklink /J
  "${lib_junction_native}" "${lib_target_native}"
  RESULT_VARIABLE lib_junction_result)
if(NOT lib_junction_result EQUAL 0)
  message(FATAL_ERROR "could not create removal lib junction")
endif()
run_remover("${lib_junction_prefix}" "${build_dir}" PACKAGE_PATH
  "lib/pure removal-time junction")
file(SHA256 "${lib_junction_target}/bonjour.dll" lib_target_actual_sha)
file(SHA256 "${lib_junction_prefix}/share/doc/pure-bonjour/README"
  lib_prefix_owned_actual_sha)
execute_process(COMMAND "$ENV{COMSPEC}" /d /c rmdir
  "${lib_junction_native}" RESULT_VARIABLE lib_unlink_result)
if(NOT lib_unlink_result EQUAL 0 OR
    NOT lib_target_actual_sha STREQUAL lib_target_sha OR
    NOT lib_prefix_owned_actual_sha STREQUAL lib_prefix_owned_sha)
  message(FATAL_ERROR "lib/pure junction mutation changed protected files")
endif()

set(doc_junction_prefix "${test_root}/Removal Doc Junction")
file(MAKE_DIRECTORY "${doc_junction_prefix}")
file(COPY "${removal_base}/" DESTINATION "${doc_junction_prefix}")
file(RENAME "${doc_junction_prefix}/share/doc/pure-bonjour"
  "${doc_junction_prefix}/share/doc/pure-bonjour-owned")
set(doc_junction_target "${test_root}/Unrelated Doc Target")
file(MAKE_DIRECTORY "${doc_junction_target}")
file(COPY
  "${doc_junction_prefix}/share/doc/pure-bonjour-owned/"
  DESTINATION "${doc_junction_target}")
file(SHA256 "${doc_junction_target}/COPYING" doc_target_sha)
file(SHA256 "${doc_junction_prefix}/lib/pure/bonjour.dll"
  doc_prefix_owned_sha)
set(doc_junction "${doc_junction_prefix}/share/doc/pure-bonjour")
cmake_path(NATIVE_PATH doc_junction NORMALIZE doc_junction_native)
cmake_path(NATIVE_PATH doc_junction_target NORMALIZE doc_target_native)
execute_process(COMMAND "$ENV{COMSPEC}" /d /c mklink /J
  "${doc_junction_native}" "${doc_target_native}"
  RESULT_VARIABLE doc_junction_result)
if(NOT doc_junction_result EQUAL 0)
  message(FATAL_ERROR "could not create removal doc junction")
endif()
run_remover("${doc_junction_prefix}" "${build_dir}" PACKAGE_PATH
  "documentation removal-time junction")
file(SHA256 "${doc_junction_target}/COPYING" doc_target_actual_sha)
file(SHA256 "${doc_junction_prefix}/lib/pure/bonjour.dll"
  doc_prefix_owned_actual_sha)
execute_process(COMMAND "$ENV{COMSPEC}" /d /c rmdir
  "${doc_junction_native}" RESULT_VARIABLE doc_unlink_result)
if(NOT doc_unlink_result EQUAL 0 OR
    NOT doc_target_actual_sha STREQUAL doc_target_sha OR
    NOT doc_prefix_owned_actual_sha STREQUAL doc_prefix_owned_sha)
  message(FATAL_ERROR
    "documentation junction mutation changed protected files")
endif()

set(noncanonical_prefix "${test_root}/Removal Noncanonical Oracle")
install_component("${noncanonical_prefix}")
set(noncanonical_authority "${test_root}/Noncanonical Authority")
file(MAKE_DIRECTORY "${noncanonical_authority}")
file(STRINGS "${oracle}" oracle_lines ENCODING UTF-8)
list(GET oracle_lines 0 oracle_row)
string(REPLACE "lib/pure/bonjour.dll" "lib/pure//bonjour.dll"
  oracle_row "${oracle_row}")
list(REMOVE_AT oracle_lines 0)
list(INSERT oracle_lines 0 "${oracle_row}")
string(JOIN "\n" oracle_text ${oracle_lines})
file(WRITE "${noncanonical_authority}/PureBonjourExpected.sha256"
  "${oracle_text}\n")
file(SHA256 "${noncanonical_prefix}/lib/pure/bonjour.dll"
  noncanonical_owned_sha)
run_remover("${noncanonical_prefix}" "${noncanonical_authority}"
  PACKAGE_INVENTORY "noncanonical removal oracle")
file(SHA256 "${noncanonical_prefix}/lib/pure/bonjour.dll"
  noncanonical_owned_actual_sha)
if(NOT noncanonical_owned_actual_sha STREQUAL noncanonical_owned_sha)
  message(FATAL_ERROR "noncanonical oracle removed an owned file")
endif()

set(inside_oracle_prefix "${test_root}/Removal Inside Oracle")
install_component("${inside_oracle_prefix}")
file(MAKE_DIRECTORY "${inside_oracle_prefix}/authority")
file(COPY_FILE "${oracle}"
  "${inside_oracle_prefix}/authority/PureBonjourExpected.sha256")
file(SHA256 "${inside_oracle_prefix}/lib/pure/bonjour.dll"
  inside_owned_sha)
run_remover("${inside_oracle_prefix}"
  "${inside_oracle_prefix}/authority" PACKAGE_INVENTORY
  "inside-prefix removal oracle")
file(SHA256 "${inside_oracle_prefix}/lib/pure/bonjour.dll"
  inside_owned_actual_sha)
if(NOT inside_owned_actual_sha STREQUAL inside_owned_sha)
  message(FATAL_ERROR "inside-prefix oracle removed an owned file")
endif()

set(reparse_oracle_prefix "${test_root}/Removal Reparse Oracle")
install_component("${reparse_oracle_prefix}")
set(reparse_authority_target "${test_root}/Reparse Authority Target")
set(reparse_authority_link "${test_root}/Reparse Authority Link")
file(MAKE_DIRECTORY "${reparse_authority_target}")
file(COPY_FILE "${oracle}"
  "${reparse_authority_target}/PureBonjourExpected.sha256")
file(WRITE "${reparse_authority_target}/sentinel.bin" "authority sentinel\n")
file(SHA256 "${reparse_authority_target}/sentinel.bin" authority_sentinel_sha)
cmake_path(NATIVE_PATH reparse_authority_target NORMALIZE
  reparse_authority_target_native)
cmake_path(NATIVE_PATH reparse_authority_link NORMALIZE
  reparse_authority_link_native)
execute_process(COMMAND "$ENV{COMSPEC}" /d /c mklink /J
  "${reparse_authority_link_native}" "${reparse_authority_target_native}"
  RESULT_VARIABLE authority_junction_result)
if(NOT authority_junction_result EQUAL 0)
  message(FATAL_ERROR "could not create authority junction")
endif()
file(SHA256 "${reparse_oracle_prefix}/lib/pure/bonjour.dll"
  reparse_owned_sha)
run_remover("${reparse_oracle_prefix}" "${reparse_authority_link}"
  PACKAGE_INVENTORY "reparse removal oracle")
file(SHA256 "${reparse_oracle_prefix}/lib/pure/bonjour.dll"
  reparse_owned_actual_sha)
file(SHA256 "${reparse_authority_target}/sentinel.bin"
  authority_sentinel_actual_sha)
execute_process(COMMAND "$ENV{COMSPEC}" /d /c rmdir
  "${reparse_authority_link_native}" RESULT_VARIABLE authority_unlink_result)
if(NOT authority_unlink_result EQUAL 0 OR
    NOT reparse_owned_actual_sha STREQUAL reparse_owned_sha OR
    NOT authority_sentinel_actual_sha STREQUAL authority_sentinel_sha)
  message(FATAL_ERROR "reparse authority mutation changed protected files")
endif()

run_remover("${relocated_prefix}" "${build_dir}" "" "normal")
assert_removed_and_preserved("${relocated_prefix}" "normal removal")

# A forged installed inventory naming an unrelated file must have no influence
# on deletion.  This is a fresh copy and the external oracle remains outside it.
set(forged_prefix "${test_root}/Forged Inventory Removal")
file(MAKE_DIRECTORY "${forged_prefix}")
file(COPY "${first_prefix}/" DESTINATION "${forged_prefix}")
file(APPEND "${forged_prefix}/${inventory_relative}"
  "lib/pure/unrelated-sentinel.bin\tforged\tforged\t0\t"
  "0000000000000000000000000000000000000000000000000000000000000000\t0\n")
run_remover("${forged_prefix}" "${build_dir}" "" "forged-inventory")
assert_removed_and_preserved("${forged_prefix}" "forged-inventory removal")
