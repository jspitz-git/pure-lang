cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS SOURCE_DIR BINARY_DIR TEST_ROOT GENERATOR MAKE_PROGRAM
    CXX_COMPILER PKG_CONFIG_EXECUTABLE PKG_CONFIG_PATH PURE_EXECUTABLE
    LLVM_READOBJ_EXECUTABLE)
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

function(expect_failure name expected)
  set(build "${TEST_ROOT}/${name}")
  file(REMOVE_RECURSE "${build}")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env
      "PKG_CONFIG_PATH=${PKG_CONFIG_PATH}"
      "${CMAKE_COMMAND}" -S "${SOURCE_DIR}" -B "${build}" -G "${GENERATOR}"
      "-DCMAKE_MAKE_PROGRAM=${MAKE_PROGRAM}"
      "-DCMAKE_CXX_COMPILER=${CXX_COMPILER}"
      "-DPKG_CONFIG_EXECUTABLE=${PKG_CONFIG_EXECUTABLE}"
      -DBUILD_TESTING=ON
      ${ARGN}
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
  )
  if(result EQUAL 0)
    message(FATAL_ERROR "${name} unexpectedly succeeded")
  endif()
  if(NOT "${output}\n${error}" MATCHES "${expected}")
    message(FATAL_ERROR
      "${name} produced the wrong diagnostic:\n${output}${error}")
  endif()
endfunction()

expect_failure("missing Pure"
  "BUILD_TESTING requires an existing PURE_EXECUTABLE"
  -DPURE_EXECUTABLE=
  "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}")
expect_failure("missing readobj"
  "Windows validation requires an existing LLVM_READOBJ_EXECUTABLE"
  "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
  -DLLVM_READOBJ_EXECUTABLE=)
