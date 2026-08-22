cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS FFI_DLL LIBFFI_DLL LLVM_READOBJ_EXECUTABLE)
  if(NOT DEFINED ${required} OR NOT EXISTS "${${required}}")
    message(FATAL_ERROR "${required} must name an existing file")
  endif()
endforeach()

function(read_pe file output_var option)
  execute_process(COMMAND "${LLVM_READOBJ_EXECUTABLE}" "${option}" "${file}"
    RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
  if(NOT result EQUAL 0)
    message(FATAL_ERROR "llvm-readobj ${option} failed:\n${output}${error}")
  endif()
  set(${output_var} "${output}" PARENT_SCOPE)
endfunction()

foreach(pe IN ITEMS "${FFI_DLL}" "${LIBFFI_DLL}")
  read_pe("${pe}" headers --file-headers)
  if(NOT headers MATCHES "Format: COFF-x86-64" OR
      NOT headers MATCHES "Machine: IMAGE_FILE_MACHINE_AMD64")
    message(FATAL_ERROR "${pe} is not an AMD64 PE image:\n${headers}")
  endif()
endforeach()

read_pe("${FFI_DLL}" exports --coff-exports)
string(REGEX MATCHALL "Name: ffi_[A-Za-z0-9_]+" export_lines "${exports}")
list(TRANSFORM export_lines REPLACE "Name: " "")
list(SORT export_lines)
set(expected_exports
  ffi_closure_addr ffi_copy_struct ffi_defs ffi_fcall ffi_free_cif
  ffi_free_closure ffi_free_struct ffi_free_struct_t ffi_new_cif
  ffi_new_closure ffi_new_struct ffi_new_struct_t ffi_put_struct_member
  ffi_struct_member ffi_struct_members ffi_struct_offsetof ffi_struct_pointer
  ffi_struct_pointers ffi_struct_type ffi_type_double_ptr ffi_type_float_ptr
  ffi_type_info ffi_type_longdouble_ptr ffi_type_pointer_ptr ffi_type_schar_ptr
  ffi_type_sint16_ptr ffi_type_sint32_ptr ffi_type_sint64_ptr ffi_type_sint8_ptr
  ffi_type_sint_ptr ffi_type_slong_ptr ffi_type_sshort_ptr ffi_type_string
  ffi_type_string_ptr ffi_type_uchar_ptr ffi_type_uint16_ptr ffi_type_uint32_ptr
  ffi_type_uint64_ptr ffi_type_uint8_ptr ffi_type_uint_ptr ffi_type_ulong_ptr
  ffi_type_ushort_ptr ffi_type_void_ptr ffi_typevect)
list(SORT expected_exports)
if(NOT export_lines STREQUAL expected_exports)
  message(FATAL_ERROR
    "Unexpected ffi.dll exports. Expected '${expected_exports}', got '${export_lines}'")
endif()

function(check_imports file expected)
  read_pe("${file}" imports --coff-imports)
  string(REGEX MATCHALL "Name: [^\r\n]+" import_lines "${imports}")
  list(TRANSFORM import_lines REPLACE "Name: " "")
  list(TRANSFORM import_lines TOLOWER)
  list(SORT import_lines)
  set(expected_imports ${expected})
  list(SORT expected_imports)
  if(NOT import_lines STREQUAL expected_imports)
    message(FATAL_ERROR
      "Unexpected imports for ${file}. Expected '${expected_imports}', got '${import_lines}'")
  endif()
endfunction()

set(ffi_imports
  api-ms-win-crt-heap-l1-1-0.dll api-ms-win-crt-private-l1-1-0.dll
  api-ms-win-crt-runtime-l1-1-0.dll api-ms-win-crt-stdio-l1-1-0.dll
  api-ms-win-crt-string-l1-1-0.dll kernel32.dll libffi-8.dll libgmp-10.dll
  libpure.dll)
check_imports("${FFI_DLL}" "${ffi_imports}")
set(libffi_imports
  api-ms-win-crt-heap-l1-1-0.dll api-ms-win-crt-private-l1-1-0.dll
  api-ms-win-crt-runtime-l1-1-0.dll api-ms-win-crt-stdio-l1-1-0.dll
  api-ms-win-crt-string-l1-1-0.dll api-ms-win-crt-utility-l1-1-0.dll kernel32.dll)
check_imports("${LIBFFI_DLL}" "${libffi_imports}")
