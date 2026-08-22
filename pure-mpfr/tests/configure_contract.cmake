cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS SOURCE_DIR BINARY_DIR TEST_ROOT GENERATOR
    MAKE_PROGRAM C_COMPILER PKG_CONFIG_EXECUTABLE PKG_CONFIG_PATH PURE_EXECUTABLE)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()
get_filename_component(binary_root "${BINARY_DIR}" ABSOLUTE)
get_filename_component(test_root "${TEST_ROOT}" ABSOLUTE)
cmake_path(IS_PREFIX binary_root "${test_root}" NORMALIZE safe_root)
if(NOT safe_root OR test_root STREQUAL binary_root)
  message(FATAL_ERROR "TEST_ROOT must be a child of BINARY_DIR")
endif()

function(expect_configure_failure probe_name pure_executable readobj diagnostic)
  set(probe_build "${TEST_ROOT}/${probe_name}")
  file(REMOVE_RECURSE "${probe_build}")
  execute_process(COMMAND "${CMAKE_COMMAND}" -E env
    "PKG_CONFIG_PATH=${PKG_CONFIG_PATH}" "${CMAKE_COMMAND}"
    -S "${SOURCE_DIR}" -B "${probe_build}" -G "${GENERATOR}"
    "-DCMAKE_MAKE_PROGRAM=${MAKE_PROGRAM}"
    "-DCMAKE_C_COMPILER=${C_COMPILER}"
    "-DPKG_CONFIG_EXECUTABLE=${PKG_CONFIG_EXECUTABLE}"
    -DBUILD_TESTING=ON "-DPURE_EXECUTABLE=${pure_executable}"
    "-DLLVM_READOBJ_EXECUTABLE=${readobj}"
    RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
  if(result EQUAL 0)
    message(FATAL_ERROR "${probe_name} was accepted")
  endif()
  if(NOT "${output}\n${error}" MATCHES "${diagnostic}")
    message(FATAL_ERROR "${probe_name} lacked diagnostic:\n${output}${error}")
  endif()
endfunction()

expect_configure_failure("missing executable" "" "unused"
  "BUILD_TESTING requires an existing PURE_EXECUTABLE")
if(WINDOWS_BUILD)
  expect_configure_failure("missing llvm readobj" "${PURE_EXECUTABLE}" ""
    "Windows BUILD_TESTING requires an existing LLVM_READOBJ_EXECUTABLE")
endif()
