cmake_minimum_required(VERSION 3.25)
foreach(required IN ITEMS SOURCE_DIR BINARY_DIR TEST_ROOT GENERATOR MAKE_PROGRAM
    C_COMPILER PKG_CONFIG_EXECUTABLE PKG_CONFIG_PATH PURE_EXECUTABLE
    SQLITE_RUNTIME_LICENSE)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()
get_filename_component(binary_root "${BINARY_DIR}" ABSOLUTE)
get_filename_component(test_root "${TEST_ROOT}" ABSOLUTE)
cmake_path(IS_PREFIX binary_root "${test_root}" NORMALIZE safe_root)
if(NOT safe_root OR test_root STREQUAL binary_root)
  message(FATAL_ERROR "TEST_ROOT must be a child of BINARY_DIR")
endif()
function(expect_configure_failure name expected)
  set(build "${TEST_ROOT}/${name}")
  file(REMOVE_RECURSE "${build}")
  execute_process(COMMAND "${CMAKE_COMMAND}" -E env
    "PKG_CONFIG_PATH=${PKG_CONFIG_PATH}" "${CMAKE_COMMAND}"
    -S "${SOURCE_DIR}" -B "${build}" -G "${GENERATOR}"
    "-DCMAKE_MAKE_PROGRAM=${MAKE_PROGRAM}"
    "-DCMAKE_C_COMPILER=${C_COMPILER}"
    "-DPKG_CONFIG_EXECUTABLE=${PKG_CONFIG_EXECUTABLE}"
    -DBUILD_TESTING=ON ${ARGN}
    RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
  if(result EQUAL 0)
    message(FATAL_ERROR "${name} configuration unexpectedly succeeded")
  endif()
  if(NOT "${output}\n${error}" MATCHES "${expected}")
    message(FATAL_ERROR "${name} produced the wrong diagnostic:\n${output}${error}")
  endif()
endfunction()
expect_configure_failure("missing Pure" "BUILD_TESTING requires an existing PURE_EXECUTABLE"
  -DPURE_EXECUTABLE= -DLLVM_READOBJ_EXECUTABLE=missing)
expect_configure_failure("missing readobj"
  "BUILD_TESTING requires an existing LLVM_READOBJ_EXECUTABLE"
  "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}" -DLLVM_READOBJ_EXECUTABLE=)

set(fake_dir "${TEST_ROOT}/sqlite fixture")
file(MAKE_DIRECTORY "${fake_dir}")
file(WRITE "${fake_dir}/libsqlite3-0.dll" "not the controlled SQLite DLL")
expect_configure_failure("wrong SQLite build" "controlled SQLite runtime"
  "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
  "-DLLVM_READOBJ_EXECUTABLE=${CMAKE_COMMAND}"
  "-DPURE_SQLITE_RUNTIME_DLL=${fake_dir}/libsqlite3-0.dll"
  "-DPURE_SQLITE_RUNTIME_LICENSE=${SQLITE_RUNTIME_LICENSE}")

set(bad_script "${TEST_ROOT}/diagnostic.pure")
file(WRITE "${bad_script}" "1 != 2;\nputs \"PURE_SQL3_SMOKE_OK\";\n")
execute_process(COMMAND "${CMAKE_COMMAND}"
  "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}" "-DMODULE_DIR=${SOURCE_DIR}"
  "-DMODULE_DLL_DIR=${BINARY_DIR}"
  "-DSQLITE_RUNTIME_DIR=${BINARY_DIR}" "-DTEST_SCRIPT=${bad_script}"
  "-DTEST_ROOT=${TEST_ROOT}/runner" -P "${SOURCE_DIR}/cmake/RunSmokeTest.cmake"
  RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
if(result EQUAL 0)
  message(FATAL_ERROR "Smoke runner accepted parser diagnostics on stderr")
endif()
