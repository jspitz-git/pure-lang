set(PURE_LIBRARY_INSTALL_DIR "lib/pure" CACHE STRING
  "Relative install directory for Pure modules")
set(PURE_RUNTIME_INSTALL_DIR "bin" CACHE STRING
  "Relative install directory for native commands")
set(PURE_INCLUDE_INSTALL_DIR "include" CACHE STRING
  "Relative install directory for developer headers")
set(PURE_DOCUMENTATION_INSTALL_DIR "share/doc/${PROJECT_NAME}" CACHE STRING
  "Relative install directory for package documentation")

foreach(destination_var IN ITEMS
    PURE_LIBRARY_INSTALL_DIR PURE_RUNTIME_INSTALL_DIR
    PURE_INCLUDE_INSTALL_DIR PURE_DOCUMENTATION_INSTALL_DIR)
  set(destination "${${destination_var}}")
  if(IS_ABSOLUTE "${destination}" OR
      destination MATCHES "(^|[/\\\\])\\.\\.([/\\\\]|$)")
    message(FATAL_ERROR
      "${destination_var} must remain within the installation prefix: "
      "${destination}")
  endif()
endforeach()

set(version "${PROJECT_VERSION}")
string(TIMESTAMP today "%B %d, %Y")
configure_file(
  README "${CMAKE_CURRENT_BINARY_DIR}/README"
  @ONLY NEWLINE_STYLE UNIX)
file(READ "${CMAKE_CURRENT_BINARY_DIR}/README" readme)
string(REPLACE "|today|" "${today}" readme "${readme}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/README" "${readme}")

install(TARGETS lv2
  RUNTIME DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  LIBRARY DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime)
install(FILES
  lv2.pure
  lv2pure.c
  lv2pure.h
  lv2-manifest-template.ttl
  DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime)
install(PROGRAMS pure2lv2
  DESTINATION "${PURE_RUNTIME_INSTALL_DIR}"
  COMPONENT development)
install(FILES pure2lv2.cmd pure2lv2.ps1
  DESTINATION "${PURE_RUNTIME_INSTALL_DIR}"
  COMPONENT development)

if(WIN32)
  find_path(LV2_HEADER_ROOT
    NAMES lv2/lv2plug.in/ns/lv2core/lv2.h
    HINTS ${LV2_INCLUDE_DIRS}
    NO_DEFAULT_PATH
    REQUIRED)
  install(DIRECTORY "${LV2_HEADER_ROOT}/lv2"
    DESTINATION "${PURE_INCLUDE_INSTALL_DIR}"
    COMPONENT development)

  find_file(LV2_LICENSE_FILE
    NAMES COPYING
    HINTS "${LV2_PREFIX}/share/licenses/lv2"
    NO_DEFAULT_PATH
    REQUIRED)
  install(FILES "${LV2_LICENSE_FILE}"
    DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}/licenses/lv2"
    COMPONENT documentation)
endif()

install(FILES
  "${CMAKE_CURRENT_BINARY_DIR}/README"
  COPYING
  WINDOWS.md
  DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}"
  COMPONENT documentation)
install(DIRECTORY examples/
  DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}/examples"
  COMPONENT documentation
  FILES_MATCHING PATTERN "*.pure")

if(BUILD_TESTING)
  install(FILES
    tests/host.pure
    cmake/VerifyGeneratedPlugins.cmake
    DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}/tests"
    COMPONENT documentation)
endif()
