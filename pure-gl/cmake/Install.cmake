set(PURE_LIBRARY_INSTALL_DIR "lib/pure" CACHE STRING
  "Relative install directory for Pure modules")
set(PURE_DOCUMENTATION_INSTALL_DIR "share/doc/${PROJECT_NAME}" CACHE STRING
  "Relative install directory for package documentation")
set(PURE_EXAMPLES_INSTALL_DIR "${PURE_DOCUMENTATION_INSTALL_DIR}/examples"
  CACHE STRING "Relative install directory for package examples")

foreach(destination_var IN ITEMS
    PURE_LIBRARY_INSTALL_DIR
    PURE_DOCUMENTATION_INSTALL_DIR
    PURE_EXAMPLES_INSTALL_DIR)
  set(destination "${${destination_var}}")
  if(IS_ABSOLUTE "${destination}" OR
      destination MATCHES "(^|[/\\\\])\\.\\.([/\\\\]|$)")
    message(FATAL_ERROR
      "${destination_var} must remain within the installation prefix: ${destination}")
  endif()
endforeach()

set(version "${PROJECT_VERSION}")
string(TIMESTAMP today "%B %d, %Y")
configure_file("${CMAKE_CURRENT_SOURCE_DIR}/README"
  "${CMAKE_CURRENT_BINARY_DIR}/README" @ONLY NEWLINE_STYLE UNIX)
file(READ "${CMAKE_CURRENT_BINARY_DIR}/README" readme)
string(REPLACE "|today|" "${today}" readme "${readme}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/README" "${readme}")

install(TARGETS pure-gl
  RUNTIME DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  LIBRARY DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime)
install(FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/GL.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/GL_ARB.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/GL_EXT.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/GL_NV.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/GL_ATI.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/GLU.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/GLUT.pure"
  DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime)

if(WIN32)
  install(FILES "${FREEGLUT_RUNTIME_DLL}" DESTINATION bin COMPONENT runtime)
  set(freeglut_license
    "$ENV{MSYSTEM_PREFIX}/share/licenses/freeglut/COPYING")
  if(NOT EXISTS "${freeglut_license}")
    message(FATAL_ERROR "Missing FreeGLUT license: ${freeglut_license}")
  endif()
  install(FILES "${freeglut_license}"
    DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}/licenses"
    RENAME "FreeGLUT.txt"
    COMPONENT documentation)
endif()

install(FILES
    "${CMAKE_CURRENT_BINARY_DIR}/README"
    "${CMAKE_CURRENT_SOURCE_DIR}/COPYING"
    "${CMAKE_CURRENT_SOURCE_DIR}/WINDOWS.md"
    "${CMAKE_CURRENT_SOURCE_DIR}/THIRD_PARTY.md"
  DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}"
  COMPONENT documentation)
install(FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/examples/simple_glut_example.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/examples/teapot.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/examples/texture.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/examples/Imlib2.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/examples/fractal.jpg"
  DESTINATION "${PURE_EXAMPLES_INSTALL_DIR}"
  COMPONENT documentation)
install(FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/examples/flexi-line/vector_math.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/examples/flexi-line/glamour.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/examples/flexi-line/flexi-line.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/examples/flexi-line/flexi-line-auto.pure"
  DESTINATION "${PURE_EXAMPLES_INSTALL_DIR}/flexi-line"
  COMPONENT documentation)
install(FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/load.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/hidden-render.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/interactive.pure"
  DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}/tests"
  COMPONENT documentation)
