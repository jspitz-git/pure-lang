foreach(required IN ITEMS LLVM_READOBJ ODBC_MODULE GMP_DLL)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

foreach(module IN ITEMS "${ODBC_MODULE}" "${GMP_DLL}")
  if(NOT EXISTS "${module}")
    message(FATAL_ERROR "Dependency does not exist: ${module}")
  endif()
  execute_process(
    COMMAND "${LLVM_READOBJ}" --coff-imports "${module}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE imports
    ERROR_VARIABLE error
    ENCODING UTF-8
  )
  if(NOT result EQUAL 0)
    message(FATAL_ERROR
      "Unable to inspect ${module} (${result})\n${imports}\n${error}")
  endif()
  if(imports MATCHES
      "Name: (msys-2\\.0|libgcc[^.]*|libstdc\\+\\+[^.]*)\\.dll")
    message(FATAL_ERROR "${module} imports an incompatible MSYS/GNU runtime")
  endif()
  if(module STREQUAL "${ODBC_MODULE}")
    foreach(required_import IN ITEMS libpure.dll libgmp-10.dll ODBC32.dll)
      if(NOT imports MATCHES "Name: ${required_import}")
        message(FATAL_ERROR
          "${ODBC_MODULE} does not import ${required_import}")
      endif()
    endforeach()
  endif()
endforeach()

message(STATUS
  "Verified pure-odbc PE closure: Pure, GMP, native ODBC32, and UCRT")
