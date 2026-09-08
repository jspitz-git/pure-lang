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

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/Install.cmake")

include(CTest)
if(BUILD_TESTING)
  pkg_get_variable(PURE_PREFIX pure prefix)
  set(PURE_AUDIO_COMPILER_RUNTIME_PATH "")
  if(MINGW AND CMAKE_C_COMPILER_ID MATCHES "Clang")
    execute_process(
      COMMAND "${CMAKE_C_COMPILER}" --print-resource-dir
      RESULT_VARIABLE compiler_resource_result
      OUTPUT_VARIABLE compiler_resource_dir
      OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    if(compiler_resource_result EQUAL 0 AND
       EXISTS "${compiler_resource_dir}/lib/windows")
      set(PURE_AUDIO_COMPILER_RUNTIME_PATH
        "${compiler_resource_dir}/lib/windows\;")
    endif()
  endif()
  set(
    PURE_AUDIO_TEST_RUNTIME_PATH
    "${PURE_PREFIX}/bin\;${PURE_AUDIO_COMPILER_RUNTIME_PATH}$ENV{MSYSTEM_PREFIX}/bin\;$ENV{SystemRoot}/System32\;$ENV{SystemRoot}"
  )

  add_executable(audio_fault_harness tests/audio_fault_harness.c)
  target_compile_features(audio_fault_harness PRIVATE c_std_11)
  target_link_libraries(
    audio_fault_harness
    PRIVATE PkgConfig::PURE PkgConfig::PORTAUDIO PkgConfig::SNDFILE
            Threads::Threads
  )
  if(MINGW)
    target_compile_options(audio_fault_harness PRIVATE -Wall -Wextra -Werror)
  endif()
  add_test(NAME pure-audio-fault-bounds COMMAND audio_fault_harness)
  set_tests_properties(
    pure-audio-fault-bounds
    PROPERTIES
      LABELS "audio;fault;bounds;no-hardware"
      ENVIRONMENT "PATH=${PURE_AUDIO_TEST_RUNTIME_PATH}"
      TIMEOUT 30
  )

  add_pure_audio_module(audio_bounds_seam tests/audio_fault_harness.c)
  target_link_libraries(
    audio_bounds_seam PRIVATE PkgConfig::PORTAUDIO PkgConfig::SNDFILE
                              Threads::Threads
  )
  set_target_properties(
    audio_bounds_seam
    PROPERTIES
      OUTPUT_NAME audio
      LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/bounds-modules"
      RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/bounds-modules"
  )
  add_dependencies(audio_bounds_seam fftw srcprocess sfinfo)
  add_custom_command(
    TARGET audio_bounds_seam POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
      "$<TARGET_FILE:fftw>"
      "$<TARGET_FILE:srcprocess>"
      "$<TARGET_FILE:sfinfo>"
      "$<TARGET_FILE_DIR:audio_bounds_seam>"
    VERBATIM
  )

  find_program(
    PURE_EXECUTABLE
    NAMES pure
    HINTS "${PURE_PREFIX}/bin"
    NO_DEFAULT_PATH
    REQUIRED
  )
  add_test(
    NAME pure-audio-load
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DMODULE_DIR=$<TARGET_FILE_DIR:audio>"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/load.pure"
      "-DTEST_DIRECTORY=${CMAKE_CURRENT_BINARY_DIR}/load-test"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake"
  )
  set_tests_properties(
    pure-audio-load
    PROPERTIES
      LABELS "audio;load;no-hardware"
      ENVIRONMENT "PATH=${PURE_AUDIO_TEST_RUNTIME_PATH}"
      REQUIRED_FILES
        "$<TARGET_FILE:audio>;$<TARGET_FILE:fftw>;$<TARGET_FILE:srcprocess>;$<TARGET_FILE:sfinfo>;$<TARGET_FILE:realtime>"
      TIMEOUT 45
  )
  add_test(
    NAME pure-audio-processing
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DMODULE_DIR=$<TARGET_FILE_DIR:audio>"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
      "-DTEST_DIRECTORY=${CMAKE_CURRENT_BINARY_DIR}/processing-test"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake"
  )
  set_tests_properties(
    pure-audio-processing
    PROPERTIES
      LABELS "audio;fftw;samplerate;sndfile;realtime;no-hardware"
      ENVIRONMENT "PATH=${PURE_AUDIO_TEST_RUNTIME_PATH}"
      REQUIRED_FILES "${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
      TIMEOUT 60
  )
  add_test(
    NAME pure-audio-public-bounds
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DMODULE_DIR=$<TARGET_FILE_DIR:audio_bounds_seam>"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/bounds.pure"
      "-DTEST_DIRECTORY=${CMAKE_CURRENT_BINARY_DIR}/bounds-test"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake"
  )
  set_tests_properties(
    pure-audio-public-bounds
    PROPERTIES
      LABELS "audio;fftw;samplerate;sndfile;bounds;no-hardware"
      ENVIRONMENT "PATH=${PURE_AUDIO_TEST_RUNTIME_PATH}"
      REQUIRED_FILES
        "$<TARGET_FILE:audio_bounds_seam>;${CMAKE_CURRENT_SOURCE_DIR}/tests/bounds.pure"
      TIMEOUT 60
  )
  foreach(mode IN ITEMS playback capture)
    add_custom_target(
      "check-audio-${mode}"
      COMMAND "${CMAKE_COMMAND}"
        "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
        "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
        "-DMODULE_DIR=$<TARGET_FILE_DIR:audio>"
        "-DMODE=${mode}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunHardwareTest.cmake"
      DEPENDS audio
      COMMENT "Running bounded pure-audio ${mode} validation"
      VERBATIM
    )
  endforeach()
endif()
