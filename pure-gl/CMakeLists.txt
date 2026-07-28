cmake_minimum_required(VERSION 3.25)

project(pure-gl VERSION 0.9 LANGUAGES C)

include(CTest)
find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(FREEGLUT REQUIRED IMPORTED_TARGET freeglut)
pkg_get_variable(PURE_PREFIX pure prefix)

find_program(LLVM_READOBJ llvm-readobj REQUIRED)
find_program(LLVM_STRINGS llvm-strings REQUIRED)
find_program(PURE_EXECUTABLE pure
  HINTS "${PURE_PREFIX}/bin"
  REQUIRED)
find_file(FREEGLUT_RUNTIME_DLL
  NAMES libfreeglut.dll
  HINTS "$ENV{MSYSTEM_PREFIX}/bin"
  REQUIRED)

add_library(pure-gl MODULE
  GL.c
  GL_ARB.c
  GL_EXT.c
  GL_NV.c
  GL_ATI.c
  GLU.c
  GLUT.c)
target_compile_features(pure-gl PRIVATE c_std_11)
target_link_libraries(pure-gl PRIVATE
  PkgConfig::PURE
  PkgConfig::FREEGLUT
  opengl32
  glu32)
if(MINGW)
  target_compile_options(pure-gl PRIVATE -Wall -Wextra -Werror)
  target_link_options(pure-gl PRIVATE "LINKER:--enable-auto-import")
endif()
set_target_properties(pure-gl PROPERTIES
  PREFIX ""
  WINDOWS_EXPORT_ALL_SYMBOLS ON)

add_custom_target(verify-windows-dependencies
  COMMAND "${CMAKE_COMMAND}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    "-DLLVM_STRINGS=${LLVM_STRINGS}"
    "-DPURE_GL_MODULE=$<TARGET_FILE:pure-gl>"
    "-DFREEGLUT_DLL=${FREEGLUT_RUNTIME_DLL}"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
  DEPENDS pure-gl
  VERBATIM)

add_custom_target(check-gl-interactive
  COMMAND "${CMAKE_COMMAND}"
    "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
    "-DPURE_LIBRARY_DIR=$<TARGET_FILE_DIR:pure-gl>"
    "-DPURE_GL_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
    "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/interactive.pure"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake"
  DEPENDS pure-gl
  COMMENT "Displaying the bounded pure-gl Windows desktop test"
  USES_TERMINAL
  VERBATIM)

if(BUILD_TESTING)
  add_test(NAME pure-gl.load-all-modules
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPURE_LIBRARY_DIR=$<TARGET_FILE_DIR:pure-gl>"
      "-DPURE_GL_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/load.pure"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake")
  set_tests_properties(pure-gl.load-all-modules PROPERTIES
    TIMEOUT 55 RUN_SERIAL TRUE)
  add_test(NAME pure-gl.hidden-render
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPURE_LIBRARY_DIR=$<TARGET_FILE_DIR:pure-gl>"
      "-DPURE_GL_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/hidden-render.pure"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake")
  set_tests_properties(pure-gl.hidden-render PROPERTIES
    TIMEOUT 55 RUN_SERIAL TRUE)
endif()
