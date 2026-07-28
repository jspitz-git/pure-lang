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
      destination MATCHES "(^|[/\\])\.\.([/\\]|$)")
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

install(TARGETS audio fftw srcprocess sfinfo realtime
  RUNTIME DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  LIBRARY DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime)
install(FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/audio.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/portaudio.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/fftw/fftw.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/samplerate/samplerate.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/sndfile/sndfile.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/realtime/realtime.pure"
  DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime)

if(WIN32)
  set(AUDIO_NEW_RUNTIME_FILENAMES
    libportaudio.dll libfftw3-3.dll libsamplerate-0.dll libsndfile-1.dll
    libogg-0.dll libvorbisenc-2.dll libFLAC.dll libopus-0.dll
    libmpg123-0.dll libmp3lame-0.dll libvorbis-0.dll)
  set(audio_runtime_files)
  foreach(runtime_file IN LISTS AUDIO_NEW_RUNTIME_FILENAMES)
    string(MAKE_C_IDENTIFIER "${runtime_file}" runtime_id)
    string(TOUPPER "${runtime_id}" runtime_id)
    list(APPEND audio_runtime_files "${AUDIO_RUNTIME_${runtime_id}}")
  endforeach()
  install(FILES ${audio_runtime_files} DESTINATION bin COMPONENT runtime)

  set(license_root "$ENV{MSYSTEM_PREFIX}/share/licenses")
  set(doc_root "$ENV{MSYSTEM_PREFIX}/share/doc")
  set(license_specs
    "${doc_root}/portaudio/LICENSE.txt|PortAudio.txt"
    "${license_root}/libsamplerate/COPYING|libsamplerate.txt"
    "${license_root}/libsndfile/COPYING|libsndfile.txt"
    "${license_root}/libogg/COPYING|libogg.txt"
    "${license_root}/flac/COPYING.Xiph|FLAC-Xiph.txt"
    "${license_root}/opus/COPYING|Opus.txt"
    "${license_root}/mpg123/COPYING|mpg123.txt")
  foreach(license_spec IN LISTS license_specs)
    string(REPLACE "|" ";" license_fields "${license_spec}")
    list(GET license_fields 0 license_source)
    list(GET license_fields 1 license_name)
    if(NOT EXISTS "${license_source}")
      message(FATAL_ERROR "Missing third-party license: ${license_source}")
    endif()
    install(FILES "${license_source}"
      DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}/licenses"
      RENAME "${license_name}" COMPONENT documentation)
  endforeach()
endif()

install(FILES
    "${CMAKE_CURRENT_BINARY_DIR}/README"
    "${CMAKE_CURRENT_SOURCE_DIR}/COPYING"
    "${CMAKE_CURRENT_SOURCE_DIR}/WINDOWS.md"
    "${CMAKE_CURRENT_SOURCE_DIR}/THIRD_PARTY.md"
  DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}"
  COMPONENT documentation)
install(FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/examples/audio_examp.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/examples/audio_test.pd"
  DESTINATION "${PURE_EXAMPLES_INSTALL_DIR}"
  COMPONENT documentation)
install(FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/load.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/hardware.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/hardware-playback.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/hardware-capture.pure"
  DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}/tests"
  COMPONENT documentation)
