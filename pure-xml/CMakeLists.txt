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
  find_program(LLVM_READOBJ NAMES llvm-readobj REQUIRED)
  add_custom_target(
    verify-windows-dependencies
    COMMAND "${CMAKE_COMMAND}"
      "-DLLVM_READOBJ=${LLVM_READOBJ}"
      "-DXML_DLL=$<TARGET_FILE:xml>"
      "-DLIBXML2_DLL=${LIBXML2_RUNTIME_DLL}"
      "-DLIBXSLT_DLL=${LIBXSLT_RUNTIME_DLL}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
    DEPENDS xml
    COMMENT "Verifying the pure-xml Windows dependency closure"
    VERBATIM
  )
endif()

include(CTest)
if(BUILD_TESTING)
  pkg_get_variable(PURE_PREFIX pure prefix)
  find_program(PURE_EXECUTABLE NAMES pure HINTS "${PURE_PREFIX}/bin" REQUIRED)
  add_test(
    NAME pure-xml-smoke
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DMODULE_DIR=$<TARGET_FILE_DIR:xml>"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
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
endif()

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/Install.cmake")
