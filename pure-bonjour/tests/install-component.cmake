cmake_minimum_required(VERSION 3.25)

if(NOT DEFINED TEST_MODE OR TEST_MODE STREQUAL "")
  set(TEST_MODE install)
endif()

function(require_value variable)
  if(NOT DEFINED ${variable} OR "${${variable}}" STREQUAL "")
    message(FATAL_ERROR "${variable} is required")
  endif()
endfunction()

if(TEST_MODE STREQUAL "destinations")
  foreach(required IN ITEMS CMAKE_COMMAND INSTALL_MODULE)
    require_value(${required})
  endforeach()

  function(expect_destination_rejected variable value case_name)
    execute_process(
      COMMAND "${CMAKE_COMMAND}"
        -DPURE_BONJOUR_VALIDATE_DESTINATIONS_ONLY=ON
        "-D${variable}=${value}"
        -P "${INSTALL_MODULE}"
      RESULT_VARIABLE result
      OUTPUT_VARIABLE output
      ERROR_VARIABLE error
      ENCODING UTF-8)
    if(result EQUAL 0)
      message(FATAL_ERROR "${case_name} destination was accepted")
    endif()
    if(NOT "${output}${error}" MATCHES "DESTINATION_OUTSIDE_PREFIX")
      message(FATAL_ERROR
        "${case_name} failed without DESTINATION_OUTSIDE_PREFIX:\n"
        "${output}${error}")
    endif()
  endfunction()

  foreach(variable IN ITEMS
      PURE_LIBRARY_INSTALL_DIR
      PURE_DOCUMENTATION_INSTALL_DIR
      PURE_EXAMPLES_INSTALL_DIR)
    expect_destination_rejected(
      "${variable}" "C:/outside" "${variable}-absolute")
    expect_destination_rejected(
      "${variable}" "safe/../../outside" "${variable}-parent")
    expect_destination_rejected(
      "${variable}" "safe\\..\\outside" "${variable}-backslash-parent")
  endforeach()
  return()
endif()

if(TEST_MODE STREQUAL "parser")
  foreach(required IN ITEMS CMAKE_COMMAND VERIFIER TEST_ROOT)
    require_value(${required})
  endforeach()

  cmake_path(ABSOLUTE_PATH TEST_ROOT NORMALIZE OUTPUT_VARIABLE test_root)
  file(REMOVE_RECURSE "${test_root}")
  file(MAKE_DIRECTORY "${test_root}")

  function(write_listing path first_line imports)
    file(WRITE "${path}"
      "${first_line}\n"
      "Format: COFF-x86-64\n"
      "Arch: x86_64\n"
      "AddressSize: 64bit\n")
    foreach(import IN LISTS imports)
      file(APPEND "${path}"
        "Import {\n"
        "  Name: ${import}\n"
        "  ImportLookupTableRVA: 0x1\n"
        "  ImportAddressTableRVA: 0x2\n"
        "  Symbol: fixture_symbol (0)\n"
        "}\n")
    endforeach()
  endfunction()

  function(run_fixture name imports expected_token)
    set(listing "${test_root}/${name}.txt")
    write_listing("${listing}" "File: fixture/bonjour.dll" "${imports}")
    execute_process(
      COMMAND "${CMAKE_COMMAND}"
        -DPURE_BONJOUR_IMPORT_FIXTURE_ONLY=ON
        "-DIMPORT_LISTING_FILE=${listing}"
        -DIMPORT_OWNER=bonjour.dll
        -P "${VERIFIER}"
      RESULT_VARIABLE result
      OUTPUT_VARIABLE output
      ERROR_VARIABLE error
      ENCODING UTF-8)
    if(expected_token STREQUAL "")
      if(NOT result EQUAL 0)
        message(FATAL_ERROR
          "valid import fixture failed (${result})\n${output}${error}")
      endif()
    else()
      if(result EQUAL 0)
        message(FATAL_ERROR "${name} import fixture was accepted")
      endif()
      if(NOT "${output}${error}" MATCHES "${expected_token}")
        message(FATAL_ERROR
          "${name} failed without ${expected_token}:\n${output}${error}")
      endif()
    endif()
  endfunction()

  run_fixture(valid
    "DNSAPI.dll;WS2_32.dll;libpure.dll;KERNEL32.dll" "")

  set(malformed "${test_root}/malformed-header.txt")
  write_listing("${malformed}" "Object: fixture/bonjour.dll" "KERNEL32.dll")
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      -DPURE_BONJOUR_IMPORT_FIXTURE_ONLY=ON
      "-DIMPORT_LISTING_FILE=${malformed}"
      -DIMPORT_OWNER=bonjour.dll
      -P "${VERIFIER}"
    RESULT_VARIABLE malformed_result
    OUTPUT_VARIABLE malformed_output
    ERROR_VARIABLE malformed_error
    ENCODING UTF-8)
  if(malformed_result EQUAL 0 OR NOT
      "${malformed_output}${malformed_error}" MATCHES "IMPORTS_MALFORMED")
    message(FATAL_ERROR
      "malformed header did not fail with IMPORTS_MALFORMED:\n"
      "${malformed_output}${malformed_error}")
  endif()

  run_fixture(unknown "mystery-runtime.dll" "IMPORT_UNKNOWN")
  run_fixture(dnssd "dnssd.dll" "IMPORT_FORBIDDEN")
  run_fixture(apple-service "mDNSResponder.exe" "IMPORT_FORBIDDEN")
  run_fixture(ambiguous "libpure.dll;LIBPURE.DLL" "IMPORT_AMBIGUOUS")
  run_fixture(missing "" "IMPORTS_MISSING")
  return()
endif()

if(NOT TEST_MODE STREQUAL "install")
  message(FATAL_ERROR "unknown TEST_MODE: ${TEST_MODE}")
endif()

foreach(required IN ITEMS CMAKE_COMMAND BUILD_DIR STAGE_PREFIX)
  require_value(${required})
endforeach()

cmake_path(ABSOLUTE_PATH BUILD_DIR NORMALIZE OUTPUT_VARIABLE build_dir)
cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE stage)
set(default_stage "${stage}-default")
file(REMOVE_RECURSE "${default_stage}" "${stage}")

execute_process(
  COMMAND "${CMAKE_COMMAND}" --build "${build_dir}"
  RESULT_VARIABLE build_result
  OUTPUT_VARIABLE build_output
  ERROR_VARIABLE build_error
  ENCODING UTF-8)
if(NOT build_result EQUAL 0)
  message(FATAL_ERROR
    "PureBonjour build failed (${build_result})\n"
    "stdout:\n${build_output}\nstderr:\n${build_error}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" --install "${build_dir}"
    --prefix "${default_stage}"
  RESULT_VARIABLE default_result
  OUTPUT_VARIABLE default_output
  ERROR_VARIABLE default_error
  ENCODING UTF-8)
if(NOT default_result EQUAL 0)
  message(FATAL_ERROR
    "default install failed (${default_result})\n"
    "stdout:\n${default_output}\nstderr:\n${default_error}")
endif()

set(expected_paths
  lib/pure/bonjour.dll
  lib/pure/bonjour.pure
  share/doc/pure-bonjour/README
  share/doc/pure-bonjour/WINDOWS.md
  share/doc/pure-bonjour/COPYING
  share/doc/pure-bonjour/COPYING.LESSER
  share/doc/pure-bonjour/examples/bonjour_examp.pure
  share/doc/pure-bonjour/PureBonjourInventory.tsv)
list(SORT expected_paths)

foreach(relative IN LISTS expected_paths)
  if(EXISTS "${default_stage}/${relative}")
    message(FATAL_ERROR
      "PureBonjour payload leaked into default install: ${relative}")
  endif()
endforeach()

execute_process(
  COMMAND "${CMAKE_COMMAND}" --install "${build_dir}"
    --prefix "${stage}" --component PureBonjour
  RESULT_VARIABLE install_result
  OUTPUT_VARIABLE install_output
  ERROR_VARIABLE install_error
  ENCODING UTF-8)
if(NOT install_result EQUAL 0)
  message(FATAL_ERROR
    "PureBonjour component install failed (${install_result})\n"
    "stdout:\n${install_output}\nstderr:\n${install_error}")
endif()

file(GLOB_RECURSE installed_files
  LIST_DIRECTORIES FALSE RELATIVE "${stage}" "${stage}/*")
foreach(relative IN LISTS installed_files)
  cmake_path(CONVERT "${relative}" TO_CMAKE_PATH_LIST relative_normalized)
  list(APPEND actual_paths "${relative_normalized}")
endforeach()
list(SORT actual_paths)
if(NOT actual_paths STREQUAL expected_paths)
  message(FATAL_ERROR
    "PureBonjour installed file set mismatch\n"
    "expected: ${expected_paths}\nactual: ${actual_paths}")
endif()

set(readme "${stage}/share/doc/pure-bonjour/README")
file(READ "${readme}" readme_text)
if(readme_text MATCHES "@version@|\\|today\\|")
  message(FATAL_ERROR "generated README retains template markers")
endif()
if(NOT readme_text MATCHES "Version 0\\.2,")
  message(FATAL_ERROR "generated README does not contain version 0.2")
endif()

set(inventory "${stage}/share/doc/pure-bonjour/PureBonjourInventory.tsv")
file(STRINGS "${inventory}" inventory_lines)
list(LENGTH inventory_lines inventory_line_count)
if(NOT inventory_line_count EQUAL 8)
  message(FATAL_ERROR
    "inventory must contain one header and seven rows: ${inventory_line_count}")
endif()
list(GET inventory_lines 0 inventory_header)
if(NOT inventory_header STREQUAL
    "relative_path\tpurpose\torigin\tversion\tsha256\tsize")
  message(FATAL_ERROR "unexpected inventory header: ${inventory_header}")
endif()

set(inventory_paths)
set(expected_inventory_metadata
  "lib/pure/bonjour.dll|Pure Bonjour native module for Microsoft DNS Service Discovery|pure-bonjour Windows backend source|0.2"
  "lib/pure/bonjour.pure|Pure language declarations for the Bonjour module|pure-bonjour source distribution|0.2"
  "share/doc/pure-bonjour/README|Generated PureBonjour user documentation|pure-bonjour README template|0.2"
  "share/doc/pure-bonjour/WINDOWS.md|Windows platform and dependency notes|pure-bonjour package metadata|0.2"
  "share/doc/pure-bonjour/COPYING|GNU General Public License notice|pure-bonjour source distribution|3.0-or-later"
  "share/doc/pure-bonjour/COPYING.LESSER|GNU Lesser General Public License notice|pure-bonjour source distribution|3.0-or-later"
  "share/doc/pure-bonjour/examples/bonjour_examp.pure|PureBonjour service publication example|pure-bonjour source distribution|0.2")
list(REMOVE_AT inventory_lines 0)
foreach(line IN LISTS inventory_lines)
  string(REPLACE "\t" ";" fields "${line}")
  list(LENGTH fields field_count)
  if(NOT field_count EQUAL 6)
    message(FATAL_ERROR "inventory row does not have six fields: ${line}")
  endif()
  list(GET fields 0 relative)
  list(GET fields 1 purpose)
  list(GET fields 2 origin)
  list(GET fields 3 version)
  list(GET fields 4 expected_sha)
  list(GET fields 5 expected_size)
  string(LENGTH "${expected_sha}" expected_sha_length)
  if(relative STREQUAL "" OR purpose STREQUAL "" OR origin STREQUAL "" OR
      version STREQUAL "" OR NOT expected_sha MATCHES "^[0-9a-f]+$" OR
      NOT expected_sha_length EQUAL 64 OR
      NOT expected_size MATCHES "^[0-9]+$")
    message(FATAL_ERROR "malformed inventory row: ${line}")
  endif()
  set(metadata "${relative}|${purpose}|${origin}|${version}")
  if(NOT metadata IN_LIST expected_inventory_metadata)
    message(FATAL_ERROR "unexpected inventory metadata: ${metadata}")
  endif()
  if(NOT EXISTS "${stage}/${relative}")
    message(FATAL_ERROR "inventory path is not installed: ${relative}")
  endif()
  file(SHA256 "${stage}/${relative}" actual_sha)
  file(SIZE "${stage}/${relative}" actual_size)
  string(TOLOWER "${actual_sha}" actual_sha)
  if(NOT actual_sha STREQUAL expected_sha OR
      NOT actual_size EQUAL expected_size)
    message(FATAL_ERROR "inventory metadata mismatch: ${relative}")
  endif()
  list(APPEND inventory_paths "${relative}")
endforeach()

set(expected_inventory_paths "${expected_paths}")
list(REMOVE_ITEM expected_inventory_paths
  share/doc/pure-bonjour/PureBonjourInventory.tsv)
list(SORT inventory_paths)
list(SORT expected_inventory_paths)
if(NOT inventory_paths STREQUAL expected_inventory_paths)
  message(FATAL_ERROR
    "inventory path set mismatch\n"
    "expected: ${expected_inventory_paths}\nactual: ${inventory_paths}")
endif()

set(manifest "${build_dir}/PureBonjourExpected.sha256")
if(NOT EXISTS "${manifest}")
  message(FATAL_ERROR "missing external expected-hash oracle: ${manifest}")
endif()
file(STRINGS "${manifest}" manifest_lines)
list(LENGTH manifest_lines manifest_count)
if(NOT manifest_count EQUAL 8)
  message(FATAL_ERROR "expected-hash oracle must contain eight rows")
endif()
set(manifest_paths)
foreach(line IN LISTS manifest_lines)
  string(LENGTH "${line}" manifest_line_length)
  if(manifest_line_length LESS 67)
    message(FATAL_ERROR "malformed expected-hash row: ${line}")
  endif()
  string(SUBSTRING "${line}" 0 64 expected_sha)
  string(SUBSTRING "${line}" 64 2 manifest_separator)
  string(SUBSTRING "${line}" 66 -1 relative)
  if(NOT expected_sha MATCHES "^[0-9a-f]+$" OR
      NOT manifest_separator STREQUAL "  " OR relative STREQUAL "")
    message(FATAL_ERROR "malformed expected-hash row: ${line}")
  endif()
  if(NOT EXISTS "${stage}/${relative}")
    message(FATAL_ERROR "expected-hash path is not installed: ${relative}")
  endif()
  file(SHA256 "${stage}/${relative}" actual_sha)
  string(TOLOWER "${actual_sha}" actual_sha)
  if(NOT actual_sha STREQUAL expected_sha)
    message(FATAL_ERROR "installed hash mismatch: ${relative}")
  endif()
  list(APPEND manifest_paths "${relative}")
endforeach()
list(SORT manifest_paths)
if(NOT manifest_paths STREQUAL expected_paths)
  message(FATAL_ERROR
    "expected-hash path set mismatch\n"
    "expected: ${expected_paths}\nactual: ${manifest_paths}")
endif()
