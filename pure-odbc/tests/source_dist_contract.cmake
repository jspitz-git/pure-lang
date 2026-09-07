cmake_minimum_required(VERSION 3.25)

function(require_no_forbidden_text label content)
  string(REPLACE "\\" "/" normalized_content "${content}")
  string(TOLOWER "${normalized_content}" normalized_content)
  foreach(forbidden IN LISTS FORBIDDEN_PATHS)
    cmake_path(CONVERT "${forbidden}" TO_CMAKE_PATH_LIST normalized NORMALIZE)
    string(TOLOWER "${normalized}" normalized)
    string(FIND "${normalized_content}" "${normalized}" leak_offset)
    if(NOT leak_offset EQUAL -1)
      message(FATAL_ERROR "Checkout path leaked through ${label}")
    endif()
  endforeach()
endfunction()

function(require_no_forbidden_file path)
  set(needles)
  set(max_needle_bytes 0)
  foreach(forbidden IN LISTS FORBIDDEN_PATHS)
    cmake_path(CONVERT "${forbidden}" TO_CMAKE_PATH_LIST normalized NORMALIZE)
    string(REPLACE "/" "\\" native "${normalized}")
    foreach(spelling IN ITEMS "${normalized}" "${native}")
      string(TOLOWER "${spelling}" lower)
      string(TOUPPER "${spelling}" upper)
      foreach(variant IN ITEMS "${spelling}" "${lower}" "${upper}")
        string(HEX "${variant}" needle)
        list(APPEND needles "${needle}")
        string(LENGTH "${needle}" needle_hex_length)
        math(EXPR needle_bytes "${needle_hex_length} / 2")
        if(needle_bytes GREATER max_needle_bytes)
          set(max_needle_bytes "${needle_bytes}")
        endif()
      endforeach()
    endforeach()
  endforeach()
  list(REMOVE_DUPLICATES needles)

  file(SIZE "${path}" file_size)
  set(chunk_bytes 1048576)
  if(max_needle_bytes GREATER 0)
    math(EXPR overlap_bytes "${max_needle_bytes} - 1")
  else()
    set(overlap_bytes 0)
  endif()
  set(offset 0)
  while(offset LESS file_size)
    math(EXPR read_bytes "${chunk_bytes} + ${overlap_bytes}")
    file(READ "${path}" chunk OFFSET ${offset} LIMIT ${read_bytes} HEX)
    string(TOLOWER "${chunk}" chunk)
    foreach(needle IN LISTS needles)
      string(TOLOWER "${needle}" needle)
      string(FIND "${chunk}" "${needle}" leak_offset)
      if(NOT leak_offset EQUAL -1)
        message(FATAL_ERROR
          "Checkout path leaked through generated file ${path}")
      endif()
    endforeach()
    math(EXPR offset "${offset} + ${chunk_bytes}")
  endwhile()
endfunction()

function(run_checked label result_var output_var error_var)
  cmake_parse_arguments(PARSE_ARGV 4 run "" "WORKING_DIRECTORY" "COMMAND")
  if(DEFINED run_WORKING_DIRECTORY)
    execute_process(
      COMMAND ${run_COMMAND}
      WORKING_DIRECTORY "${run_WORKING_DIRECTORY}"
      RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error
      ENCODING UTF-8)
  else()
    execute_process(
      COMMAND ${run_COMMAND}
      RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error
      ENCODING UTF-8)
  endif()
  require_no_forbidden_text("${label} stdout" "${output}")
  require_no_forbidden_text("${label} stderr" "${error}")
  set(${result_var} "${result}" PARENT_SCOPE)
  set(${output_var} "${output}" PARENT_SCOPE)
  set(${error_var} "${error}" PARENT_SCOPE)
endfunction()

if(DEFINED PURE_ODBC_SCAN_FILE_PROBE)
  set(FORBIDDEN_PATHS "${PURE_ODBC_SCAN_FORBIDDEN}")
  require_no_forbidden_file("${PURE_ODBC_SCAN_FILE_PROBE}")
  return()
endif()

if(DEFINED PURE_ODBC_SCAN_OUTPUT_PROBE)
  set(FORBIDDEN_PATHS "${PURE_ODBC_SCAN_FORBIDDEN}")
  run_checked("probe command" result output error
    COMMAND "${CMAKE_COMMAND}" -E echo "${PURE_ODBC_SCAN_FORBIDDEN}")
  if(NOT result EQUAL 0)
    message(FATAL_ERROR "Output probe command unexpectedly failed")
  endif()
  return()
endif()

include("${CMAKE_CURRENT_LIST_DIR}/ContractTestRoot.cmake")

set(required_directories
  CLANG64_PREFIX PKG_CONFIG_PATH PORTABLE_PURE_PREFIX WINDOWS_DIRECTORY
  PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY)
set(required_files
  CMAKE_EXECUTABLE MAKE_EXECUTABLE NINJA_EXECUTABLE C_COMPILER
  PKG_CONFIG_EXECUTABLE PURE_EXECUTABLE PURE_RUNTIME_DLL LLVM_READOBJ
  GMP_RUNTIME_DLL ODBC_HEADER ODBC_IMPORT_LIBRARY SYSTEM_ODBC_DLL)
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

pure_odbc_validate_contract_test_root("cleanup" unused_test_root)
pure_odbc_reset_contract_test_root("cleanup")
set(dist_root "${TEST_ROOT}/d")
set(checkout_source "${TEST_ROOT}/checkout source with spaces")
set(extract_parent "${TEST_ROOT}/distribution source with spaces")
set(extracted_source "${extract_parent}/pure-odbc-0.10")
set(extracted_build "${TEST_ROOT}/b")
file(MAKE_DIRECTORY "${checkout_source}" "${extract_parent}")
set(FORBIDDEN_PATHS "${SOURCE_DIR}" "${checkout_source}")

set(scan_probe "${dist_root}/large-scan-probe.bin")
string(REPEAT "x" 9437184 scan_probe_prefix)
file(WRITE "${scan_probe}" "${scan_probe_prefix}${SOURCE_DIR}")
unset(scan_probe_prefix)
execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DPURE_ODBC_SCAN_FILE_PROBE=${scan_probe}"
    "-DPURE_ODBC_SCAN_FORBIDDEN=${SOURCE_DIR}"
    -P "${CMAKE_CURRENT_LIST_FILE}"
  RESULT_VARIABLE scan_probe_result
  OUTPUT_VARIABLE scan_probe_output
  ERROR_VARIABLE scan_probe_error
  ENCODING UTF-8)
file(REMOVE "${scan_probe}")
if(scan_probe_result EQUAL 0)
  message(FATAL_ERROR
    "Large generated-file scan accepted a checkout path after 8 MiB")
endif()
if(NOT scan_probe_error MATCHES "Checkout path leaked")
  message(FATAL_ERROR
    "Large generated-file scan failed with the wrong diagnostic\n"
    "${scan_probe_output}${scan_probe_error}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    -DPURE_ODBC_SCAN_OUTPUT_PROBE=ON
    "-DPURE_ODBC_SCAN_FORBIDDEN=${SOURCE_DIR}"
    -P "${CMAKE_CURRENT_LIST_FILE}"
  RESULT_VARIABLE output_probe_result
  OUTPUT_VARIABLE output_probe_output
  ERROR_VARIABLE output_probe_error
  ENCODING UTF-8)
if(output_probe_result EQUAL 0)
  message(FATAL_ERROR "Command-output scan accepted a checkout path")
endif()
if(NOT output_probe_error MATCHES "Checkout path leaked")
  message(FATAL_ERROR
    "Command-output scan failed with the wrong diagnostic\n"
    "${output_probe_output}${output_probe_error}")
endif()

_pure_odbc_require_no_reparse("${SOURCE_DIR}" "distribution input" TRUE)
file(COPY "${SOURCE_DIR}/" DESTINATION "${checkout_source}")
_pure_odbc_require_no_reparse(
  "${checkout_source}" "copied distribution checkout" TRUE)
cmake_path(GET MAKE_EXECUTABLE PARENT_PATH msys_usr_bin)

set(real_data_directory "${checkout_source}/tests/data-real")
set(junction_data_directory "${checkout_source}/tests/data")
file(RENAME "${junction_data_directory}" "${real_data_directory}")
set(powershell
  "${WINDOWS_DIRECTORY}/System32/WindowsPowerShell/v1.0/powershell.exe")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    "PURE_ODBC_LINK_PATH=${junction_data_directory}"
    "PURE_ODBC_LINK_TARGET=${real_data_directory}"
    "SystemRoot=${WINDOWS_DIRECTORY}" "windir=${WINDOWS_DIRECTORY}"
    "${powershell}" -NoProfile -NonInteractive -ExecutionPolicy Bypass
    -Command "$ErrorActionPreference='Stop'; New-Item -ItemType Junction -Path $env:PURE_ODBC_LINK_PATH -Target $env:PURE_ODBC_LINK_TARGET | Out-Null"
  RESULT_VARIABLE junction_create_result
  OUTPUT_VARIABLE junction_create_output
  ERROR_VARIABLE junction_create_error
  ENCODING UTF-8)
if(NOT junction_create_result EQUAL 0)
  message(FATAL_ERROR
    "Unable to create the distribution reparse fixture "
    "(${junction_create_result})\n${junction_create_output}${junction_create_error}")
endif()
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    "PATH=${msys_usr_bin};${CLANG64_PREFIX}/bin;${WINDOWS_DIRECTORY}/System32"
    "PKG_CONFIG_PATH=${PKG_CONFIG_PATH}"
    "${MAKE_EXECUTABLE}" date=September\ 7,\ 2026 dist
  WORKING_DIRECTORY "${checkout_source}"
  RESULT_VARIABLE junction_dist_result
  OUTPUT_VARIABLE junction_dist_output
  ERROR_VARIABLE junction_dist_error
  ENCODING UTF-8)
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    "PURE_ODBC_LINK_PATH=${junction_data_directory}"
    "SystemRoot=${WINDOWS_DIRECTORY}" "windir=${WINDOWS_DIRECTORY}"
    "${powershell}" -NoProfile -NonInteractive -ExecutionPolicy Bypass
    -Command "$ErrorActionPreference='Stop'; $item=Get-Item -LiteralPath $env:PURE_ODBC_LINK_PATH -Force; if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { throw 'fixture is not a reparse point' }; [IO.Directory]::Delete($env:PURE_ODBC_LINK_PATH, $false)"
  RESULT_VARIABLE junction_remove_result
  OUTPUT_VARIABLE junction_remove_output
  ERROR_VARIABLE junction_remove_error
  ENCODING UTF-8)
if(NOT junction_remove_result EQUAL 0)
  message(FATAL_ERROR
    "Unable to remove the distribution reparse fixture "
    "(${junction_remove_result})\n${junction_remove_output}${junction_remove_error}")
endif()
file(RENAME "${real_data_directory}" "${junction_data_directory}")
file(REMOVE "${checkout_source}/pure-odbc-0.10.tar.gz")
if(junction_dist_result EQUAL 0)
  message(FATAL_ERROR
    "make dist accepted a required asset through a junction parent")
endif()
if(NOT junction_dist_error MATCHES
    "refusing reparse distribution input: tests/data/people\\.csv")
  message(FATAL_ERROR
    "make dist rejected the junction fixture with the wrong diagnostic\n"
    "${junction_dist_output}${junction_dist_error}")
endif()
_pure_odbc_require_no_reparse(
  "${checkout_source}" "restored copied distribution checkout" TRUE)

set(checkout_junction "${dist_root}/checkout-root-junction")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    "PURE_ODBC_LINK_PATH=${checkout_junction}"
    "PURE_ODBC_LINK_TARGET=${checkout_source}"
    "SystemRoot=${WINDOWS_DIRECTORY}" "windir=${WINDOWS_DIRECTORY}"
    "${powershell}" -NoProfile -NonInteractive -ExecutionPolicy Bypass
    -Command "$ErrorActionPreference='Stop'; New-Item -ItemType Junction -Path $env:PURE_ODBC_LINK_PATH -Target $env:PURE_ODBC_LINK_TARGET | Out-Null"
  RESULT_VARIABLE root_junction_create_result
  OUTPUT_VARIABLE root_junction_create_output
  ERROR_VARIABLE root_junction_create_error
  ENCODING UTF-8)
if(NOT root_junction_create_result EQUAL 0)
  message(FATAL_ERROR
    "Unable to create the checkout-root reparse fixture "
    "(${root_junction_create_result})\n"
    "${root_junction_create_output}${root_junction_create_error}")
endif()
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    "PATH=${msys_usr_bin};${CLANG64_PREFIX}/bin;${WINDOWS_DIRECTORY}/System32"
    "PKG_CONFIG_PATH=${PKG_CONFIG_PATH}"
    "${MAKE_EXECUTABLE}" date=September\ 7,\ 2026 dist
  WORKING_DIRECTORY "${checkout_junction}"
  RESULT_VARIABLE root_junction_dist_result
  OUTPUT_VARIABLE root_junction_dist_output
  ERROR_VARIABLE root_junction_dist_error
  ENCODING UTF-8)
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    "PURE_ODBC_LINK_PATH=${checkout_junction}"
    "SystemRoot=${WINDOWS_DIRECTORY}" "windir=${WINDOWS_DIRECTORY}"
    "${powershell}" -NoProfile -NonInteractive -ExecutionPolicy Bypass
    -Command "$ErrorActionPreference='Stop'; $item=Get-Item -LiteralPath $env:PURE_ODBC_LINK_PATH -Force; if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { throw 'fixture is not a reparse point' }; [IO.Directory]::Delete($env:PURE_ODBC_LINK_PATH, $false)"
  RESULT_VARIABLE root_junction_remove_result
  OUTPUT_VARIABLE root_junction_remove_output
  ERROR_VARIABLE root_junction_remove_error
  ENCODING UTF-8)
if(NOT root_junction_remove_result EQUAL 0)
  message(FATAL_ERROR
    "Unable to remove the checkout-root reparse fixture "
    "(${root_junction_remove_result})\n"
    "${root_junction_remove_output}${root_junction_remove_error}")
endif()
file(REMOVE "${checkout_source}/pure-odbc-0.10.tar.gz")
if(root_junction_dist_result EQUAL 0)
  message(FATAL_ERROR "make dist accepted a junction in the checkout path")
endif()
if(NOT root_junction_dist_error MATCHES
    "refusing reparse distribution input: CMakeLists\\.txt")
  message(FATAL_ERROR
    "make dist rejected the checkout junction with the wrong diagnostic\n"
    "${root_junction_dist_output}${root_junction_dist_error}")
endif()

run_checked("make dist" dist_result dist_output dist_error
  WORKING_DIRECTORY "${checkout_source}"
  COMMAND "${CMAKE_COMMAND}" -E env
    "PATH=${msys_usr_bin};${CLANG64_PREFIX}/bin;${WINDOWS_DIRECTORY}/System32"
    "PKG_CONFIG_PATH=${PKG_CONFIG_PATH}"
    "${MAKE_EXECUTABLE}" date=September\ 7,\ 2026 dist
)
if(NOT dist_result EQUAL 0)
  message(FATAL_ERROR
    "make dist failed (${dist_result})\nstdout:\n${dist_output}\n"
    "stderr:\n${dist_error}")
endif()

set(archive "${checkout_source}/pure-odbc-0.10.tar.gz")
if(NOT EXISTS "${archive}" OR IS_DIRECTORY "${archive}" OR
    IS_SYMLINK "${archive}")
  message(FATAL_ERROR "make dist did not create a regular archive: ${archive}")
endif()
run_checked("source archive extraction"
  extract_result extract_output extract_error
  WORKING_DIRECTORY "${extract_parent}"
  COMMAND "${CMAKE_COMMAND}" -E tar xzf "${archive}")
if(NOT extract_result EQUAL 0)
  message(FATAL_ERROR
    "Unable to extract source archive (${extract_result})\n"
    "${extract_output}${extract_error}")
endif()
if(NOT IS_DIRECTORY "${extracted_source}" OR
    IS_SYMLINK "${extracted_source}")
  message(FATAL_ERROR
    "Archive did not contain the expected regular source root: "
    "${extracted_source}")
endif()
_pure_odbc_require_no_reparse(
  "${extracted_source}" "extracted distribution" TRUE)

set(required_assets
  CMakeLists.txt
  COPYING
  COPYING.LESSER
  Makefile
  README
  WINDOWS.md
  cmake/Install.cmake
  cmake/RunPureTest.cmake
  cmake/VerifyInstalledPackage.cmake
  cmake/VerifyWindowsDependencies.cmake
  debian/changelog
  debian/compat
  debian/control
  debian/copyright
  debian/docs
  debian/rules
  debian/source/format
  debian/watch
  examples/menagerie.pure
  odbc.c
  odbc.pure
  odbc_api.h
  tests/ContractTestRoot.cmake
  tests/access_smoke.pure
  tests/cleanup_contract.cmake
  tests/configure_contract.cmake
  tests/data/Schema.ini
  tests/data/people.csv
  tests/install_contract.cmake
  tests/load.pure
  tests/odbc_fault_harness.c
  tests/run_pure_test.c
  tests/runner_contract.cmake
  tests/runtime_verifier_contract.cmake
  tests/smoke.pure
  tests/source_dist_contract.cmake)

file(GLOB_RECURSE archived_assets LIST_DIRECTORIES FALSE
  RELATIVE "${extracted_source}" "${extracted_source}/*")
foreach(relative IN LISTS archived_assets)
  cmake_path(CONVERT "${relative}" TO_CMAKE_PATH_LIST relative NORMALIZE)
  list(APPEND normalized_archived_assets "${relative}")
endforeach()
list(SORT normalized_archived_assets)
list(SORT required_assets)
if(NOT normalized_archived_assets STREQUAL required_assets)
  set(missing_assets ${required_assets})
  set(unexpected_assets ${normalized_archived_assets})
  list(REMOVE_ITEM missing_assets ${normalized_archived_assets})
  list(REMOVE_ITEM unexpected_assets ${required_assets})
  message(FATAL_ERROR
    "Archive contents differ from the declared distribution inputs\n"
    "missing: ${missing_assets}\nunexpected: ${unexpected_assets}")
endif()

foreach(relative IN LISTS required_assets)
  set(source "${SOURCE_DIR}/${relative}")
  set(extracted "${extracted_source}/${relative}")
  if(NOT EXISTS "${source}" OR IS_DIRECTORY "${source}" OR
      IS_SYMLINK "${source}")
    message(FATAL_ERROR
      "Declared distribution input is not a regular file: ${source}")
  endif()
  _pure_odbc_require_no_reparse("${source}" "distribution input ${relative}" FALSE)
  if(NOT EXISTS "${extracted}" OR IS_DIRECTORY "${extracted}" OR
      IS_SYMLINK "${extracted}")
    message(FATAL_ERROR
      "Archive is missing regular required asset: ${relative}")
  endif()
  _pure_odbc_require_no_reparse("${extracted}" "archive asset ${relative}" FALSE)
  if(relative STREQUAL "README")
    file(READ "${source}" expected_readme)
    string(REPLACE "@version@" "0.10" expected_readme "${expected_readme}")
    string(REPLACE "|today|" "September 7, 2026"
      expected_readme "${expected_readme}")
    file(READ "${extracted}" actual_readme)
    if(NOT actual_readme STREQUAL expected_readme)
      message(FATAL_ERROR "Transformed README content differs from its input")
    endif()
  else()
    file(SHA256 "${source}" source_hash)
    file(SHA256 "${extracted}" extracted_hash)
    if(NOT source_hash STREQUAL extracted_hash)
      message(FATAL_ERROR
        "Archive asset hash differs from its distribution input: ${relative}")
    endif()
  endif()
endforeach()

# The extracted build must remain viable after the producing checkout loses the
# native driver source. Both paths are beneath the validated owned test root.
file(REMOVE "${checkout_source}/odbc.c")
if(EXISTS "${checkout_source}/odbc.c" OR IS_SYMLINK "${checkout_source}/odbc.c")
  message(FATAL_ERROR "Unable to remove the copied checkout-side driver")
endif()

set(configure_command
  "${CMAKE_EXECUTABLE}" -S "${extracted_source}" -B "${extracted_build}"
  -G Ninja
  "-DCMAKE_MAKE_PROGRAM=${NINJA_EXECUTABLE}"
  "-DCMAKE_C_COMPILER=${C_COMPILER}"
  -DCMAKE_C_COMPILER_TARGET=x86_64-w64-windows-gnu
  -DCMAKE_BUILD_TYPE=Release
  -DBUILD_TESTING=ON
  -DPURE_ODBC_STRICT_WINDOWS_AUDIT=ON
  "-DPURE_ODBC_CLANG64_PREFIX=${CLANG64_PREFIX}"
  "-DPURE_ODBC_PKG_CONFIG_PATH=${PKG_CONFIG_PATH}"
  "-DPKG_CONFIG_EXECUTABLE=${PKG_CONFIG_EXECUTABLE}"
  "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
  "-DPURE_RUNTIME_DLL=${PURE_RUNTIME_DLL}"
  "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ}"
  "-DPURE_ODBC_MAKE_EXECUTABLE=${MAKE_EXECUTABLE}"
  "-DGMP_RUNTIME_DLL=${GMP_RUNTIME_DLL}"
  "-DODBC_HEADER=${ODBC_HEADER}"
  "-DODBC_IMPORT_LIBRARY=${ODBC_IMPORT_LIBRARY}"
  "-DSYSTEM_ODBC_DLL=${SYSTEM_ODBC_DLL}")
run_checked("extracted strict configure"
  configure_result configure_output configure_error
  COMMAND ${configure_command})
if(NOT configure_result EQUAL 0)
  message(FATAL_ERROR
    "Extracted strict configure failed (${configure_result})\n"
    "stdout:\n${configure_output}\nstderr:\n${configure_error}")
endif()

run_checked("extracted four-worker build"
  build_result build_output build_error
  COMMAND "${CMAKE_EXECUTABLE}" --build "${extracted_build}" --parallel 4)
if(NOT build_result EQUAL 0)
  message(FATAL_ERROR
    "Extracted four-worker build failed (${build_result})\n"
    "${build_output}${build_error}")
endif()
run_checked("extracted PE verification" pe_result pe_output pe_error
  COMMAND "${CMAKE_EXECUTABLE}" --build "${extracted_build}"
    --target verify-windows-dependencies --parallel 4
)
if(NOT pe_result EQUAL 0)
  message(FATAL_ERROR
    "Extracted PE verification failed (${pe_result})\n${pe_output}${pe_error}")
endif()
run_checked("extracted verbose CTest including install and verifier output"
  test_result test_output test_error
  COMMAND "${CMAKE_CTEST_COMMAND}" --test-dir "${extracted_build}"
    -LE source-distribution --verbose --output-on-failure --no-tests=error)
if(NOT test_result EQUAL 0)
  message(FATAL_ERROR
    "Extracted full ODBC test suite failed (${test_result})\n"
    "${test_output}${test_error}")
endif()

file(GLOB_RECURSE generated_files LIST_DIRECTORIES FALSE
  "${extracted_build}/*")
foreach(generated IN LISTS generated_files)
  if(IS_SYMLINK "${generated}")
    message(FATAL_ERROR "Extracted build produced a symlink: ${generated}")
  endif()
  require_no_forbidden_file("${generated}")
endforeach()

message(STATUS
  "pure-odbc source distribution contract passed: ${required_assets}")
