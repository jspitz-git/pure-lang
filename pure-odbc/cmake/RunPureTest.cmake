cmake_minimum_required(VERSION 3.29)

foreach(required IN ITEMS
    PURE_EXECUTABLE PURE_SOURCE_DIR MODULE_DIR SCRIPT WORK_DIRECTORY)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
  cmake_path(ABSOLUTE_PATH ${required} NORMALIZE OUTPUT_VARIABLE normalized)
  set(${required} "${normalized}")
endforeach()

foreach(file_input IN ITEMS PURE_EXECUTABLE SCRIPT)
  if(NOT EXISTS "${${file_input}}" OR IS_DIRECTORY "${${file_input}}")
    message(FATAL_ERROR
      "${file_input} must be an existing file: ${${file_input}}")
  endif()
endforeach()
foreach(directory_input IN ITEMS PURE_SOURCE_DIR MODULE_DIR WORK_DIRECTORY)
  if(NOT IS_DIRECTORY "${${directory_input}}")
    message(FATAL_ERROR
      "${directory_input} must be an existing directory: ${${directory_input}}")
  endif()
endforeach()

cmake_path(GET PURE_EXECUTABLE PARENT_PATH pure_bin)
unset(ENV{PURELIB})
if(WIN32)
  if(NOT DEFINED ENV{SystemRoot} OR "$ENV{SystemRoot}" STREQUAL "")
    message(FATAL_ERROR "SystemRoot is required to construct the test PATH")
  endif()
  cmake_path(CONVERT "$ENV{SystemRoot}" TO_CMAKE_PATH_LIST windows_root NORMALIZE)
  if(NOT IS_DIRECTORY "${windows_root}" OR
      NOT IS_DIRECTORY "${windows_root}/System32")
    message(FATAL_ERROR "SystemRoot does not identify a Windows installation")
  endif()
  set(ENV{PATH}
    "${MODULE_DIR};${pure_bin};${windows_root}/System32;${windows_root}")
else()
  set(ENV{PATH} "${MODULE_DIR}:${pure_bin}:/usr/bin:/bin")
endif()

execute_process(
  COMMAND "${PURE_EXECUTABLE}" --norc
    -I "${PURE_SOURCE_DIR}"
    -L "${MODULE_DIR}"
    -x "${SCRIPT}"
  WORKING_DIRECTORY "${WORK_DIRECTORY}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
  ENCODING UTF-8
)

if(NOT error STREQUAL "")
  message(
    "pure-odbc test emitted stderr\nstdout:\n${output}\nstderr:\n${error}")
  cmake_language(EXIT 1)
endif()
if(result EQUAL 77)
  message(STATUS "${output}")
  cmake_language(EXIT 77)
endif()
if(NOT result EQUAL 0)
  message(
    "pure-odbc test failed (${result})\nstdout:\n${output}\nstderr:\n${error}")
  cmake_language(EXIT "${result}")
endif()
message(STATUS "${output}")
