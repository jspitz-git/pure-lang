foreach(required IN ITEMS
    LLVM_READOBJ PURE_LILV_MODULE LILV_DLL SERD_DLL SORD_DLL SRATOM_DLL ZIX_DLL)
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
    ENCODING UTF-8)
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

read_imports("${PURE_LILV_MODULE}" module_imports)
require_import(module_imports "libpure\\.dll" "pure-lilv module")
require_import(module_imports "liblilv-0\\.dll" "pure-lilv module")
require_import(module_imports "libserd-0\\.dll" "pure-lilv module")

read_imports("${LILV_DLL}" lilv_imports)
require_import(lilv_imports "libserd-0\\.dll" "Lilv runtime")
require_import(lilv_imports "libsord-0\\.dll" "Lilv runtime")
require_import(lilv_imports "libsratom-0\\.dll" "Lilv runtime")
require_import(lilv_imports "libzix-0\\.dll" "Lilv runtime")

foreach(runtime IN ITEMS SERD_DLL SORD_DLL SRATOM_DLL ZIX_DLL)
  read_imports("${${runtime}}" ignored_imports)
endforeach()

file(STRINGS "${LILV_DLL}" dynmanifest_strings
  REGEX "lv2_dyn_manifest_(open|get_subjects|get_data|close)")
list(LENGTH dynmanifest_strings dynmanifest_count)
if(dynmanifest_count LESS 4)
  message(FATAL_ERROR
    "Controlled Lilv runtime does not contain Dynamic Manifest entry points")
endif()

message(STATUS
  "Verified pure-lilv PE closure and Dynamic Manifest-enabled Lilv runtime")
