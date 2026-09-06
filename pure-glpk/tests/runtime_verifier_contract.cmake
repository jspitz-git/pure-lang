foreach(required IN ITEMS
    SOURCE_DIR BINARY_DIR CONTRACT_ROOT PORTABLE_PURE_PREFIX TEST_ROOT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH SOURCE_DIR NORMALIZE OUTPUT_VARIABLE source_dir)
cmake_path(ABSOLUTE_PATH BINARY_DIR NORMALIZE OUTPUT_VARIABLE binary_dir)
cmake_path(ABSOLUTE_PATH CONTRACT_ROOT NORMALIZE OUTPUT_VARIABLE contract_root)
cmake_path(ABSOLUTE_PATH PORTABLE_PURE_PREFIX NORMALIZE
  OUTPUT_VARIABLE portable_pure_prefix)
cmake_path(ABSOLUTE_PATH TEST_ROOT NORMALIZE OUTPUT_VARIABLE test_root)

set(self_arguments
  "-DSOURCE_DIR=${source_dir}"
  "-DBINARY_DIR=${binary_dir}"
  "-DCONTRACT_ROOT=${contract_root}"
  "-DPORTABLE_PURE_PREFIX=${portable_pure_prefix}"
)
function(expect_unsafe_root_rejected label unsafe_root)
  execute_process(
    COMMAND "${CMAKE_COMMAND}" ${self_arguments}
      "-DTEST_ROOT=${unsafe_root}"
      -DROOT_SAFETY_PROBE=ON
      -P "${CMAKE_CURRENT_LIST_FILE}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8
  )
  if(result EQUAL 0)
    message(FATAL_ERROR
      "Cleanup guard accepted unsafe ${label} TEST_ROOT: ${unsafe_root}")
  endif()
  if(NOT "${output}\n${error}" MATCHES "Unsafe TEST_ROOT")
    message(FATAL_ERROR
      "Unsafe ${label} TEST_ROOT produced the wrong diagnostic\n"
      "${output}\n${error}")
  endif()
endfunction()

function(require_safe_test_root)
  foreach(directory IN ITEMS source_dir binary_dir portable_pure_prefix)
    if(NOT IS_DIRECTORY "${${directory}}")
      message(FATAL_ERROR
        "${directory} must be an existing directory: ${${directory}}")
    endif()
  endforeach()
  cmake_path(GET contract_root PARENT_PATH contract_parent)
  if(NOT "${contract_parent}" STREQUAL "${binary_dir}")
    message(FATAL_ERROR
      "Unsafe CONTRACT_ROOT; expected a direct child of BINARY_DIR\n"
      "CONTRACT_ROOT: ${contract_root}\nBINARY_DIR: ${binary_dir}")
  endif()
  cmake_path(GET test_root PARENT_PATH test_parent)
  if(NOT "${test_parent}" STREQUAL "${contract_root}")
    message(FATAL_ERROR
      "Unsafe TEST_ROOT; expected a direct child of CONTRACT_ROOT\n"
      "TEST_ROOT: ${test_root}\nCONTRACT_ROOT: ${contract_root}")
  endif()
  foreach(protected IN ITEMS source_dir binary_dir portable_pure_prefix)
    cmake_path(IS_PREFIX test_root "${${protected}}" NORMALIZE
      test_root_contains_protected)
    if(test_root_contains_protected)
      message(FATAL_ERROR
        "Unsafe TEST_ROOT contains protected ${protected}: ${${protected}}")
    endif()
  endforeach()
endfunction()

require_safe_test_root()
if(ROOT_SAFETY_PROBE)
  return()
endif()
expect_unsafe_root_rejected("source" "${source_dir}")
expect_unsafe_root_rejected("binary" "${binary_dir}")
expect_unsafe_root_rejected("portable-prefix" "${portable_pure_prefix}")

file(REMOVE_RECURSE "${test_root}")
file(MAKE_DIRECTORY "${test_root}/modules")

set(module_names
  glpk.dll
  libglpk-40.dll
  libcolamd.dll
  libamd.dll
  libsuitesparseconfig.dll
  libomp.dll
  libgmp-10.dll
  zlib1.dll
)
foreach(module IN LISTS module_names)
  file(WRITE "${test_root}/modules/${module}" "fixture for ${module}\n")
endforeach()

# These fixtures are deliberately literal and independent of the verifier.
file(WRITE "${test_root}/glpk.dll.imports" [=[
LiBpUrE.DlL
KERNEL32.DLL
Api-Ms-Win-Crt-String-L1-1-0.DLL
libgmp-10.DLL
api-ms-win-crt-heap-l1-1-0.dll
LIBGLPK-40.dll
API-MS-WIN-CRT-RUNTIME-L1-1-0.DLL
api-ms-win-crt-private-l1-1-0.dll
Api-Ms-Win-Crt-Locale-L1-1-0.Dll
API-MS-WIN-CRT-STDIO-L1-1-0.DLL
]=])
file(WRITE "${test_root}/libglpk-40.dll.imports" [=[
ZLIB1.DLL
api-ms-win-crt-time-l1-1-0.dll
LIBAMD.dll
API-MS-WIN-CRT-HEAP-L1-1-0.DLL
libgmp-10.dll
api-ms-win-crt-convert-l1-1-0.dll
Kernel32.dll
api-ms-win-crt-string-l1-1-0.dll
LIBCOLAMD.DLL
api-ms-win-crt-math-l1-1-0.dll
API-MS-WIN-CRT-UTILITY-L1-1-0.DLL
api-ms-win-crt-filesystem-l1-1-0.dll
Api-Ms-Win-Crt-Locale-L1-1-0.Dll
api-ms-win-crt-runtime-l1-1-0.dll
API-MS-WIN-CRT-PRIVATE-L1-1-0.DLL
api-ms-win-crt-stdio-l1-1-0.dll
]=])
file(WRITE "${test_root}/libcolamd.dll.imports" [=[
LIBSUITESPARSECONFIG.DLL
api-ms-win-crt-string-l1-1-0.dll
KERNEL32.dll
API-MS-WIN-CRT-HEAP-L1-1-0.DLL
api-ms-win-crt-utility-l1-1-0.dll
Api-Ms-Win-Crt-Runtime-L1-1-0.Dll
api-ms-win-crt-private-l1-1-0.dll
API-MS-WIN-CRT-STDIO-L1-1-0.DLL
]=])
file(WRITE "${test_root}/libamd.dll.imports" [=[
libsuitesparseconfig.DLL
API-MS-WIN-CRT-STRING-L1-1-0.DLL
api-ms-win-crt-math-l1-1-0.dll
Kernel32.DLL
api-ms-win-crt-runtime-l1-1-0.dll
API-MS-WIN-CRT-HEAP-L1-1-0.DLL
api-ms-win-crt-stdio-l1-1-0.dll
Api-Ms-Win-Crt-Private-L1-1-0.Dll
]=])
file(WRITE "${test_root}/libsuitesparseconfig.dll.imports" [=[
LIBOMP.DLL
api-ms-win-crt-private-l1-1-0.dll
API-MS-WIN-CRT-MATH-L1-1-0.DLL
kernel32.dll
api-ms-win-crt-convert-l1-1-0.dll
Api-Ms-Win-Crt-String-L1-1-0.Dll
api-ms-win-crt-heap-l1-1-0.dll
API-MS-WIN-CRT-RUNTIME-L1-1-0.DLL
api-ms-win-crt-filesystem-l1-1-0.dll
Api-Ms-Win-Crt-Stdio-L1-1-0.Dll
API-MS-WIN-CRT-LOCALE-L1-1-0.DLL
]=])
file(WRITE "${test_root}/libomp.dll.imports" [=[
KERNEL32.DLL
api-ms-win-crt-utility-l1-1-0.dll
API-MS-WIN-CRT-CONVERT-L1-1-0.DLL
api-ms-win-crt-string-l1-1-0.dll
Api-Ms-Win-Crt-Environment-L1-1-0.Dll
api-ms-win-crt-private-l1-1-0.dll
API-MS-WIN-CRT-HEAP-L1-1-0.DLL
api-ms-win-crt-runtime-l1-1-0.dll
Api-Ms-Win-Crt-Filesystem-L1-1-0.Dll
api-ms-win-crt-stdio-l1-1-0.dll
API-MS-WIN-CRT-LOCALE-L1-1-0.DLL
]=])
file(WRITE "${test_root}/libgmp-10.dll.imports" [=[
API-MS-WIN-CRT-TIME-L1-1-0.DLL
kernel32.dll
api-ms-win-crt-locale-l1-1-0.dll
Api-Ms-Win-Crt-Convert-L1-1-0.Dll
api-ms-win-crt-utility-l1-1-0.dll
API-MS-WIN-CRT-HEAP-L1-1-0.DLL
api-ms-win-crt-environment-l1-1-0.dll
Api-Ms-Win-Crt-String-L1-1-0.Dll
api-ms-win-crt-private-l1-1-0.dll
API-MS-WIN-CRT-RUNTIME-L1-1-0.DLL
api-ms-win-crt-filesystem-l1-1-0.dll
Api-Ms-Win-Crt-Stdio-L1-1-0.Dll
]=])
file(WRITE "${test_root}/zlib1.dll.imports" [=[
Kernel32.DLL
api-ms-win-crt-private-l1-1-0.dll
API-MS-WIN-CRT-CONVERT-L1-1-0.DLL
api-ms-win-crt-string-l1-1-0.dll
Api-Ms-Win-Crt-Locale-L1-1-0.Dll
api-ms-win-crt-utility-l1-1-0.dll
API-MS-WIN-CRT-HEAP-L1-1-0.DLL
api-ms-win-crt-runtime-l1-1-0.dll
Api-Ms-Win-Crt-Stdio-L1-1-0.Dll
]=])

file(WRITE "${test_root}/fake-llvm-readobj.cmd" [=[@echo off
set "fixture=%~dp0%~nx2.imports"
if not exist "%fixture%" (
  echo Missing fixture for %~nx2 1>&2
  exit /b 2
)
for /f "usebackq delims=" %%L in ("%fixture%") do echo Name: %%L
if exist "%~dp0inject-unexpected" if /i "%~nx2"=="glpk.dll" echo Name: libunexpected.dll
]=])

set(verifier "${source_dir}/cmake/VerifyWindowsDependencies.cmake")
set(verifier_arguments
  "-DLLVM_READOBJ=${test_root}/fake-llvm-readobj.cmd"
  "-DGLPK_MODULE=${test_root}/modules/glpk.dll"
  "-DGLPK_DLL=${test_root}/modules/libglpk-40.dll"
  "-DCOLAMD_DLL=${test_root}/modules/libcolamd.dll"
  "-DAMD_DLL=${test_root}/modules/libamd.dll"
  "-DSUITESPARSECONFIG_DLL=${test_root}/modules/libsuitesparseconfig.dll"
  "-DOMP_DLL=${test_root}/modules/libomp.dll"
  "-DGMP_DLL=${test_root}/modules/libgmp-10.dll"
  "-DZLIB_DLL=${test_root}/modules/zlib1.dll"
  -P "${verifier}"
)

execute_process(
  COMMAND "${CMAKE_COMMAND}" ${verifier_arguments}
  RESULT_VARIABLE exact_result
  OUTPUT_VARIABLE exact_output
  ERROR_VARIABLE exact_error
  ENCODING UTF-8
)
if(NOT exact_result EQUAL 0)
  message(FATAL_ERROR
    "Exact import fixtures were rejected (${exact_result})\n"
    "stdout:\n${exact_output}\nstderr:\n${exact_error}")
endif()

file(WRITE "${test_root}/inject-unexpected" "libunexpected.dll\n")
execute_process(
  COMMAND "${CMAKE_COMMAND}" ${verifier_arguments}
  RESULT_VARIABLE unexpected_result
  OUTPUT_VARIABLE unexpected_output
  ERROR_VARIABLE unexpected_error
  ENCODING UTF-8
)
set(unexpected_diagnostics "${unexpected_output}\n${unexpected_error}")
if(unexpected_result EQUAL 0)
  message(FATAL_ERROR
    "PE verifier accepted unexpected import libunexpected.dll")
endif()
if(NOT unexpected_diagnostics MATCHES "libunexpected\\.dll")
  message(FATAL_ERROR
    "PE verifier rejected the mutation without naming libunexpected.dll\n"
    "${unexpected_diagnostics}")
endif()

message(STATUS "Exact PE import contract rejected libunexpected.dll")
