foreach(required IN ITEMS
    PURE_PREFIX MODULE_FILE PURE_SOURCE_DIR TCL_PREFIX TEST_SCRIPT TEST_ROOT
    EXPECTED_MARKER)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

set(stage "${TEST_ROOT}/Pure Tk Runtime")
set(work_dir "${stage}/Working Directory")
file(REMOVE_RECURSE "${TEST_ROOT}")
file(MAKE_DIRECTORY "${stage}" "${work_dir}" "${stage}/lib/pure")

file(COPY "${PURE_PREFIX}/" DESTINATION "${stage}")
file(COPY "${MODULE_FILE}" DESTINATION "${stage}/lib/pure")
file(COPY "${PURE_SOURCE_DIR}/tk.pure" DESTINATION "${stage}/lib/pure")
foreach(runtime IN ITEMS tcl86.dll tk86.dll zlib1.dll)
  file(COPY "${TCL_PREFIX}/bin/${runtime}" DESTINATION "${stage}/bin")
endforeach()
if(NOT OMIT_TCL_SCRIPTS)
  foreach(library_dir IN ITEMS tcl8.6 tk8.6)
    file(COPY "${TCL_PREFIX}/lib/${library_dir}" DESTINATION "${stage}/lib")
  endforeach()
endif()

unset(ENV{PURELIB})
unset(ENV{TCL_LIBRARY})
unset(ENV{TK_LIBRARY})
unset(ENV{TCLLIBPATH})
set(ENV{PURE_TK_EXPECTED_PREFIX} "${stage}")
set(ENV{PATH} "${stage}/bin;C:/Windows/System32;C:/Windows")

execute_process(
  COMMAND "${stage}/bin/pure.exe" --norc -q
    -I "${stage}/lib/pure"
    -L "${stage}/lib/pure"
  INPUT_FILE "${TEST_SCRIPT}"
  WORKING_DIRECTORY "${work_dir}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
  TIMEOUT 25
  ENCODING UTF-8
)

if(NOT "${result}" STREQUAL "0")
  message(FATAL_ERROR
    "Relocatable pure-tk test exited with ${result}\n"
    "stdout:\n${output}\nstderr:\n${error}")
endif()
if(NOT output MATCHES "(^|\r?\n)${EXPECTED_MARKER}(\r?\n|$)")
  message(FATAL_ERROR
    "Relocatable pure-tk test did not emit ${EXPECTED_MARKER}\n"
    "stdout:\n${output}\nstderr:\n${error}")
endif()

message(STATUS "Relocatable pure-tk discovery test passed")
