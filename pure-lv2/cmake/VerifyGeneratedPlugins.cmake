foreach(required IN ITEMS
    LLVM_READOBJ PURE_LV2_MODULE BATCH_PLUGIN SOURCE_PLUGIN)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

function(inspect_plugin binary description require_module)
  if(NOT EXISTS "${binary}")
    message(FATAL_ERROR "Missing ${description}: ${binary}")
  endif()
  execute_process(
    COMMAND "${LLVM_READOBJ}" --file-headers --coff-imports --coff-exports
      "${binary}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8)
  if(NOT result EQUAL 0)
    message(FATAL_ERROR
      "Unable to inspect ${description} (${result})\n${output}\n${error}")
  endif()
  if(NOT output MATCHES "Format: COFF-x86-64")
    message(FATAL_ERROR "${description} is not a 64-bit PE/COFF binary")
  endif()
  if(NOT output MATCHES "Name: libpure\\.dll")
    message(FATAL_ERROR "${description} does not import libpure.dll")
  endif()
  if(require_module AND NOT output MATCHES "Name: lv2\\.dll")
    message(FATAL_ERROR "${description} does not import lv2.dll")
  endif()
  if(output MATCHES
      "Name: (msys-2\\.0|libgcc[^.]*|libstdc\\+\\+[^.]*|libc\\+\\+)\\.dll")
    message(FATAL_ERROR "${description} imports an incompatible runtime")
  endif()
  foreach(export IN ITEMS
      lv2_descriptor
      lv2_dyn_manifest_open
      lv2_dyn_manifest_get_subjects
      lv2_dyn_manifest_get_data
      lv2_dyn_manifest_close)
    if(NOT output MATCHES "Name: ${export}(\r?\n|$)")
      message(FATAL_ERROR "${description} does not export ${export}")
    endif()
  endforeach()
endfunction()

inspect_plugin("${BATCH_PLUGIN}" "batch-generated Pure LV2 plugin" TRUE)
inspect_plugin("${SOURCE_PLUGIN}" "source-loaded Pure LV2 plugin" FALSE)

execute_process(
  COMMAND "${LLVM_READOBJ}" --file-headers --coff-imports "${PURE_LV2_MODULE}"
  RESULT_VARIABLE module_result
  OUTPUT_VARIABLE module_output
  ERROR_VARIABLE module_error
  ENCODING UTF-8)
if(NOT module_result EQUAL 0 OR
    NOT module_output MATCHES "Format: COFF-x86-64" OR
    NOT module_output MATCHES "Name: libpure\\.dll")
  message(FATAL_ERROR
    "Invalid staged pure-lv2 module\n${module_output}\n${module_error}")
endif()

message(STATUS "Verified generated Pure LV2 plugin exports and PE dependencies")
