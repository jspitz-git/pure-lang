set(PURE_LIBRARY_INSTALL_DIR "lib/pure" CACHE STRING
  "Relative install directory for Pure modules")
set(PURE_DOCUMENTATION_INSTALL_DIR "share/doc/${PROJECT_NAME}" CACHE STRING
  "Relative install directory for package documentation")
set(PURE_EXAMPLES_INSTALL_DIR "${PURE_DOCUMENTATION_INSTALL_DIR}/examples"
  CACHE STRING "Relative install directory for package examples")

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

set(version "${PROJECT_VERSION}")
string(TIMESTAMP today "%B %d, %Y")
configure_file("${CMAKE_CURRENT_SOURCE_DIR}/README"
  "${CMAKE_CURRENT_BINARY_DIR}/README" @ONLY NEWLINE_STYLE UNIX)
file(READ "${CMAKE_CURRENT_BINARY_DIR}/README" readme)
string(REPLACE "|today|" "${today}" readme "${readme}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/README" "${readme}")

install(TARGETS pmlib midifile
  RUNTIME DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  LIBRARY DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime)
install(FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/midi.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/portmidi.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/midifile/midifile.pure"
  DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime)

if(WIN32)
  install(FILES "${PORTMIDI_RUNTIME_DLL}" DESTINATION bin COMPONENT runtime)
  set(portmidi_license
    "$ENV{MSYSTEM_PREFIX}/share/licenses/portmidi/license.txt")
  if(NOT EXISTS "${portmidi_license}")
    message(FATAL_ERROR "Missing PortMidi license: ${portmidi_license}")
  endif()
  install(FILES "${portmidi_license}"
    DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}/licenses"
    RENAME "PortMidi.txt"
    COMPONENT documentation)
endif()

install(FILES
    "${CMAKE_CURRENT_BINARY_DIR}/README"
    "${CMAKE_CURRENT_SOURCE_DIR}/COPYING"
    "${CMAKE_CURRENT_SOURCE_DIR}/WINDOWS.md"
    "${CMAKE_CURRENT_SOURCE_DIR}/THIRD_PARTY.md"
  DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}"
  COMPONENT documentation)
install(FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/examples/midi_examp.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/examples/prelude3.mid"
  DESTINATION "${PURE_EXAMPLES_INSTALL_DIR}"
  COMPONENT documentation)
install(FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/device-timing.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/hardware-output.pure"
  DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}/tests"
  COMPONENT documentation)
