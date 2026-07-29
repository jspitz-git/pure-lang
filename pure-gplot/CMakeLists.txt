cmake_minimum_required(VERSION 3.25)

project(pure-gplot VERSION 0.1 LANGUAGES C)

include(CTest)

set(PURE_PREFIX "" CACHE PATH "Portable Pure prefix used for tests")
set(GNUPLOT_ROOT "" CACHE PATH
  "Controlled gnuplot 6.0.4 root used for Windows tests and packaging")

if(WIN32)
  add_library(gplot MODULE gplot_win.c)
  target_compile_features(gplot PRIVATE c_std_11)
  target_compile_options(gplot PRIVATE -Wall -Wextra)
  set_target_properties(gplot PROPERTIES
    PREFIX ""
    WINDOWS_EXPORT_ALL_SYMBOLS ON)
endif()

if(BUILD_TESTING)
  if(NOT IS_DIRECTORY "${PURE_PREFIX}")
    message(FATAL_ERROR "Set PURE_PREFIX to a portable Pure installation")
  endif()
  find_program(PURE_EXECUTABLE
    NAMES pure.exe pure
    HINTS "${PURE_PREFIX}/bin"
    NO_DEFAULT_PATH
    REQUIRED)

  if(WIN32)
    add_test(
      NAME pure-gplot-command
      COMMAND "${CMAKE_COMMAND}"
        "-DBUILD_ROOT=${CMAKE_CURRENT_BINARY_DIR}"
        "-DTEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/command test"
        "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
        "-DPURE_PREFIX=${PURE_PREFIX}"
        "-DMODULE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
        "-DMODULE_DLL_DIR=$<TARGET_FILE_DIR:gplot>"
        "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/command.pure"
        "-DGNUPLOT_EXECUTABLE=${GNUPLOT_ROOT}/bin/gnuplot.exe"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunCommandTest.cmake")
    set_tests_properties(pure-gplot-command PROPERTIES
      LABELS "pure-gplot;command;windows"
      REQUIRED_FILES
        "$<TARGET_FILE:gplot>;${PURE_EXECUTABLE};${GNUPLOT_ROOT}/bin/gnuplot.exe;${CMAKE_CURRENT_SOURCE_DIR}/tests/command.pure"
      TIMEOUT 30)
  endif()
endif()