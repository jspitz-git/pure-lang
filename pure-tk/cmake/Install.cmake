set(
  PURE_LIBRARY_INSTALL_DIR "lib/pure"
  CACHE STRING "Relative install directory for Pure modules"
)
set(
  PURE_RUNTIME_INSTALL_DIR "bin"
  CACHE STRING "Relative install directory for bundled runtime DLLs"
)
set(
  TCL_LIBRARY_INSTALL_DIR "lib"
  CACHE STRING "Relative install directory for Tcl/Tk script libraries"
)
set(
  PURE_DOCUMENTATION_INSTALL_DIR "share/doc/${PROJECT_NAME}"
  CACHE STRING "Relative install directory for package documentation"
)

foreach(destination_var IN ITEMS
    PURE_LIBRARY_INSTALL_DIR
    PURE_RUNTIME_INSTALL_DIR
    TCL_LIBRARY_INSTALL_DIR
    PURE_DOCUMENTATION_INSTALL_DIR)
  set(destination "${${destination_var}}")
  if(IS_ABSOLUTE "${destination}" OR
      destination MATCHES "(^|[/\\\\])\\.\\.([/\\\\]|$)")
    message(FATAL_ERROR
      "${destination_var} must remain within the installation prefix: ${destination}")
  endif()
endforeach()

set(version "${PROJECT_VERSION}")
string(TIMESTAMP today "%B %d, %Y")
configure_file(
  "${CMAKE_CURRENT_SOURCE_DIR}/README"
  "${CMAKE_CURRENT_BINARY_DIR}/README"
  @ONLY
  NEWLINE_STYLE UNIX
)
file(READ "${CMAKE_CURRENT_BINARY_DIR}/README" readme)
string(REPLACE "|today|" "${today}" readme "${readme}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/README" "${readme}")

install(
  TARGETS pure-tk
  RUNTIME DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  LIBRARY DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime
)
install(
  FILES "${CMAKE_CURRENT_SOURCE_DIR}/tk.pure"
  DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime
)

if(WIN32)
  install(
    FILES "${TCL_RUNTIME_DLL}" "${TK_RUNTIME_DLL}"
    DESTINATION "${PURE_RUNTIME_INSTALL_DIR}"
    COMPONENT runtime
  )
  install(
    DIRECTORY
      "${TCL_PREFIX}/lib/tcl8.6"
      "${TCL_PREFIX}/lib/tk8.6"
    DESTINATION "${TCL_LIBRARY_INSTALL_DIR}"
    COMPONENT runtime
    PATTERN "demos" EXCLUDE
    PATTERN "images" EXCLUDE
  )
  install(
    FILES "${TCL_PREFIX}/lib/tk8.6/demos/license.terms"
    DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}"
    RENAME tcl-tk-license.terms
    COMPONENT documentation
  )
  install(
    FILES "${TCL_PREFIX}/share/licenses/zlib/LICENSE"
    DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}"
    RENAME zlib-LICENSE
    COMPONENT documentation
  )
endif()

install(
  FILES
    "${CMAKE_CURRENT_BINARY_DIR}/README"
    "${CMAKE_CURRENT_SOURCE_DIR}/COPYING"
    "${CMAKE_CURRENT_SOURCE_DIR}/WINDOWS.md"
  DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}"
  COMPONENT documentation
)
install(
  FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/relocatable.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
  DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}/tests"
  COMPONENT documentation
)
