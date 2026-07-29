cmake_minimum_required(VERSION 3.20)

project(PureOctaveWindowsToolchain NONE)

include(CTest)

set(PURE_PREFIX "${PURE_PREFIX}" CACHE PATH "Relocatable Pure prefix")
set(OCTAVE_ROOT "${OCTAVE_ROOT}" CACHE PATH "Root of the validated Octave distribution")
set(GPG_EXECUTABLE "${GPG_EXECUTABLE}" CACHE FILEPATH "GnuPG executable used to validate Octave")
set(PURE_OCTAVE_WORK_ROOT "${CMAKE_BINARY_DIR}/pure-octave-work" CACHE PATH
  "Temporary work root for a signed Octave distribution")

if (NOT OCTAVE_ROOT)
  include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/AcquireWindowsOctave.cmake")
  acquire_windows_octave(OCTAVE_ROOT
    WORK_ROOT "${PURE_OCTAVE_WORK_ROOT}"
    GPG_EXECUTABLE "${GPG_EXECUTABLE}")
endif ()

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/OctaveToolchain.cmake")
pure_octave_validate_toolchain()

if (BUILD_TESTING)
  set(rejected_root_test "${CMAKE_CURRENT_BINARY_DIR}/pure-octave-rejected-root.cmake")
  file(CONFIGURE OUTPUT "${rejected_root_test}" CONTENT [=[
set(fake_root "@CMAKE_CURRENT_BINARY_DIR@/fake-octave-root")
file(MAKE_DIRECTORY "${fake_root}/bin")
file(WRITE "${fake_root}/bin/octave-cli.exe" "")
execute_process(
  COMMAND "@CMAKE_COMMAND@" -S "@CMAKE_CURRENT_SOURCE_DIR@" -B "@CMAKE_CURRENT_BINARY_DIR@/fake-octave-build"
    -G "@CMAKE_GENERATOR@" -DBUILD_TESTING=OFF "-DPURE_PREFIX=@PURE_PREFIX@"
    "-DOCTAVE_ROOT=${fake_root}"
  RESULT_VARIABLE configure_result
  OUTPUT_VARIABLE configure_stdout
  ERROR_VARIABLE configure_stderr)
set(configure_output "${configure_stdout}${configure_stderr}")
if (configure_result EQUAL 0)
  message(FATAL_ERROR "The incomplete fake Octave root unexpectedly configured.")
endif ()
foreach (required_text
    "Missing required Octave 11.3.0 toolchain paths:"
    "mkoctfile"
    "public headers"
    "import libraries"
    "runtime directory"
    "module directory"
    "share directory")
  string(FIND "${configure_output}" "${required_text}" found_text)
  if (found_text EQUAL -1)
    message(FATAL_ERROR "Rejected-root diagnostic omitted '${required_text}':\n${configure_output}")
  endif ()
endforeach ()
]=] @ONLY)
  add_test(NAME pure-octave-rejected-root
    COMMAND "${CMAKE_COMMAND}" -P "${rejected_root_test}")
  add_test(NAME pure-octave-extraction-containment
    COMMAND "${CMAKE_COMMAND}" -P
      "${CMAKE_CURRENT_SOURCE_DIR}/cmake/ContainmentRegression.cmake")

  add_test(NAME pure-octave-embed-probe
    COMMAND "${CMAKE_COMMAND}"
      "-DMKOCTFILE=${OCTAVE_MKOCTFILE}"
      "-DPROBE_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}/probes/embed_probe.cc"
      "-DPROBE_BINARY=${CMAKE_CURRENT_BINARY_DIR}/embed_probe.exe"
      "-DOCTAVE_RUNTIME_DIR=${OCTAVE_RUNTIME_DIR}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunEmbedProbe.cmake")
endif ()
