if(NOT DEFINED CMAKE_COMMAND OR "${CMAKE_COMMAND}" STREQUAL "")
  message(FATAL_ERROR "CMAKE_COMMAND is required")
endif()
if(NOT DEFINED VERIFIER OR "${VERIFIER}" STREQUAL "")
  message(FATAL_ERROR "VERIFIER is required")
endif()
if(NOT DEFINED TEST_ROOT OR "${TEST_ROOT}" STREQUAL "")
  message(FATAL_ERROR "TEST_ROOT is required")
endif()

file(MAKE_DIRECTORY "${TEST_ROOT}")
set(module "${TEST_ROOT}/fastcgi.dll")
file(WRITE "${module}" "fixture")

function(write_readobj path imports exports)
  file(WRITE "${path}" "@echo off\r\n")
  file(APPEND "${path}" "if /I \"%~1\"==\"--coff-imports\" (\r\n")
  file(APPEND "${path}" "  echo File: %~2\r\n")
  file(APPEND "${path}" "  echo Format: COFF-x86-64\r\n")
  file(APPEND "${path}" "  echo Arch: x86_64\r\n")
  file(APPEND "${path}" "  echo AddressSize: 64bit\r\n")
  foreach(import IN LISTS imports)
    file(APPEND "${path}" "  echo Import {\r\n")
    file(APPEND "${path}" "  echo   Name: ${import}\r\n")
    file(APPEND "${path}" "  echo }\r\n")
  endforeach()
  file(APPEND "${path}" "  exit /b 0\r\n)\r\n")
  file(APPEND "${path}" "if /I \"%~1\"==\"--coff-exports\" (\r\n")
  foreach(export IN LISTS exports)
    file(APPEND "${path}" "  echo Name: ${export}\r\n")
  endforeach()
  file(APPEND "${path}" "  exit /b 0\r\n)\r\n")
  file(APPEND "${path}" "exit /b 1\r\n")
endfunction()

function(expect_malformed_import_output name body expected_error)
  set(readobj "${TEST_ROOT}/${name}-readobj.cmd")
  file(WRITE "${readobj}" "@echo off\r\n")
  file(APPEND "${readobj}" "if /I \"%~1\"==\"--coff-imports\" (\r\n")
  if(NOT body STREQUAL "")
    file(APPEND "${readobj}" "${body}")
  endif()
  file(APPEND "${readobj}" "  exit /b 0\r\n)\r\n")
  file(APPEND "${readobj}" "if /I \"%~1\"==\"--coff-exports\" (\r\n")
  foreach(export IN ITEMS FCGI_Accept FCGI_Finish fastcgi_defs fastcgi_to_file)
    file(APPEND "${readobj}" "  echo Name: ${export}\r\n")
  endforeach()
  file(APPEND "${readobj}" "  exit /b 0\r\n)\r\n")
  file(APPEND "${readobj}" "exit /b 1\r\n")
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DLLVM_READOBJ=${readobj}"
      "-DMODULE=${module}"
      -P "${VERIFIER}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error)
  if(result EQUAL 0)
    message(FATAL_ERROR "${name} fixture was accepted")
  endif()
  if(NOT error MATCHES "${expected_error}")
    message(FATAL_ERROR "${name} fixture failed unexpectedly: ${output}${error}")
  endif()
endfunction()

function(expect_rejected name imports exports expected_error)
  set(readobj "${TEST_ROOT}/${name}-readobj.cmd")
  write_readobj("${readobj}" "${imports}" "${exports}")
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DLLVM_READOBJ=${readobj}"
      "-DMODULE=${module}"
      -P "${VERIFIER}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error)
  if(result EQUAL 0)
    message(FATAL_ERROR "${name} fixture was accepted")
  endif()
  if(NOT error MATCHES "${expected_error}")
    message(FATAL_ERROR "${name} fixture failed unexpectedly: ${output}${error}")
  endif()
endfunction()

function(expect_accepted name imports exports)
  set(readobj "${TEST_ROOT}/${name}-readobj.cmd")
  write_readobj("${readobj}" "${imports}" "${exports}")
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DLLVM_READOBJ=${readobj}"
      "-DMODULE=${module}"
      -P "${VERIFIER}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error)
  if(NOT result EQUAL 0)
    message(FATAL_ERROR "${name} fixture was rejected: ${output}${error}")
  endif()
endfunction()

set(exact_exports "FCGI_Accept;FCGI_Finish;fastcgi_defs;fastcgi_to_file")
expect_accepted(zero-import-pe "" "${exact_exports}")
expect_rejected(
  bare-fcgi
  "fcgi.dll"
  "${exact_exports}"
  "dynamic FastCGI dependency is forbidden")
expect_rejected(
  near-match-symbols
  "kernel32.dll"
  "FCGI_Accept_extra;FCGI_Finish_extra;fastcgi_defs_extra;fastcgi_to_file_extra"
  "required symbol is not exported: FCGI_Accept")
expect_malformed_import_output(
  empty-import-output "" "llvm-readobj imports output is malformed")
expect_malformed_import_output(
  truncated-import-block
  "  echo File: %~2\r\n  echo Format: COFF-x86-64\r\n  echo Arch: x86_64\r\n  echo AddressSize: 64bit\r\n  echo Import {\r\n  echo   Symbol: truncated (0)\r\n"
  "llvm-readobj imports output is malformed")
