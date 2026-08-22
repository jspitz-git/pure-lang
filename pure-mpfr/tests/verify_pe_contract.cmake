cmake_minimum_required(VERSION 3.25)
foreach(required IN ITEMS MPFR_DLL LLVM_READOBJ_EXECUTABLE)
  if(NOT DEFINED ${required} OR NOT EXISTS "${${required}}")
    message(FATAL_ERROR "${required} must name an existing file")
  endif()
endforeach()
function(read_pe output_var option)
  execute_process(COMMAND "${LLVM_READOBJ_EXECUTABLE}" "${option}" "${MPFR_DLL}"
    RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
  if(NOT result EQUAL 0)
    message(FATAL_ERROR "llvm-readobj ${option} failed:\n${output}${error}")
  endif()
  set(${output_var} "${output}" PARENT_SCOPE)
endfunction()
read_pe(headers --file-headers)
if(NOT headers MATCHES "Format: COFF-x86-64" OR
    NOT headers MATCHES "Machine: IMAGE_FILE_MACHINE_AMD64")
  message(FATAL_ERROR "mpfr.dll is not AMD64:\n${headers}")
endif()
read_pe(exports --coff-exports)
string(REGEX MATCHALL "Name: [A-Za-z0-9_]+_mpfr|Name: mpfr_[A-Za-z0-9_]+" lines "${exports}")
list(TRANSFORM lines REPLACE "Name: " "")
list(SORT lines)
set(expected_exports
  acos_mpfr acosh_mpfr add_mpfr asin_mpfr asinh_mpfr atan2_mpfr atan_mpfr
  atanh_mpfr ceil_mpfr cos_mpfr cosh_mpfr div_mpfr exp_mpfr floor_mpfr
  ln_mpfr log_mpfr mpfr_free mpfr_from_bigint mpfr_from_double mpfr_from_mpfr
  mpfr_from_str mpfr_get_print_prec mpfr_set_print_prec mpfr_tag mpfr_to_bigint
  mpfr_to_double mpfr_to_int mul_mpfr neg_mpfr pow_mpfr round_mpfr sin_mpfr
  sinh_mpfr sqrt_mpfr sub_mpfr tan_mpfr tanh_mpfr trunc_mpfr)
list(SORT expected_exports)
if(NOT lines STREQUAL expected_exports)
  message(FATAL_ERROR "Unexpected mpfr.dll exports. Expected '${expected_exports}', got '${lines}'")
endif()
read_pe(imports --coff-imports)
string(REGEX MATCHALL "Name: [^\r\n]+" lines "${imports}")
list(TRANSFORM lines REPLACE "Name: " "")
list(TRANSFORM lines TOLOWER)
list(SORT lines)
set(expected_imports
  api-ms-win-crt-heap-l1-1-0.dll api-ms-win-crt-math-l1-1-0.dll
  api-ms-win-crt-private-l1-1-0.dll api-ms-win-crt-runtime-l1-1-0.dll
  api-ms-win-crt-stdio-l1-1-0.dll api-ms-win-crt-string-l1-1-0.dll
  kernel32.dll libgmp-10.dll libmpfr-6.dll libpure.dll)
list(SORT expected_imports)
if(NOT lines STREQUAL expected_imports)
  message(FATAL_ERROR "Unexpected mpfr.dll imports. Expected '${expected_imports}', got '${lines}'")
endif()
