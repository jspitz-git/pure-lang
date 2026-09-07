cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS SOURCE_DIR BINARY_DIR CONTRACT_ROOT TEST_ROOT GENERATOR
    MAKE_PROGRAM C_COMPILER PKG_CONFIG_EXECUTABLE PKG_CONFIG_PATH PURE_EXECUTABLE
    LLVM_READOBJ_EXECUTABLE)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

foreach(path_var IN ITEMS SOURCE_DIR BINARY_DIR CONTRACT_ROOT TEST_ROOT)
  cmake_path(ABSOLUTE_PATH ${path_var} NORMALIZE OUTPUT_VARIABLE normalized)
  set(${path_var} "${normalized}")
endforeach()

function(require_safe_test_root)
  foreach(directory IN ITEMS SOURCE_DIR BINARY_DIR)
    if(NOT IS_DIRECTORY "${${directory}}")
      message(FATAL_ERROR
        "${directory} must be an existing directory: ${${directory}}")
    endif()
  endforeach()
  cmake_path(GET CONTRACT_ROOT PARENT_PATH contract_parent)
  if(NOT "${contract_parent}" STREQUAL "${BINARY_DIR}")
    message(FATAL_ERROR
      "Unsafe CONTRACT_ROOT; expected a direct child of BINARY_DIR\n"
      "CONTRACT_ROOT: ${CONTRACT_ROOT}\nBINARY_DIR: ${BINARY_DIR}")
  endif()
  cmake_path(GET TEST_ROOT PARENT_PATH test_parent)
  if(NOT "${test_parent}" STREQUAL "${CONTRACT_ROOT}")
    message(FATAL_ERROR
      "Unsafe TEST_ROOT; expected a direct child of CONTRACT_ROOT\n"
      "TEST_ROOT: ${TEST_ROOT}\nCONTRACT_ROOT: ${CONTRACT_ROOT}")
  endif()
  foreach(protected IN ITEMS SOURCE_DIR BINARY_DIR)
    cmake_path(IS_PREFIX TEST_ROOT "${${protected}}" NORMALIZE
      test_root_contains_protected)
    if(test_root_contains_protected)
      message(FATAL_ERROR
        "Unsafe TEST_ROOT contains protected ${protected}: ${${protected}}")
    endif()
  endforeach()
endfunction()

require_safe_test_root()
if(ROOT_SAFETY_PROBE)
  return()
endif()

function(expect_unsafe_root_rejected label unsafe_contract_root unsafe_test_root)
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${SOURCE_DIR}"
      "-DBINARY_DIR=${BINARY_DIR}"
      "-DCONTRACT_ROOT=${unsafe_contract_root}"
      "-DTEST_ROOT=${unsafe_test_root}"
      "-DGENERATOR=${GENERATOR}"
      "-DMAKE_PROGRAM=${MAKE_PROGRAM}"
      "-DC_COMPILER=${C_COMPILER}"
      "-DPKG_CONFIG_EXECUTABLE=${PKG_CONFIG_EXECUTABLE}"
      "-DPKG_CONFIG_PATH=${PKG_CONFIG_PATH}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}"
      -DROOT_SAFETY_PROBE=ON
      -P "${CMAKE_CURRENT_LIST_FILE}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8
  )
  if(result EQUAL 0)
    message(FATAL_ERROR
      "Configure cleanup guard accepted unsafe ${label}: ${unsafe_test_root}")
  endif()
  if(NOT "${output}\n${error}" MATCHES "Unsafe (CONTRACT_ROOT|TEST_ROOT)")
    message(FATAL_ERROR
      "Unsafe configure ${label} produced the wrong diagnostic\n${output}\n${error}")
  endif()
endfunction()

expect_unsafe_root_rejected("source TEST_ROOT" "${CONTRACT_ROOT}" "${SOURCE_DIR}")
expect_unsafe_root_rejected("binary TEST_ROOT" "${CONTRACT_ROOT}" "${BINARY_DIR}")
expect_unsafe_root_rejected("CONTRACT_ROOT" "${SOURCE_DIR}" "${SOURCE_DIR}/configure")

function(expect_configure_failure name expected)
  set(build_dir "${TEST_ROOT}/${name}")
  file(REMOVE_RECURSE "${build_dir}")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env
      "PKG_CONFIG_PATH=${PKG_CONFIG_PATH}"
      "${CMAKE_COMMAND}" -S "${SOURCE_DIR}" -B "${build_dir}"
        -G "${GENERATOR}"
        "-DCMAKE_MAKE_PROGRAM=${MAKE_PROGRAM}"
        "-DCMAKE_C_COMPILER=${C_COMPILER}"
        -DCMAKE_C_COMPILER_WORKS=1
        -DCMAKE_C_ABI_COMPILED=1
        "-DPKG_CONFIG_EXECUTABLE=${PKG_CONFIG_EXECUTABLE}"
        -DBUILD_TESTING=ON ${ARGN}
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error)
  if(result EQUAL 0)
    message(FATAL_ERROR "${name} configuration unexpectedly succeeded")
  endif()
  if(NOT "${output}\n${error}" MATCHES "${expected}")
    message(FATAL_ERROR "${name} produced the wrong diagnostic:\n${output}${error}")
  endif()
endfunction()

expect_configure_failure("missing Pure" "PURE_EXECUTABLE"
  -DPURE_EXECUTABLE= "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}")
expect_configure_failure("nonexistent Pure" "PURE_EXECUTABLE"
  "-DPURE_EXECUTABLE=${TEST_ROOT}/missing/pure.exe"
  "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}")
file(MAKE_DIRECTORY "${TEST_ROOT}/directory-as-executable")
expect_configure_failure("directory Pure" "PURE_EXECUTABLE"
  "-DPURE_EXECUTABLE=${TEST_ROOT}/directory-as-executable"
  "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}")
expect_configure_failure("missing readobj" "LLVM_READOBJ_EXECUTABLE"
  "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}" -DLLVM_READOBJ_EXECUTABLE=)
expect_configure_failure("nonexistent readobj" "LLVM_READOBJ_EXECUTABLE"
  "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
  "-DLLVM_READOBJ_EXECUTABLE=${TEST_ROOT}/missing/llvm-readobj.exe")
expect_configure_failure("directory readobj" "LLVM_READOBJ_EXECUTABLE"
  "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
  "-DLLVM_READOBJ_EXECUTABLE=${TEST_ROOT}/directory-as-executable")
