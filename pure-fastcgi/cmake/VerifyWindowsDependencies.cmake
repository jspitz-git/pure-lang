foreach(required_variable IN ITEMS LLVM_READOBJ LLVM_NM MODULE)
  if(NOT DEFINED ${required_variable} OR "${${required_variable}}" STREQUAL "")
    message(FATAL_ERROR "${required_variable} is required")
  endif()
endforeach()

if(NOT EXISTS "${MODULE}")
  message(FATAL_ERROR "FastCGI module does not exist: ${MODULE}")
endif()

execute_process(
  COMMAND "${LLVM_READOBJ}" --coff-imports "${MODULE}"
  RESULT_VARIABLE read_result
  OUTPUT_VARIABLE imports
  ERROR_VARIABLE read_error)
if(NOT read_result EQUAL 0)
  message(FATAL_ERROR "llvm-readobj failed: ${read_error}")
endif()
string(TOLOWER "${imports}" imports_lower)
if(imports_lower MATCHES "lib?fcgi[^\r\n]*\\.dll")
  message(FATAL_ERROR "dynamic FastCGI dependency is forbidden")
endif()

execute_process(
  COMMAND "${LLVM_NM}" --defined-only "${MODULE}"
  RESULT_VARIABLE nm_result
  OUTPUT_VARIABLE definitions
  ERROR_VARIABLE nm_error)
if(NOT nm_result EQUAL 0)
  message(FATAL_ERROR "llvm-nm failed: ${nm_error}")
endif()

foreach(required_symbol IN ITEMS
    FCGI_Accept
    FCGI_Finish
    fastcgi_defs
    fastcgi_to_file)
  if(NOT definitions MATCHES "${required_symbol}")
    message(FATAL_ERROR "required symbol is not exported: ${required_symbol}")
  endif()
endforeach()
