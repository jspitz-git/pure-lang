cmake_minimum_required(VERSION 3.25)
foreach(required IN ITEMS SOURCE_DIR TEST_ROOT GENERATOR MAKE_PROGRAM C_COMPILER
    PKG_CONFIG_EXECUTABLE PKG_CONFIG_PATH PURE_EXECUTABLE LLVM_READOBJ_EXECUTABLE)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()
function(expect_missing name omitted expected)
  set(dir "${TEST_ROOT}/${name}")
  file(REMOVE_RECURSE "${dir}")
  set(args -S "${SOURCE_DIR}" -B "${dir}" -G "${GENERATOR}"
    "-DCMAKE_MAKE_PROGRAM=${MAKE_PROGRAM}" "-DCMAKE_C_COMPILER=${C_COMPILER}"
    "-DPKG_CONFIG_EXECUTABLE=${PKG_CONFIG_EXECUTABLE}" -DBUILD_TESTING=ON)
  if(NOT omitted STREQUAL "pure")
    list(APPEND args "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}")
  endif()
  if(NOT omitted STREQUAL "readobj")
    list(APPEND args "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}")
  endif()
  execute_process(COMMAND "${CMAKE_COMMAND}" -E env
    "PKG_CONFIG_PATH=${PKG_CONFIG_PATH}" "${CMAKE_COMMAND}" ${args}
    RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
  if(result EQUAL 0 OR NOT "${output}\n${error}" MATCHES "${expected}")
    message(FATAL_ERROR "${name} was not rejected correctly:\n${output}${error}")
  endif()
endfunction()
expect_missing("missing Pure" pure "PURE_EXECUTABLE")
expect_missing("missing readobj" readobj "LLVM_READOBJ_EXECUTABLE")
