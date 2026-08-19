cmake_minimum_required(VERSION 3.25)
project(pure_bonjour VERSION 0.2 LANGUAGES C)

if(NOT WIN32)
  message(FATAL_ERROR "pure-bonjour Windows backend requires Windows")
endif()

if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
  message(FATAL_ERROR "PureBonjour supports only 64-bit Windows")
endif()

if(NOT DEFINED PURE_PREFIX)
  message(FATAL_ERROR "PURE_PREFIX is required")
endif()
set(pure_bonjour_requested_prefix "${PURE_PREFIX}")
include(cmake/ValidateConfigure.cmake)
pure_bonjour_validate_target()

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pure_bonjour_validate_configure("${pure_bonjour_requested_prefix}" "${PURE_INCLUDE_DIRS}"
  "${pkgcfg_lib_PURE_pure}")
file(REAL_PATH "${pure_bonjour_requested_prefix}" PURE_PREFIX)

add_library(pure-bonjour MODULE bonjour_windows.c)
set_target_properties(pure-bonjour PROPERTIES OUTPUT_NAME bonjour PREFIX ""
  WINDOWS_EXPORT_ALL_SYMBOLS ON)
target_compile_features(pure-bonjour PRIVATE c_std_11)
target_compile_definitions(pure-bonjour PRIVATE
  _WIN32_WINNT=0x0A00 UNICODE _UNICODE)
target_compile_options(pure-bonjour PRIVATE -Wall -Wextra -Werror)
target_link_libraries(pure-bonjour PRIVATE PkgConfig::PURE dnsapi ws2_32)

include(cmake/Install.cmake)

get_filename_component(pure_bonjour_compiler_directory
  "${CMAKE_C_COMPILER}" DIRECTORY)
find_program(PURE_BONJOUR_LLVM_READOBJ
  NAMES llvm-readobj
  HINTS "${pure_bonjour_compiler_directory}"
  REQUIRED)
add_custom_target(verify-windows-dependencies
  COMMAND "${CMAKE_COMMAND}"
    "-DLLVM_READOBJ=${PURE_BONJOUR_LLVM_READOBJ}"
    "-DMODULE=$<TARGET_FILE:pure-bonjour>"
    "-DPURE_PREFIX=${PURE_PREFIX}"
    "-DVERIFY_WORK_DIR=${CMAKE_CURRENT_BINARY_DIR}/dependency-audit"
    "-DDEPENDENCY_REPORT=${CMAKE_CURRENT_BINARY_DIR}/PureBonjourDependencies.tsv"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
  DEPENDS pure-bonjour
  COMMENT "Verifying recursive PureBonjour Windows dependencies"
  VERBATIM)

include(CTest)
if(BUILD_TESTING)
  add_test(NAME pure-bonjour-configure-contract
    COMMAND "${CMAKE_COMMAND}"
      "-DVALIDATOR=${CMAKE_CURRENT_SOURCE_DIR}/cmake/ValidateConfigure.cmake"
      "-DTEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/configure-contract"
      "-DC_COMPILER=${CMAKE_C_COMPILER}"
      "-DGENERATOR=${CMAKE_GENERATOR}"
      "-DMAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/configure-contract.cmake")
  set_tests_properties(pure-bonjour-configure-contract PROPERTIES
    LABELS "bonjour;unit;configure" TIMEOUT 15)

  add_test(NAME pure-bonjour-sdk-runtime-closure-contract
    COMMAND "${CMAKE_COMMAND}"
      "-DSTAGER=${CMAKE_CURRENT_SOURCE_DIR}/../pure/cmake/StageWindowsRuntimeDlls.cmake"
      "-DTEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/sdk-runtime-closure-fixture"
      "-DLLVM_READOBJ=${PURE_BONJOUR_LLVM_READOBJ}"
      "-DTOOLCHAIN_BIN=${pure_bonjour_compiler_directory}"
      "-DPURE_RUNTIME_BIN=${PURE_PREFIX}/bin"
      "-DPRODUCTION_MANIFEST=${CMAKE_CURRENT_SOURCE_DIR}/cmake/PureWindowsRuntimeClosure.cmake"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/sdk-runtime-closure.cmake")
  set_tests_properties(pure-bonjour-sdk-runtime-closure-contract PROPERTIES
    LABELS "bonjour;unit;ci;packaging" TIMEOUT 15)

  add_executable(pure-bonjour-installed-sdk-consumer
    tests/installed-sdk-consumer.c)
  target_compile_features(pure-bonjour-installed-sdk-consumer PRIVATE c_std_11)
  target_compile_options(pure-bonjour-installed-sdk-consumer PRIVATE
    -Wall -Wextra -Werror)
  target_link_libraries(pure-bonjour-installed-sdk-consumer PRIVATE
    PkgConfig::PURE)
  add_test(NAME pure-bonjour-installed-sdk-consumer
    COMMAND pure-bonjour-installed-sdk-consumer)
  set_tests_properties(pure-bonjour-installed-sdk-consumer PROPERTIES
    LABELS "bonjour;unit;installed" TIMEOUT 10)

  add_test(NAME pure-bonjour-ci-contract
    COMMAND "${CMAKE_COMMAND}"
      "-DWORKFLOW=${CMAKE_CURRENT_SOURCE_DIR}/../.github/workflows/non-linux-release-validation.yml"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/ci-contract.cmake")
  set_tests_properties(pure-bonjour-ci-contract PROPERTIES
    LABELS "bonjour;unit;ci" TIMEOUT 30)

  add_test(NAME pure-bonjour-install-destinations
    COMMAND "${CMAKE_COMMAND}"
      -DTEST_MODE=destinations
      "-DCMAKE_COMMAND=${CMAKE_COMMAND}"
      "-DINSTALL_MODULE=${CMAKE_CURRENT_SOURCE_DIR}/cmake/Install.cmake"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/install-component.cmake")
  set_tests_properties(pure-bonjour-install-destinations PROPERTIES
    LABELS "bonjour;unit;packaging" TIMEOUT 10)

  add_test(NAME pure-bonjour-dependency-parser
    COMMAND "${CMAKE_COMMAND}"
      -DTEST_MODE=parser
      "-DCMAKE_COMMAND=${CMAKE_COMMAND}"
      "-DVERIFIER=${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
      "-DTEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/dependency-parser-fixtures"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/install-component.cmake")
  set_tests_properties(pure-bonjour-dependency-parser PROPERTIES
    LABELS "bonjour;unit;packaging" TIMEOUT 10)

  add_test(NAME pure-bonjour-install-component
    COMMAND "${CMAKE_COMMAND}"
      -DTEST_MODE=install
      "-DCMAKE_COMMAND=${CMAKE_COMMAND}"
      "-DBUILD_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DSTAGE_PREFIX=${CMAKE_CURRENT_BINARY_DIR}/PureBonjour component stage"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/install-component.cmake")
  set_tests_properties(pure-bonjour-install-component PROPERTIES
    LABELS "bonjour;packaging" TIMEOUT 30)

  add_test(NAME pure-bonjour-package-verifier
    COMMAND "${CMAKE_COMMAND}"
      -DTEST_MODE=valid
      "-DCMAKE_COMMAND=${CMAKE_COMMAND}"
      "-DBUILD_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DVERIFIER=${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyInstalledPackage.cmake"
      "-DSOURCE_PREFIX=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DPURE_PREFIX=${PURE_PREFIX}"
      "-DTEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/package-verifier"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/package-mutations.cmake")
  set_tests_properties(pure-bonjour-package-verifier PROPERTIES
    LABELS "bonjour;packaging;installed" TIMEOUT 60 RUN_SERIAL TRUE)

  add_test(NAME pure-bonjour-package-mutations
    COMMAND "${CMAKE_COMMAND}"
      -DTEST_MODE=mutations
      "-DCMAKE_COMMAND=${CMAKE_COMMAND}"
      "-DBUILD_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DVERIFIER=${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyInstalledPackage.cmake"
      "-DSOURCE_PREFIX=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DPURE_PREFIX=${PURE_PREFIX}"
      "-DTEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/package-mutations"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/package-mutations.cmake")
  set_tests_properties(pure-bonjour-package-mutations PROPERTIES
    LABELS "bonjour;packaging;installed;mutation" TIMEOUT 120 RUN_SERIAL TRUE)

  add_test(NAME pure-bonjour-relocation-ownership
    COMMAND "${CMAKE_COMMAND}"
      "-DCMAKE_COMMAND=${CMAKE_COMMAND}"
      "-DBUILD_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DVERIFIER=${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyInstalledPackage.cmake"
      "-DSOURCE_PREFIX=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DPURE_PREFIX=${PURE_PREFIX}"
      "-DTEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/Relocation Ownership"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/relocation-ownership.cmake")
  set_tests_properties(pure-bonjour-relocation-ownership PROPERTIES
    LABELS "bonjour;packaging;installed;relocation" TIMEOUT 180
    RUN_SERIAL TRUE)

  add_library(pure-bonjour-test-backend OBJECT bonjour_windows.c)
  target_compile_features(pure-bonjour-test-backend PRIVATE c_std_11)
  target_compile_definitions(pure-bonjour-test-backend PRIVATE
    _WIN32_WINNT=0x0A00 UNICODE _UNICODE BONJOUR_WINDOWS_TESTING)
  target_compile_options(pure-bonjour-test-backend PRIVATE -Wall -Wextra -Werror)
  target_include_directories(pure-bonjour-test-backend PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR})
  target_link_libraries(pure-bonjour-test-backend PRIVATE PkgConfig::PURE)

  add_executable(pure-bonjour-unit tests/unit.c
    $<TARGET_OBJECTS:pure-bonjour-test-backend>)
  target_compile_features(pure-bonjour-unit PRIVATE c_std_11)
  target_compile_definitions(pure-bonjour-unit PRIVATE
    _WIN32_WINNT=0x0A00 UNICODE _UNICODE BONJOUR_WINDOWS_TESTING)
  target_compile_options(pure-bonjour-unit PRIVATE -Wall -Wextra -Werror -UNDEBUG)
  target_include_directories(pure-bonjour-unit PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
  target_link_libraries(pure-bonjour-unit PRIVATE PkgConfig::PURE dnsapi ws2_32)
  add_test(NAME pure-bonjour-unit COMMAND pure-bonjour-unit)
  set_tests_properties(pure-bonjour-unit PROPERTIES LABELS "bonjour;unit"
    TIMEOUT 10 ENVIRONMENT_MODIFICATION
    "PATH=path_list_prepend:${PURE_PREFIX}/bin")

  add_executable(pure-bonjour-lifecycle tests/lifecycle.c
    $<TARGET_OBJECTS:pure-bonjour-test-backend>)
  target_compile_features(pure-bonjour-lifecycle PRIVATE c_std_11)
  target_compile_definitions(pure-bonjour-lifecycle PRIVATE
    _WIN32_WINNT=0x0A00 UNICODE _UNICODE BONJOUR_WINDOWS_TESTING)
  target_compile_options(pure-bonjour-lifecycle PRIVATE
    -Wall -Wextra -Werror -UNDEBUG)
  target_include_directories(pure-bonjour-lifecycle PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR})
  target_link_libraries(pure-bonjour-lifecycle PRIVATE
    PkgConfig::PURE dnsapi ws2_32)
  add_test(NAME pure-bonjour-lifecycle COMMAND pure-bonjour-lifecycle)
  set_tests_properties(pure-bonjour-lifecycle PROPERTIES
    LABELS "bonjour;lifecycle" TIMEOUT 10 ENVIRONMENT_MODIFICATION
    "PATH=path_list_prepend:${PURE_PREFIX}/bin")

  set(PURE_BONJOUR_LOOPBACK_TIMEOUT_SECONDS 30)
  add_test(NAME pure-bonjour-smoke-budget-contract
    COMMAND "${CMAKE_COMMAND}"
      "-DRUNNER=${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunSmokeTest.cmake"
      "-DSMOKE_OUTER_TIMEOUT_SECONDS=${PURE_BONJOUR_LOOPBACK_TIMEOUT_SECONDS}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/TestSmokeBudgets.cmake")
  set_tests_properties(pure-bonjour-smoke-budget-contract PROPERTIES
    LABELS "bonjour;unit" TIMEOUT 5)

  set(PURE_EXECUTABLE "${PURE_PREFIX}/bin/pure.exe")
  if(EXISTS "${PURE_EXECUTABLE}")
    add_test(NAME pure-bonjour-loopback
      COMMAND "${CMAKE_COMMAND}"
        "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
        "-DMODULE_PATH=$<TARGET_FILE:pure-bonjour>"
        "-DWRAPPER_PATH=${CMAKE_CURRENT_SOURCE_DIR}/bonjour.pure"
        "-DSMOKE_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
        "-DSMOKE_ROOT=${CMAKE_CURRENT_BINARY_DIR}"
        "-DSMOKE_OUTER_TIMEOUT_SECONDS=${PURE_BONJOUR_LOOPBACK_TIMEOUT_SECONDS}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunSmokeTest.cmake")
    set_tests_properties(pure-bonjour-loopback PROPERTIES
      LABELS "bonjour;dnssd;integration"
      TIMEOUT ${PURE_BONJOUR_LOOPBACK_TIMEOUT_SECONDS})
  endif()
endif()
