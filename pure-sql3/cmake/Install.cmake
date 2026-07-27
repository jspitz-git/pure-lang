set(
  PURE_LIBRARY_INSTALL_DIR "lib/pure"
  CACHE STRING "Relative install directory for Pure modules"
)
set(
  PURE_RUNTIME_INSTALL_DIR "bin"
  CACHE STRING "Relative install directory for bundled runtime DLLs"
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
    PURE_RUNTIME_INSTALL_DIR
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
  TARGETS sql3util
  RUNTIME DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  LIBRARY DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime
)
install(
  FILES "${CMAKE_CURRENT_SOURCE_DIR}/sql3.pure"
  DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime
)
install(
  FILES
    "${CMAKE_CURRENT_BINARY_DIR}/README"
    "${CMAKE_CURRENT_SOURCE_DIR}/COPYING"
  DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}"
  COMPONENT documentation
)
install(
  DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/examples/"
  DESTINATION "${PURE_EXAMPLES_INSTALL_DIR}"
  COMPONENT documentation
  FILES_MATCHING PATTERN "*.pure"
)

set(
  PURE_SQLITE_RUNTIME_DLL ""
  CACHE FILEPATH "Controlled SQLite runtime DLL bundled with pure-sql3"
)
set(
  PURE_SQLITE_RUNTIME_LICENSE ""
  CACHE FILEPATH "License for the bundled SQLite runtime DLL"
)
if(WIN32)
  pkg_get_variable(SQLITE3_PREFIX sqlite3 prefix)
  if(NOT PURE_SQLITE_RUNTIME_DLL)
    find_file(
      detected_pure_sqlite_runtime_dll
      NAMES libsqlite3-0.dll
      HINTS "${SQLITE3_PREFIX}/bin"
      NO_DEFAULT_PATH
    )
    if(detected_pure_sqlite_runtime_dll)
      set(
        PURE_SQLITE_RUNTIME_DLL "${detected_pure_sqlite_runtime_dll}"
        CACHE FILEPATH "Controlled SQLite runtime DLL bundled with pure-sql3"
        FORCE
      )
    endif()
  endif()
  if(NOT PURE_SQLITE_RUNTIME_LICENSE)
    find_file(
      detected_pure_sqlite_runtime_license
      NAMES LICENSE
      HINTS "${SQLITE3_PREFIX}/share/licenses/sqlite3"
      NO_DEFAULT_PATH
    )
    if(detected_pure_sqlite_runtime_license)
      set(
        PURE_SQLITE_RUNTIME_LICENSE "${detected_pure_sqlite_runtime_license}"
        CACHE FILEPATH "License for the bundled SQLite runtime DLL"
        FORCE
      )
    endif()
  endif()
  if(NOT EXISTS "${PURE_SQLITE_RUNTIME_DLL}")
    message(FATAL_ERROR
      "PURE_SQLITE_RUNTIME_DLL does not exist: ${PURE_SQLITE_RUNTIME_DLL}")
  endif()
  if(NOT EXISTS "${PURE_SQLITE_RUNTIME_LICENSE}")
    message(FATAL_ERROR
      "PURE_SQLITE_RUNTIME_LICENSE does not exist: ${PURE_SQLITE_RUNTIME_LICENSE}")
  endif()
  get_filename_component(sqlite_runtime_name "${PURE_SQLITE_RUNTIME_DLL}" NAME)
  if(NOT sqlite_runtime_name STREQUAL "libsqlite3-0.dll")
    message(FATAL_ERROR
      "Expected libsqlite3-0.dll, got: ${sqlite_runtime_name}")
  endif()
  install(
    FILES "${PURE_SQLITE_RUNTIME_DLL}"
    DESTINATION "${PURE_RUNTIME_INSTALL_DIR}"
    COMPONENT runtime
  )
  install(
    FILES "${PURE_SQLITE_RUNTIME_LICENSE}"
    DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}"
    RENAME sqlite3-LICENSE
    COMPONENT documentation
  )
endif()
