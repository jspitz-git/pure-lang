cmake_minimum_required(VERSION 3.25)
foreach(required WORK EXTRACTED_BUILD CLANG64_PREFIX PURE_PREFIX FORBIDDEN)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} required by extracted-source driver")
  endif()
endforeach()
get_filename_component(source "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
set(build "${EXTRACTED_BUILD}")
set(logs "${WORK}/logs")
file(MAKE_DIRECTORY "${logs}")
set(ps C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe)
set(tools "${source}/tests/source_dist_tools.ps1")
set(path_tools "${source}/cmake/SourceArchiveTools.ps1")
set(ENV{PATH} "${CLANG64_PREFIX}/bin;${CLANG64_PREFIX}/../usr/bin;C:/Windows/System32")

function(scan directory)
  execute_process(COMMAND "${ps}" -NoProfile -NonInteractive -ExecutionPolicy Bypass
    -File "${tools}" -Mode Scan -Directory "${directory}" -Forbidden "${FORBIDDEN}" -SourceTools "${path_tools}"
    RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
  if(NOT rc EQUAL 0)
    message(FATAL_ERROR "Unbounded extracted-source leak scan failed: ${out}${err}")
  endif()
  message(STATUS "${out}")
endfunction()
function(step name)
  string(TIMESTAMP start "%s" UTC)
  execute_process(COMMAND ${ARGN} RESULT_VARIABLE rc
    OUTPUT_FILE "${logs}/${name}.stdout" ERROR_FILE "${logs}/${name}.stderr")
  string(TIMESTAMP end "%s" UTC)
  math(EXPR elapsed "${end}-${start}")
  scan("${logs}")
  file(READ "${logs}/${name}.stdout" out)
  file(READ "${logs}/${name}.stderr" err)
  if(NOT rc EQUAL 0)
    message(FATAL_ERROR "Extracted ${name} failed rc=${rc}: ${out}${err}")
  endif()
  message(STATUS "SOURCE_DIST_STEP_OK step=${name} seconds=${elapsed}")
endfunction()

# Generate the strict preset from declared external tool/runtime prefixes, not
# any checkout or pre-existing build cache. Native helper sources come solely
# from this archive; this file is itself archived and executed from extraction.
set(preset "${WORK}/strict.cmake")
set(rows
  "CMAKE_C_COMPILER|${CLANG64_PREFIX}/bin/clang.exe"
  "CMAKE_MAKE_PROGRAM|${CLANG64_PREFIX}/bin/ninja.exe"
  "PKG_CONFIG_EXECUTABLE|${CLANG64_PREFIX}/bin/pkgconf.exe"
  "LLVM_READOBJ|${CLANG64_PREFIX}/bin/llvm-readobj.exe"
  "PURE_AUDIO_CLANG64_PREFIX|${CLANG64_PREFIX}"
  "PURE_AUDIO_PURE_PREFIX|${PURE_PREFIX}"
  "PURE_INCLUDE_DIR|${PURE_PREFIX}/include"
  "PURE_EXECUTABLE|${PURE_PREFIX}/bin/pure.exe"
  "PURE_HEADER|${PURE_PREFIX}/include/pure/runtime.h"
  "PURE_IMPORT_LIBRARY|${PURE_PREFIX}/lib/libpure.dll.a"
  "PURE_RUNTIME_DLL|${PURE_PREFIX}/bin/libpure.dll"
  "PORTAUDIO_HEADER|${CLANG64_PREFIX}/include/portaudio.h"
  "PORTAUDIO_IMPORT_LIBRARY|${CLANG64_PREFIX}/lib/libportaudio.dll.a"
  "FFTW_HEADER|${CLANG64_PREFIX}/include/fftw3.h"
  "FFTW_IMPORT_LIBRARY|${CLANG64_PREFIX}/lib/libfftw3.dll.a"
  "SAMPLERATE_HEADER|${CLANG64_PREFIX}/include/samplerate.h"
  "SAMPLERATE_IMPORT_LIBRARY|${CLANG64_PREFIX}/lib/libsamplerate.dll.a"
  "SNDFILE_HEADER|${CLANG64_PREFIX}/include/sndfile.h"
  "SNDFILE_IMPORT_LIBRARY|${CLANG64_PREFIX}/lib/libsndfile.dll.a"
  "PTHREAD_HEADER|${CLANG64_PREFIX}/include/pthread.h"
  "PTHREAD_IMPORT_LIBRARY|${CLANG64_PREFIX}/lib/libpthread.dll.a"
  "GMP_HEADER|${CLANG64_PREFIX}/include/gmp.h"
  "MPFR_HEADER|${CLANG64_PREFIX}/include/mpfr.h"
  "PURE_AUDIO_WINDOWS_HEADER|${CLANG64_PREFIX}/include/windows.h"
  "PURE_AUDIO_WINDOWS_SYSTEM_DIRECTORY|C:/Windows/System32"
  "PURE_AUDIO_MAKE_EXECUTABLE|${CLANG64_PREFIX}/bin/mingw32-make.exe"
  "PURE_AUDIO_SH_EXECUTABLE|${CLANG64_PREFIX}/../usr/bin/sh.exe"
  "PURE_AUDIO_STRICT_WINDOWS_AUDIT|ON" "CMAKE_BUILD_TYPE|Release" "BUILD_TESTING|ON")
set(text "# Extracted-source explicit strict inputs.\n")
foreach(row IN LISTS rows)
  string(REPLACE "|" ";" fields "${row}")
  list(GET fields 0 name)
  list(GET fields 1 value)
  if(IS_ABSOLUTE "${value}")
    get_filename_component(value "${value}" ABSOLUTE)
  endif()
  string(APPEND text "set(${name} [==[${value}]==] CACHE STRING \"Declared input\" FORCE)\n")
endforeach()
set(runtime)
foreach(name pure.exe libpure.dll libc++.dll libgmp-10.dll libiconv-2.dll libmpfr-6.dll
    libpcre-1.dll libpcreposix-0.dll libreadline8.dll libtermcap-0.dll libwinpthread-1.dll libzstd.dll zlib1.dll)
  list(APPEND runtime "${name}|${PURE_PREFIX}/bin/${name}")
endforeach()
foreach(name libportaudio.dll libfftw3-3.dll libsamplerate-0.dll libsndfile-1.dll libogg-0.dll
    libvorbisenc-2.dll libFLAC.dll libopus-0.dll libmpg123-0.dll libmp3lame-0.dll libvorbis-0.dll)
  list(APPEND runtime "${name}|${CLANG64_PREFIX}/bin/${name}")
endforeach()
string(APPEND text "set(PURE_AUDIO_RUNTIME_SOURCES [==[${runtime}]==] CACHE STRING \"Declared runtime\" FORCE)\n")
file(WRITE "${preset}" "${text}")
scan("${source}")
step(configure "${CMAKE_COMMAND}" -S "${source}" -B "${build}" -G Ninja -C "${preset}")
# Exactly two explicit four-worker build commands are the public release gate.
step(build "${CMAKE_COMMAND}" --build "${build}" --parallel 4)
step(pe "${CMAKE_COMMAND}" --build "${build}" --target verify-windows-dependencies --parallel 4)
get_filename_component(tool_dir "${CMAKE_COMMAND}" DIRECTORY)
# Exclude only this recursive distribution test; every Task 1-6 mandatory test
# remains registered and executes from the extracted source/native helpers.
step(tests "${tool_dir}/ctest.exe" --test-dir "${build}" --output-on-failure --parallel 4
  -E "^pure-audio-source-dist-contract$")
set(stage "${WORK}/package")
file(COPY "${PURE_PREFIX}/" DESTINATION "${stage}")
step(install-runtime "${CMAKE_COMMAND}" --install "${build}" --prefix "${stage}" --component runtime)
step(install-documentation "${CMAKE_COMMAND}" --install "${build}" --prefix "${stage}" --component documentation)
step(installed-verifier "${CMAKE_COMMAND}" "-DAUDIO_INSTALL_CONTEXT=${build}/windows-install-context.cmake"
  "-DSTAGE_PREFIX=${stage}" -P "${source}/cmake/VerifyInstalledPackage.cmake")
scan("${build}")
scan("${stage}")
file(READ "${logs}/installed-verifier.stdout" verified)
if(NOT verified MATCHES "INSTALL_PACKAGE_OK" OR NOT verified MATCHES "PURE_AUDIO_DONE_[a-f0-9]+")
  message(FATAL_ERROR "Public installed verifier did not prove package inventory and Task4 token execution")
endif()
file(WRITE "${WORK}/extracted-result.txt" "EXTRACTED_SOURCE_OK\n${verified}\n")
message(STATUS "EXTRACTED_SOURCE_OK strict=1 build_workers=4 pe_workers=4 mandatory_tests=10 components=2 public_verifier=1")
