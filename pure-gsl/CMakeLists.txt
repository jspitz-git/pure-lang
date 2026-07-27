cmake_minimum_required(VERSION 3.25)

project(pure-gsl VERSION 0.12 LANGUAGES C)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(GSL REQUIRED IMPORTED_TARGET "gsl>=2.8")

add_library(gsl MODULE gsl.c)
target_compile_features(gsl PRIVATE c_std_11)
target_link_libraries(gsl PRIVATE PkgConfig::PURE PkgConfig::GSL)
if(MINGW)
  target_link_options(gsl PRIVATE "LINKER:--enable-auto-import")
endif()
set_target_properties(
  gsl
  PROPERTIES
    PREFIX ""
    WINDOWS_EXPORT_ALL_SYMBOLS ON
)

if(WIN32)
  pkg_get_variable(GSL_PREFIX gsl prefix)
  find_file(
    GSL_RUNTIME_DLL
    NAMES libgsl-28.dll
    HINTS "${GSL_PREFIX}/bin"
    NO_DEFAULT_PATH
    REQUIRED
  )
  find_file(
    GSLCBLAS_RUNTIME_DLL
    NAMES libgslcblas-0.dll
    HINTS "${GSL_PREFIX}/bin"
    NO_DEFAULT_PATH
    REQUIRED
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
    NAME pure-gsl-load
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DMODULE_DIR=$<TARGET_FILE_DIR:gsl>"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunLoadTest.cmake"
  )
  set_tests_properties(
    pure-gsl-load
    PROPERTIES
      LABELS "gsl;load;modules"
      REQUIRED_FILES "$<TARGET_FILE:gsl>;${CMAKE_CURRENT_SOURCE_DIR}/gsl.pure"
      TIMEOUT 30
  )
endif()
