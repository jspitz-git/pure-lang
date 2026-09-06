cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS SOURCE_DIR BINARY_DIR TEST_ROOT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

set(fake_readobj "${TEST_ROOT}/fake-llvm-readobj.cmd")
file(REMOVE_RECURSE "${TEST_ROOT}")
file(MAKE_DIRECTORY "${TEST_ROOT}")
file(WRITE "${fake_readobj}" "@echo off\r\n"
  "set module=%~nx3\r\n"
  "echo Format: COFF-x86-64\r\n"
  "echo Machine: IMAGE_FILE_MACHINE_AMD64\r\n"
  "echo Name: libpure.dll\r\n"
  "echo Name: libc++.dll\r\n"
  "echo Name: KERNEL32.dll\r\n"
  "echo Name: api-ms-win-crt-private-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-runtime-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-stdio-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-string-l1-1-0.dll\r\n"
  "if /I not \"%module%\"==\"stlalgorithm.dll\" echo Name: api-ms-win-crt-heap-l1-1-0.dll\r\n"
  "if /I \"%module%\"==\"stlvec.dll\" echo Name: stlbase.dll\r\n"
  "if /I \"%module%\"==\"stlalgorithm.dll\" echo Name: api-ms-win-crt-utility-l1-1-0.dll\r\n"
  "if /I \"%module%\"==\"stlalgorithm.dll\" echo Name: stlbase.dll\r\n"
  "if /I \"%module%\"==\"stlalgorithm.dll\" echo Name: stlvec.dll\r\n"
  "if /I \"%module%\"==\"stlmap.dll\" echo Name: stlbase.dll\r\n"
  "if /I \"%module%\"==\"stlmmap.dll\" echo Name: stlbase.dll\r\n"
  "if /I \"%module%\"==\"stlhmap.dll\" echo Name: api-ms-win-crt-math-l1-1-0.dll\r\n"
  "if /I \"%module%\"==\"stlhmap.dll\" echo Name: stlbase.dll\r\n"
  "echo Name: unexpected-audit.dll\r\n")

foreach(module IN ITEMS stlbase stlvec stlalgorithm stlmap stlmmap stlhmap)
  file(WRITE "${TEST_ROOT}/${module}.dll" "fixture")
  string(TOUPPER "${module}" upper)
  set("${upper}_DLL" "${TEST_ROOT}/${module}.dll")
endforeach()

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DLLVM_READOBJ=${fake_readobj}"
    "-DSTLBASE_DLL=${STLBASE_DLL}"
    "-DSTLVEC_DLL=${STLVEC_DLL}"
    "-DSTLALGORITHM_DLL=${STLALGORITHM_DLL}"
    "-DSTLMAP_DLL=${STLMAP_DLL}"
    "-DSTLMMAP_DLL=${STLMMAP_DLL}"
    "-DSTLHMAP_DLL=${STLHMAP_DLL}"
    -P "${SOURCE_DIR}/cmake/VerifyWindowsRuntime.cmake"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
)
if(result EQUAL 0)
  message(FATAL_ERROR
    "The runtime verifier accepted an unexpected DLL import:\n${output}${error}")
endif()
if(NOT "${output}\n${error}" MATCHES "imports differ" OR
    NOT "${output}\n${error}" MATCHES "unexpected-audit\\.dll")
  message(FATAL_ERROR
    "The verifier failed for the wrong reason:\n${output}${error}")
endif()
