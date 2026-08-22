cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS SOURCE_DIR BINARY_DIR TEST_ROOT GENERATOR
    MAKE_PROGRAM C_COMPILER PKG_CONFIG_EXECUTABLE PKG_CONFIG_PATH PURE_EXECUTABLE)
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

set(probe_build "${TEST_ROOT}/missing llvm readobj")
file(REMOVE_RECURSE "${probe_build}")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env "PKG_CONFIG_PATH=${PKG_CONFIG_PATH}"
    "${CMAKE_COMMAND}" -S "${SOURCE_DIR}" -B "${probe_build}"
    -G "${GENERATOR}"
    "-DCMAKE_MAKE_PROGRAM=${MAKE_PROGRAM}"
    "-DCMAKE_C_COMPILER=${C_COMPILER}"
    "-DPKG_CONFIG_EXECUTABLE=${PKG_CONFIG_EXECUTABLE}"
    -DBUILD_TESTING=ON "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
    -DLLVM_READOBJ_EXECUTABLE=
  RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
if(result EQUAL 0)
  message(FATAL_ERROR "Windows BUILD_TESTING accepted an empty llvm-readobj")
endif()
if(NOT "${output}\n${error}" MATCHES
    "Windows BUILD_TESTING requires an existing LLVM_READOBJ_EXECUTABLE")
  message(FATAL_ERROR "Missing llvm-readobj diagnostic:\n${output}${error}")
endif()

set(probe_build "${TEST_ROOT}/missing executable")
file(REMOVE_RECURSE "${probe_build}")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env "PKG_CONFIG_PATH=${PKG_CONFIG_PATH}"
    "${CMAKE_COMMAND}" -S "${SOURCE_DIR}" -B "${probe_build}"
    -G "${GENERATOR}"
    "-DCMAKE_MAKE_PROGRAM=${MAKE_PROGRAM}"
    "-DCMAKE_C_COMPILER=${C_COMPILER}"
    "-DPKG_CONFIG_EXECUTABLE=${PKG_CONFIG_EXECUTABLE}"
    -DBUILD_TESTING=ON -DPURE_EXECUTABLE=
  RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
if(result EQUAL 0)
  message(FATAL_ERROR "BUILD_TESTING=ON accepted an empty PURE_EXECUTABLE")
endif()
if(NOT "${output}\n${error}" MATCHES
    "BUILD_TESTING requires an existing PURE_EXECUTABLE")
  message(FATAL_ERROR "Missing required configure diagnostic:\n${output}${error}")
endif()
