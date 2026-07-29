foreach (required_variable OBJDUMP IMPLEMENTATION PURE_RUNTIME_STUB)
  if (NOT DEFINED ${required_variable} OR "${${required_variable}}" STREQUAL "")
    message(FATAL_ERROR
      "${required_variable} is required for the Pure runtime stub audit.")
  endif ()
endforeach ()

foreach (input IN ITEMS "${IMPLEMENTATION}" "${PURE_RUNTIME_STUB}" "${OBJDUMP}")
  if (NOT EXISTS "${input}")
    message(FATAL_ERROR "Pure runtime stub audit input is missing: ${input}")
  endif ()
endforeach ()

execute_process(
  COMMAND "${OBJDUMP}" -p "${IMPLEMENTATION}"
  RESULT_VARIABLE implementation_result
  OUTPUT_VARIABLE implementation_output
  ERROR_VARIABLE implementation_stderr)
if (NOT implementation_result EQUAL 0)
  message(FATAL_ERROR
    "Could not inspect Pure/Octave implementation:\n${implementation_stderr}")
endif ()
execute_process(
  COMMAND "${OBJDUMP}" -p "${PURE_RUNTIME_STUB}"
  RESULT_VARIABLE stub_result
  OUTPUT_VARIABLE stub_output
  ERROR_VARIABLE stub_stderr)
if (NOT stub_result EQUAL 0)
  message(FATAL_ERROR "Could not inspect Pure runtime stub:\n${stub_stderr}")
endif ()

string(REPLACE "\r\n" "\n" implementation_output "${implementation_output}")
string(REPLACE "\n" ";" implementation_lines "${implementation_output}")
set(in_libpure FALSE)
set(implementation_imports)
foreach (line IN LISTS implementation_lines)
  if (line MATCHES "^[ \t]*DLL Name: libpure\\.dll[ \t]*$")
    set(in_libpure TRUE)
  elseif (in_libpure AND line MATCHES "^[ \t]*DLL Name:")
    break()
  elseif (in_libpure AND line MATCHES
      "^[ \t]*[0-9A-Fa-f]+[ \t]+<none>[ \t]+[0-9A-Fa-f]+[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*$")
    list(APPEND implementation_imports "${CMAKE_MATCH_1}")
  endif ()
endforeach ()
list(REMOVE_DUPLICATES implementation_imports)
list(SORT implementation_imports)
if (NOT implementation_imports)
  message(FATAL_ERROR "Implementation has no named libpure.dll imports.")
endif ()

string(REPLACE "\r\n" "\n" stub_output "${stub_output}")
string(REPLACE "\n" ";" stub_lines "${stub_output}")
set(in_stub_names FALSE)
set(stub_exports)
foreach (line IN LISTS stub_lines)
  if (line MATCHES "^\\[Ordinal/Name Pointer\\] Table")
    set(in_stub_names TRUE)
  elseif (in_stub_names AND stub_exports AND line STREQUAL "")
    break()
  elseif (in_stub_names AND line MATCHES
      "^[ \t]*\\[[ \t]*[0-9]+\\][^\r\n]*[ \t][0-9A-Fa-f]+[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*$")
    list(APPEND stub_exports "${CMAKE_MATCH_1}")
  endif ()
endforeach ()
list(REMOVE_DUPLICATES stub_exports)
list(SORT stub_exports)
if (NOT stub_exports)
  message(FATAL_ERROR "Pure runtime stub has no named exports.")
endif ()

set(missing_exports)
foreach (import IN LISTS implementation_imports)
  list(FIND stub_exports "${import}" export_index)
  if (export_index EQUAL -1)
    list(APPEND missing_exports "${import}")
  endif ()
endforeach ()
set(unexpected_exports)
foreach (export IN LISTS stub_exports)
  list(FIND implementation_imports "${export}" import_index)
  if (import_index EQUAL -1)
    list(APPEND unexpected_exports "${export}")
  endif ()
endforeach ()

if (missing_exports OR unexpected_exports)
  if (missing_exports)
    string(JOIN ", " missing_text ${missing_exports})
  else ()
    set(missing_text "<none>")
  endif ()
  if (unexpected_exports)
    string(JOIN ", " unexpected_text ${unexpected_exports})
  else ()
    set(unexpected_text "<none>")
  endif ()
  message(FATAL_ERROR
    "Pure runtime stub export mismatch.\n"
    "Missing exports: ${missing_text}\n"
    "Unexpected exports: ${unexpected_text}")
endif ()
