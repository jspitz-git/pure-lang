cmake_minimum_required(VERSION 3.25)

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

_pure_odbc_require_no_reparse("${SOURCE_DIR}" "distribution input" TRUE)
file(COPY "${SOURCE_DIR}/" DESTINATION "${checkout_source}")
_pure_odbc_require_no_reparse(
  "${checkout_source}" "copied distribution checkout" TRUE)
cmake_path(GET MAKE_EXECUTABLE PARENT_PATH msys_usr_bin)

execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    "PATH=${msys_usr_bin};${CLANG64_PREFIX}/bin;${WINDOWS_DIRECTORY}/System32"
    "PKG_CONFIG_PATH=${PKG_CONFIG_PATH}"
    "${MAKE_EXECUTABLE}" date=September\ 7,\ 2026 dist
  WORKING_DIRECTORY "${checkout_source}"
  RESULT_VARIABLE dist_result
  OUTPUT_VARIABLE dist_output
  ERROR_VARIABLE dist_error
  ENCODING UTF-8)
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
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E tar xzf "${archive}"
  WORKING_DIRECTORY "${extract_parent}"
  RESULT_VARIABLE extract_result
  OUTPUT_VARIABLE extract_output
  ERROR_VARIABLE extract_error
  ENCODING UTF-8)
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
execute_process(
  COMMAND ${configure_command}
  RESULT_VARIABLE configure_result
  OUTPUT_VARIABLE configure_output
  ERROR_VARIABLE configure_error
  ENCODING UTF-8)
if(NOT configure_result EQUAL 0)
  message(FATAL_ERROR
    "Extracted strict configure failed (${configure_result})\n"
    "stdout:\n${configure_output}\nstderr:\n${configure_error}")
endif()

execute_process(
  COMMAND "${CMAKE_EXECUTABLE}" --build "${extracted_build}" --parallel 4
  RESULT_VARIABLE build_result
  OUTPUT_VARIABLE build_output
  ERROR_VARIABLE build_error
  ENCODING UTF-8)
if(NOT build_result EQUAL 0)
  message(FATAL_ERROR
    "Extracted four-worker build failed (${build_result})\n"
    "${build_output}${build_error}")
endif()
execute_process(
  COMMAND "${CMAKE_EXECUTABLE}" --build "${extracted_build}"
    --target verify-windows-dependencies --parallel 4
  RESULT_VARIABLE pe_result
  OUTPUT_VARIABLE pe_output
  ERROR_VARIABLE pe_error
  ENCODING UTF-8)
if(NOT pe_result EQUAL 0)
  message(FATAL_ERROR
    "Extracted PE verification failed (${pe_result})\n${pe_output}${pe_error}")
endif()
execute_process(
  COMMAND "${CMAKE_CTEST_COMMAND}" --test-dir "${extracted_build}"
    -LE source-distribution --output-on-failure --no-tests=error
  RESULT_VARIABLE test_result
  OUTPUT_VARIABLE test_output
  ERROR_VARIABLE test_error
  ENCODING UTF-8)
if(NOT test_result EQUAL 0)
  message(FATAL_ERROR
    "Extracted full ODBC test suite failed (${test_result})\n"
    "${test_output}${test_error}")
endif()

set(forbidden_paths "${SOURCE_DIR}" "${checkout_source}")
file(GLOB_RECURSE generated_files LIST_DIRECTORIES FALSE
  "${extracted_build}/*")
foreach(generated IN LISTS generated_files)
  if(IS_SYMLINK "${generated}")
    message(FATAL_ERROR "Extracted build produced a symlink: ${generated}")
  endif()
  file(SIZE "${generated}" generated_size)
  if(generated_size GREATER 8388608)
    continue()
  endif()
  file(READ "${generated}" generated_content LIMIT 8388608)
  string(REPLACE "\\" "/" generated_content "${generated_content}")
  string(TOLOWER "${generated_content}" generated_content)
  foreach(forbidden IN LISTS forbidden_paths)
    cmake_path(CONVERT "${forbidden}" TO_CMAKE_PATH_LIST forbidden NORMALIZE)
    string(TOLOWER "${forbidden}" forbidden)
    string(FIND "${generated_content}" "${forbidden}" leak_offset)
    if(NOT leak_offset EQUAL -1)
      message(FATAL_ERROR
        "Checkout path leaked into extracted build output: ${generated}")
    endif()
  endforeach()
endforeach()

message(STATUS
  "pure-odbc source distribution contract passed: ${required_assets}")
