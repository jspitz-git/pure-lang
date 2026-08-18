cmake_minimum_required(VERSION 3.25)
project(pure_fastcgi C)

if(NOT WIN32)
  message(FATAL_ERROR "pure-fastcgi requires Windows")
endif()

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(GMP REQUIRED IMPORTED_TARGET gmp)
pkg_check_modules(MPFR REQUIRED IMPORTED_TARGET mpfr)

set(PURE_FASTCGI_FCGI2_ARCHIVE "" CACHE FILEPATH
  "Absolute path to the verified fcgi2 source archive")
if(NOT IS_ABSOLUTE "${PURE_FASTCGI_FCGI2_ARCHIVE}"
    OR NOT EXISTS "${PURE_FASTCGI_FCGI2_ARCHIVE}")
  message(FATAL_ERROR
    "PURE_FASTCGI_FCGI2_ARCHIVE must name an existing absolute file")
endif()

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/Fcgi2Dependency.cmake")
pure_fastcgi_prepare_fcgi2(
  ARCHIVE "${PURE_FASTCGI_FCGI2_ARCHIVE}"
  OUT_SOURCE_DIR fcgi2_source)
pure_fastcgi_add_fcgi2_target(SOURCE_DIR "${fcgi2_source}")
target_compile_options(fcgi2-static PRIVATE
  "-ffile-prefix-map=${CMAKE_CURRENT_SOURCE_DIR}=."
  "-ffile-prefix-map=${CMAKE_CURRENT_BINARY_DIR}=.")

add_library(pure-fastcgi MODULE fastcgi.c fastcgi_extra.c)
set_target_properties(pure-fastcgi PROPERTIES
  OUTPUT_NAME fastcgi
  PREFIX ""
  WINDOWS_EXPORT_ALL_SYMBOLS ON)
target_compile_features(pure-fastcgi PRIVATE c_std_11)
target_compile_options(pure-fastcgi PRIVATE
  "-ffile-prefix-map=${CMAKE_CURRENT_SOURCE_DIR}=."
  "-ffile-prefix-map=${CMAKE_CURRENT_BINARY_DIR}=.")
target_link_libraries(pure-fastcgi PRIVATE
  fcgi2-static
  PkgConfig::PURE
  PkgConfig::GMP
  PkgConfig::MPFR)

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/Install.cmake")

include(CTest)
find_program(LLVM_READOBJ NAMES llvm-readobj REQUIRED)
find_program(POWERSHELL_EXECUTABLE
  NAMES powershell.exe
  HINTS "$ENV{SystemRoot}/System32/WindowsPowerShell/v1.0"
  NO_DEFAULT_PATH
  REQUIRED)
add_custom_target(
  verify-windows-dependencies
  COMMAND "${CMAKE_COMMAND}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    "-DMODULE=$<TARGET_FILE:pure-fastcgi>"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
  DEPENDS pure-fastcgi
  COMMENT "Verifying the pure-fastcgi Windows dependency closure"
  VERBATIM)

if(BUILD_TESTING)
  add_executable(pure-fastcgi-protocol-harness
    tests/protocol_harness.c)
  target_compile_features(pure-fastcgi-protocol-harness PRIVATE c_std_11)
  target_link_options(pure-fastcgi-protocol-harness PRIVATE -municode)
  add_dependencies(pure-fastcgi-protocol-harness pure-fastcgi)

  add_executable(pure-fastcgi-protocol-codec-test
    tests/protocol_codec_test.c)
  target_compile_features(pure-fastcgi-protocol-codec-test PRIVATE c_std_11)
  add_test(
    NAME pure-fastcgi-protocol-codec
    COMMAND pure-fastcgi-protocol-codec-test)
  set_tests_properties(pure-fastcgi-protocol-codec PROPERTIES
    LABELS "fastcgi;protocol;codec"
    TIMEOUT 20)

  add_executable(pure-fastcgi-protocol-codec-ndebug-test
    tests/protocol_codec_test.c)
  target_compile_features(pure-fastcgi-protocol-codec-ndebug-test
    PRIVATE c_std_11)
  target_compile_definitions(pure-fastcgi-protocol-codec-ndebug-test PRIVATE
    NDEBUG
    PURE_FASTCGI_NDEBUG_PROBE)
  add_test(
    NAME pure-fastcgi-protocol-codec-ndebug
    COMMAND "${CMAKE_COMMAND}"
      "-DPROGRAM=$<TARGET_FILE:pure-fastcgi-protocol-codec-ndebug-test>"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunNdebugCodecTest.cmake")
  set_tests_properties(pure-fastcgi-protocol-codec-ndebug PROPERTIES
    LABELS "fastcgi;protocol;codec"
    TIMEOUT 20)

  set(PURE_FASTCGI_PURE_EXECUTABLE "${PURE_PREFIX}/bin/pure.exe")
  set(PURE_FASTCGI_PURE_RUNTIME_DIR "${PURE_PREFIX}/bin")
  add_test(
    NAME pure-fastcgi-protocol-smoke
    COMMAND "${CMAKE_COMMAND}"
      "-DHARNESS=$<TARGET_FILE:pure-fastcgi-protocol-harness>"
      "-DMODULE=$<TARGET_FILE:pure-fastcgi>"
      "-DMODULE_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}/fastcgi.pure"
      "-DWORKER=${CMAKE_CURRENT_SOURCE_DIR}/tests/protocol_worker.pure"
      "-DPURE_EXECUTABLE=${PURE_FASTCGI_PURE_EXECUTABLE}"
      "-DPURE_RUNTIME_DIR=${PURE_FASTCGI_PURE_RUNTIME_DIR}"
      "-DTEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/protocol-smoke"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunProtocolTest.cmake")
  set_tests_properties(pure-fastcgi-protocol-smoke PROPERTIES
    LABELS "fastcgi;protocol;smoke"
    TIMEOUT 20)

  add_test(
    NAME pure-fastcgi-protocol-failures
    COMMAND "${CMAKE_COMMAND}"
      "-DHARNESS=$<TARGET_FILE:pure-fastcgi-protocol-harness>"
      "-DMODULE=$<TARGET_FILE:pure-fastcgi>"
      "-DMODULE_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}/fastcgi.pure"
      "-DWORKER=${CMAKE_CURRENT_SOURCE_DIR}/tests/protocol_worker.pure"
      "-DTRUNCATED_WORKER=${CMAKE_CURRENT_SOURCE_DIR}/tests/protocol_worker_truncated.pure"
      "-DTRUNCATED_WRONG_WORKER=${CMAKE_CURRENT_SOURCE_DIR}/tests/protocol_worker_truncated_wrong.pure"
      "-DHANG_WORKER=${CMAKE_CURRENT_SOURCE_DIR}/tests/protocol_worker_hang.pure"
      "-DPURE_EXECUTABLE=${PURE_FASTCGI_PURE_EXECUTABLE}"
      "-DPURE_RUNTIME_DIR=${PURE_FASTCGI_PURE_RUNTIME_DIR}"
      "-DTEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/protocol-failures"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/protocol_failures.cmake")
  set_tests_properties(pure-fastcgi-protocol-failures PROPERTIES
    LABELS "fastcgi;protocol;failures"
    TIMEOUT 30)

  add_test(
    NAME pure-fastcgi-source-contract
    COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DFCGI2_ARCHIVE=${PURE_FASTCGI_FCGI2_ARCHIVE}"
      "-DTEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/source-contract"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/source-contract.cmake")
  set_tests_properties(pure-fastcgi-source-contract PROPERTIES
    LABELS "fastcgi;source;contract"
    TIMEOUT 30)
  add_test(
    NAME pure-fastcgi-compile-contract
    COMMAND "${CMAKE_COMMAND}"
      "-DBUILD_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/CompilePatchedSources.cmake")
  set_tests_properties(pure-fastcgi-compile-contract PROPERTIES
    LABELS "fastcgi;compile;contract"
    RUN_SERIAL TRUE
    TIMEOUT 60)
  add_test(
    NAME pure-fastcgi-windows-dependency-verifier
    COMMAND "${CMAKE_COMMAND}"
      "-DVERIFIER=${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
      "-DTEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/windows-dependency-verifier"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/VerifyWindowsDependenciesTest.cmake")
  set_tests_properties(pure-fastcgi-windows-dependency-verifier PROPERTIES
    LABELS "fastcgi;windows;verifier"
    TIMEOUT 30)

  add_test(
    NAME pure-fastcgi-install-component
    COMMAND "${CMAKE_COMMAND}"
      "-DBUILD_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DSTAGE_PREFIX=${CMAKE_CURRENT_BINARY_DIR}/PureFastCGI component stage"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/install-component.cmake")
  set_tests_properties(pure-fastcgi-install-component PROPERTIES
    LABELS "fastcgi;install;windows"
    RUN_SERIAL TRUE
    TIMEOUT 120)

  add_test(
    NAME pure-fastcgi-package-verifier
    COMMAND "${CMAKE_COMMAND}"
      "-DBUILD_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DSTAGE_PREFIX=${CMAKE_CURRENT_BINARY_DIR}/PureFastCGI verifier stage"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DPURE_RUNTIME_ROOT=${PURE_PREFIX}/bin"
      "-DLLVM_READOBJ=${LLVM_READOBJ}"
      "-DPOWERSHELL_EXECUTABLE=${POWERSHELL_EXECUTABLE}"
      "-DVERIFIER=${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyInstalledPackage.cmake"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/package-mutations.cmake")
  set_tests_properties(pure-fastcgi-package-verifier PROPERTIES
    LABELS "fastcgi;package;windows"
    RUN_SERIAL TRUE
    TIMEOUT 180)
endif()
