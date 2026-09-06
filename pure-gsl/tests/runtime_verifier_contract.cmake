cmake_minimum_required(VERSION 3.25)
foreach(required IN ITEMS SOURCE_DIR TEST_ROOT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()
file(REMOVE_RECURSE "${TEST_ROOT}")
file(MAKE_DIRECTORY "${TEST_ROOT}")
set(fake "${TEST_ROOT}/readobj.cmd")
file(WRITE "${fake}" "@echo off\r\nset module=%~nx3\r\n"
  "if \"%module%\"==\"\" set module=%~nx2\r\n"
  "echo Format: COFF-x86-64\r\n"
  "echo Machine: IMAGE_FILE_MACHINE_AMD64\r\n"
  "echo Name: KERNEL32.dll\r\n"
  "if /I \"%module%\"==\"gsl.dll\" echo Name: libpure.dll\r\n"
  "if /I \"%module%\"==\"gsl.dll\" echo Name: libgsl-28.dll\r\n"
  "if /I \"%module%\"==\"libgsl-28.dll\" echo Name: libgslcblas-0.dll\r\n"
  "echo Name: unexpected-audit.dll\r\n")
foreach(name IN ITEMS gsl libgsl-28 libgslcblas-0)
  file(WRITE "${TEST_ROOT}/${name}.dll" "fixture")
endforeach()
execute_process(COMMAND "${CMAKE_COMMAND}"
  "-DLLVM_READOBJ=${fake}" "-DGSL_MODULE=${TEST_ROOT}/gsl.dll"
  "-DGSL_DLL=${TEST_ROOT}/libgsl-28.dll"
  "-DGSLCBLAS_DLL=${TEST_ROOT}/libgslcblas-0.dll"
  -P "${SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
  RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
if(result EQUAL 0)
  message(FATAL_ERROR "PE verifier accepted an unexpected import")
endif()
if(NOT "${output}\n${error}" MATCHES "unexpected-audit\\.dll")
  message(FATAL_ERROR "PE verifier failed for the wrong reason:\n${output}${error}")
endif()
