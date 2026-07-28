cmake_minimum_required(VERSION 3.25)

project(pure-odbc VERSION 0.10 LANGUAGES C)

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
  add_test(
    NAME pure-odbc-load
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DMODULE_DIR=$<TARGET_FILE_DIR:odbc>"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunLoadTest.cmake"
  )
  set_tests_properties(
    pure-odbc-load
    PROPERTIES
      LABELS "odbc;load;driver-manager"
      REQUIRED_FILES "$<TARGET_FILE:odbc>;${CMAKE_CURRENT_SOURCE_DIR}/odbc.pure"
      TIMEOUT 30
  )
endif()
