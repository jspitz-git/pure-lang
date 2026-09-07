cmake_minimum_required(VERSION 3.25)

include("${CMAKE_CURRENT_LIST_DIR}/ContractTestRoot.cmake")

foreach(required IN ITEMS
    GENERATOR MAKE_PROGRAM C_COMPILER C_COMPILER_TARGET
    PKG_CONFIG_EXECUTABLE PKG_CONFIG_PATH PURE_EXECUTABLE PURE_RUNTIME_DLL
    LLVM_READOBJ_EXECUTABLE MSYS_MAKE_EXECUTABLE GMP_RUNTIME_DLL
    ODBC_HEADER ODBC_IMPORT_LIBRARY SYSTEM_ODBC_DLL CLANG64_PREFIX
    PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

pure_odbc_validate_contract_test_root("cleanup" unused_test_root)
pure_odbc_reset_contract_test_root("cleanup")
set(configure_root "${TEST_ROOT}/task5-configure")
file(MAKE_DIRECTORY "${configure_root}")

set(common_arguments
  -G "${GENERATOR}"
  "-DCMAKE_MAKE_PROGRAM=${MAKE_PROGRAM}"
  "-DCMAKE_C_COMPILER=${C_COMPILER}"
  "-DCMAKE_C_COMPILER_TARGET=${C_COMPILER_TARGET}"
  -DCMAKE_BUILD_TYPE=Release
  -DBUILD_TESTING=ON
  -DPURE_ODBC_STRICT_WINDOWS_AUDIT=ON
  "-DPURE_ODBC_CLANG64_PREFIX=${CLANG64_PREFIX}"
  "-DPURE_ODBC_PKG_CONFIG_PATH=${PKG_CONFIG_PATH}"
  "-DPKG_CONFIG_EXECUTABLE=${PKG_CONFIG_EXECUTABLE}"
  "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
  "-DPURE_RUNTIME_DLL=${PURE_RUNTIME_DLL}"
  "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}"
  "-DPURE_ODBC_MAKE_EXECUTABLE=${MSYS_MAKE_EXECUTABLE}"
  "-DGMP_RUNTIME_DLL=${GMP_RUNTIME_DLL}"
  "-DODBC_HEADER=${ODBC_HEADER}"
  "-DODBC_IMPORT_LIBRARY=${ODBC_IMPORT_LIBRARY}"
  "-DSYSTEM_ODBC_DLL=${SYSTEM_ODBC_DLL}"
)

function(run_configure name result_var diagnostics_var)
  string(MAKE_C_IDENTIFIER "${name}" identifier)
  set(build_dir "${configure_root}/${identifier}")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env
      "PKG_CONFIG_PATH=${PKG_CONFIG_PATH}"
      "${CMAKE_COMMAND}" -S "${SOURCE_DIR}" -B "${build_dir}"
      ${common_arguments} ${ARGN}
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8
  )
  set(${result_var} "${result}" PARENT_SCOPE)
  set(${diagnostics_var} "${output}\n${error}" PARENT_SCOPE)
endfunction()

function(expect_configure_failure name expected)
  run_configure("${name}" result diagnostics ${ARGN})
  if(result EQUAL 0)
    message(FATAL_ERROR "${name} configuration unexpectedly succeeded")
  endif()
  if(NOT "${expected}" STREQUAL "" AND
      NOT diagnostics MATCHES "${expected}")
    message(FATAL_ERROR
      "${name} produced the wrong diagnostic\n${diagnostics}")
  endif()
endfunction()

run_configure("strict positive" positive_result positive_diagnostics)
if(NOT positive_result EQUAL 0)
  message(FATAL_ERROR
    "Valid strict configuration failed (${positive_result})\n"
    "${positive_diagnostics}")
endif()

set(owned_inputs
  PURE_ODBC_CLANG64_PREFIX
  PURE_ODBC_PKG_CONFIG_PATH
  LLVM_READOBJ_EXECUTABLE
  PURE_ODBC_MAKE_EXECUTABLE
  GMP_RUNTIME_DLL
  ODBC_HEADER
  ODBC_IMPORT_LIBRARY
  SYSTEM_ODBC_DLL
  PURE_EXECUTABLE
  PURE_RUNTIME_DLL
)
file(MAKE_DIRECTORY "${configure_root}/directory-input")
foreach(input IN LISTS owned_inputs)
  expect_configure_failure(
    "missing ${input}" "${input}"
    "-D${input}=${configure_root}/missing/${input}")
  expect_configure_failure(
    "directory ${input}" ""
    "-D${input}=${configure_root}/directory-input")
endforeach()

expect_configure_failure("missing C compiler" ""
  "-DCMAKE_C_COMPILER=${configure_root}/missing/clang.exe")
expect_configure_failure("directory C compiler" ""
  "-DCMAKE_C_COMPILER=${configure_root}/directory-input")
expect_configure_failure("missing Ninja" ""
  "-DCMAKE_MAKE_PROGRAM=${configure_root}/missing/ninja.exe")
expect_configure_failure("directory Ninja" ""
  "-DCMAKE_MAKE_PROGRAM=${configure_root}/directory-input")

set(outside "${configure_root}/outside")
file(MAKE_DIRECTORY "${outside}")
foreach(copy_pair IN ITEMS
    "pkgconf.exe|${PKG_CONFIG_EXECUTABLE}|PKG_CONFIG_EXECUTABLE"
    "llvm-readobj.exe|${LLVM_READOBJ_EXECUTABLE}|LLVM_READOBJ_EXECUTABLE"
    "make.exe|${MSYS_MAKE_EXECUTABLE}|PURE_ODBC_MAKE_EXECUTABLE"
    "pure.exe|${PURE_EXECUTABLE}|PURE_EXECUTABLE"
    "libpure.dll|${PURE_RUNTIME_DLL}|PURE_RUNTIME_DLL"
    "libgmp-10.dll|${GMP_RUNTIME_DLL}|GMP_RUNTIME_DLL"
    "sql.h|${ODBC_HEADER}|ODBC_HEADER"
    "libodbc32.a|${ODBC_IMPORT_LIBRARY}|ODBC_IMPORT_LIBRARY")
  string(REPLACE "|" ";" fields "${copy_pair}")
  list(GET fields 0 basename)
  list(GET fields 1 source)
  list(GET fields 2 variable)
  file(COPY_FILE "${source}" "${outside}/${basename}")
  expect_configure_failure(
    "wrong origin ${variable}" "${variable}.*(CLANG64|Pure SDK|MSYS)"
    "-D${variable}=${outside}/${basename}")
endforeach()

set(fake_clang64 "${configure_root}/not-clang64")
file(MAKE_DIRECTORY "${fake_clang64}")
expect_configure_failure(
  "wrong compiler origin" "CMAKE_C_COMPILER.*CLANG64"
  "-DPURE_ODBC_CLANG64_PREFIX=${fake_clang64}")

expect_configure_failure(
  "wrong compiler id" "compiler ID.*Clang"
  -DCMAKE_C_COMPILER_FORCED=ON
  -DCMAKE_C_COMPILER_ID=GNU
  -DCMAKE_C_COMPILER_VERSION=22.1.8)
expect_configure_failure(
  "wrong Clang major" "Clang 22"
  -DCMAKE_C_COMPILER_FORCED=ON
  -DCMAKE_C_COMPILER_ID=Clang
  -DCMAKE_C_COMPILER_VERSION=21.0.0)
expect_configure_failure(
  "non x86-64 target" "x86-64 Windows target"
  -DCMAKE_C_COMPILER_FORCED=ON
  -DCMAKE_C_COMPILER_ID=Clang
  -DCMAKE_C_COMPILER_VERSION=22.1.8
  -DCMAKE_C_STANDARD_COMPUTED_DEFAULT=17
  -DCMAKE_C_EXTENSIONS_COMPUTED_DEFAULT=ON
  -DCMAKE_C_COMPILER_TARGET=i686-w64-windows-gnu
  -DCMAKE_SIZEOF_VOID_P=4)

file(WRITE "${outside}/ninja.exe" "not Ninja\n")
expect_configure_failure(
  "wrong Ninja" ""
  "-DCMAKE_MAKE_PROGRAM=${outside}/ninja.exe")

message(STATUS "pure-odbc strict configure contracts passed")
