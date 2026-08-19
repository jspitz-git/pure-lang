cmake_minimum_required(VERSION 3.25)

if(DEFINED PURE_BONJOUR_GENERATE_ORACLES)
  foreach(required IN ITEMS
      PURE_BONJOUR_MODULE
      PURE_BONJOUR_MODULE_SOURCE
      PURE_BONJOUR_README
      PURE_BONJOUR_WINDOWS_NOTES
      PURE_BONJOUR_COPYING
      PURE_BONJOUR_COPYING_LESSER
      PURE_BONJOUR_EXAMPLE
      PURE_BONJOUR_LIBRARY_DESTINATION
      PURE_BONJOUR_DOCUMENTATION_DESTINATION
      PURE_BONJOUR_EXAMPLES_DESTINATION
      PURE_BONJOUR_BINARY_DIR
      PURE_BONJOUR_VERSION)
    if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
      message(FATAL_ERROR
        "${required} is required for PureBonjour oracle generation")
    endif()
  endforeach()

  set(records)
  function(pure_bonjour_record relative source purpose origin version)
    if(NOT EXISTS "${source}" OR IS_DIRECTORY "${source}")
      message(FATAL_ERROR "PureBonjour package input does not exist: ${source}")
    endif()
    if(IS_ABSOLUTE "${relative}" OR
        relative MATCHES "(^|[/\\\\])\\.\\.([/\\\\]|$)")
      message(FATAL_ERROR
        "PureBonjour inventory path escapes the install prefix: ${relative}")
    endif()
    list(APPEND records
      "${relative}|${source}|${purpose}|${origin}|${version}")
    set(records "${records}" PARENT_SCOPE)
  endfunction()

  pure_bonjour_record(
    "${PURE_BONJOUR_LIBRARY_DESTINATION}/bonjour.dll"
    "${PURE_BONJOUR_MODULE}"
    "Pure Bonjour native module for Microsoft DNS Service Discovery"
    "pure-bonjour Windows backend source" "${PURE_BONJOUR_VERSION}")
  pure_bonjour_record(
    "${PURE_BONJOUR_LIBRARY_DESTINATION}/bonjour.pure"
    "${PURE_BONJOUR_MODULE_SOURCE}"
    "Pure language declarations for the Bonjour module"
    "pure-bonjour source distribution" "${PURE_BONJOUR_VERSION}")
  pure_bonjour_record(
    "${PURE_BONJOUR_DOCUMENTATION_DESTINATION}/README"
    "${PURE_BONJOUR_README}"
    "Generated PureBonjour user documentation"
    "pure-bonjour README template" "${PURE_BONJOUR_VERSION}")
  pure_bonjour_record(
    "${PURE_BONJOUR_DOCUMENTATION_DESTINATION}/WINDOWS.md"
    "${PURE_BONJOUR_WINDOWS_NOTES}"
    "Windows platform and dependency notes"
    "pure-bonjour package metadata" "${PURE_BONJOUR_VERSION}")
  pure_bonjour_record(
    "${PURE_BONJOUR_DOCUMENTATION_DESTINATION}/COPYING"
    "${PURE_BONJOUR_COPYING}"
    "GNU General Public License notice"
    "pure-bonjour source distribution" "3.0-or-later")
  pure_bonjour_record(
    "${PURE_BONJOUR_DOCUMENTATION_DESTINATION}/COPYING.LESSER"
    "${PURE_BONJOUR_COPYING_LESSER}"
    "GNU Lesser General Public License notice"
    "pure-bonjour source distribution" "3.0-or-later")
  pure_bonjour_record(
    "${PURE_BONJOUR_EXAMPLES_DESTINATION}/bonjour_examp.pure"
    "${PURE_BONJOUR_EXAMPLE}"
    "PureBonjour service publication example"
    "pure-bonjour source distribution" "${PURE_BONJOUR_VERSION}")

  list(SORT records COMPARE STRING CASE SENSITIVE ORDER ASCENDING)
  set(inventory "${PURE_BONJOUR_BINARY_DIR}/PureBonjourInventory.tsv")
  file(WRITE "${inventory}"
    "relative_path\tpurpose\torigin\tversion\tsha256\tsize\n")
  foreach(record IN LISTS records)
    string(REPLACE "|" ";" fields "${record}")
    list(GET fields 0 relative)
    list(GET fields 1 source)
    list(GET fields 2 purpose)
    list(GET fields 3 origin)
    list(GET fields 4 version)
    file(SHA256 "${source}" sha256)
    file(SIZE "${source}" size)
    string(TOLOWER "${sha256}" sha256)
    file(APPEND "${inventory}"
      "${relative}\t${purpose}\t${origin}\t${version}\t${sha256}\t${size}\n")
  endforeach()

  list(APPEND records
    "${PURE_BONJOUR_DOCUMENTATION_DESTINATION}/PureBonjourInventory.tsv|${inventory}|||")
  list(SORT records COMPARE STRING CASE SENSITIVE ORDER ASCENDING)
  set(manifest "${PURE_BONJOUR_BINARY_DIR}/PureBonjourExpected.sha256")
  file(WRITE "${manifest}" "")
  foreach(record IN LISTS records)
    string(REPLACE "|" ";" fields "${record}")
    list(GET fields 0 relative)
    list(GET fields 1 source)
    file(SHA256 "${source}" sha256)
    string(TOLOWER "${sha256}" sha256)
    file(APPEND "${manifest}" "${sha256}  ${relative}\n")
  endforeach()
  return()
endif()

set(PURE_LIBRARY_INSTALL_DIR "lib/pure" CACHE STRING
  "Relative install directory for Pure modules")
set(PURE_DOCUMENTATION_INSTALL_DIR "share/doc/pure-bonjour" CACHE STRING
  "Relative install directory for package documentation")
set(PURE_EXAMPLES_INSTALL_DIR "${PURE_DOCUMENTATION_INSTALL_DIR}/examples"
  CACHE STRING "Relative install directory for package examples")

foreach(destination_variable IN ITEMS
    PURE_LIBRARY_INSTALL_DIR
    PURE_DOCUMENTATION_INSTALL_DIR
    PURE_EXAMPLES_INSTALL_DIR)
  set(destination "${${destination_variable}}")
  if(destination STREQUAL "" OR IS_ABSOLUTE "${destination}" OR
      destination MATCHES "(^|[/\\\\])\\.\\.([/\\\\]|$)")
    message(FATAL_ERROR
      "DESTINATION_OUTSIDE_PREFIX: ${destination_variable} must remain "
      "within the installation prefix: ${destination}")
  endif()
endforeach()
if(DEFINED PURE_BONJOUR_VALIDATE_DESTINATIONS_ONLY)
  return()
endif()

set(version "${PROJECT_VERSION}")
string(TIMESTAMP today "%B %d, %Y")
configure_file(
  "${CMAKE_CURRENT_SOURCE_DIR}/README"
  "${CMAKE_CURRENT_BINARY_DIR}/README"
  @ONLY NEWLINE_STYLE UNIX)
file(READ "${CMAKE_CURRENT_BINARY_DIR}/README" generated_readme)
string(REPLACE "|today|" "${today}" generated_readme "${generated_readme}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/README" "${generated_readme}")

set(windows_notes "${CMAKE_CURRENT_SOURCE_DIR}/WINDOWS.md")

set(pure_bonjour_inventory
  "${CMAKE_CURRENT_BINARY_DIR}/PureBonjourInventory.tsv")
set(pure_bonjour_manifest
  "${CMAKE_CURRENT_BINARY_DIR}/PureBonjourExpected.sha256")
add_custom_command(
  OUTPUT "${pure_bonjour_inventory}" "${pure_bonjour_manifest}"
  COMMAND "${CMAKE_COMMAND}"
    -DPURE_BONJOUR_GENERATE_ORACLES=ON
    "-DPURE_BONJOUR_MODULE=$<TARGET_FILE:pure-bonjour>"
    "-DPURE_BONJOUR_MODULE_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}/bonjour.pure"
    "-DPURE_BONJOUR_README=${CMAKE_CURRENT_BINARY_DIR}/README"
    "-DPURE_BONJOUR_WINDOWS_NOTES=${windows_notes}"
    "-DPURE_BONJOUR_COPYING=${CMAKE_CURRENT_SOURCE_DIR}/COPYING"
    "-DPURE_BONJOUR_COPYING_LESSER=${CMAKE_CURRENT_SOURCE_DIR}/COPYING.LESSER"
    "-DPURE_BONJOUR_EXAMPLE=${CMAKE_CURRENT_SOURCE_DIR}/examples/bonjour_examp.pure"
    "-DPURE_BONJOUR_LIBRARY_DESTINATION=${PURE_LIBRARY_INSTALL_DIR}"
    "-DPURE_BONJOUR_DOCUMENTATION_DESTINATION=${PURE_DOCUMENTATION_INSTALL_DIR}"
    "-DPURE_BONJOUR_EXAMPLES_DESTINATION=${PURE_EXAMPLES_INSTALL_DIR}"
    "-DPURE_BONJOUR_BINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
    "-DPURE_BONJOUR_VERSION=${PROJECT_VERSION}"
    -P "${CMAKE_CURRENT_LIST_FILE}"
  DEPENDS
    pure-bonjour
    "${CMAKE_CURRENT_SOURCE_DIR}/bonjour.pure"
    "${CMAKE_CURRENT_BINARY_DIR}/README"
    "${windows_notes}"
    "${CMAKE_CURRENT_SOURCE_DIR}/COPYING"
    "${CMAKE_CURRENT_SOURCE_DIR}/COPYING.LESSER"
    "${CMAKE_CURRENT_SOURCE_DIR}/examples/bonjour_examp.pure"
    "${CMAKE_CURRENT_LIST_FILE}"
  COMMENT "Generating authoritative PureBonjour package oracles"
  VERBATIM)
add_custom_target(pure-bonjour-package-oracles ALL
  DEPENDS "${pure_bonjour_inventory}" "${pure_bonjour_manifest}")

install(TARGETS pure-bonjour
  RUNTIME DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  LIBRARY DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT PureBonjour EXCLUDE_FROM_ALL)
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/bonjour.pure"
  DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT PureBonjour EXCLUDE_FROM_ALL)
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/README"
  DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}"
  COMPONENT PureBonjour EXCLUDE_FROM_ALL)
install(FILES "${windows_notes}"
  DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}"
  COMPONENT PureBonjour EXCLUDE_FROM_ALL)
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/COPYING"
  DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}"
  COMPONENT PureBonjour EXCLUDE_FROM_ALL)
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/COPYING.LESSER"
  DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}"
  COMPONENT PureBonjour EXCLUDE_FROM_ALL)
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/examples/bonjour_examp.pure"
  DESTINATION "${PURE_EXAMPLES_INSTALL_DIR}"
  COMPONENT PureBonjour EXCLUDE_FROM_ALL)
install(FILES "${pure_bonjour_inventory}"
  DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}"
  COMPONENT PureBonjour EXCLUDE_FROM_ALL)
