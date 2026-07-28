set(PURE_LIBRARY_INSTALL_DIR "lib/pure" CACHE STRING
  "Relative install directory for Pure modules")
set(PURE_RUNTIME_INSTALL_DIR "bin" CACHE STRING
  "Relative install directory for bundled runtime DLLs")
set(PURE_LV2_INSTALL_DIR "lib/lv2" CACHE STRING
  "Relative install directory for bundled LV2 specifications and plugins")
set(PURE_DOCUMENTATION_INSTALL_DIR "share/doc/${PROJECT_NAME}" CACHE STRING
  "Relative install directory for package documentation")

foreach(destination_var IN ITEMS
    PURE_LIBRARY_INSTALL_DIR PURE_RUNTIME_INSTALL_DIR PURE_LV2_INSTALL_DIR
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
  README "${CMAKE_CURRENT_BINARY_DIR}/README"
  @ONLY NEWLINE_STYLE UNIX)
file(READ "${CMAKE_CURRENT_BINARY_DIR}/README" readme)
string(REPLACE "|today|" "${today}" readme "${readme}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/README" "${readme}")

install(TARGETS lilv
  RUNTIME DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  LIBRARY DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime)
install(FILES lilv.pure
  DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime)

if(WIN32)
  install(FILES
    "${LILV_RUNTIME_DLL}"
    "${SERD_RUNTIME_DLL}"
    "${SORD_RUNTIME_DLL}"
    "${SRATOM_RUNTIME_DLL}"
    "${ZIX_RUNTIME_DLL}"
    DESTINATION "${PURE_RUNTIME_INSTALL_DIR}"
    COMPONENT runtime)

  pkg_get_variable(LV2_SOURCE_DIR lv2 lv2dir)
  if(NOT IS_DIRECTORY "${LV2_SOURCE_DIR}")
    message(FATAL_ERROR "LV2 specification directory not found: ${LV2_SOURCE_DIR}")
  endif()
  install(DIRECTORY "${LV2_SOURCE_DIR}/"
    DESTINATION "${PURE_LV2_INSTALL_DIR}"
    COMPONENT runtime)

  foreach(package IN ITEMS lv2 serd sord sratom zix)
    string(TOUPPER "${package}" package_upper)
    if(package STREQUAL "lv2")
      set(package_prefix "${LV2_PREFIX}")
    elseif(package STREQUAL "serd")
      set(package_prefix "${SERD_PREFIX}")
    elseif(package STREQUAL "sord")
      set(package_prefix "${SORD_PREFIX}")
    elseif(package STREQUAL "sratom")
      set(package_prefix "${SRATOM_PREFIX}")
    else()
      set(package_prefix "${ZIX_PREFIX}")
    endif()
    find_file("${package_upper}_LICENSE_FILE"
      NAMES COPYING
      HINTS "${package_prefix}/share/licenses/${package}"
      NO_DEFAULT_PATH
      REQUIRED)
    install(FILES "${${package_upper}_LICENSE_FILE}"
      DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}/licenses/${package}"
      COMPONENT documentation)
  endforeach()
  install(FILES "${LILV_LICENSE_FILE}"
    DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}/licenses/lilv"
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
  FILES_MATCHING PATTERN "*.pure" PATTERN "*.mid")

if(BUILD_TESTING)
  install(FILES tests/smoke.pure
    DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}/tests"
    COMPONENT documentation)
  install(DIRECTORY "${test_lv2_root}/"
    DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}/tests/lv2"
    COMPONENT documentation)
endif()
