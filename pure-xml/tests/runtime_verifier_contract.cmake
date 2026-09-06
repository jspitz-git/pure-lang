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
  "if \"%module%\"==\"\" set module=%~nx2\r\n"
  "echo Format: COFF-x86-64\r\n"
  "echo Machine: IMAGE_FILE_MACHINE_AMD64\r\n"
  "echo Name: KERNEL32.dll\r\n"
  "if /I \"%module%\"==\"xml.dll\" goto xml\r\n"
  "if /I \"%module%\"==\"libxml2-16.dll\" goto libxml2\r\n"
  "if /I \"%module%\"==\"libxslt-1.dll\" goto libxslt\r\n"
  "if /I \"%module%\"==\"libiconv-2.dll\" goto iconv\r\n"
  "if /I \"%module%\"==\"zlib1.dll\" goto zlib\r\n"
  ":xml\r\n"
  "echo Name: libpure.dll\r\n"
  "echo Name: libxslt-1.dll\r\n"
  "echo Name: libxml2-16.dll\r\n"
  "echo Name: api-ms-win-crt-runtime-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-heap-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-private-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-string-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-stdio-l1-1-0.dll\r\n"
  "goto unexpected\r\n"
  ":libxml2\r\n"
  "echo Name: zlib1.dll\r\n"
  "echo Name: libiconv-2.dll\r\n"
  "echo Name: bcrypt.dll\r\n"
  "echo Name: api-ms-win-crt-stdio-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-runtime-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-filesystem-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-string-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-utility-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-heap-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-math-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-environment-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-private-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-convert-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-locale-l1-1-0.dll\r\n"
  "goto unexpected\r\n"
  ":libxslt\r\n"
  "echo Name: libxml2-16.dll\r\n"
  "echo Name: api-ms-win-crt-stdio-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-runtime-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-filesystem-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-math-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-environment-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-private-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-string-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-utility-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-heap-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-locale-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-convert-l1-1-0.dll\r\n"
  "goto unexpected\r\n"
  ":iconv\r\n"
  "echo Name: api-ms-win-crt-runtime-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-locale-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-heap-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-private-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-utility-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-string-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-stdio-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-convert-l1-1-0.dll\r\n"
  "goto unexpected\r\n"
  ":zlib\r\n"
  "echo Name: api-ms-win-crt-runtime-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-stdio-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-convert-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-heap-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-private-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-string-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-utility-l1-1-0.dll\r\n"
  "echo Name: api-ms-win-crt-locale-l1-1-0.dll\r\n"
  ":unexpected\r\n"
  "echo Name: unexpected-audit.dll\r\n")

foreach(module IN ITEMS xml libxml2-16 libxslt-1 libiconv-2 zlib1)
  file(WRITE "${TEST_ROOT}/${module}.dll" "fixture")
endforeach()
execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DLLVM_READOBJ=${fake_readobj}"
    "-DXML_DLL=${TEST_ROOT}/xml.dll"
    "-DLIBXML2_DLL=${TEST_ROOT}/libxml2-16.dll"
    "-DLIBXSLT_DLL=${TEST_ROOT}/libxslt-1.dll"
    "-DLIBICONV_DLL=${TEST_ROOT}/libiconv-2.dll"
    "-DZLIB_DLL=${TEST_ROOT}/zlib1.dll"
    -P "${SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
)
if(result EQUAL 0)
  message(FATAL_ERROR "PE verifier accepted unexpected-audit.dll")
endif()
if(NOT "${output}\n${error}" MATCHES "imports differ" OR
    NOT "${output}\n${error}" MATCHES "unexpected-audit\\.dll")
  message(FATAL_ERROR
    "PE verifier failed for the wrong reason:\n${output}${error}")
endif()
