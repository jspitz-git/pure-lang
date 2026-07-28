foreach(required IN ITEMS STAGE_PREFIX SOURCE_RUNTIME_DIR LLVM_READOBJ)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE stage)
cmake_path(ABSOLUTE_PATH SOURCE_RUNTIME_DIR NORMALIZE OUTPUT_VARIABLE source_bin)
set(module_dir "${stage}/lib/pure")
set(doc_dir "${stage}/share/doc/pure-audio")

set(module_files
  audio.dll fftw.dll srcprocess.dll sfinfo.dll realtime.dll
  audio.pure portaudio.pure fftw.pure samplerate.pure sndfile.pure realtime.pure)
set(runtime_files
  libportaudio.dll libfftw3-3.dll libsamplerate-0.dll libsndfile-1.dll
  libogg-0.dll libvorbisenc-2.dll libFLAC.dll libopus-0.dll
  libmpg123-0.dll libmp3lame-0.dll libvorbis-0.dll)
set(documentation_files README COPYING WINDOWS.md THIRD_PARTY.md)
set(license_files
  PortAudio.txt libsamplerate.txt libsndfile.txt libogg.txt FLAC-Xiph.txt
  Opus.txt mpg123.txt)
set(example_files audio_examp.pure audio_test.pd)
set(test_files
  load.pure smoke.pure hardware.pure hardware-playback.pure
  hardware-capture.pure)

set(expected_files)
foreach(name IN LISTS module_files)
  list(APPEND expected_files "${module_dir}/${name}")
endforeach()
foreach(name IN LISTS runtime_files)
  list(APPEND expected_files "${stage}/bin/${name}")
endforeach()
foreach(name IN LISTS documentation_files)
  list(APPEND expected_files "${doc_dir}/${name}")
endforeach()
foreach(name IN LISTS license_files)
  list(APPEND expected_files "${doc_dir}/licenses/${name}")
endforeach()
foreach(name IN LISTS example_files)
  list(APPEND expected_files "${doc_dir}/examples/${name}")
endforeach()
foreach(name IN LISTS test_files)
  list(APPEND expected_files "${doc_dir}/tests/${name}")
endforeach()
foreach(expected IN LISTS expected_files)
  if(NOT EXISTS "${expected}")
    message(FATAL_ERROR "Missing installed pure-audio file: ${expected}")
  endif()
endforeach()

foreach(runtime_file IN LISTS runtime_files)
  file(SHA256 "${stage}/bin/${runtime_file}" staged_hash)
  file(SHA256 "${source_bin}/${runtime_file}" source_hash)
  if(NOT staged_hash STREQUAL source_hash)
    message(FATAL_ERROR "Runtime hash mismatch for ${runtime_file}")
  endif()
endforeach()
foreach(reused IN ITEMS libc++.dll libwinpthread-1.dll)
  if(NOT EXISTS "${stage}/bin/${reused}" OR
      NOT EXISTS "${source_bin}/${reused}")
    message(FATAL_ERROR "Missing reused runtime: ${reused}")
  endif()
  file(SHA256 "${stage}/bin/${reused}" staged_hash)
  file(SHA256 "${source_bin}/${reused}" source_hash)
  if(NOT staged_hash STREQUAL source_hash)
    message(FATAL_ERROR "Conflicting reused runtime: ${reused}")
  endif()
endforeach()

set(test_directory "${stage}/pure-audio-installed-test")
file(REMOVE_RECURSE "${test_directory}")
file(MAKE_DIRECTORY "${test_directory}")
set(ENV{PATH} "${stage}/bin;C:/Windows/System32;C:/Windows")
set(ENV{PURELIB} "")
execute_process(
  COMMAND "${stage}/bin/pure.exe" --norc
    -I "${module_dir}" -L "${module_dir}"
    -x "${doc_dir}/tests/smoke.pure"
  WORKING_DIRECTORY "${test_directory}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
  TIMEOUT 60
  ENCODING UTF-8)
file(REMOVE_RECURSE "${test_directory}")
if(NOT result EQUAL 0)
  message(FATAL_ERROR
    "Installed pure-audio smoke test failed (${result})\n"
    "stdout:\n${output}\nstderr:\n${error}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    "-DRUNTIME_DIR=${stage}/bin"
    "-DAUDIO_MODULE=${module_dir}/audio.dll"
    "-DFFTW_MODULE=${module_dir}/fftw.dll"
    "-DSRCPROCESS_MODULE=${module_dir}/srcprocess.dll"
    "-DSFINFO_MODULE=${module_dir}/sfinfo.dll"
    "-DREALTIME_MODULE=${module_dir}/realtime.dll"
    -P "${CMAKE_CURRENT_LIST_DIR}/VerifyWindowsDependencies.cmake"
  RESULT_VARIABLE audit_result
  OUTPUT_VARIABLE audit_output
  ERROR_VARIABLE audit_error
  ENCODING UTF-8)
if(NOT audit_result EQUAL 0)
  message(FATAL_ERROR
    "Installed pure-audio PE audit failed (${audit_result})\n"
    "stdout:\n${audit_output}\nstderr:\n${audit_error}")
endif()

list(LENGTH expected_files expected_count)
list(LENGTH runtime_files runtime_count)
message(STATUS
  "Verified installed pure-audio: ${expected_count} package files, "
  "${runtime_count} new runtime DLLs, 2 hash-matched reused DLLs, "
  "sanitized hardware-free smoke test, and staged PE closure")
