cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS PURE_GL_RUNNER PURE_EXECUTABLE PURE_GL_SOURCE_DIR
    PURE_GL_MODULE FREEGLUT_RUNTIME_DLL PURE_GL_PURE_PREFIX
    PURE_GL_CLANG64_PREFIX PURE_GL_WINDOWS_SYSTEM_DIRECTORY TEST_SCRIPT
    TEST_WORKING_DIRECTORY TIMEOUT_MS)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

function(require_path name kind)
  file(TO_CMAKE_PATH "${${name}}" input)
  cmake_path(IS_ABSOLUTE input absolute)
  cmake_path(NORMAL_PATH input OUTPUT_VARIABLE normalized)
  if(NOT absolute OR NOT input STREQUAL normalized)
    message(FATAL_ERROR "${name} must be a normalized absolute ${kind}")
  endif()
  if(NOT EXISTS "${input}" OR
      (kind STREQUAL "regular file" AND IS_DIRECTORY "${input}") OR
      (kind STREQUAL "directory" AND NOT IS_DIRECTORY "${input}"))
    message(FATAL_ERROR "${name} must name an existing ${kind}: ${input}")
  endif()
  set(${name} "${input}" PARENT_SCOPE)
endfunction()

foreach(file_var IN ITEMS PURE_GL_RUNNER PURE_EXECUTABLE PURE_GL_MODULE
    FREEGLUT_RUNTIME_DLL TEST_SCRIPT)
  require_path(${file_var} "regular file")
endforeach()
foreach(directory_var IN ITEMS PURE_GL_SOURCE_DIR PURE_GL_PURE_PREFIX
    PURE_GL_CLANG64_PREFIX PURE_GL_WINDOWS_SYSTEM_DIRECTORY
    TEST_WORKING_DIRECTORY)
  require_path(${directory_var} "directory")
endforeach()
if(NOT TIMEOUT_MS MATCHES "^[1-9][0-9]*$" OR TIMEOUT_MS GREATER 180000)
  message(FATAL_ERROR "TIMEOUT_MS must be an integer from 1 through 180000")
endif()
math(EXPR runner_outer_timeout_seconds "(${TIMEOUT_MS} + 5000 + 999) / 1000")

set(arguments --pure "${PURE_EXECUTABLE}" --script "${TEST_SCRIPT}"
  --timeout-ms "${TIMEOUT_MS}" --cwd "${TEST_WORKING_DIRECTORY}")
foreach(interface IN ITEMS GL GL_ARB GL_EXT GL_NV GL_ATI GLU GLUT)
  set(path "${PURE_GL_SOURCE_DIR}/${interface}.pure")
  if(NOT EXISTS "${path}" OR IS_DIRECTORY "${path}")
    message(FATAL_ERROR "${interface}.pure interface input is required: ${path}")
  endif()
  list(APPEND arguments --input "${path}")
endforeach()
list(APPEND arguments --input "${PURE_GL_MODULE}"
  --input "${FREEGLUT_RUNTIME_DLL}" --include "${PURE_GL_SOURCE_DIR}")
cmake_path(GET PURE_GL_MODULE PARENT_PATH module_directory)
cmake_path(GET FREEGLUT_RUNTIME_DLL PARENT_PATH freeglut_runtime_directory)
set(pure_bin "${PURE_GL_PURE_PREFIX}/bin")
foreach(directory IN ITEMS pure_bin module_directory freeglut_runtime_directory)
  if(NOT IS_DIRECTORY "${${directory}}")
    message(FATAL_ERROR
      "${directory} must name an existing directory: ${${directory}}")
  endif()
endforeach()
list(APPEND arguments --library "${module_directory}"
  --path-entry "${pure_bin}" --path-entry "${module_directory}"
  --path-entry "${freeglut_runtime_directory}"
  --path-entry "${PURE_GL_WINDOWS_SYSTEM_DIRECTORY}")

execute_process(COMMAND "${PURE_GL_RUNNER}" ${arguments}
  RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error
  ENCODING UTF-8 TIMEOUT "${runner_outer_timeout_seconds}")
if(NOT result EQUAL 0)
  message(FATAL_ERROR
    "pure-gl test failed (${result})\nstdout:\n${output}\nstderr:\n${error}")
endif()
if(NOT error STREQUAL "")
  message(FATAL_ERROR
    "pure-gl runner emitted stderr\nstdout:\n${output}\nstderr:\n${error}")
endif()
string(STRIP "${output}" output)
if(NOT output STREQUAL "")
  message(STATUS "${output}")
endif()
