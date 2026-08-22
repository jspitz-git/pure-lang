cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS SOURCE_DIR BINARY_DIR TEST_ROOT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

get_filename_component(binary_root "${BINARY_DIR}" ABSOLUTE)
get_filename_component(test_root "${TEST_ROOT}" ABSOLUTE)
cmake_path(IS_PREFIX binary_root "${test_root}" NORMALIZE test_root_is_safe)
if(NOT test_root_is_safe OR test_root STREQUAL binary_root)
  message(FATAL_ERROR "TEST_ROOT must be a child of BINARY_DIR")
endif()

set(missing_executable_build "${TEST_ROOT}/missing executable")
file(REMOVE_RECURSE "${missing_executable_build}")

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    -S "${SOURCE_DIR}"
    -B "${missing_executable_build}"
    -G Ninja
    -DBUILD_TESTING=ON
    -DPURE_EXECUTABLE=
  RESULT_VARIABLE configure_result
  OUTPUT_VARIABLE configure_stdout
  ERROR_VARIABLE configure_stderr
)

if(configure_result EQUAL 0)
  message(FATAL_ERROR
    "BUILD_TESTING=ON accepted an empty PURE_EXECUTABLE")
endif()

set(configure_output "${configure_stdout}\n${configure_stderr}")
if(NOT configure_output MATCHES
    "BUILD_TESTING requires an existing PURE_EXECUTABLE")
  message(FATAL_ERROR
    "Missing-executable configure failed without the required diagnostic:\n"
    "${configure_output}")
endif()
