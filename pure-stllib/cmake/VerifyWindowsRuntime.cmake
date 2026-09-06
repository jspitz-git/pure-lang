foreach(required IN ITEMS
    LLVM_READOBJ
    STLBASE_DLL
    STLVEC_DLL
    STLALGORITHM_DLL
    STLMAP_DLL
    STLMMAP_DLL
    STLHMAP_DLL)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

set(modules
  "${STLBASE_DLL}"
  "${STLVEC_DLL}"
  "${STLALGORITHM_DLL}"
  "${STLMAP_DLL}"
  "${STLMMAP_DLL}"
  "${STLHMAP_DLL}"
)

function(read_pe module output_var)
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
  read_pe("${module}" pe)
  if(NOT pe MATCHES "Format: COFF-x86-64" OR
      NOT pe MATCHES "Machine: IMAGE_FILE_MACHINE_AMD64")
    message(FATAL_ERROR "${module} is not an AMD64 PE image")
  endif()
  string(REGEX MATCHALL "Name: [^\r\n]+" name_lines "${pe}")
  set(imports)
  foreach(line IN LISTS name_lines)
    string(REPLACE "Name: " "" name "${line}")
    if(name MATCHES "\\.dll$")
      string(TOLOWER "${name}" name)
      list(APPEND imports "${name}")
    endif()
  endforeach()
  set(expected ${ARGN})
  list(REMOVE_DUPLICATES imports)
  list(SORT imports)
  list(SORT expected)
  if(NOT imports STREQUAL expected)
    message(FATAL_ERROR
      "${module} imports differ. Expected '${expected}', got '${imports}'")
  endif()
endfunction()

foreach(module IN LISTS modules)
  if(NOT EXISTS "${module}")
    message(FATAL_ERROR "Module does not exist: ${module}")
  endif()
endforeach()

set(common_imports
  api-ms-win-crt-private-l1-1-0.dll
  api-ms-win-crt-runtime-l1-1-0.dll
  api-ms-win-crt-stdio-l1-1-0.dll
  api-ms-win-crt-string-l1-1-0.dll
  kernel32.dll
  libc++.dll
  libpure.dll
)
require_exact_imports("${STLBASE_DLL}" ${common_imports}
  api-ms-win-crt-heap-l1-1-0.dll)
require_exact_imports("${STLVEC_DLL}" ${common_imports}
  api-ms-win-crt-heap-l1-1-0.dll stlbase.dll)
require_exact_imports("${STLALGORITHM_DLL}" ${common_imports}
  api-ms-win-crt-utility-l1-1-0.dll stlbase.dll stlvec.dll)
require_exact_imports("${STLMAP_DLL}" ${common_imports}
  api-ms-win-crt-heap-l1-1-0.dll stlbase.dll)
require_exact_imports("${STLMMAP_DLL}" ${common_imports}
  api-ms-win-crt-heap-l1-1-0.dll stlbase.dll)
require_exact_imports("${STLHMAP_DLL}" ${common_imports}
  api-ms-win-crt-heap-l1-1-0.dll api-ms-win-crt-math-l1-1-0.dll stlbase.dll)

message(STATUS
  "Verified exact pure-stllib AMD64 PE import contracts")
