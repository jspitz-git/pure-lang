cmake_minimum_required(VERSION 3.25)

project(pure-csv VERSION 1.6 LANGUAGES C)

include(CTest)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")

set(
  PURE_LIBRARY_INSTALL_DIR "lib/pure"
  CACHE STRING "Relative install directory for Pure modules"
)
set(
  PURE_DOCUMENTATION_INSTALL_DIR "share/doc/${PROJECT_NAME}"
  CACHE STRING "Relative install directory for package documentation"
)
foreach(destination_var IN ITEMS
    PURE_LIBRARY_INSTALL_DIR
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
  README
  "${CMAKE_CURRENT_BINARY_DIR}/README.configured"
  @ONLY
  NEWLINE_STYLE UNIX
)
file(READ "${CMAKE_CURRENT_BINARY_DIR}/README.configured" readme)
string(REPLACE "|today|" "${today}" readme "${readme}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/README" "${readme}")

add_library(csv MODULE csv.c)
target_link_libraries(csv PRIVATE PkgConfig::PURE)
set_target_properties(
  csv
  PROPERTIES
    PREFIX ""
    WINDOWS_EXPORT_ALL_SYMBOLS ON
)

set(
  PURE_EXECUTABLE ""
  CACHE FILEPATH "Pure interpreter used for package smoke tests"
)
if(BUILD_TESTING)
  if(PURE_EXECUTABLE)
    if(NOT EXISTS "${PURE_EXECUTABLE}")
      message(FATAL_ERROR "PURE_EXECUTABLE does not exist: ${PURE_EXECUTABLE}")
    endif()
    if(WIN32)
      set(PURE_CSV_NATIVE_NEWLINE "CRLF")
    else()
      set(PURE_CSV_NATIVE_NEWLINE "LF")
    endif()
    add_test(
      NAME pure-csv-smoke
      COMMAND "${CMAKE_COMMAND}"
        "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
        "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
        "-DPURE_MODULE_DIR=$<TARGET_FILE_DIR:csv>"
        "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
        "-DTEST_DIRECTORY=${CMAKE_CURRENT_BINARY_DIR}/pure csv smoke data"
        "-DNATIVE_NEWLINE=${PURE_CSV_NATIVE_NEWLINE}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunSmokeTest.cmake"
    )
  else()
    message(STATUS "PURE_EXECUTABLE is not set; pure-csv smoke test is disabled")
  endif()
endif()
install(
  TARGETS csv
  RUNTIME DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  LIBRARY DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime
)
install(
  FILES csv.pure
  DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime
)
install(
  FILES "${CMAKE_CURRENT_BINARY_DIR}/README" COPYING
  DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}"
  COMPONENT documentation
)
