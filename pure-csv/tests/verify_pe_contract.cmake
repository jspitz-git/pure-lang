cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS CSV_DLL LLVM_READOBJ_EXECUTABLE)
  if(NOT DEFINED ${required} OR NOT EXISTS "${${required}}")
    message(FATAL_ERROR "${required} must name an existing file")
  endif()
endforeach()

function(read_pe output_var option)
  execute_process(
    COMMAND "${LLVM_READOBJ_EXECUTABLE}" "${option}" "${CSV_DLL}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
  )
  if(NOT result EQUAL 0)
    message(FATAL_ERROR "llvm-readobj ${option} failed:\n${output}${error}")
  endif()
  set(${output_var} "${output}" PARENT_SCOPE)
endfunction()

read_pe(headers --file-headers)
if(NOT headers MATCHES "Format: COFF-x86-64" OR
    NOT headers MATCHES "Machine: IMAGE_FILE_MACHINE_AMD64")
  message(FATAL_ERROR "csv.dll is not an AMD64 PE image:\n${headers}")
endif()

read_pe(exports --coff-exports)
string(REGEX MATCHALL "Name: csv_[A-Za-z0-9_]+" export_lines "${exports}")
list(TRANSFORM export_lines REPLACE "Name: " "")
list(SORT export_lines)
set(expected_exports csv_close csv_getheader csv_open csv_read csv_write)
if(NOT export_lines STREQUAL expected_exports)
  message(FATAL_ERROR
    "Unexpected csv.dll exports. Expected '${expected_exports}', got "
    "'${export_lines}'")
endif()

read_pe(imports --coff-imports)
string(REGEX MATCHALL "Name: [^\r\n]+" import_lines "${imports}")
list(TRANSFORM import_lines REPLACE "Name: " "")
list(TRANSFORM import_lines TOLOWER)
list(SORT import_lines)
set(expected_imports
  api-ms-win-crt-convert-l1-1-0.dll
  api-ms-win-crt-heap-l1-1-0.dll
  api-ms-win-crt-private-l1-1-0.dll
  api-ms-win-crt-runtime-l1-1-0.dll
  api-ms-win-crt-stdio-l1-1-0.dll
  api-ms-win-crt-string-l1-1-0.dll
  kernel32.dll
  libpure.dll)
if(NOT import_lines STREQUAL expected_imports)
  message(FATAL_ERROR
    "Unexpected csv.dll imports. Expected '${expected_imports}', got "
    "'${import_lines}'")
endif()
