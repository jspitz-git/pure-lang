set(PURE_LIBRARY_INSTALL_DIR "lib/pure" CACHE STRING
  "Relative install directory for Pure modules")
set(PURE_DOCUMENTATION_INSTALL_DIR "share/doc/${PROJECT_NAME}" CACHE STRING
  "Relative install directory for package documentation")
set(PURE_GPLOT_GNUPLOT_INSTALL_DIR "tools/gnuplot" CACHE STRING
  "Relative install directory for the optional managed gnuplot tree")
option(PURE_GPLOT_INSTALL_GNUPLOT
  "Install the optional managed gnuplot 6.0.4 component" OFF)

foreach(destination_var IN ITEMS
    PURE_LIBRARY_INSTALL_DIR PURE_DOCUMENTATION_INSTALL_DIR
    PURE_GPLOT_GNUPLOT_INSTALL_DIR)
  set(destination "${${destination_var}}")
  if(IS_ABSOLUTE "${destination}" OR
      destination MATCHES "(^|[/\\\\])\\.\\.([/\\\\]|$)")
    message(FATAL_ERROR
      "${destination_var} must remain within the installation prefix: "
      "${destination}")
  endif()
endforeach()

if(WIN32)
  install(TARGETS gplot
    RUNTIME DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
    LIBRARY DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
    COMPONENT runtime)
endif()
install(FILES gplot.pure
  DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime)

if(PURE_GPLOT_INSTALL_GNUPLOT)
  if(NOT WIN32)
    message(FATAL_ERROR
      "PURE_GPLOT_INSTALL_GNUPLOT is supported only for Windows packages")
  endif()
  if(NOT EXISTS "${GNUPLOT_ROOT}/bin/gnuplot.exe")
    message(FATAL_ERROR
      "GNUPLOT_ROOT must contain the controlled gnuplot 6.0.4 distribution")
  endif()
  execute_process(
    COMMAND "${GNUPLOT_ROOT}/bin/gnuplot.exe" --version
    RESULT_VARIABLE gnuplot_version_result
    OUTPUT_VARIABLE gnuplot_version_output
    ERROR_VARIABLE gnuplot_version_error
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ENCODING UTF-8)
  if(NOT "${gnuplot_version_result}" STREQUAL "0" OR
      NOT gnuplot_version_output STREQUAL "gnuplot 6.0 patchlevel 4")
    message(FATAL_ERROR
      "GNUPLOT_ROOT has an unsupported version\n"
      "stdout: ${gnuplot_version_output}\n"
      "stderr: ${gnuplot_version_error}")
  endif()
  if(NOT EXISTS "${GNUPLOT_ROOT}/license/Copyright")
    message(FATAL_ERROR "GNUPLOT_ROOT is missing license/Copyright")
  endif()

  set(controlled_gnuplot_root
    "${CMAKE_CURRENT_BINARY_DIR}/managed-gnuplot-6.0.4")
  file(REMOVE_RECURSE "${controlled_gnuplot_root}")
  file(MAKE_DIRECTORY "${controlled_gnuplot_root}")
  file(COPY "${GNUPLOT_ROOT}/"
    DESTINATION "${controlled_gnuplot_root}"
    PATTERN "unins000.exe" EXCLUDE
    PATTERN "unins000.dat" EXCLUDE)
  execute_process(
    COMMAND "${controlled_gnuplot_root}/bin/gnuplot.exe" --version
    RESULT_VARIABLE staged_version_result
    OUTPUT_VARIABLE staged_version_output
    ERROR_VARIABLE staged_version_error
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ENCODING UTF-8)
  if(NOT "${staged_version_result}" STREQUAL "0" OR
      NOT staged_version_output STREQUAL "gnuplot 6.0 patchlevel 4")
    message(FATAL_ERROR
      "The controlled build-tree copy of gnuplot is invalid\n"
      "stdout: ${staged_version_output}\n"
      "stderr: ${staged_version_error}")
  endif()

  install(DIRECTORY "${controlled_gnuplot_root}/"
    DESTINATION "${PURE_GPLOT_GNUPLOT_INSTALL_DIR}"
    COMPONENT gnuplot
    PATTERN "unins000.exe" EXCLUDE
    PATTERN "unins000.dat" EXCLUDE)
  install(DIRECTORY "${controlled_gnuplot_root}/license/"
    DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}/licenses/gnuplot"
    COMPONENT documentation)
endif()

install(FILES
  COPYING
  COPYING.LESSER
  WINDOWS.md
  DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}"
  COMPONENT documentation)
install(FILES gplot_test.pure
  DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}/examples"
  COMPONENT documentation)
install(FILES
  tests/render.pure
  tests/missing.pure
  DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}/tests"
  COMPONENT documentation)