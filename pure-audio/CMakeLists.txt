cmake_minimum_required(VERSION 3.25)

project(pure-audio VERSION 0.6 LANGUAGES C)

find_package(PkgConfig REQUIRED)
find_package(Threads REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(PORTAUDIO REQUIRED IMPORTED_TARGET portaudio-2.0)
pkg_check_modules(FFTW REQUIRED IMPORTED_TARGET fftw3)
pkg_check_modules(SAMPLERATE REQUIRED IMPORTED_TARGET samplerate)
pkg_check_modules(SNDFILE REQUIRED IMPORTED_TARGET sndfile)

function(add_pure_audio_module target source)
  add_library(${target} MODULE "${source}")
  target_compile_features(${target} PRIVATE c_std_11)
  target_link_libraries(${target} PRIVATE PkgConfig::PURE)
  if(MINGW)
    target_compile_options(${target} PRIVATE -Wall -Wextra -Werror)
    target_link_options(${target} PRIVATE "LINKER:--enable-auto-import")
  endif()
  set_target_properties(
    ${target}
    PROPERTIES
      PREFIX ""
      WINDOWS_EXPORT_ALL_SYMBOLS ON
  )
endfunction()

add_pure_audio_module(audio audio.c)
target_link_libraries(audio PRIVATE PkgConfig::PORTAUDIO Threads::Threads)

add_pure_audio_module(fftw fftw/fftw.c)
target_link_libraries(fftw PRIVATE PkgConfig::FFTW)

add_pure_audio_module(srcprocess samplerate/srcprocess.c)
target_link_libraries(srcprocess PRIVATE PkgConfig::SAMPLERATE)

add_pure_audio_module(sfinfo sndfile/sfinfo.c)
target_link_libraries(sfinfo PRIVATE PkgConfig::SNDFILE)

add_pure_audio_module(realtime realtime/realtime.c)
target_link_libraries(realtime PRIVATE Threads::Threads)

if(WIN32)
  set(AUDIO_RUNTIME_FILENAMES
    libportaudio.dll
    libfftw3-3.dll
    libsamplerate-0.dll
    libsndfile-1.dll
    libogg-0.dll
    libvorbisenc-2.dll
    libFLAC.dll
    libopus-0.dll
    libmpg123-0.dll
    libmp3lame-0.dll
    libvorbis-0.dll
    libwinpthread-1.dll
    libc++.dll
  )
  foreach(runtime_file IN LISTS AUDIO_RUNTIME_FILENAMES)
    string(MAKE_C_IDENTIFIER "${runtime_file}" runtime_id)
    string(TOUPPER "${runtime_id}" runtime_id)
    find_file(
      "AUDIO_RUNTIME_${runtime_id}"
      NAMES "${runtime_file}"
      HINTS "$ENV{MSYSTEM_PREFIX}/bin"
      NO_DEFAULT_PATH
      REQUIRED
    )
  endforeach()
  find_program(LLVM_READOBJ NAMES llvm-readobj REQUIRED)
  add_custom_target(
    verify-windows-dependencies
    COMMAND "${CMAKE_COMMAND}"
      "-DLLVM_READOBJ=${LLVM_READOBJ}"
      "-DRUNTIME_DIR=$ENV{MSYSTEM_PREFIX}/bin"
      "-DAUDIO_MODULE=$<TARGET_FILE:audio>"
      "-DFFTW_MODULE=$<TARGET_FILE:fftw>"
      "-DSRCPROCESS_MODULE=$<TARGET_FILE:srcprocess>"
      "-DSFINFO_MODULE=$<TARGET_FILE:sfinfo>"
      "-DREALTIME_MODULE=$<TARGET_FILE:realtime>"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
    DEPENDS audio fftw srcprocess sfinfo realtime
    COMMENT "Verifying the pure-audio Windows dependency closure"
    VERBATIM
  )
endif()
