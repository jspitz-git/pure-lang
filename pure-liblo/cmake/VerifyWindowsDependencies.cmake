foreach(required IN ITEMS LLVM_READOBJ PURE_LIBLO_MODULE LIBLO_DLL)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

function(read_imports binary output_var)
  if(NOT EXISTS "${binary}")
    message(FATAL_ERROR "Missing binary: ${binary}")
  endif()
  execute_process(
    COMMAND "${LLVM_READOBJ}" --file-headers --coff-imports "${binary}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8
  )
  if(NOT result EQUAL 0)
    message(FATAL_ERROR
      "Unable to inspect ${binary} (${result})\n${output}\n${error}")
  endif()
  if(NOT output MATCHES "Format: COFF-x86-64")
    message(FATAL_ERROR "${binary} is not a 64-bit PE/COFF binary")
  endif()
  if(output MATCHES
      "Name: (msys-2\\.0|libgcc[^.]*|libstdc\\+\\+[^.]*|libc\\+\\+)\\.dll")
    message(FATAL_ERROR "${binary} imports an incompatible POSIX/C++ runtime")
  endif()
  set(${output_var} "${output}" PARENT_SCOPE)
endfunction()

function(require_import imports_var import_name description)
  if(NOT "${${imports_var}}" MATCHES "Name: ${import_name}")
    message(FATAL_ERROR "${description} does not import ${import_name}")
  endif()
endfunction()

read_imports("${PURE_LIBLO_MODULE}" module_imports)
require_import(module_imports "liblo\\.dll" "pure-liblo module")
require_import(module_imports "libpure\\.dll" "pure-liblo module")
require_import(module_imports "libgmp-10\\.dll" "pure-liblo module")

read_imports("${LIBLO_DLL}" liblo_imports)
require_import(liblo_imports "WSOCK32\\.dll" "liblo runtime")
require_import(liblo_imports "WS2_32\\.dll" "liblo runtime")
require_import(liblo_imports "IPHLPAPI\\.DLL" "liblo runtime")

message(STATUS
  "Verified pure-liblo PE closure: lo.dll, bundled liblo.dll, reused "
  "libpure/libgmp, native Winsock/IP Helper APIs, and UCRT")
