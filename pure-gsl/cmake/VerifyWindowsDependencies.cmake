foreach(required IN ITEMS LLVM_READOBJ GSL_MODULE GSL_DLL GSLCBLAS_DLL)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

function(read_imports module output_var)
  execute_process(
    COMMAND "${LLVM_READOBJ}" --file-headers --coff-imports "${module}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8
  )
  if(NOT result EQUAL 0)
    message(FATAL_ERROR
      "Unable to inspect ${module} (${result})\nstdout:\n${output}\nstderr:\n${error}")
  endif()
  set(${output_var} "${output}" PARENT_SCOPE)
endfunction()

function(require_exact_imports module)
  read_imports("${module}" imports)
  if(NOT imports MATCHES "Format: COFF-x86-64" OR
      NOT imports MATCHES "Machine: IMAGE_FILE_MACHINE_AMD64")
    message(FATAL_ERROR "${module} is not an AMD64 PE image")
  endif()
  string(REGEX MATCHALL "Name: [^\r\n]+" lines "${imports}")
  set(actual)
  foreach(line IN LISTS lines)
    string(REPLACE "Name: " "" name "${line}")
    if(name MATCHES "\\.dll$")
      string(TOLOWER "${name}" name)
      list(APPEND actual "${name}")
    endif()
  endforeach()
  set(expected ${ARGN})
  list(REMOVE_DUPLICATES actual)
  list(SORT actual)
  list(SORT expected)
  if(NOT actual STREQUAL expected)
    message(FATAL_ERROR
      "${module} imports differ. Expected '${expected}', got '${actual}'")
  endif()
endfunction()

foreach(module IN ITEMS "${GSL_MODULE}" "${GSL_DLL}" "${GSLCBLAS_DLL}")
  if(NOT EXISTS "${module}")
    message(FATAL_ERROR "Dependency does not exist: ${module}")
  endif()
  read_imports("${module}" imports)
  if(imports MATCHES
      "Name: (msys-2\\.0|libgcc[^.]*|libstdc\\+\\+[^.]*)\\.dll")
    message(FATAL_ERROR "${module} imports an incompatible MSYS/GNU runtime")
  endif()
endforeach()

set(base_crt api-ms-win-crt-heap-l1-1-0.dll
  api-ms-win-crt-private-l1-1-0.dll api-ms-win-crt-runtime-l1-1-0.dll
  api-ms-win-crt-stdio-l1-1-0.dll api-ms-win-crt-string-l1-1-0.dll kernel32.dll)
set(full_crt ${base_crt} api-ms-win-crt-convert-l1-1-0.dll
  api-ms-win-crt-environment-l1-1-0.dll api-ms-win-crt-filesystem-l1-1-0.dll
  api-ms-win-crt-locale-l1-1-0.dll api-ms-win-crt-math-l1-1-0.dll
  api-ms-win-crt-time-l1-1-0.dll api-ms-win-crt-utility-l1-1-0.dll)
require_exact_imports("${GSL_MODULE}"
  api-ms-win-crt-math-l1-1-0.dll api-ms-win-crt-private-l1-1-0.dll
  api-ms-win-crt-runtime-l1-1-0.dll api-ms-win-crt-stdio-l1-1-0.dll
  api-ms-win-crt-string-l1-1-0.dll kernel32.dll libgsl-28.dll libpure.dll)
require_exact_imports("${GSL_DLL}" ${full_crt} libgslcblas-0.dll)
require_exact_imports("${GSLCBLAS_DLL}" ${full_crt})

message(STATUS
  "Verified pure-gsl PE dependencies: libpure, GSL 2.8, CBLAS, and UCRT")
