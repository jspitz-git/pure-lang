foreach(required IN ITEMS LLVM_READOBJ XML_DLL LIBXML2_DLL LIBXSLT_DLL
    LIBICONV_DLL ZLIB_DLL)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
  if(NOT EXISTS "${${required}}")
    message(FATAL_ERROR "${required} must name an existing file")
  endif()
endforeach()

function(require_exact_imports module)
  execute_process(
    COMMAND "${LLVM_READOBJ}" --file-headers --coff-imports "${module}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE pe
    ERROR_VARIABLE error
    ENCODING UTF-8
  )
  if(NOT result EQUAL 0)
    message(FATAL_ERROR
      "Unable to inspect ${module} (${result})\nstdout:\n${pe}\nstderr:\n${error}")
  endif()
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

set(base_crt
  api-ms-win-crt-heap-l1-1-0.dll
  api-ms-win-crt-private-l1-1-0.dll
  api-ms-win-crt-runtime-l1-1-0.dll
  api-ms-win-crt-stdio-l1-1-0.dll
  api-ms-win-crt-string-l1-1-0.dll
  kernel32.dll
)
set(full_crt ${base_crt}
  api-ms-win-crt-convert-l1-1-0.dll
  api-ms-win-crt-environment-l1-1-0.dll
  api-ms-win-crt-filesystem-l1-1-0.dll
  api-ms-win-crt-locale-l1-1-0.dll
  api-ms-win-crt-math-l1-1-0.dll
  api-ms-win-crt-utility-l1-1-0.dll
)
require_exact_imports("${XML_DLL}" ${base_crt}
  libpure.dll libxml2-16.dll libxslt-1.dll)
require_exact_imports("${LIBXML2_DLL}" ${full_crt}
  bcrypt.dll libiconv-2.dll zlib1.dll)
require_exact_imports("${LIBXSLT_DLL}" ${full_crt} libxml2-16.dll)
require_exact_imports("${LIBICONV_DLL}" ${base_crt}
  api-ms-win-crt-convert-l1-1-0.dll
  api-ms-win-crt-locale-l1-1-0.dll
  api-ms-win-crt-utility-l1-1-0.dll)
require_exact_imports("${ZLIB_DLL}" ${base_crt}
  api-ms-win-crt-convert-l1-1-0.dll
  api-ms-win-crt-locale-l1-1-0.dll
  api-ms-win-crt-utility-l1-1-0.dll)

message(STATUS
  "Verified exact pure-xml AMD64 PE import closure through iconv and zlib")
