foreach(required IN ITEMS
    LLVM_READOBJ GLPK_MODULE GLPK_DLL COLAMD_DLL AMD_DLL
    SUITESPARSECONFIG_DLL OMP_DLL GMP_DLL ZLIB_DLL)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
  cmake_path(ABSOLUTE_PATH ${required} NORMALIZE OUTPUT_VARIABLE normalized)
  set(${required} "${normalized}")
  if(NOT EXISTS "${${required}}" OR IS_DIRECTORY "${${required}}")
    message(FATAL_ERROR "${required} must be an existing file: ${${required}}")
  endif()
endforeach()

set(glpk_module_expected
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
)
set(glpk_dll_expected
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
)
set(colamd_dll_expected
  api-ms-win-crt-heap-l1-1-0.dll
  api-ms-win-crt-private-l1-1-0.dll
  api-ms-win-crt-runtime-l1-1-0.dll
  api-ms-win-crt-stdio-l1-1-0.dll
  api-ms-win-crt-string-l1-1-0.dll
  api-ms-win-crt-utility-l1-1-0.dll
  kernel32.dll
  libsuitesparseconfig.dll
)
set(amd_dll_expected
  api-ms-win-crt-heap-l1-1-0.dll
  api-ms-win-crt-math-l1-1-0.dll
  api-ms-win-crt-private-l1-1-0.dll
  api-ms-win-crt-runtime-l1-1-0.dll
  api-ms-win-crt-stdio-l1-1-0.dll
  api-ms-win-crt-string-l1-1-0.dll
  kernel32.dll
  libsuitesparseconfig.dll
)
set(suitesparseconfig_dll_expected
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
)
set(omp_dll_expected
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
)
set(gmp_dll_expected
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
)
set(zlib_dll_expected
  api-ms-win-crt-convert-l1-1-0.dll
  api-ms-win-crt-heap-l1-1-0.dll
  api-ms-win-crt-locale-l1-1-0.dll
  api-ms-win-crt-private-l1-1-0.dll
  api-ms-win-crt-runtime-l1-1-0.dll
  api-ms-win-crt-stdio-l1-1-0.dll
  api-ms-win-crt-string-l1-1-0.dll
  api-ms-win-crt-utility-l1-1-0.dll
  kernel32.dll
)

function(verify_imports module expected_variable)
  execute_process(
    COMMAND "${LLVM_READOBJ}" --coff-imports "${module}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8
  )
  if(NOT result EQUAL 0)
    message(FATAL_ERROR
      "Unable to inspect ${module} (${result})\n"
      "stdout:\n${output}\nstderr:\n${error}")
  endif()

  string(REGEX MATCHALL "Name: [^\r\n]+" import_lines "${output}")
  set(actual)
  foreach(line IN LISTS import_lines)
    string(REGEX REPLACE "^Name: " "" name "${line}")
    string(TOLOWER "${name}" name)
    list(APPEND actual "${name}")
  endforeach()
  list(SORT actual)
  set(expected "${${expected_variable}}")

  if(NOT actual STREQUAL expected)
    set(missing "${expected}")
    foreach(name IN LISTS actual)
      list(REMOVE_ITEM missing "${name}")
    endforeach()
    set(unexpected "${actual}")
    foreach(name IN LISTS expected)
      list(REMOVE_ITEM unexpected "${name}")
    endforeach()
    message(FATAL_ERROR
      "${module} import mismatch\n"
      "expected: ${expected}\n"
      "actual: ${actual}\n"
      "missing: ${missing}\n"
      "unexpected: ${unexpected}")
  endif()
endfunction()

verify_imports("${GLPK_MODULE}" glpk_module_expected)
verify_imports("${GLPK_DLL}" glpk_dll_expected)
verify_imports("${COLAMD_DLL}" colamd_dll_expected)
verify_imports("${AMD_DLL}" amd_dll_expected)
verify_imports("${SUITESPARSECONFIG_DLL}" suitesparseconfig_dll_expected)
verify_imports("${OMP_DLL}" omp_dll_expected)
verify_imports("${GMP_DLL}" gmp_dll_expected)
verify_imports("${ZLIB_DLL}" zlib_dll_expected)

message(STATUS "Verified exact pure-glpk PE imports for 8 AMD64 binaries")
