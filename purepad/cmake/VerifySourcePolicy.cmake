cmake_minimum_required(VERSION 3.25)

foreach(required_variable IN ITEMS PUREPAD_SOURCE_DIR PUREPAD_BUILD_DIR)
  if(NOT DEFINED ${required_variable} OR "${${required_variable}}" STREQUAL "")
    message(FATAL_ERROR "${required_variable} is required")
  endif()
endforeach()
if(NOT IS_DIRECTORY "${PUREPAD_SOURCE_DIR}")
  message(FATAL_ERROR
    "PurePad source directory does not exist: ${PUREPAD_SOURCE_DIR}")
endif()
if(NOT IS_DIRECTORY "${PUREPAD_BUILD_DIR}")
  message(FATAL_ERROR
    "PurePad build directory does not exist: ${PUREPAD_BUILD_DIR}")
endif()

file(REAL_PATH "${PUREPAD_BUILD_DIR}" purepad_build_path)
file(GLOB_RECURSE purepad_cpp_files LIST_DIRECTORIES FALSE
  "${PUREPAD_SOURCE_DIR}/*.cc"
  "${PUREPAD_SOURCE_DIR}/*.cpp"
  "${PUREPAD_SOURCE_DIR}/*.cxx"
  "${PUREPAD_SOURCE_DIR}/*.h"
  "${PUREPAD_SOURCE_DIR}/*.hh"
  "${PUREPAD_SOURCE_DIR}/*.hpp"
  "${PUREPAD_SOURCE_DIR}/*.hxx")
list(SORT purepad_cpp_files)

string(CONCAT purepad_thread_api "Terminate" "Thread")
string(CONCAT purepad_association_api "RegisterShell" "FileTypes")
set(purepad_checked_count 0)
foreach(purepad_cpp_file IN LISTS purepad_cpp_files)
  file(REAL_PATH "${purepad_cpp_file}" purepad_cpp_path)
  cmake_path(IS_PREFIX purepad_build_path "${purepad_cpp_path}" NORMALIZE
    purepad_generated_source)
  if(purepad_generated_source)
    continue()
  endif()

  math(EXPR purepad_checked_count "${purepad_checked_count} + 1")
  file(READ "${purepad_cpp_path}" purepad_cpp_contents)
  string(FIND "${purepad_cpp_contents}" "${purepad_thread_api}"
    purepad_thread_api_index)
  if(NOT purepad_thread_api_index EQUAL -1)
    message(FATAL_ERROR
      "PurePad source uses a forbidden process-lifecycle API: "
      "${purepad_cpp_path}")
  endif()
  string(FIND "${purepad_cpp_contents}" "${purepad_association_api}"
    purepad_association_api_index)
  if(NOT purepad_association_api_index EQUAL -1)
    message(FATAL_ERROR
      "PurePad source uses a forbidden startup-association API: "
      "${purepad_cpp_path}")
  endif()
endforeach()

if(purepad_checked_count EQUAL 0)
  message(FATAL_ERROR "PurePad source policy found no C++ files to check")
endif()
message(STATUS
  "PurePad source policy checked ${purepad_checked_count} C++ files")
