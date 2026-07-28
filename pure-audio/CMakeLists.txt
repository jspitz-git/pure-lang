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
