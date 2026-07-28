foreach(name IN ITEMS PURE_EXECUTABLE PURE_LIBRARY_DIR PURE_GL_SOURCE_DIR TEST_SCRIPT)
  if(NOT DEFINED ${name} OR "${${name}}" STREQUAL "")
    message(FATAL_ERROR "${name} is required")
  endif()
endforeach()

set(path "${PURE_LIBRARY_DIR}")
if(DEFINED ENV{PATH} AND NOT "$ENV{PATH}" STREQUAL "")
  set(path "${path};$ENV{PATH}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    "PATH=${path}"
    "PURE_LIBRARY=${PURE_GL_SOURCE_DIR}"
    "${PURE_EXECUTABLE}" -x "${TEST_SCRIPT}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
  TIMEOUT 20)
if(NOT result EQUAL 0)
  message(FATAL_ERROR
    "Pure test failed (${result})\nstdout:\n${output}\nstderr:\n${error}")
endif()
message(STATUS "${output}")
