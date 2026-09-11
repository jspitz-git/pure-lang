cmake_minimum_required(VERSION 3.25)
foreach(required SOURCE_DIR CLANG64_PREFIX PURE_PREFIX)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "source workflow requires explicit ${required}")
  endif()
endforeach()
if(NOT EXTRACTED_SOURCE_WORKFLOW)
  if(NOT DEFINED DIST_ROOT OR "${DIST_ROOT}" STREQUAL "")
    message(FATAL_ERROR "source workflow requires an explicit short DIST_ROOT")
  endif()
  set(MIDI_SOURCE_HELPERS_ONLY ON)
  include("${CMAKE_CURRENT_LIST_DIR}/CreateSourceArchive.cmake")
  execute_process(COMMAND "${SOURCE_POWERSHELL}" -NoProfile -NonInteractive -ExecutionPolicy Bypass
    -File "${CMAKE_CURRENT_LIST_DIR}/SourceArchiveTools.ps1" -Mode Workflow
    -SourceDir "${SOURCE_DIR}" -DistRoot "${DIST_ROOT}" -Clang64Prefix "${CLANG64_PREFIX}"
    -PurePrefix "${PURE_PREFIX}" -Manifest "${source_manifest_argument}" RESULT_VARIABLE rc)
  if(NOT rc EQUAL 0)
    message(FATAL_ERROR "source distribution workflow failed (${rc})")
  endif()
  return()
endif()
if(NOT DEFINED WORK_DIR)
  message(FATAL_ERROR "extracted workflow requires owned WORK_DIR")
endif()
# All project helpers below are resolved from extraction. The only external
# inputs are the same explicit audited toolchain, portable Pure and Windows.
set(cmake "${CLANG64_PREFIX}/bin/cmake.exe")
set(build "${WORK_DIR}/b")
set(stage "${WORK_DIR}/stage")
set(ENV{PATH} "${CLANG64_PREFIX}/bin;${PURE_PREFIX}/bin;C:/Windows/System32;C:/Windows")
unset(ENV{PURELIB})
unset(ENV{PURE_INCLUDE})
unset(ENV{PURE_LIBRARY})
function(source_step name)
  execute_process(COMMAND ${ARGN} RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 1800)
  file(WRITE "${WORK_DIR}/${name}.log" "${out}\n${err}")
  message(STATUS "${out}")
  if(NOT rc EQUAL 0)
    message(FATAL_ERROR "extracted source ${name} failed (${rc}): ${err}")
  endif()
endfunction()
source_step(preset "${cmake}" "-DSOURCE_DIR=${SOURCE_DIR}" "-DCLANG64_PREFIX=${CLANG64_PREFIX}"
  "-DPURE_PREFIX=${PURE_PREFIX}" "-DRUNNER=unused-for-preset"
  -DWRITE_PRESET_ONLY=ON "-DPRESET_OUTPUT=${WORK_DIR}/inputs.cmake"
  -P "${SOURCE_DIR}/tests/configure_contract.cmake")
source_step(configure "${cmake}" -S "${SOURCE_DIR}" -B "${build}" -G Ninja -C "${WORK_DIR}/inputs.cmake")
# Separate invocations, both with exactly four workers, are part of the public
# release contract. ASan targets are built in the normal build alongside Release.
message(STATUS "SOURCE_BUILD_COMMAND ${cmake} --build ${build} --parallel 4")
source_step(build "${cmake}" --build "${build}" --parallel 4)
message(STATUS "SOURCE_PE_BUILD_COMMAND ${cmake} --build ${build} --target verify-windows-dependencies --parallel 4")
source_step(pe "${cmake}" --build "${build}" --target verify-windows-dependencies --parallel 4)
# The archive matrix is hardware-free and does not invoke this workflow, so run
# it too. Only source-distcheck is a separate explicit target, avoiding recursion.
source_step(tests "${CLANG64_PREFIX}/bin/ctest.exe" --test-dir "${build}"
  -L no-hardware --no-tests=error --output-on-failure -V)
file(MAKE_DIRECTORY "${stage}")
file(COPY "${PURE_PREFIX}/" DESTINATION "${stage}")
source_step(runtime "${cmake}" --install "${build}" --prefix "${stage}" --component runtime)
source_step(documentation "${cmake}" --install "${build}" --prefix "${stage}" --component documentation)
source_step(installed "${cmake}" "-DMIDI_INSTALL_CONTEXT=${build}/windows-install-context.cmake"
  "-DSTAGE_PREFIX=${stage}" -P "${SOURCE_DIR}/cmake/VerifyInstalledPackage.cmake")
message(STATUS "SOURCE_EXTRACTED_OK mandatory_tests=19 pe=16 runtime=6 documentation=11 installed_tests=2")
