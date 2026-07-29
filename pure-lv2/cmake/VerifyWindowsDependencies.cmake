foreach(required IN ITEMS LLVM_READOBJ PURE_LV2_MODULE)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

execute_process(
  COMMAND "${LLVM_READOBJ}" --file-headers --coff-imports
    "${PURE_LV2_MODULE}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
  ENCODING UTF-8)
if(NOT result EQUAL 0)
  message(FATAL_ERROR
    "Unable to inspect ${PURE_LV2_MODULE} (${result})\n${output}\n${error}")
endif()
if(NOT output MATCHES "Format: COFF-x86-64")
  message(FATAL_ERROR "pure-lv2 module is not a 64-bit PE/COFF binary")
endif()
if(NOT output MATCHES "Name: libpure\\.dll")
  message(FATAL_ERROR "pure-lv2 module does not import libpure.dll")
endif()
if(output MATCHES
    "Name: (msys-2\\.0|libgcc[^.]*|libstdc\\+\\+[^.]*|libc\\+\\+)\\.dll")
  message(FATAL_ERROR "pure-lv2 module imports an incompatible runtime")
endif()

message(STATUS "Verified the pure-lv2 PE32+ module dependency set")
