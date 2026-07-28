foreach(required IN ITEMS STAGE_PREFIX SOURCE_RUNTIME_DIR LLVM_READOBJ)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE stage)
cmake_path(ABSOLUTE_PATH SOURCE_RUNTIME_DIR NORMALIZE OUTPUT_VARIABLE source_bin)
set(module_dir "${stage}/lib/pure")
set(doc_dir "${stage}/share/doc/pure-midi")

set(expected_files
  "${module_dir}/pmlib.dll"
  "${module_dir}/midifile.dll"
  "${module_dir}/midi.pure"
  "${module_dir}/portmidi.pure"
  "${module_dir}/midifile.pure"
  "${stage}/bin/libportmidi.dll"
  "${doc_dir}/README"
  "${doc_dir}/COPYING"
  "${doc_dir}/WINDOWS.md"
  "${doc_dir}/THIRD_PARTY.md"
  "${doc_dir}/licenses/PortMidi.txt"
  "${doc_dir}/examples/midi_examp.pure"
  "${doc_dir}/examples/prelude3.mid"
  "${doc_dir}/tests/device-timing.pure"
  "${doc_dir}/tests/smoke.pure"
  "${doc_dir}/tests/hardware-output.pure")
foreach(expected IN LISTS expected_files)
  if(NOT EXISTS "${expected}")
    message(FATAL_ERROR "Missing installed pure-midi file: ${expected}")
  endif()
endforeach()

file(SHA256 "${stage}/bin/libportmidi.dll" staged_hash)
file(SHA256 "${source_bin}/libportmidi.dll" source_hash)
if(NOT staged_hash STREQUAL source_hash)
  message(FATAL_ERROR "Staged PortMidi runtime hash mismatch")
endif()

set(ENV{PATH} "${stage}/bin;C:/Windows/System32;C:/Windows")
set(ENV{PURELIB} "")
set(test_directory "${stage}/pure-midi-installed-test")
file(REMOVE_RECURSE "${test_directory}")
file(MAKE_DIRECTORY "${test_directory}")
file(COPY "${doc_dir}/examples/prelude3.mid" DESTINATION "${test_directory}")
foreach(test_name IN ITEMS device-timing smoke)
  execute_process(
    COMMAND "${stage}/bin/pure.exe" --norc
      -I "${module_dir}" -L "${module_dir}"
      -x "${doc_dir}/tests/${test_name}.pure"
    WORKING_DIRECTORY "${test_directory}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    TIMEOUT 45
    ENCODING UTF-8)
  if(NOT result EQUAL 0)
    message(FATAL_ERROR
      "Installed pure-midi ${test_name} test failed (${result})\n"
      "stdout:\n${output}\nstderr:\n${error}")
  endif()
endforeach()
file(REMOVE_RECURSE "${test_directory}")

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    "-DPORTMIDI_DLL=${stage}/bin/libportmidi.dll"
    "-DPMLIB_MODULE=${module_dir}/pmlib.dll"
    "-DMIDIFILE_MODULE=${module_dir}/midifile.dll"
    -P "${CMAKE_CURRENT_LIST_DIR}/VerifyWindowsDependencies.cmake"
  RESULT_VARIABLE audit_result
  OUTPUT_VARIABLE audit_output
  ERROR_VARIABLE audit_error
  ENCODING UTF-8)
if(NOT audit_result EQUAL 0)
  message(FATAL_ERROR
    "Installed pure-midi PE audit failed (${audit_result})\n"
    "stdout:\n${audit_output}\nstderr:\n${audit_error}")
endif()

list(LENGTH expected_files expected_count)
message(STATUS
  "Verified installed pure-midi: ${expected_count} package files, "
  "hash-matched PortMidi runtime, 2 sanitized hardware-free tests, "
  "and staged PE closure")
