set(
  PURE_LIBRARY_INSTALL_DIR "lib/pure"
  CACHE STRING "Relative install directory for Pure modules"
)
set(
  PURE_DOCUMENTATION_INSTALL_DIR "share/doc/${PROJECT_NAME}"
  CACHE STRING "Relative install directory for package documentation"
)
set(
  PURE_EXAMPLES_INSTALL_DIR "${PURE_DOCUMENTATION_INSTALL_DIR}/examples"
  CACHE STRING "Relative install directory for package examples"
)

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

string(TIMESTAMP today "%B %d, %Y")
function(configure_package_readme source output package_version)
  set(version "${package_version}")
  configure_file(
    "${source}"
    "${output}"
    @ONLY
    NEWLINE_STYLE UNIX
  )
  file(READ "${output}" readme)
  string(REPLACE "|today|" "${today}" readme "${readme}")
  file(WRITE "${output}" "${readme}")
endfunction()

configure_package_readme(
  "${CMAKE_CURRENT_SOURCE_DIR}/README"
  "${CMAKE_CURRENT_BINARY_DIR}/README"
  "${PROJECT_VERSION}"
)
configure_package_readme(
  "${CMAKE_CURRENT_SOURCE_DIR}/pure-stlvec/README"
  "${CMAKE_CURRENT_BINARY_DIR}/pure-stlvec-README"
  "0.4"
)
configure_package_readme(
  "${CMAKE_CURRENT_SOURCE_DIR}/pure-stlmap/README"
  "${CMAKE_CURRENT_BINARY_DIR}/pure-stlmap-README"
  "0.4"
)

install(
  TARGETS
    stlbase
    stlvec
    stlalgorithm
    stlmap
    stlmmap
    stlhmap
  RUNTIME DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  LIBRARY DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime
)
install(
  FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/stlbase.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/pure-stlvec/stlvec.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/pure-stlmap/stlmap.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/pure-stlmap/stlmmap.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/pure-stlmap/stlhmap.pure"
  DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime
)
install(
  DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/pure-stlvec/stlvec/"
  DESTINATION "${PURE_LIBRARY_INSTALL_DIR}/stlvec"
  COMPONENT runtime
  FILES_MATCHING PATTERN "*.pure"
)

install(
  FILES
    "${CMAKE_CURRENT_BINARY_DIR}/README"
    "${CMAKE_CURRENT_BINARY_DIR}/pure-stlvec-README"
    "${CMAKE_CURRENT_BINARY_DIR}/pure-stlmap-README"
    "${CMAKE_CURRENT_SOURCE_DIR}/COPYING"
    "${CMAKE_CURRENT_SOURCE_DIR}/WINDOWS.md"
    "${CMAKE_CURRENT_SOURCE_DIR}/doc/pure-stllib-cheatsheet.pdf"
    "${CMAKE_CURRENT_SOURCE_DIR}/doc/pure-stllib-cheatsheet.ods"
  DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}"
  COMPONENT documentation
)
install(
  DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/pure-stlvec/examples/"
  DESTINATION "${PURE_EXAMPLES_INSTALL_DIR}/stlvec"
  COMPONENT documentation
)
install(
  DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/pure-stlmap/examples/"
  DESTINATION "${PURE_EXAMPLES_INSTALL_DIR}/stlmap"
  COMPONENT documentation
)
