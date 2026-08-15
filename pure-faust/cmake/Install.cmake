set(PURE_FAUST_LIBRARY_INSTALL_DIR "lib/pure" CACHE STRING
  "Relative install directory for Pure modules")
set(PURE_FAUST_DOCUMENTATION_INSTALL_DIR "share/doc/pure-faust" CACHE STRING
  "Relative install directory for pure-faust documentation")

foreach(destination_var IN ITEMS
    PURE_FAUST_LIBRARY_INSTALL_DIR PURE_FAUST_DOCUMENTATION_INSTALL_DIR)
  set(destination "${${destination_var}}")
  if(IS_ABSOLUTE "${destination}" OR
      destination MATCHES "(^|[/\\\\])\\.\\.([/\\\\]|$)")
    message(FATAL_ERROR
      "${destination_var} must remain within the installation prefix: ${destination}")
  endif()
endforeach()

install(FILES faust2.pure
  DESTINATION "${PURE_FAUST_LIBRARY_INSTALL_DIR}"
  COMPONENT Runtime)
install(FILES
  COPYING
  COPYING.LESSER
  WINDOWS.md
  DESTINATION "${PURE_FAUST_DOCUMENTATION_INSTALL_DIR}"
  COMPONENT Runtime)

# Task 4 adds the optional payload to this intentionally empty component.
install(CODE "" COMPONENT FaustDeveloper EXCLUDE_FROM_ALL)
