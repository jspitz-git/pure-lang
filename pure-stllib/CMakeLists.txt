cmake_minimum_required(VERSION 3.25)

project(pure-stllib VERSION 0.6 LANGUAGES CXX)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(GMP REQUIRED IMPORTED_TARGET gmp)
pkg_get_variable(PURE_PREFIX pure prefix)

option(PURE_STLLIB_WARNINGS_AS_ERRORS
  "Treat supported compiler warnings as errors" ON)

add_library(stlbase SHARED stlbase.cpp)
target_compile_features(stlbase PRIVATE cxx_std_17)
target_include_directories(stlbase PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(stlbase PRIVATE PkgConfig::PURE PkgConfig::GMP)

add_library(stlvec SHARED pure-stlvec/stlvec.cpp)
target_compile_features(stlvec PRIVATE cxx_std_17)
target_include_directories(
  stlvec
  PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/pure-stlvec"
)
target_link_libraries(stlvec PRIVATE PkgConfig::PURE stlbase)

add_library(
  stlalgorithm
  SHARED
  pure-stlvec/sv_modifying.cpp
  pure-stlvec/sv_nonmodifying.cpp
  pure-stlvec/sv_sort.cpp
  pure-stlvec/sv_merge.cpp
  pure-stlvec/sv_heap.cpp
  pure-stlvec/sv_minmax.cpp
  pure-stlvec/sv_numeric.cpp
)
target_compile_features(stlalgorithm PRIVATE cxx_std_17)
target_include_directories(
  stlalgorithm
  PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/pure-stlvec"
)
target_link_libraries(stlalgorithm PRIVATE PkgConfig::PURE stlbase stlvec)

foreach(module IN ITEMS stlmap stlmmap stlhmap)
  add_library(${module} SHARED "pure-stlmap/${module}.cpp")
  target_compile_features(${module} PRIVATE cxx_std_17)
  target_include_directories(
    ${module}
    PRIVATE
      "${CMAKE_CURRENT_SOURCE_DIR}"
      "${CMAKE_CURRENT_SOURCE_DIR}/pure-stlmap"
  )
  target_link_libraries(${module} PRIVATE PkgConfig::PURE stlbase)
endforeach()

foreach(module IN ITEMS
    stlbase
    stlvec
    stlalgorithm
    stlmap
    stlmmap
    stlhmap)
  set_target_properties(
    ${module}
    PROPERTIES
      CXX_EXTENSIONS OFF
      PREFIX ""
      WINDOWS_EXPORT_ALL_SYMBOLS ON
  )
  if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(${module} PRIVATE -Wall -Wextra -Wpedantic)
    if(PURE_STLLIB_WARNINGS_AS_ERRORS)
      target_compile_options(${module} PRIVATE -Werror)
    endif()
  endif()
endforeach()

if(WIN32)
  set(LLVM_READOBJ_EXECUTABLE "" CACHE FILEPATH
    "llvm-readobj used for Windows PE validation")
  if(NOT LLVM_READOBJ_EXECUTABLE OR
      NOT EXISTS "${LLVM_READOBJ_EXECUTABLE}")
    message(FATAL_ERROR
      "Windows validation requires an existing LLVM_READOBJ_EXECUTABLE")
  endif()
  add_custom_target(
    verify-windows-runtime
    COMMAND "${CMAKE_COMMAND}"
      "-DLLVM_READOBJ=${LLVM_READOBJ_EXECUTABLE}"
      "-DSTLBASE_DLL=$<TARGET_FILE:stlbase>"
      "-DSTLVEC_DLL=$<TARGET_FILE:stlvec>"
      "-DSTLALGORITHM_DLL=$<TARGET_FILE:stlalgorithm>"
      "-DSTLMAP_DLL=$<TARGET_FILE:stlmap>"
      "-DSTLMMAP_DLL=$<TARGET_FILE:stlmmap>"
      "-DSTLHMAP_DLL=$<TARGET_FILE:stlhmap>"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyWindowsRuntime.cmake"
    DEPENDS
      stlbase
      stlvec
      stlalgorithm
      stlmap
      stlmmap
      stlhmap
    COMMENT "Verifying the pure-stllib Windows runtime dependency closure"
    VERBATIM
  )
endif()

include(CTest)
if(BUILD_TESTING)
  if(WIN32)
    set(PURE_EXECUTABLE "" CACHE FILEPATH "Installed Pure interpreter for tests")
    if(NOT PURE_EXECUTABLE OR NOT EXISTS "${PURE_EXECUTABLE}")
      message(FATAL_ERROR "BUILD_TESTING requires an existing PURE_EXECUTABLE")
    endif()
  else()
    find_program(PURE_EXECUTABLE NAMES pure HINTS "${PURE_PREFIX}/bin" REQUIRED)
  endif()
  get_filename_component(pure_bin_dir "${PURE_EXECUTABLE}" DIRECTORY)
  get_filename_component(pure_runtime_prefix "${pure_bin_dir}" DIRECTORY)
  if(NOT EXISTS "${pure_runtime_prefix}/lib/pure/math.pure")
    message(FATAL_ERROR
      "PURE_EXECUTABLE must belong to an installed Pure runtime prefix")
  endif()

  foreach(test_kind IN ITEMS stlvec stlmap)
    add_test(
      NAME "pure-stllib-${test_kind}"
      COMMAND "${CMAKE_COMMAND}"
        "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
        "-DPACKAGE_DIRS=${CMAKE_CURRENT_SOURCE_DIR};${CMAKE_CURRENT_SOURCE_DIR}/pure-stlvec;${CMAKE_CURRENT_SOURCE_DIR}/pure-stlmap"
        "-DTEST_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
        "-DMODULE_DIR=$<TARGET_FILE_DIR:stlbase>"
        "-DTEST_KIND=${test_kind}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPackageTests.cmake"
    )
    set_tests_properties(
      "pure-stllib-${test_kind}"
      PROPERTIES
        REQUIRED_FILES
          "$<TARGET_FILE:stlbase>;$<TARGET_FILE:stlvec>;$<TARGET_FILE:stlalgorithm>;$<TARGET_FILE:stlmap>;$<TARGET_FILE:stlmmap>;$<TARGET_FILE:stlhmap>"
        TIMEOUT 120
    )
  endforeach()

  set_tests_properties(
    pure-stllib-stlvec
    PROPERTIES LABELS "stllib;vector;algorithms;lifetime"
  )
  set_tests_properties(
    pure-stllib-stlmap
    PROPERTIES LABELS "stllib;map;multimap;hashmap;set;iterators"
  )

  if(WIN32)
    set(contract_root "${CMAKE_CURRENT_BINARY_DIR}/pure-stllib contract")
    add_test(NAME pure-stllib-configure-contract COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DTEST_ROOT=${contract_root}/configure"
      "-DGENERATOR=${CMAKE_GENERATOR}"
      "-DMAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}"
      "-DCXX_COMPILER=${CMAKE_CXX_COMPILER}"
      "-DPKG_CONFIG_EXECUTABLE=${PKG_CONFIG_EXECUTABLE}"
      "-DPKG_CONFIG_PATH=$ENV{PKG_CONFIG_PATH}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/configure_contract.cmake")
    add_test(NAME pure-stllib-numeric-contract COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/numeric_contract.cmake")
    add_test(NAME pure-stllib-runner-diagnostics-contract
      COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DTEST_ROOT=${contract_root}/runner"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/runner_diagnostics_contract.cmake")
    add_test(NAME pure-stllib-runner-allowlist-contract
      COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DTEST_ROOT=${contract_root}/allowlist"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/runner_allowlist_contract.cmake")
    add_test(NAME pure-stllib-runtime-verifier-contract
      COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DTEST_ROOT=${contract_root}/runtime verifier"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/runtime_verifier_contract.cmake")
    add_test(NAME pure-stllib-install-contract COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DTEST_ROOT=${contract_root}/install"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/install_contract.cmake")
    set_tests_properties(
      pure-stllib-configure-contract
      pure-stllib-numeric-contract
      pure-stllib-runner-diagnostics-contract
      pure-stllib-runner-allowlist-contract
      pure-stllib-runtime-verifier-contract
      pure-stllib-install-contract
      PROPERTIES LABELS "stllib;contract" TIMEOUT 180)
  endif()
endif()

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/Install.cmake")
