cmake_minimum_required(VERSION 3.25)

project(pure-gl VERSION 0.9 LANGUAGES C)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(FREEGLUT REQUIRED IMPORTED_TARGET freeglut)

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
