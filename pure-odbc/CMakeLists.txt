cmake_minimum_required(VERSION 3.29)

project(pure-odbc VERSION 0.10 LANGUAGES C)

option(PURE_ODBC_BUILD_FAULT_TESTS "Build native ODBC fault-injection tests" OFF)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(GMP REQUIRED IMPORTED_TARGET gmp)

add_library(odbc MODULE odbc.c)
target_compile_features(odbc PRIVATE c_std_11)
target_link_libraries(odbc PRIVATE PkgConfig::PURE PkgConfig::GMP)
if(WIN32)
  target_link_libraries(odbc PRIVATE odbc32)
endif()
if(MINGW)
  target_compile_options(odbc PRIVATE -Wall -Wextra -Werror)
  target_link_options(odbc PRIVATE "LINKER:--enable-auto-import")
endif()
set_target_properties(odbc PROPERTIES PREFIX "" WINDOWS_EXPORT_ALL_SYMBOLS ON)

if(WIN32)
  find_file(
    GMP_RUNTIME_DLL
    NAMES libgmp-10.dll
    HINTS "$ENV{MSYSTEM_PREFIX}/bin"
    NO_DEFAULT_PATH
    REQUIRED
  )
  find_program(LLVM_READOBJ NAMES llvm-readobj REQUIRED)
  add_custom_target(
    verify-windows-dependencies
    COMMAND "${CMAKE_COMMAND}"
      "-DLLVM_READOBJ=${LLVM_READOBJ}"
      "-DODBC_MODULE=$<TARGET_FILE:odbc>"
      "-DGMP_DLL=${GMP_RUNTIME_DLL}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
    DEPENDS odbc
    COMMENT "Verifying the pure-odbc Windows dependency closure"
    VERBATIM
  )
endif()

include(CTest)
if(BUILD_TESTING)
  pkg_get_variable(PURE_PREFIX pure prefix)
  find_program(
    PURE_EXECUTABLE
    NAMES pure
    HINTS "${PURE_PREFIX}/bin"
    NO_DEFAULT_PATH
    REQUIRED
  )
  include("${CMAKE_CURRENT_SOURCE_DIR}/tests/ContractTestRoot.cmake")
  pure_odbc_prepare_contract_test_root(
    "access"
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_BINARY_DIR}"
    access_work_directory
  )
  configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/data/people.csv"
    "${access_work_directory}/people.csv"
    COPYONLY
  )
  configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/data/Schema.ini"
    "${access_work_directory}/Schema.ini"
    COPYONLY
  )

  add_test(
    NAME pure-odbc-manager-smoke
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DMODULE_DIR=$<TARGET_FILE_DIR:odbc>"
      "-DSCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
      "-DWORK_DIRECTORY=${CMAKE_CURRENT_BINARY_DIR}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake"
  )
  set_tests_properties(
    pure-odbc-manager-smoke
    PROPERTIES
      LABELS "odbc;driver-manager;drivers;diagnostics"
      REQUIRED_FILES
        "$<TARGET_FILE:odbc>;${CMAKE_CURRENT_SOURCE_DIR}/odbc.pure;${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
      TIMEOUT 30
  )
  add_test(
    NAME pure-odbc-access-text-smoke
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DMODULE_DIR=$<TARGET_FILE_DIR:odbc>"
      "-DSCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/access_smoke.pure"
      "-DWORK_DIRECTORY=${access_work_directory}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake"
  )
  set_tests_properties(
    pure-odbc-access-text-smoke
    PROPERTIES
      LABELS "odbc;access-text;parameters;results;cleanup"
      REQUIRED_FILES
        "$<TARGET_FILE:odbc>;${CMAKE_CURRENT_SOURCE_DIR}/odbc.pure;${CMAKE_CURRENT_SOURCE_DIR}/tests/access_smoke.pure;${access_work_directory}/people.csv;${access_work_directory}/Schema.ini"
      SKIP_RETURN_CODE 77
      TIMEOUT 60
  )

  if(WIN32)
    cmake_path(GET PKG_CONFIG_EXECUTABLE PARENT_PATH pkg_config_bin)
    cmake_path(GET pkg_config_bin PARENT_PATH msystem_prefix)
    cmake_path(GET msystem_prefix PARENT_PATH msys_root)
    find_program(
      PURE_ODBC_MAKE_EXECUTABLE
      NAMES make
      HINTS "${msys_root}/usr/bin"
      NO_DEFAULT_PATH
      REQUIRED
    )
    add_test(
      NAME pure-odbc-runner-contract
      COMMAND "${CMAKE_COMMAND}"
        "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/runner_contract.cmake"
    )
    add_test(
      NAME pure-odbc-cleanup-contract
      COMMAND "${CMAKE_COMMAND}"
        "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
        "-DMAKE_EXECUTABLE=${PURE_ODBC_MAKE_EXECUTABLE}"
        "-DPKG_CONFIG_EXECUTABLE=${PKG_CONFIG_EXECUTABLE}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/cleanup_contract.cmake"
    )
    set_tests_properties(
      pure-odbc-runner-contract pure-odbc-cleanup-contract
      PROPERTIES LABELS "odbc;contract" TIMEOUT 120
    )
  endif()

  if(PURE_ODBC_BUILD_FAULT_TESTS)
    add_executable(pure-odbc-fault-tests tests/odbc_fault_harness.c)
    target_compile_features(pure-odbc-fault-tests PRIVATE c_std_11)
    target_compile_definitions(pure-odbc-fault-tests PRIVATE PURE_ODBC_TESTING)
    target_link_libraries(
      pure-odbc-fault-tests
      PRIVATE PkgConfig::PURE PkgConfig::GMP
    )
    if(WIN32)
      target_link_libraries(pure-odbc-fault-tests PRIVATE odbc32)
    endif()
    if(MINGW)
      target_compile_options(
        pure-odbc-fault-tests
        PRIVATE -Wall -Wextra -Werror -fsanitize=address -fno-omit-frame-pointer
      )
      target_link_options(pure-odbc-fault-tests PRIVATE -fsanitize=address)
    endif()
    add_test(NAME pure-odbc-fault COMMAND pure-odbc-fault-tests)
    set_tests_properties(
      pure-odbc-fault
      PROPERTIES LABELS "odbc;fault;asan" TIMEOUT 30
    )
  endif()
endif()
include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/Install.cmake")
