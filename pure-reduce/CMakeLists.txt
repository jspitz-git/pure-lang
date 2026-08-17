cmake_minimum_required(VERSION 3.25)
project(PureReduce LANGUAGES NONE)

set(PURE_REDUCE_SOURCE_DIR "" CACHE PATH
  "Existing checkout of pinned REDUCE sources")
set(PURE_REDUCE_UPSTREAM_COMMIT
  "7efba90661139ae9c73c99fddd55f3fb2fabf69a")
set(PURE_REDUCE_MSYS2_BASH "C:/msys64/usr/bin/bash.exe" CACHE FILEPATH
  "MSYS2 bash used only to build the pinned REDUCE dependency")
set(PURE_REDUCE_MAKE "C:/msys64/usr/bin/make.exe" CACHE FILEPATH
  "GNU make used only to build the pinned REDUCE dependency")
set(PURE_REDUCE_UPSTREAM_BINARY_DIR
  "${CMAKE_CURRENT_BINARY_DIR}/reduce-upstream" CACHE PATH
  "Private binary root for the complete pinned REDUCE build")
set(PURE_EXECUTABLE "" CACHE FILEPATH
  "Pure interpreter used for pure-reduce functional tests")

include("${CMAKE_CURRENT_LIST_DIR}/cmake/ReduceSource.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/cmake/ReduceUpstream.cmake")

if(PURE_REDUCE_SOURCE_DIR)
  pure_reduce_verify_source(
    "${PURE_REDUCE_SOURCE_DIR}"
    PURE_REDUCE_VERIFIED_COMMIT
    PURE_REDUCE_SOURCE_TREE_SHA256)
  pure_reduce_define_upstream_build()
endif()

if(PURE_REDUCE_SOURCE_DIR)
  enable_language(CXX)
  cmake_path(GET CMAKE_CXX_COMPILER PARENT_PATH
    _pure_reduce_compiler_directory)
  find_program(PURE_REDUCE_LLVM_READOBJ
    NAMES llvm-readobj
    HINTS "${_pure_reduce_compiler_directory}"
    REQUIRED)
  set(_pure_reduce_cslbase
    "${PURE_REDUCE_UPSTREAM_BINARY_DIR}/source/csl/cslbase")
  add_library(pure-reduce-bridge-objects OBJECT
    bridge/reduce_bridge.cpp)
  set_target_properties(pure-reduce-bridge-objects PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO
    POSITION_INDEPENDENT_CODE YES)
  target_compile_definitions(pure-reduce-bridge-objects PRIVATE
    PURE_REDUCE_BUILDING)
  target_include_directories(pure-reduce-bridge-objects PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/bridge"
    "${_pure_reduce_cslbase}")
  add_dependencies(pure-reduce-bridge-objects pure-reduce-upstream)

  add_library(reduce MODULE
    $<TARGET_OBJECTS:pure-reduce-bridge-objects>
    bridge/reduce.def)
  set_target_properties(reduce PROPERTIES
    PREFIX ""
    OUTPUT_NAME "reduce"
    WINDOWS_EXPORT_ALL_SYMBOLS OFF)
  add_custom_command(TARGET reduce POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
      "${PURE_REDUCE_CSL_IMAGE}" "$<TARGET_FILE_DIR:reduce>/reduce.img"
    COMMENT "Staging reduce.img beside reduce.dll"
    VERBATIM)
  add_dependencies(reduce pure-reduce-upstream)
  target_link_options(reduce PRIVATE
    -Wl,--no-undefined)
  target_link_libraries(reduce PRIVATE
    ${PURE_REDUCE_CSL_LINK_INTERFACE})

  add_executable(pure-reduce-bridge-contract
    tests/bridge-contract.cpp
    $<TARGET_OBJECTS:pure-reduce-bridge-objects>)
  set_target_properties(pure-reduce-bridge-contract PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  target_include_directories(pure-reduce-bridge-contract PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/bridge"
    "${_pure_reduce_cslbase}")
  target_compile_definitions(pure-reduce-bridge-contract PRIVATE
    PURE_REDUCE_STATIC)
  add_dependencies(pure-reduce-bridge-contract pure-reduce-upstream)
  target_link_options(pure-reduce-bridge-contract PRIVATE
    -Wl,--no-undefined)
  target_link_libraries(pure-reduce-bridge-contract PRIVATE
    ${PURE_REDUCE_CSL_LINK_INTERFACE})
endif()

include("${CMAKE_CURRENT_LIST_DIR}/cmake/Install.cmake")

include(CTest)
if(BUILD_TESTING)
  add_test(
    NAME pure-reduce-source-contract
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_REDUCE_SOURCE_DIR=${PURE_REDUCE_SOURCE_DIR}"
      -P "${CMAKE_CURRENT_LIST_DIR}/tests/source-contract.cmake")
  set_tests_properties(pure-reduce-source-contract PROPERTIES LABELS "reduce")
  if(PURE_REDUCE_SOURCE_DIR)
    add_test(
      NAME pure-reduce-bridge-contract
      COMMAND pure-reduce-bridge-contract)
    set_tests_properties(pure-reduce-bridge-contract PROPERTIES
      LABELS "reduce")
    add_test(
      NAME pure-reduce-bridge-contract-live-redundant
      COMMAND pure-reduce-bridge-contract
        --live-redundant "${PURE_REDUCE_CSL_IMAGE}")
    set_tests_properties(pure-reduce-bridge-contract-live-redundant PROPERTIES
      LABELS "reduce")
    add_test(
      NAME pure-reduce-bridge-contract-live-cleanup
      COMMAND pure-reduce-bridge-contract
        --live-cleanup "${PURE_REDUCE_CSL_IMAGE}")
    set_tests_properties(pure-reduce-bridge-contract-live-cleanup PROPERTIES
      LABELS "reduce")
    if(PURE_EXECUTABLE)
      if(NOT IS_ABSOLUTE "${PURE_EXECUTABLE}" OR
         NOT EXISTS "${PURE_EXECUTABLE}")
        message(FATAL_ERROR
          "PURE_EXECUTABLE must be an existing absolute file: ${PURE_EXECUTABLE}")
      endif()
      get_filename_component(_pure_reduce_runtime_dir
        "${PURE_EXECUTABLE}" DIRECTORY)
      get_filename_component(_pure_reduce_prefix
        "${_pure_reduce_runtime_dir}" DIRECTORY)
      set(_pure_reduce_library_dir "${_pure_reduce_prefix}/lib/pure")
      if(NOT IS_DIRECTORY "${_pure_reduce_library_dir}")
        message(FATAL_ERROR
          "Pure library directory does not exist: ${_pure_reduce_library_dir}")
      endif()
      foreach(_test_name IN ITEMS smoke lifecycle)
        add_test(
          NAME "pure-reduce-${_test_name}"
          COMMAND "${CMAKE_COMMAND}"
            "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
            "-DPURE_LIBRARY_DIR=${_pure_reduce_library_dir}"
            "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_LIST_DIR}"
            "-DMODULE_DIR=$<TARGET_FILE_DIR:reduce>"
            "-DTEST_SCRIPT=${CMAKE_CURRENT_LIST_DIR}/tests/${_test_name}.pure"
            "-DEXPECTED_MARKER=pure-reduce ${_test_name} passed"
            -P "${CMAKE_CURRENT_LIST_DIR}/cmake/RunPureReduceTest.cmake")
        set_tests_properties("pure-reduce-${_test_name}" PROPERTIES
          LABELS "reduce")
      endforeach()
      add_test(
        NAME pure-reduce-initialization-failure
        COMMAND "${CMAKE_COMMAND}"
          "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
          "-DPURE_LIBRARY_DIR=${_pure_reduce_library_dir}"
          "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_LIST_DIR}"
          "-DMODULE_DIR=$<TARGET_FILE_DIR:reduce>"
          "-DTEST_SCRIPT=${CMAKE_CURRENT_LIST_DIR}/tests/initialization-failure.pure"
          "-DEXPECTED_MARKER=pure-reduce initialization-failure passed"
          -P "${CMAKE_CURRENT_LIST_DIR}/cmake/RunPureReduceTest.cmake")
      set_tests_properties(pure-reduce-initialization-failure PROPERTIES
        LABELS "reduce")
      add_test(
        NAME pure-reduce-unicode-relocation
        COMMAND "${CMAKE_COMMAND}"
          "-DCMAKE_COMMAND=${CMAKE_COMMAND}"
          "-DREDUCE_DLL=$<TARGET_FILE:reduce>"
          "-DREDUCE_IMAGE=${PURE_REDUCE_CSL_IMAGE}"
          "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
          "-DPURE_LIBRARY_DIR=${_pure_reduce_library_dir}"
          "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_LIST_DIR}"
          "-DPURE_MODULE=${CMAKE_CURRENT_LIST_DIR}/reduce.pure"
          "-DTEST_DRIVER=${CMAKE_CURRENT_LIST_DIR}/cmake/RunPureReduceTest.cmake"
          "-DTEST_SCRIPT=${CMAKE_CURRENT_LIST_DIR}/tests/unicode-relocation.pure"
          "-DSTAGE_ROOT=${CMAKE_CURRENT_BINARY_DIR}"
          "-DEXPECTED_MARKER=pure-reduce unicode-relocation passed"
          -P "${CMAKE_CURRENT_LIST_DIR}/cmake/RunPureReduceUnicodeTest.cmake")
      set_tests_properties(pure-reduce-unicode-relocation PROPERTIES
        LABELS "reduce")
    else()
      message(STATUS
        "PURE_EXECUTABLE is not set; pure-reduce functional tests are disabled")
    endif()
    add_test(
      NAME pure-reduce-upstream-build
      COMMAND "${CMAKE_COMMAND}" --build "${CMAKE_BINARY_DIR}"
        --target pure-reduce-upstream -- -j1)
    set_tests_properties(pure-reduce-upstream-build PROPERTIES
      FIXTURES_SETUP pure-reduce-upstream-built
      LABELS "reduce")
    add_test(
      NAME pure-reduce-upstream-contract
      COMMAND "${CMAKE_COMMAND}"
        "-DPURE_REDUCE_SOURCE_DIR=${PURE_REDUCE_SOURCE_DIR}"
        "-DPURE_REDUCE_UPSTREAM_BINARY_DIR=${PURE_REDUCE_UPSTREAM_BINARY_DIR}"
        "-DPURE_REDUCE_MSYS2_BASH=${PURE_REDUCE_MSYS2_BASH}"
        "-DPURE_REDUCE_MAKE=${PURE_REDUCE_MAKE}"
        -P "${CMAKE_CURRENT_LIST_DIR}/tests/upstream-contract.cmake")
    set_tests_properties(pure-reduce-upstream-contract PROPERTIES
      FIXTURES_REQUIRED pure-reduce-upstream-built
      LABELS "reduce")
    add_test(
      NAME pure-reduce-upstream-artifacts-required
      COMMAND "${CMAKE_COMMAND}"
        "-DPURE_REDUCE_SOURCE_DIR=${PURE_REDUCE_SOURCE_DIR}"
        "-DPURE_REDUCE_UPSTREAM_CONTRACT=${CMAKE_CURRENT_LIST_DIR}/tests/upstream-contract.cmake"
        "-DPURE_REDUCE_MSYS2_BASH=${PURE_REDUCE_MSYS2_BASH}"
        "-DPURE_REDUCE_MAKE=${PURE_REDUCE_MAKE}"
        -P "${CMAKE_CURRENT_LIST_DIR}/tests/upstream-artifacts-required.cmake")
    set_tests_properties(pure-reduce-upstream-artifacts-required PROPERTIES
      LABELS "reduce")
    add_test(
      NAME pure-reduce-upstream-revalidation
      COMMAND "${CMAKE_COMMAND}"
        "-DPURE_REDUCE_SOURCE_DIR=${PURE_REDUCE_SOURCE_DIR}"
        "-DPURE_REDUCE_UPSTREAM_MODULE=${CMAKE_CURRENT_LIST_DIR}/cmake/ReduceUpstream.cmake"
        "-DPURE_REDUCE_MSYS2_BASH=${PURE_REDUCE_MSYS2_BASH}"
        "-DPURE_REDUCE_MAKE=${PURE_REDUCE_MAKE}"
        -P "${CMAKE_CURRENT_LIST_DIR}/tests/upstream-revalidation.cmake")
    set_tests_properties(pure-reduce-upstream-revalidation PROPERTIES
      LABELS "reduce")
    add_test(
      NAME pure-reduce-utf8-image-patch-contract
      COMMAND "${CMAKE_COMMAND}"
        "-DPURE_REDUCE_SOURCE_DIR=${PURE_REDUCE_SOURCE_DIR}"
        "-DPURE_REDUCE_SOURCE_TREE_SHA256=${PURE_REDUCE_SOURCE_TREE_SHA256}"
        -P "${CMAKE_CURRENT_LIST_DIR}/tests/utf8-image-patch-contract.cmake")
    set_tests_properties(pure-reduce-utf8-image-patch-contract PROPERTIES
      LABELS "reduce")
    cmake_path(GET PURE_REDUCE_LLVM_READOBJ PARENT_PATH
      _pure_reduce_clang64_bin)
    add_test(
      NAME pure-reduce-audit-windows-dependencies
      COMMAND "${CMAKE_COMMAND}"
        "-DPURE_REDUCE_SOURCE_DIR=${CMAKE_CURRENT_LIST_DIR}"
        "-DPURE_REDUCE_LLVM_READOBJ=${PURE_REDUCE_LLVM_READOBJ}"
        "-DPURE_REDUCE_CXX_COMPILER=${CMAKE_CXX_COMPILER}"
        "-DPURE_REDUCE_DLL=$<TARGET_FILE:reduce>"
        "-DPURE_REDUCE_SEARCH_DIRS=${PURE_REDUCE_UPSTREAM_BINARY_DIR};$<TARGET_FILE_DIR:reduce>;${_pure_reduce_clang64_bin}"
        "-DPURE_REDUCE_TEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/audit windows dependencies"
        -P "${CMAKE_CURRENT_LIST_DIR}/tests/audit-windows-dependencies.cmake")
    set_tests_properties(pure-reduce-audit-windows-dependencies PROPERTIES
      LABELS "reduce;audit;windows"
      REQUIRED_FILES "$<TARGET_FILE:reduce>"
      TIMEOUT 60)
    if(PURE_EXECUTABLE)
      add_test(
        NAME pure-reduce-install-component
        COMMAND "${CMAKE_COMMAND}"
          "-DBUILD_DIR=${CMAKE_CURRENT_BINARY_DIR}"
          "-DSTAGE_PREFIX=${CMAKE_CURRENT_BINARY_DIR}/PureReduce component stage"
          "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
          "-DPURE_LIBRARY_DIR=${_pure_reduce_library_dir}"
          "-DTEST_DRIVER=${CMAKE_CURRENT_LIST_DIR}/cmake/RunPureReduceTest.cmake"
          -P "${CMAKE_CURRENT_LIST_DIR}/tests/install-component.cmake")
      set_tests_properties(pure-reduce-install-component PROPERTIES
        LABELS "reduce;install;windows"
        REQUIRED_FILES "$<TARGET_FILE:reduce>"
        TIMEOUT 120)
    endif()
  endif()
endif()
