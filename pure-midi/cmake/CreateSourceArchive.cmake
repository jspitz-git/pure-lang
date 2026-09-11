cmake_minimum_required(VERSION 3.25)
# The public source inventory is deliberately explicit. No checkout, build,
# glob, Git index, or generated install inventory can add archive members.
set(MIDI_SOURCE_FILES
  CMakeLists.txt COPYING Makefile README THIRD_PARTY.md WINDOWS.md
  cmake/CreateSourceArchive.cmake cmake/Install.cmake cmake/RunHardwareTest.cmake
  cmake/RunPureTest.cmake cmake/SourceArchiveTools.ps1 cmake/SourceWorkflow.cmake
  cmake/VerifyInstalledPackage.cmake cmake/VerifyWindowsDependencies.cmake cmake/install_guard.c
  debian/changelog debian/compat debian/control debian/copyright debian/docs
  debian/rules debian/source/format debian/watch
  examples/midi_examp.pure examples/prelude3.mid licenses/PortMidi.txt licenses/origins.tsv
  midi.pure midi_bounds.c midi_bounds.h midi_stream.c midi_stream.h
  midifile/Makefile midifile/mf.c midifile/mf.h midifile/midifile.c midifile/midifile.h
  midifile/midifile.pure pmdev.c pmdev.h portmidi.h portmidi.pure porttime.h
  tests/bounds.pure tests/cleanup_contract.cmake tests/configure_contract.cmake
  tests/device-timing.pure tests/hardware-output.pure tests/install_contract.cmake
  tests/install_guard_contract.ps1 tests/midi_boundary_harness.c tests/midi_lifecycle_harness.c
  tests/midifile_fault_harness.c tests/midifile_test_api.h tests/run_pure_test.c
  tests/runner_contract.cmake tests/runner_fixture.c tests/runner_hardware_fixture.c
  tests/runtime_verifier_contract.cmake tests/smoke.pure tests/source_dist_contract.cmake
  tests/source_dist_extracted.cmake tests/source_dist_tools.ps1)
list(SORT MIDI_SOURCE_FILES)
if(NOT DEFINED SOURCE_DIR)
  cmake_path(GET CMAKE_CURRENT_LIST_DIR PARENT_PATH SOURCE_DIR)
endif()
if(NOT DEFINED DIST_DIR)
  set(DIST_DIR "${SOURCE_DIR}")
endif()
cmake_host_system_information(RESULT source_windows_root QUERY WINDOWS_REGISTRY
  "HKLM/SOFTWARE/Microsoft/Windows NT/CurrentVersion" VALUE SystemRoot)
set(SOURCE_POWERSHELL "${source_windows_root}/System32/WindowsPowerShell/v1.0/powershell.exe")
list(JOIN MIDI_SOURCE_FILES "|" source_manifest_argument)
if(MIDI_SOURCE_HELPERS_ONLY)
  return()
endif()
execute_process(COMMAND "${SOURCE_POWERSHELL}" -NoProfile -NonInteractive
  -ExecutionPolicy Bypass -File "${CMAKE_CURRENT_LIST_DIR}/SourceArchiveTools.ps1"
  -Mode Create -SourceDir "${SOURCE_DIR}" -OutputDir "${DIST_DIR}"
  -Manifest "${source_manifest_argument}" RESULT_VARIABLE rc)
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "source archive creation failed (${rc})")
endif()
