cmake_minimum_required(VERSION 3.25)

project(pure-xml VERSION 0.7 LANGUAGES C)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(LIBXML2 REQUIRED IMPORTED_TARGET "libxml-2.0>=2.9")
pkg_check_modules(LIBXSLT REQUIRED IMPORTED_TARGET "libxslt>=1.1")

add_library(xml MODULE xml.c)
target_compile_features(xml PRIVATE c_std_11)
target_link_libraries(
  xml
  PRIVATE
    PkgConfig::PURE
    PkgConfig::LIBXML2
    PkgConfig::LIBXSLT
)
if(CMAKE_C_COMPILER_ID MATCHES "Clang|GNU")
  target_compile_options(xml PRIVATE -Wno-deprecated-declarations)
elseif(MSVC)
  target_compile_options(xml PRIVATE /wd4996)
endif()
set_target_properties(
  xml
  PROPERTIES
    PREFIX ""
    WINDOWS_EXPORT_ALL_SYMBOLS ON
)

if(WIN32)
  pkg_get_variable(LIBXML2_PREFIX libxml-2.0 prefix)
  pkg_get_variable(LIBXSLT_PREFIX libxslt prefix)
  find_file(
    LIBXML2_RUNTIME_DLL
    NAMES libxml2-16.dll
    HINTS "${LIBXML2_PREFIX}/bin"
    NO_DEFAULT_PATH
    REQUIRED
  )
  find_file(
    LIBXSLT_RUNTIME_DLL
    NAMES libxslt-1.dll
    HINTS "${LIBXSLT_PREFIX}/bin"
    NO_DEFAULT_PATH
    REQUIRED
  )
  find_file(
    LIBICONV_RUNTIME_DLL
    NAMES libiconv-2.dll
    HINTS "${LIBXML2_PREFIX}/bin"
    NO_DEFAULT_PATH
    REQUIRED
  )
  find_file(
    ZLIB_RUNTIME_DLL
    NAMES zlib1.dll
    HINTS "${LIBXML2_PREFIX}/bin"
    NO_DEFAULT_PATH
    REQUIRED
  )
  set(LLVM_READOBJ_EXECUTABLE "" CACHE FILEPATH
    "llvm-readobj used for Windows PE validation")
  if(NOT LLVM_READOBJ_EXECUTABLE OR
      NOT EXISTS "${LLVM_READOBJ_EXECUTABLE}")
    message(FATAL_ERROR
      "Windows validation requires an existing LLVM_READOBJ_EXECUTABLE")
  endif()
  add_custom_target(
    verify-windows-dependencies
    COMMAND "${CMAKE_COMMAND}"
      "-DLLVM_READOBJ=${LLVM_READOBJ_EXECUTABLE}"
      "-DXML_DLL=$<TARGET_FILE:xml>"
      "-DLIBXML2_DLL=${LIBXML2_RUNTIME_DLL}"
      "-DLIBXSLT_DLL=${LIBXSLT_RUNTIME_DLL}"
      "-DLIBICONV_DLL=${LIBICONV_RUNTIME_DLL}"
      "-DZLIB_DLL=${ZLIB_RUNTIME_DLL}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
    DEPENDS xml
    COMMENT "Verifying the pure-xml Windows dependency closure"
    VERBATIM
  )
endif()

include(CTest)
if(BUILD_TESTING)
  pkg_get_variable(PURE_PREFIX pure prefix)
  if(WIN32)
    set(PURE_EXECUTABLE "" CACHE FILEPATH "Installed Pure interpreter for tests")
    if(NOT PURE_EXECUTABLE OR NOT EXISTS "${PURE_EXECUTABLE}")
      message(FATAL_ERROR "BUILD_TESTING requires an existing PURE_EXECUTABLE")
    endif()
  else()
    find_program(PURE_EXECUTABLE NAMES pure HINTS "${PURE_PREFIX}/bin" REQUIRED)
  endif()
  add_test(
    NAME pure-xml-smoke
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPACKAGE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DMODULE_DIR=$<TARGET_FILE_DIR:xml>"
      "-DRUNTIME_BIN_DIR=${LIBXML2_PREFIX}/bin"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
      "-DTEST_DATA_DIR=${CMAKE_CURRENT_SOURCE_DIR}/tests"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunSmokeTest.cmake"
  )
  set_tests_properties(
    pure-xml-smoke
    PROPERTIES
      LABELS "xml;xpath;xslt;encoding;paths;network-isolated"
      REQUIRED_FILES
        "$<TARGET_FILE:xml>;${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure;${CMAKE_CURRENT_SOURCE_DIR}/tests/input-utf8.xml;${CMAKE_CURRENT_SOURCE_DIR}/tests/transform.xsl"
      TIMEOUT 60
  )
  if(WIN32)
    set(contract_root "${CMAKE_CURRENT_BINARY_DIR}/pure-xml contract")
    add_executable(pure-xml-network-contract tests/network_contract.c)
    target_link_libraries(pure-xml-network-contract PRIVATE PkgConfig::LIBXML2)
    if(CMAKE_C_COMPILER_ID MATCHES "Clang|GNU")
      target_compile_options(pure-xml-network-contract PRIVATE
        -Wno-deprecated-declarations)
    endif()
    add_test(NAME pure-xml-network-contract
      COMMAND pure-xml-network-contract)
    set_tests_properties(pure-xml-network-contract PROPERTIES
      ENVIRONMENT_MODIFICATION
        "PATH=path_list_prepend:${LIBXML2_PREFIX}/bin")
    add_test(NAME pure-xml-runtime-verifier-contract COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DTEST_ROOT=${contract_root}/verifier"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/runtime_verifier_contract.cmake")
    add_test(NAME pure-xml-install-contract COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DTEST_ROOT=${contract_root}/install"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}"
      "-DLIBXML2_RUNTIME_DLL=${LIBXML2_RUNTIME_DLL}"
      "-DLIBXSLT_RUNTIME_DLL=${LIBXSLT_RUNTIME_DLL}"
      "-DLIBICONV_RUNTIME_DLL=${LIBICONV_RUNTIME_DLL}"
      "-DZLIB_RUNTIME_DLL=${ZLIB_RUNTIME_DLL}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/install_contract.cmake")
    add_test(NAME pure-xml-configure-contract COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DTEST_ROOT=${contract_root}/configure"
      "-DGENERATOR=${CMAKE_GENERATOR}"
      "-DMAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}"
      "-DC_COMPILER=${CMAKE_C_COMPILER}"
      "-DPKG_CONFIG_EXECUTABLE=${PKG_CONFIG_EXECUTABLE}"
      "-DPKG_CONFIG_PATH=$ENV{PKG_CONFIG_PATH}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/configure_contract.cmake")
    add_test(NAME pure-xml-runner-diagnostics-contract
      COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DRUNTIME_BIN_DIR=${LIBXML2_PREFIX}/bin"
      "-DTEST_ROOT=${contract_root}/runner"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/runner_diagnostics_contract.cmake")
    set_tests_properties(
      pure-xml-configure-contract
      pure-xml-runner-diagnostics-contract
      pure-xml-runtime-verifier-contract
      pure-xml-install-contract
      pure-xml-network-contract
      PROPERTIES LABELS "xml;contract" TIMEOUT 60)
  endif()
endif()

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/Install.cmake")
