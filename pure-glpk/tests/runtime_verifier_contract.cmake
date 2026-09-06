foreach(required IN ITEMS SOURCE_DIR TEST_ROOT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH SOURCE_DIR NORMALIZE OUTPUT_VARIABLE source_dir)
cmake_path(ABSOLUTE_PATH TEST_ROOT NORMALIZE OUTPUT_VARIABLE test_root)
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
api-ms-win-crt-heap-l1-1-0.dll
api-ms-win-crt-locale-l1-1-0.dll
api-ms-win-crt-private-l1-1-0.dll
api-ms-win-crt-runtime-l1-1-0.dll
api-ms-win-crt-stdio-l1-1-0.dll
api-ms-win-crt-string-l1-1-0.dll
kernel32.dll
libglpk-40.dll
libgmp-10.dll
libpure.dll
]=])
file(WRITE "${test_root}/libglpk-40.dll.imports" [=[
api-ms-win-crt-convert-l1-1-0.dll
api-ms-win-crt-filesystem-l1-1-0.dll
api-ms-win-crt-heap-l1-1-0.dll
api-ms-win-crt-locale-l1-1-0.dll
api-ms-win-crt-math-l1-1-0.dll
api-ms-win-crt-private-l1-1-0.dll
api-ms-win-crt-runtime-l1-1-0.dll
api-ms-win-crt-stdio-l1-1-0.dll
api-ms-win-crt-string-l1-1-0.dll
api-ms-win-crt-time-l1-1-0.dll
api-ms-win-crt-utility-l1-1-0.dll
kernel32.dll
libamd.dll
libcolamd.dll
libgmp-10.dll
zlib1.dll
]=])
file(WRITE "${test_root}/libcolamd.dll.imports" [=[
api-ms-win-crt-heap-l1-1-0.dll
api-ms-win-crt-private-l1-1-0.dll
api-ms-win-crt-runtime-l1-1-0.dll
api-ms-win-crt-stdio-l1-1-0.dll
api-ms-win-crt-string-l1-1-0.dll
api-ms-win-crt-utility-l1-1-0.dll
kernel32.dll
libsuitesparseconfig.dll
]=])
file(WRITE "${test_root}/libamd.dll.imports" [=[
api-ms-win-crt-heap-l1-1-0.dll
api-ms-win-crt-math-l1-1-0.dll
api-ms-win-crt-private-l1-1-0.dll
api-ms-win-crt-runtime-l1-1-0.dll
api-ms-win-crt-stdio-l1-1-0.dll
api-ms-win-crt-string-l1-1-0.dll
kernel32.dll
libsuitesparseconfig.dll
]=])
file(WRITE "${test_root}/libsuitesparseconfig.dll.imports" [=[
api-ms-win-crt-convert-l1-1-0.dll
api-ms-win-crt-filesystem-l1-1-0.dll
api-ms-win-crt-heap-l1-1-0.dll
api-ms-win-crt-locale-l1-1-0.dll
api-ms-win-crt-math-l1-1-0.dll
api-ms-win-crt-private-l1-1-0.dll
api-ms-win-crt-runtime-l1-1-0.dll
api-ms-win-crt-stdio-l1-1-0.dll
api-ms-win-crt-string-l1-1-0.dll
kernel32.dll
libomp.dll
]=])
file(WRITE "${test_root}/libomp.dll.imports" [=[
api-ms-win-crt-convert-l1-1-0.dll
api-ms-win-crt-environment-l1-1-0.dll
api-ms-win-crt-filesystem-l1-1-0.dll
api-ms-win-crt-heap-l1-1-0.dll
api-ms-win-crt-locale-l1-1-0.dll
api-ms-win-crt-private-l1-1-0.dll
api-ms-win-crt-runtime-l1-1-0.dll
api-ms-win-crt-stdio-l1-1-0.dll
api-ms-win-crt-string-l1-1-0.dll
api-ms-win-crt-utility-l1-1-0.dll
kernel32.dll
]=])
file(WRITE "${test_root}/libgmp-10.dll.imports" [=[
api-ms-win-crt-convert-l1-1-0.dll
api-ms-win-crt-environment-l1-1-0.dll
api-ms-win-crt-filesystem-l1-1-0.dll
api-ms-win-crt-heap-l1-1-0.dll
api-ms-win-crt-locale-l1-1-0.dll
api-ms-win-crt-private-l1-1-0.dll
api-ms-win-crt-runtime-l1-1-0.dll
api-ms-win-crt-stdio-l1-1-0.dll
api-ms-win-crt-string-l1-1-0.dll
api-ms-win-crt-time-l1-1-0.dll
api-ms-win-crt-utility-l1-1-0.dll
kernel32.dll
]=])
file(WRITE "${test_root}/zlib1.dll.imports" [=[
api-ms-win-crt-convert-l1-1-0.dll
api-ms-win-crt-heap-l1-1-0.dll
api-ms-win-crt-locale-l1-1-0.dll
api-ms-win-crt-private-l1-1-0.dll
api-ms-win-crt-runtime-l1-1-0.dll
api-ms-win-crt-stdio-l1-1-0.dll
api-ms-win-crt-string-l1-1-0.dll
api-ms-win-crt-utility-l1-1-0.dll
kernel32.dll
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
