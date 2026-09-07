cmake_minimum_required(VERSION 3.25)

set(required_directories STAGE_PREFIX WINDOWS_DIRECTORY)
set(required_files
  BASELINE_MANIFEST RUNTIME_COMPONENT_MANIFEST DOCUMENTATION_COMPONENT_MANIFEST
  LLVM_READOBJ ODBC_MODULE_SOURCE ODBC_INTERFACE_SOURCE README_SOURCE
  COPYING_SOURCE COPYING_LESSER_SOURCE WINDOWS_SOURCE EXAMPLE_SOURCE
  SMOKE_SOURCE PEOPLE_SOURCE SCHEMA_SOURCE GMP_DLL_SOURCE
  PURE_RUNTIME_DLL_SOURCE RUN_PURE_TEST_EXECUTABLE
  WINDOWS_DEPENDENCY_VERIFIER SYSTEM_ODBC_DLL)
foreach(required IN LISTS required_directories required_files)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
  cmake_path(ABSOLUTE_PATH ${required} NORMALIZE OUTPUT_VARIABLE normalized)
  set(${required} "${normalized}")
endforeach()
foreach(required IN LISTS required_directories)
  if(NOT IS_DIRECTORY "${${required}}")
    message(FATAL_ERROR
      "${required} must be an existing directory: ${${required}}")
  endif()
endforeach()
foreach(required IN LISTS required_files)
  if(NOT EXISTS "${${required}}" OR IS_DIRECTORY "${${required}}" OR
      IS_SYMLINK "${${required}}")
    message(FATAL_ERROR
      "${required} must be an existing regular file: ${${required}}")
  endif()
endforeach()

set(PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY "${WINDOWS_DIRECTORY}")
include("${CMAKE_CURRENT_LIST_DIR}/../tests/ContractTestRoot.cmake")
_pure_odbc_require_no_reparse("${STAGE_PREFIX}" "STAGE_PREFIX" TRUE)
_pure_odbc_require_no_reparse("${WINDOWS_DIRECTORY}" "WINDOWS_DIRECTORY" FALSE)
foreach(required IN LISTS required_files)
  _pure_odbc_require_no_reparse("${${required}}" "${required}" FALSE)
endforeach()

file(REAL_PATH "${STAGE_PREFIX}" STAGE_PREFIX)
file(REAL_PATH "${WINDOWS_DIRECTORY}" WINDOWS_DIRECTORY)
foreach(required IN LISTS required_files)
  file(REAL_PATH "${${required}}" canonical)
  set(${required} "${canonical}")
endforeach()

set(expected_runtime_files
  lib/pure/odbc.dll
  lib/pure/odbc.pure)
set(expected_documentation_files
  share/doc/pure-odbc/README
  share/doc/pure-odbc/COPYING
  share/doc/pure-odbc/COPYING.LESSER
  share/doc/pure-odbc/WINDOWS.md
  share/doc/pure-odbc/examples/menagerie.pure
  share/doc/pure-odbc/tests/smoke.pure
  share/doc/pure-odbc/tests/data/people.csv
  share/doc/pure-odbc/tests/data/Schema.ini)
set(expected_owned_files
  ${expected_runtime_files} ${expected_documentation_files})
set(owned_sources
  "${ODBC_MODULE_SOURCE}"
  "${ODBC_INTERFACE_SOURCE}"
  "${README_SOURCE}"
  "${COPYING_SOURCE}"
  "${COPYING_LESSER_SOURCE}"
  "${WINDOWS_SOURCE}"
  "${EXAMPLE_SOURCE}"
  "${SMOKE_SOURCE}"
  "${PEOPLE_SOURCE}"
  "${SCHEMA_SOURCE}")

function(compare_exact_manifest label expected_var actual_var)
  set(expected "${${expected_var}}")
  set(actual "${${actual_var}}")
  list(SORT expected)
  list(SORT actual)
  if(NOT actual STREQUAL expected)
    set(missing "${expected}")
    foreach(relative IN LISTS actual)
      list(REMOVE_ITEM missing "${relative}")
    endforeach()
    set(unexpected "${actual}")
    foreach(relative IN LISTS expected)
      list(REMOVE_ITEM unexpected "${relative}")
    endforeach()
    message(FATAL_ERROR
      "${label} mismatch\nexpected: ${expected}\nactual: ${actual}\n"
      "missing: ${missing}\nunexpected: ${unexpected}")
  endif()
endfunction()

function(read_component_manifest label manifest output)
  file(STRINGS "${manifest}" entries ENCODING UTF-8)
  set(relative_entries)
  set(folded_entries)
  foreach(entry IN LISTS entries)
    if(entry STREQUAL "")
      message(FATAL_ERROR "${label} contains an empty record: ${manifest}")
    endif()
    cmake_path(CONVERT "${entry}" TO_CMAKE_PATH_LIST entry NORMALIZE)
    cmake_path(ABSOLUTE_PATH entry NORMALIZE OUTPUT_VARIABLE absolute)
    cmake_path(RELATIVE_PATH absolute BASE_DIRECTORY "${STAGE_PREFIX}"
      OUTPUT_VARIABLE relative)
    cmake_path(CONVERT "${relative}" TO_CMAKE_PATH_LIST relative NORMALIZE)
    if(IS_ABSOLUTE "${relative}" OR relative MATCHES "(^|/)\\.\\.(/|$)")
      message(FATAL_ERROR
        "${label} contains a path outside STAGE_PREFIX: ${entry}")
    endif()
    string(TOLOWER "${relative}" folded)
    list(FIND folded_entries "${folded}" duplicate_index)
    if(NOT duplicate_index EQUAL -1)
      message(FATAL_ERROR "${label} contains duplicate path: ${relative}")
    endif()
    list(APPEND folded_entries "${folded}")
    list(APPEND relative_entries "${relative}")
  endforeach()
  set(${output} "${relative_entries}" PARENT_SCOPE)
endfunction()

function(read_baseline_manifest manifest paths_output hashes_output)
  file(STRINGS "${manifest}" records ENCODING UTF-8)
  set(paths)
  set(hashes)
  set(folded_paths)
  foreach(record IN LISTS records)
    string(FIND "${record}" "|" separator)
    if(separator LESS 1)
      message(FATAL_ERROR "Malformed baseline manifest record: ${record}")
    endif()
    string(SUBSTRING "${record}" 0 ${separator} hash)
    math(EXPR path_start "${separator} + 1")
    string(SUBSTRING "${record}" ${path_start} -1 relative)
    string(LENGTH "${hash}" hash_length)
    string(TOLOWER "${hash}" hash)
    if(NOT hash_length EQUAL 64 OR NOT hash MATCHES "^[0-9a-f]+$")
      message(FATAL_ERROR "Malformed baseline hash for ${relative}: ${hash}")
    endif()
    cmake_path(CONVERT "${relative}" TO_CMAKE_PATH_LIST relative NORMALIZE)
    if(relative STREQUAL "" OR IS_ABSOLUTE "${relative}" OR
        relative MATCHES "(^|/)\\.\\.(/|$)" OR relative MATCHES "\\|")
      message(FATAL_ERROR "Unsafe baseline manifest path: ${relative}")
    endif()
    string(TOLOWER "${relative}" folded)
    list(FIND folded_paths "${folded}" duplicate_index)
    if(NOT duplicate_index EQUAL -1)
      message(FATAL_ERROR "Duplicate baseline manifest path: ${relative}")
    endif()
    list(APPEND folded_paths "${folded}")
    list(APPEND paths "${relative}")
    list(APPEND hashes "${hash}")
  endforeach()
  set(${paths_output} "${paths}" PARENT_SCOPE)
  set(${hashes_output} "${hashes}" PARENT_SCOPE)
endfunction()

function(snapshot_prefix root paths_output hashes_output)
  file(GLOB_RECURSE entries LIST_DIRECTORIES FALSE RELATIVE "${root}"
    "${root}/*")
  list(SORT entries)
  set(paths)
  set(hashes)
  foreach(relative IN LISTS entries)
    cmake_path(CONVERT "${relative}" TO_CMAKE_PATH_LIST relative NORMALIZE)
    if(IS_SYMLINK "${root}/${relative}")
      message(FATAL_ERROR "Installed prefix contains a symlink: ${relative}")
    endif()
    file(SHA256 "${root}/${relative}" hash)
    string(TOLOWER "${hash}" hash)
    list(APPEND paths "${relative}")
    list(APPEND hashes "${hash}")
  endforeach()
  set(${paths_output} "${paths}" PARENT_SCOPE)
  set(${hashes_output} "${hashes}" PARENT_SCOPE)
endfunction()

function(classify_forbidden basename manager_output driver_output)
  string(TOLOWER "${basename}" basename)
  if(basename MATCHES
      "^(odbc32|libodbc|libodbc32|libiodbc|unixodbc)([-_.0-9]*)\\.dll$")
    set(manager TRUE)
  else()
    set(manager FALSE)
  endif()
  if(basename MATCHES
      "^(msodbcsql[0-9]*|sqlncli[0-9]*|myodbc.*|psqlodbc.*|sqlite3?odbc.*|odbcjt32|aceodbc)\\.dll$")
    set(driver TRUE)
  else()
    set(driver FALSE)
  endif()
  set(${manager_output} "${manager}" PARENT_SCOPE)
  set(${driver_output} "${driver}" PARENT_SCOPE)
endfunction()

file(GLOB_RECURSE installed_files LIST_DIRECTORIES FALSE
  RELATIVE "${STAGE_PREFIX}" "${STAGE_PREFIX}/*")
foreach(relative IN LISTS installed_files)
  cmake_path(CONVERT "${relative}" TO_CMAKE_PATH_LIST relative NORMALIZE)
  string(TOLOWER "${relative}" lower_relative)
  if(lower_relative STREQUAL "lib/pure/odbc.dll")
    continue()
  endif()
  cmake_path(GET relative FILENAME basename)
  classify_forbidden("${basename}" is_manager is_driver)
  if(is_manager)
    message(FATAL_ERROR "Found bundled ODBC manager: ${relative}")
  endif()
  if(is_driver)
    message(FATAL_ERROR "Found bundled ODBC driver: ${relative}")
  endif()
endforeach()

foreach(reused IN ITEMS
    "GMP|${GMP_DLL_SOURCE}|${STAGE_PREFIX}/bin/libgmp-10.dll"
    "Pure runtime|${PURE_RUNTIME_DLL_SOURCE}|${STAGE_PREFIX}/bin/libpure.dll")
  string(REPLACE "|" ";" fields "${reused}")
  list(GET fields 0 label)
  list(GET fields 1 source)
  list(GET fields 2 installed)
  if(NOT EXISTS "${installed}" OR IS_DIRECTORY "${installed}")
    message(FATAL_ERROR "Missing staged ${label}: ${installed}")
  endif()
  file(SHA256 "${source}" source_hash)
  file(SHA256 "${installed}" installed_hash)
  if(NOT installed_hash STREQUAL source_hash)
    message(FATAL_ERROR
      "${label} hash mismatch\nsource: ${source_hash}\n"
      "installed: ${installed_hash}")
  endif()
endforeach()

read_component_manifest("runtime component manifest"
  "${RUNTIME_COMPONENT_MANIFEST}" actual_runtime_files)
compare_exact_manifest("runtime component manifest"
  expected_runtime_files actual_runtime_files)
read_component_manifest("documentation component manifest"
  "${DOCUMENTATION_COMPONENT_MANIFEST}" actual_documentation_files)
compare_exact_manifest("documentation component manifest"
  expected_documentation_files actual_documentation_files)

read_baseline_manifest("${BASELINE_MANIFEST}" baseline_paths baseline_hashes)
snapshot_prefix("${STAGE_PREFIX}" installed_paths installed_hashes)

set(actual_delta "${installed_paths}")
foreach(relative IN LISTS baseline_paths)
  list(REMOVE_ITEM actual_delta "${relative}")
endforeach()
compare_exact_manifest("Installed prefix delta"
  expected_owned_files actual_delta)

foreach(relative IN LISTS baseline_paths)
  list(FIND installed_paths "${relative}" installed_index)
  if(installed_index EQUAL -1)
    message(FATAL_ERROR "Install removed pre-existing file: ${relative}")
  endif()
  list(FIND baseline_paths "${relative}" baseline_index)
  list(GET baseline_hashes ${baseline_index} expected_hash)
  list(GET installed_hashes ${installed_index} actual_hash)
  if(NOT actual_hash STREQUAL expected_hash)
    message(FATAL_ERROR "Install changed pre-existing file: ${relative}")
  endif()
endforeach()

list(LENGTH expected_owned_files expected_count)
list(LENGTH owned_sources source_count)
if(NOT expected_count EQUAL 10 OR NOT source_count EQUAL expected_count)
  message(FATAL_ERROR
    "Internal pure-odbc manifest error: ${expected_count} paths and "
    "${source_count} sources")
endif()
math(EXPR last_owned_index "${expected_count} - 1")
foreach(index RANGE ${last_owned_index})
  list(GET expected_owned_files ${index} relative)
  list(GET owned_sources ${index} source)
  set(installed "${STAGE_PREFIX}/${relative}")
  if(NOT EXISTS "${installed}" OR IS_DIRECTORY "${installed}" OR
      IS_SYMLINK "${installed}")
    message(FATAL_ERROR "Missing installed pure-odbc file: ${relative}")
  endif()
  file(SHA256 "${source}" source_hash)
  file(SHA256 "${installed}" installed_hash)
  if(NOT installed_hash STREQUAL source_hash)
    message(FATAL_ERROR
      "Installed pure-odbc hash mismatch for ${relative}\n"
      "source: ${source_hash}\ninstalled: ${installed_hash}")
  endif()
endforeach()

set(module_dir "${STAGE_PREFIX}/lib/pure")
set(installed_smoke
  "${STAGE_PREFIX}/share/doc/pure-odbc/tests/smoke.pure")
execute_process(
  COMMAND "${RUN_PURE_TEST_EXECUTABLE}"
    "${STAGE_PREFIX}/bin/pure.exe"
    "${module_dir}"
    "${module_dir}"
    "${installed_smoke}"
    "${WINDOWS_DIRECTORY}"
  RESULT_VARIABLE smoke_result
  OUTPUT_VARIABLE smoke_output
  ERROR_VARIABLE smoke_error
  ENCODING UTF-8
)
if(NOT smoke_result EQUAL 0 OR NOT smoke_error STREQUAL "")
  message(FATAL_ERROR
    "Installed pure-odbc strict smoke test failed (${smoke_result})\n"
    "stdout:\n${smoke_output}\nstderr:\n${smoke_error}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    "-DSTAGE_PREFIX=${STAGE_PREFIX}"
    "-DODBC_MODULE=${module_dir}/odbc.dll"
    "-DGMP_DLL=${STAGE_PREFIX}/bin/libgmp-10.dll"
    "-DPURE_RUNTIME_DLL=${STAGE_PREFIX}/bin/libpure.dll"
    "-DPURE_EXECUTABLE=${STAGE_PREFIX}/bin/pure.exe"
    "-DWINDOWS_DIRECTORY=${WINDOWS_DIRECTORY}"
    "-DSYSTEM_ODBC_DLL=${SYSTEM_ODBC_DLL}"
    "-DPURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY=${WINDOWS_DIRECTORY}"
    -P "${WINDOWS_DEPENDENCY_VERIFIER}"
  RESULT_VARIABLE audit_result
  OUTPUT_VARIABLE audit_output
  ERROR_VARIABLE audit_error
  ENCODING UTF-8
)
if(NOT audit_result EQUAL 0)
  message(FATAL_ERROR
    "Installed pure-odbc PE audit failed (${audit_result})\n"
    "stdout:\n${audit_output}\nstderr:\n${audit_error}")
endif()

message(STATUS
  "Verified installed pure-odbc: exact 10-file component delta and hashes, "
  "unchanged full-prefix baseline, byte-identical GMP/Pure runtime, no ODBC "
  "manager or driver, strict manager/IM002 smoke, and exact staged PE closure")
