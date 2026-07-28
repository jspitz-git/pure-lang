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
  TARGETS glpk
  RUNTIME DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  LIBRARY DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime
)
install(
  FILES "${CMAKE_CURRENT_SOURCE_DIR}/glpk.pure"
  DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime
)

if(WIN32)
  find_file(
    GLPK_RUNTIME_LICENSE
    NAMES LICENSE
    HINTS "$ENV{MSYSTEM_PREFIX}/share/licenses/glpk"
    NO_DEFAULT_PATH
    REQUIRED
  )
  find_file(
    SUITESPARSE_RUNTIME_LICENSE
    NAMES LICENSE
    HINTS "$ENV{MSYSTEM_PREFIX}/share/licenses/suitesparse"
    NO_DEFAULT_PATH
    REQUIRED
  )
  find_file(
    LLVM_RUNTIME_LICENSE
    NAMES LICENSE
    HINTS "$ENV{MSYSTEM_PREFIX}/share/licenses/llvm"
    NO_DEFAULT_PATH
    REQUIRED
  )
  install(
    FILES
      "${GLPK_RUNTIME_DLL}"
      "${COLAMD_RUNTIME_DLL}"
      "${AMD_RUNTIME_DLL}"
      "${SUITESPARSECONFIG_RUNTIME_DLL}"
      "${OMP_RUNTIME_DLL}"
    DESTINATION "${PURE_RUNTIME_INSTALL_DIR}"
    COMPONENT runtime
  )
  install(
    FILES "${GLPK_RUNTIME_LICENSE}"
    DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}"
    RENAME glpk-LICENSE
    COMPONENT documentation
  )
  install(
    FILES "${SUITESPARSE_RUNTIME_LICENSE}"
    DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}"
    RENAME suitesparse-LICENSE
    COMPONENT documentation
  )
  install(
    FILES "${LLVM_RUNTIME_LICENSE}"
    DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}"
    RENAME llvm-openmp-LICENSE
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
  DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/examples/"
  DESTINATION "${PURE_EXAMPLES_INSTALL_DIR}"
  COMPONENT documentation
  FILES_MATCHING PATTERN "*.pure"
)
install(
  FILES "${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
  DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}/tests"
  COMPONENT documentation
)
