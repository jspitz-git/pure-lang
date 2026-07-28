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
  COMMAND "${CMAKE_COMMAND}" -E env "PATH=${path}"
    "${PURE_EXECUTABLE}" --norc
      -I "${PURE_GL_SOURCE_DIR}"
      -L "${PURE_LIBRARY_DIR}"
      -x "${TEST_SCRIPT}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
  TIMEOUT 45)
if(NOT result EQUAL 0 OR NOT error STREQUAL "")
  message(FATAL_ERROR
    "Pure test failed (${result})\nstdout:\n${output}\nstderr:\n${error}")
endif()
string(STRIP "${output}" output)
if(NOT output STREQUAL "")
  message(STATUS "${output}")
endif()
