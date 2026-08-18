foreach(required_variable IN ITEMS LLVM_READOBJ MODULE)
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
string(REGEX MATCHALL "name: [^\r\n]+" import_name_lines "${imports_lower}")
foreach(import_name_line IN LISTS import_name_lines)
  string(REGEX REPLACE "^name: *" "" import_name "${import_name_line}")
  string(STRIP "${import_name}" import_name)
  if(import_name MATCHES "(^|/)(lib)?fcgi.*\\.dll$")
    message(FATAL_ERROR "dynamic FastCGI dependency is forbidden")
  endif()
endforeach()

execute_process(
  COMMAND "${LLVM_READOBJ}" --coff-exports "${MODULE}"
  RESULT_VARIABLE export_result
  OUTPUT_VARIABLE exports
  ERROR_VARIABLE export_error)
if(NOT export_result EQUAL 0)
  message(FATAL_ERROR "llvm-readobj exports failed: ${export_error}")
endif()

string(REGEX MATCHALL "Name: [^\r\n]+" export_name_lines "${exports}")
set(export_names)
foreach(export_name_line IN LISTS export_name_lines)
  string(REGEX REPLACE "^Name: *" "" export_name "${export_name_line}")
  string(STRIP "${export_name}" export_name)
  list(APPEND export_names "${export_name}")
endforeach()

foreach(required_symbol IN ITEMS
    FCGI_Accept
    FCGI_Finish
    fastcgi_defs
    fastcgi_to_file)
  list(FIND export_names "${required_symbol}" required_symbol_index)
  if(required_symbol_index EQUAL -1)
    message(FATAL_ERROR "required symbol is not exported: ${required_symbol}")
  endif()
endforeach()
