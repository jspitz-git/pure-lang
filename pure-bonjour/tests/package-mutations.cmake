cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS
    CMAKE_COMMAND BUILD_DIR VERIFIER SOURCE_PREFIX PURE_PREFIX TEST_ROOT TEST_MODE)
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

set(valid_stage "${test_root}/valid-component")
execute_process(
  COMMAND "${CMAKE_COMMAND}" --install "${build_dir}"
    --prefix "${valid_stage}" --component PureBonjour
  RESULT_VARIABLE install_result
  OUTPUT_VARIABLE install_output
  ERROR_VARIABLE install_error
  ENCODING UTF-8)
if(NOT install_result EQUAL 0)
  message(FATAL_ERROR
    "PureBonjour install failed (${install_result})\n"
    "${install_output}${install_error}")
endif()

function(run_verifier stage oracle_directory expected_token case_name)
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DSTAGE_PREFIX=${stage}"
      "-DSOURCE_PREFIX=${source_prefix}"
      "-DBUILD_PREFIX=${oracle_directory}"
      "-DPURE_PREFIX=${pure_prefix}"
      -P "${VERIFIER}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8)
  set(log "${output}${error}")
  if(expected_token STREQUAL "")
    if(NOT result EQUAL 0)
      message(FATAL_ERROR
        "${case_name} valid package was rejected (${result})\n${log}")
    endif()
  else()
    if(result EQUAL 0)
      message(FATAL_ERROR "${case_name} mutation was accepted")
    endif()
    if(NOT log MATCHES "${expected_token}")
      message(FATAL_ERROR
        "${case_name} failed without ${expected_token}\n${log}")
    endif()
  endif()
endfunction()

run_verifier("${valid_stage}" "${build_dir}" "" "valid-stage")
if(TEST_MODE STREQUAL "valid")
  return()
elseif(NOT TEST_MODE STREQUAL "mutations")
  message(FATAL_ERROR "unknown TEST_MODE: ${TEST_MODE}")
endif()

function(fresh_case case_name output_stage output_build)
  set(case_stage "${test_root}/${case_name}/stage")
  set(case_build "${test_root}/${case_name}/oracle")
  file(MAKE_DIRECTORY "${case_stage}" "${case_build}")
  file(COPY "${valid_stage}/" DESTINATION "${case_stage}")
  file(COPY_FILE "${oracle}"
    "${case_build}/PureBonjourExpected.sha256" ONLY_IF_DIFFERENT)
  set(${output_stage} "${case_stage}" PARENT_SCOPE)
  set(${output_build} "${case_build}" PARENT_SCOPE)
endfunction()

function(write_lines path)
  set(lines "${ARGN}")
  string(JOIN "\n" content ${lines})
  file(WRITE "${path}" "${content}\n")
endfunction()

function(replace_inventory_path inventory row_index replacement)
  file(STRINGS "${inventory}" lines ENCODING UTF-8)
  list(GET lines ${row_index} row)
  string(REPLACE "\t" ";" fields "${row}")
  list(REMOVE_AT fields 0)
  list(PREPEND fields "${replacement}")
  string(JOIN "\t" replacement_row ${fields})
  list(REMOVE_AT lines ${row_index})
  list(INSERT lines ${row_index} "${replacement_row}")
  write_lines("${inventory}" ${lines})
endfunction()

function(replace_oracle_path oracle_path row_index replacement)
  file(STRINGS "${oracle_path}" lines ENCODING UTF-8)
  list(GET lines ${row_index} row)
  string(SUBSTRING "${row}" 0 64 sha)
  set(replacement_row "${sha}  ${replacement}")
  list(REMOVE_AT lines ${row_index})
  list(INSERT lines ${row_index} "${replacement_row}")
  write_lines("${oracle_path}" ${lines})
endfunction()

function(append_utf16 path value)
  set(script "${test_root}/append-utf16.ps1")
  if(NOT EXISTS "${script}")
    file(WRITE "${script}" [=[
param([string]$Path, [string]$Value)
$bytes = [Text.Encoding]::Unicode.GetBytes($Value)
$stream = [IO.File]::Open($Path, [IO.FileMode]::Append,
  [IO.FileAccess]::Write, [IO.FileShare]::Read)
try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
]=])
  endif()
  set(powershell
    "$ENV{SystemRoot}/System32/WindowsPowerShell/v1.0/powershell.exe")
  execute_process(
    COMMAND "${powershell}" -NoLogo -NoProfile -NonInteractive
      -File "${script}" -Path "${path}" -Value "${value}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8)
  if(NOT result EQUAL 0)
    message(FATAL_ERROR "UTF-16LE fixture creation failed: ${output}${error}")
  endif()
endfunction()

# Each case starts from a fresh copy.  A production verifier with a missing
# branch for the named behavior makes the corresponding assertion fail.
fresh_case(changed-module stage case_build)
file(APPEND "${stage}/lib/pure/bonjour.dll" "changed")
run_verifier("${stage}" "${case_build}" PACKAGE_HASH "changed-module")

fresh_case(deleted-license stage case_build)
file(REMOVE "${stage}/share/doc/pure-bonjour/COPYING.LESSER")
run_verifier("${stage}" "${case_build}" PACKAGE_SET "deleted-license")

fresh_case(undeclared-file stage case_build)
file(WRITE "${stage}/share/doc/pure-bonjour/undeclared.txt" "not owned\n")
run_verifier("${stage}" "${case_build}" PACKAGE_SET "undeclared-file")

fresh_case(forged-inventory-hash stage case_build)
set(inventory "${stage}/${inventory_relative}")
file(STRINGS "${inventory}" lines ENCODING UTF-8)
list(GET lines 1 row)
string(REPLACE "\t" ";" fields "${row}")
list(REMOVE_AT fields 4)
list(INSERT fields 4
  "0000000000000000000000000000000000000000000000000000000000000000")
string(JOIN "\t" forged_row ${fields})
list(REMOVE_AT lines 1)
list(INSERT lines 1 "${forged_row}")
write_lines("${inventory}" ${lines})
run_verifier("${stage}" "${case_build}" PACKAGE_HASH "forged-inventory-hash")

fresh_case(duplicate-inventory-path stage case_build)
set(inventory "${stage}/${inventory_relative}")
file(STRINGS "${inventory}" lines ENCODING UTF-8)
list(GET lines 1 duplicate_row)
list(APPEND lines "${duplicate_row}")
write_lines("${inventory}" ${lines})
run_verifier("${stage}" "${case_build}" PACKAGE_INVENTORY
  "duplicate-inventory-path")

fresh_case(case-colliding-inventory-path stage case_build)
set(inventory "${stage}/${inventory_relative}")
file(STRINGS "${inventory}" lines ENCODING UTF-8)
list(GET lines 1 collision_row)
string(REPLACE "lib/pure/bonjour.dll" "LIB/PURE/BONJOUR.DLL"
  collision_row "${collision_row}")
list(APPEND lines "${collision_row}")
write_lines("${inventory}" ${lines})
run_verifier("${stage}" "${case_build}" PACKAGE_INVENTORY
  "case-colliding-inventory-path")

fresh_case(absolute-inventory-path stage case_build)
replace_inventory_path("${stage}/${inventory_relative}" 1
  "C:/outside/bonjour.dll")
run_verifier("${stage}" "${case_build}" PACKAGE_INVENTORY
  "absolute-inventory-path")

fresh_case(parent-inventory-path stage case_build)
replace_inventory_path("${stage}/${inventory_relative}" 1
  "lib/pure/../../outside.dll")
run_verifier("${stage}" "${case_build}" PACKAGE_INVENTORY
  "parent-inventory-path")

fresh_case(malformed-inventory-row stage case_build)
set(inventory "${stage}/${inventory_relative}")
file(APPEND "${inventory}" "malformed-row\n")
run_verifier("${stage}" "${case_build}" PACKAGE_INVENTORY
  "malformed-inventory-row")

foreach(prefix_name IN ITEMS source build stage)
  fresh_case("ascii-prefix-${prefix_name}" stage case_build)
  if(prefix_name STREQUAL "source")
    set(leaked_prefix "${source_prefix}")
  elseif(prefix_name STREQUAL "build")
    set(leaked_prefix "${case_build}")
  else()
    set(leaked_prefix "${stage}")
  endif()
  string(REPLACE "/" "\\" leaked_prefix "${leaked_prefix}")
  string(TOUPPER "${leaked_prefix}" leaked_prefix)
  file(APPEND "${stage}/lib/pure/bonjour.pure" "\n${leaked_prefix}\n")
  run_verifier("${stage}" "${case_build}" PACKAGE_PREFIX
    "ascii-prefix-${prefix_name}")
endforeach()

fresh_case(mixed-case-prefix stage case_build)
string(REPLACE "pure-lang" "PuRe-LaNg" leaked_prefix "${source_prefix}")
string(REPLACE "pure-bonjour" "PuRe-BoNjOuR"
  leaked_prefix "${leaked_prefix}")
file(APPEND "${stage}/lib/pure/bonjour.pure" "\n${leaked_prefix}\n")
run_verifier("${stage}" "${case_build}" PACKAGE_PREFIX "mixed-case-prefix")

foreach(prefix_name IN ITEMS source build stage)
  fresh_case("utf16-prefix-${prefix_name}" stage case_build)
  if(prefix_name STREQUAL "source")
    set(leaked_prefix "${source_prefix}")
  elseif(prefix_name STREQUAL "build")
    set(leaked_prefix "${case_build}")
  else()
    set(leaked_prefix "${stage}")
  endif()
  string(TOLOWER "${leaked_prefix}" leaked_prefix)
  append_utf16("${stage}/lib/pure/bonjour.pure" "${leaked_prefix}")
  run_verifier("${stage}" "${case_build}" PACKAGE_PREFIX
    "utf16-prefix-${prefix_name}")
endforeach()

# The external oracle is parsed and normalized independently of the installed
# inventory, so malformed authority never reaches path or hash operations.
fresh_case(duplicate-oracle-path stage case_build)
set(case_oracle "${case_build}/PureBonjourExpected.sha256")
file(STRINGS "${case_oracle}" lines ENCODING UTF-8)
list(GET lines 0 duplicate_row)
list(APPEND lines "${duplicate_row}")
write_lines("${case_oracle}" ${lines})
run_verifier("${stage}" "${case_build}" PACKAGE_INVENTORY
  "duplicate-oracle-path")

fresh_case(case-colliding-oracle-path stage case_build)
set(case_oracle "${case_build}/PureBonjourExpected.sha256")
file(STRINGS "${case_oracle}" lines ENCODING UTF-8)
list(GET lines 0 collision_row)
string(REPLACE "lib/pure/bonjour.dll" "LIB/PURE/BONJOUR.DLL"
  collision_row "${collision_row}")
list(APPEND lines "${collision_row}")
write_lines("${case_oracle}" ${lines})
run_verifier("${stage}" "${case_build}" PACKAGE_INVENTORY
  "case-colliding-oracle-path")

fresh_case(absolute-oracle-path stage case_build)
replace_oracle_path("${case_build}/PureBonjourExpected.sha256" 0
  "C:/outside/bonjour.dll")
run_verifier("${stage}" "${case_build}" PACKAGE_INVENTORY
  "absolute-oracle-path")

fresh_case(parent-oracle-path stage case_build)
replace_oracle_path("${case_build}/PureBonjourExpected.sha256" 0
  "lib/pure/../../outside.dll")
run_verifier("${stage}" "${case_build}" PACKAGE_INVENTORY
  "parent-oracle-path")

fresh_case(malformed-oracle-row stage case_build)
file(APPEND "${case_build}/PureBonjourExpected.sha256" "malformed-row\n")
run_verifier("${stage}" "${case_build}" PACKAGE_INVENTORY
  "malformed-oracle-row")

# A directory junction is a reparse point.  It is removed explicitly before
# CMake recursively removes the surrounding fixture tree.
fresh_case(reparse-point stage case_build)
set(junction "${stage}/share/doc/pure-bonjour/reparse")
set(junction_target "${test_root}/reparse-target")
file(MAKE_DIRECTORY "${junction_target}")
file(WRITE "${junction_target}/outside.txt" "outside fixture\n")
cmake_path(NATIVE_PATH junction NORMALIZE junction_native)
cmake_path(NATIVE_PATH junction_target NORMALIZE target_native)
execute_process(
  COMMAND "$ENV{COMSPEC}" /d /c mklink /J
    "${junction_native}" "${target_native}"
  RESULT_VARIABLE junction_result
  OUTPUT_VARIABLE junction_output
  ERROR_VARIABLE junction_error
  ENCODING UTF-8)
if(NOT junction_result EQUAL 0)
  message(FATAL_ERROR
    "could not create reparse fixture (${junction_result})\n"
    "${junction_output}${junction_error}")
endif()
execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DSTAGE_PREFIX=${stage}"
    "-DSOURCE_PREFIX=${source_prefix}"
    "-DBUILD_PREFIX=${case_build}"
    "-DPURE_PREFIX=${pure_prefix}"
    -P "${VERIFIER}"
  RESULT_VARIABLE reparse_result
  OUTPUT_VARIABLE reparse_output
  ERROR_VARIABLE reparse_error
  ENCODING UTF-8)
execute_process(
  COMMAND "$ENV{COMSPEC}" /d /c rmdir "${junction_native}"
  RESULT_VARIABLE remove_junction_result
  OUTPUT_VARIABLE remove_junction_output
  ERROR_VARIABLE remove_junction_error
  ENCODING UTF-8)
if(NOT remove_junction_result EQUAL 0)
  message(FATAL_ERROR
    "could not remove reparse fixture (${remove_junction_result})\n"
    "${remove_junction_output}${remove_junction_error}")
endif()
if(reparse_result EQUAL 0 OR NOT
    "${reparse_output}${reparse_error}" MATCHES "PACKAGE_SET")
  message(FATAL_ERROR
    "reparse point was not rejected with PACKAGE_SET\n"
    "${reparse_output}${reparse_error}")
endif()
