cmake_minimum_required(VERSION 3.25)

include("${CMAKE_CURRENT_LIST_DIR}/ContractTestRoot.cmake")
pure_glpk_validate_contract_test_root("configure" unused_test_root)

foreach(required IN ITEMS GENERATOR MAKE_PROGRAM C_COMPILER
    PKG_CONFIG_EXECUTABLE PKG_CONFIG_PATH PURE_EXECUTABLE LLVM_READOBJ_EXECUTABLE)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

pure_glpk_run_root_safety_probes("configure")
pure_glpk_reset_contract_test_root("configure")

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
