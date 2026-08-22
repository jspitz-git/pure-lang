cmake_minimum_required(VERSION 3.25)
foreach(required IN ITEMS SQL3_DLL SQLITE_DLL LLVM_READOBJ_EXECUTABLE)
  if(NOT DEFINED ${required} OR NOT EXISTS "${${required}}")
    message(FATAL_ERROR "${required} must name an existing file")
  endif()
endforeach()
function(read_pe file option out)
  execute_process(COMMAND "${LLVM_READOBJ_EXECUTABLE}" "${option}" "${file}"
    RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
  if(NOT result EQUAL 0)
    message(FATAL_ERROR "llvm-readobj failed for ${file}:\n${output}${error}")
  endif()
  set(${out} "${output}" PARENT_SCOPE)
endfunction()
foreach(file IN ITEMS "${SQL3_DLL}" "${SQLITE_DLL}")
  read_pe("${file}" --file-headers headers)
  if(NOT headers MATCHES "Format: COFF-x86-64" OR
      NOT headers MATCHES "Machine: IMAGE_FILE_MACHINE_AMD64")
    message(FATAL_ERROR "${file} is not an AMD64 PE image:\n${headers}")
  endif()
endforeach()
read_pe("${SQL3_DLL}" --coff-exports exports)
string(REGEX MATCHALL "Name: sql3util_[A-Za-z0-9_]+" names "${exports}")
list(TRANSFORM names REPLACE "Name: " "")
list(SORT names)
set(expected_exports sql3util_bind_blob sql3util_bind_text sql3util_bind_value
  sql3util_column_blob sql3util_column_key sql3util_column_value
  sql3util_create_function sql3util_open sql3util_prepare
  sql3util_result_value sql3util_value)
list(SORT expected_exports)
if(NOT names STREQUAL expected_exports)
  message(FATAL_ERROR "Unexpected sql3util exports: ${names}")
endif()
function(check_imports file expected)
  read_pe("${file}" --coff-imports imports)
  string(REGEX MATCHALL "Name: [^\r\n]+" names "${imports}")
  list(TRANSFORM names REPLACE "Name: " "")
  list(TRANSFORM names TOLOWER)
  list(SORT names)
  set(wanted ${expected})
  list(SORT wanted)
  if(NOT names STREQUAL wanted)
    message(FATAL_ERROR "Unexpected imports for ${file}. Expected '${wanted}', got '${names}'")
  endif()
endfunction()
set(sql3_imports api-ms-win-crt-heap-l1-1-0.dll
  api-ms-win-crt-private-l1-1-0.dll api-ms-win-crt-runtime-l1-1-0.dll
  api-ms-win-crt-stdio-l1-1-0.dll api-ms-win-crt-string-l1-1-0.dll
  kernel32.dll libgmp-10.dll libpure.dll libsqlite3-0.dll)
check_imports("${SQL3_DLL}" "${sql3_imports}")
set(sqlite_imports api-ms-win-crt-heap-l1-1-0.dll
  api-ms-win-crt-math-l1-1-0.dll api-ms-win-crt-private-l1-1-0.dll
  api-ms-win-crt-runtime-l1-1-0.dll api-ms-win-crt-stdio-l1-1-0.dll
  api-ms-win-crt-string-l1-1-0.dll api-ms-win-crt-time-l1-1-0.dll
  api-ms-win-crt-utility-l1-1-0.dll kernel32.dll)
check_imports("${SQLITE_DLL}" "${sqlite_imports}")
