if(NOT DEFINED PURE_EXECUTABLE OR NOT DEFINED PURE_OBJECT_INSPECTOR)
  message(FATAL_ERROR "Missing Windows stack-reserve test inputs")
endif()

execute_process(
  COMMAND "${PURE_OBJECT_INSPECTOR}" --file-headers "${PURE_EXECUTABLE}"
  RESULT_VARIABLE inspect_result
  OUTPUT_VARIABLE inspect_output
  ERROR_VARIABLE inspect_error
)
if(NOT inspect_result EQUAL 0)
  message(FATAL_ERROR
    "Could not inspect pure.exe PE headers:\n${inspect_output}${inspect_error}")
endif()

if(NOT inspect_output MATCHES "SizeOfStackReserve: 8388608([\r\n]|$)")
  message(FATAL_ERROR
    "pure.exe does not reserve the required 8 MiB Windows stack:\n"
    "${inspect_output}")
endif()
