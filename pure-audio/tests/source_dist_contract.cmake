cmake_minimum_required(VERSION 3.25)

foreach(required SOURCE_DIR MODULE_DIR CLANG64_PREFIX PURE_PREFIX RUNNER)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()
set(PURE_AUDIO_RUNNER "${RUNNER}")
set(PURE_AUDIO_RUNNER_HELPERS_ONLY ON)
include("${SOURCE_DIR}/cmake/RunPureTest.cmake")

# Independent release boundary. Never read the producer's DISTFILES or its
# manifest to calculate expected archive membership. Hashes below snapshot the
# actual declared inputs before invoking the public producer.
set(expected_files
  COPYING CMakeLists.txt Makefile Makefile.common README WINDOWS.md THIRD_PARTY.md
  audio.c audio.pure audio_test_api.h portaudio.pure
  cmake/Install.cmake cmake/RunHardwareTest.cmake cmake/RunPureTest.cmake
  cmake/VerifyInstalledPackage.cmake cmake/VerifyWindowsDependencies.cmake cmake/install_guard.c
  cmake/CreateSourceArchive.cmake cmake/SourceArchiveTools.ps1
  cmake/SourceWorkflow.cmake
  debian/changelog debian/compat debian/control debian/copyright debian/docs
  debian/rules debian/source/format debian/watch
  examples/audio_examp.pure examples/audio_test.pd
  fftw/Makefile fftw/fftw.c fftw/fftw.pure
  samplerate/Makefile samplerate/samplerate.pure samplerate/src.pure
  samplerate/srcprocess.c samplerate/srcprocess.h
  sndfile/Makefile sndfile/sndfile.pure sndfile/sf.pure sndfile/sfinfo.c sndfile/sfinfo.h
  realtime/Makefile realtime/realtime.c realtime/realtime.pure
  tests/audio_fault_harness.c tests/bounds.pure tests/cleanup_contract.cmake
  tests/configure_contract.cmake tests/hardware-capture.pure tests/hardware-playback.pure
  tests/hardware.pure tests/install_contract.cmake tests/install_guard_contract.ps1
  tests/load.pure tests/run_pure_test.c tests/runner_contract.cmake
  tests/runtime_verifier_contract.cmake tests/smoke.pure tests/source_dist_contract.cmake
  tests/source_dist_tools.ps1
  tests/source_dist_extracted.cmake
  licenses/.gitattributes licenses/FFTW-COPYING.txt licenses/FFTW-COPYRIGHT.txt licenses/FLAC-Xiph.txt
  licenses/GMP-COPYING-LESSERv3.txt licenses/GMP-COPYINGv2.txt licenses/GMP-COPYINGv3.txt
  licenses/LAME-COPYING.txt licenses/MPFR-COPYING-LESSER.txt licenses/MPFR-COPYING.txt
  licenses/Opus.txt licenses/PCRE-LICENCE.txt licenses/PortAudio.txt
  licenses/Pure-COPYING-LESSER.txt licenses/Pure-COPYING.txt licenses/Pure-README.txt
  licenses/Readline-COPYING.txt licenses/Termcap-COPYING.txt licenses/Vorbis-COPYING.txt
  licenses/Zlib-LICENSE.txt licenses/Zstd-LICENSE.txt licenses/libcxx.txt
  licenses/libiconv-COPYING-LIB.txt licenses/libogg.txt licenses/libsamplerate.txt
  licenses/libsndfile.txt licenses/mpg123.txt licenses/origins.tsv licenses/winpthreads.txt)
list(SORT expected_files)

pure_audio_create_leaf(work)
set(checkout "${work}/producer checkout with spaces")
set(extracted "${work}/distribution source with spaces")
file(MAKE_DIRECTORY "${checkout}" "${extracted}")
set(expected_rows)
foreach(path IN LISTS expected_files)
  if(NOT EXISTS "${SOURCE_DIR}/${path}" OR IS_DIRECTORY "${SOURCE_DIR}/${path}")
    message(FATAL_ERROR "Invalid contract input: ${path}")
  endif()
  file(SHA256 "${SOURCE_DIR}/${path}" hash)
  list(APPEND expected_rows "${path}|${hash}")
  get_filename_component(parent "${checkout}/${path}" DIRECTORY)
  file(MAKE_DIRECTORY "${parent}")
  file(COPY_FILE "${SOURCE_DIR}/${path}" "${checkout}/${path}")
endforeach()
list(JOIN expected_rows "\n" snapshot)
file(WRITE "${work}/expected-source-sha256.tsv" "${snapshot}\n")

set(ENV{PATH} "${CLANG64_PREFIX}/../usr/bin;${CLANG64_PREFIX}/bin;${PURE_PREFIX}/bin;C:/Windows/System32")
# Public make distcheck exports its command variables in MAKEFLAGS. Fixtures
# must not inherit its valid audit-build argument into an invalid-input probe.
unset(ENV{MAKEFLAGS})
unset(ENV{MFLAGS})
unset(ENV{MAKEOVERRIDES})
if(PATH_RED_ONLY)
  if(DEFINED LEGACY_MAKEFILE)
    file(COPY_FILE "${LEGACY_MAKEFILE}" "${checkout}/Makefile")
  endif()
  set(accepted)
  set(changed)
  foreach(case source-endpoint-junction source-ancestor checkout-link archive-endpoint-junction archive-existing output-ancestor caller-dist)
    set(candidate "${work}/${case}")
    file(MAKE_DIRECTORY "${candidate}")
    file(COPY "${checkout}/" DESTINATION "${candidate}")
    set(outside "${work}/outside-${case}")
    file(MAKE_DIRECTORY "${outside}")
    file(WRITE "${outside}/sentinel" "OUTSIDE-SENTINEL\n")
    set(invocation_root "${candidate}")
    set(extra)
    set(junction "")
    if(case STREQUAL "source-endpoint-junction")
      file(REMOVE "${candidate}/audio.c")
      set(junction "${candidate}/audio.c")
      execute_process(COMMAND C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -NonInteractive -Command
        "New-Item -ItemType Junction -Path '${junction}' -Target '${outside}' -ErrorAction Stop | Out-Null"
        RESULT_VARIABLE setup)
    elseif(case STREQUAL "source-ancestor")
      file(RENAME "${candidate}/examples" "${candidate}/original-examples")
      set(junction "${candidate}/examples")
      execute_process(COMMAND C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -NonInteractive -Command
        "New-Item -ItemType Junction -Path '${candidate}/examples' -Target '${candidate}/original-examples' -ErrorAction Stop | Out-Null"
        RESULT_VARIABLE setup)
    elseif(case STREQUAL "checkout-link")
      set(invocation_root "${work}/checkout-alias")
      set(junction "${invocation_root}")
      execute_process(COMMAND C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -NonInteractive -Command
        "New-Item -ItemType Junction -Path '${invocation_root}' -Target '${candidate}' -ErrorAction Stop | Out-Null"
        RESULT_VARIABLE setup)
    elseif(case STREQUAL "archive-endpoint-junction")
      set(junction "${candidate}/pure-audio-0.6.tar.gz")
      execute_process(COMMAND C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -NonInteractive -Command
        "New-Item -ItemType Junction -Path '${junction}' -Target '${outside}' -ErrorAction Stop | Out-Null"
        RESULT_VARIABLE setup)
    elseif(case STREQUAL "output-ancestor")
      file(MAKE_DIRECTORY "${outside}/deep")
      set(junction "${work}/output-alias")
      execute_process(COMMAND C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -NonInteractive -Command
        "New-Item -ItemType Junction -Path '${junction}' -Target '${outside}' -ErrorAction Stop | Out-Null"
        RESULT_VARIABLE setup)
      set(extra "DIST_OUTPUT_DIRECTORY=${junction}/deep")
    elseif(case STREQUAL "archive-existing")
      file(WRITE "${candidate}/pure-audio-0.6.tar.gz" "EXISTING-ARCHIVE\n")
      set(setup 0)
    else()
      # Both the destructive legacy target and its archive resolve beneath
      # this native-owned leaf, never to the workspace or a user directory.
      set(extra "dist=../outside-${case}")
      set(setup 0)
    endif()
    if(NOT setup EQUAL 0)
      message(FATAL_ERROR "Cannot construct actual ${case} mutation")
    endif()
    if(NOT junction STREQUAL "")
      execute_process(COMMAND C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -NonInteractive -Command
        "if(-not ((Get-Item -LiteralPath '${junction}' -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'fixture is not an actual reparse point' }"
        RESULT_VARIABLE setup)
      if(NOT setup EQUAL 0)
        message(FATAL_ERROR "Mutation ${case} lacks a real reparse attribute")
      endif()
    endif()
    execute_process(COMMAND "${CLANG64_PREFIX}/bin/mingw32-make.exe"
      "SHELL=${CLANG64_PREFIX}/../usr/bin/sh.exe" "DLL=.dll"
      "DIST_CMAKE=${CMAKE_COMMAND}" "DIST_TAR=${CLANG64_PREFIX}/../usr/bin/tar.exe" ${extra} dist
      WORKING_DIRECTORY "${invocation_root}" RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error TIMEOUT 90)
    file(WRITE "${work}/${case}.log" "${output}${error}")
    if(result EQUAL 0)
      list(APPEND accepted "${case}")
    endif()
    if(NOT EXISTS "${outside}/sentinel")
      list(APPEND changed "${case}")
    else()
      file(READ "${outside}/sentinel" sentinel)
      file(GLOB_RECURSE outside_files LIST_DIRECTORIES FALSE "${outside}/*")
      list(LENGTH outside_files outside_count)
      if(NOT sentinel STREQUAL "OUTSIDE-SENTINEL\n" OR NOT outside_count EQUAL 1)
        list(APPEND changed "${case}")
      endif()
    endif()
    if(case STREQUAL "archive-existing")
      file(READ "${candidate}/pure-audio-0.6.tar.gz" previous)
      if(NOT previous STREQUAL "EXISTING-ARCHIVE\n")
        list(APPEND changed "${case}")
      endif()
    endif()
    if(NOT junction STREQUAL "" AND IS_SYMLINK "${junction}")
      execute_process(COMMAND C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -NonInteractive -Command
        "[IO.Directory]::Delete('${junction}')" RESULT_VARIABLE cleanup)
      if(NOT cleanup EQUAL 0)
        message(FATAL_ERROR "Cannot unlink exact owned fixture junction")
      endif()
    endif()
  endforeach()
  if(accepted OR changed)
    message(FATAL_ERROR "Real make dist accepted unsafe inputs: ${accepted}; changed outside/pre-existing bytes: ${changed} (${work})")
  endif()
  message(STATUS "SOURCE_DIST_PATHS_OK negatives=7 outside_unchanged=7 evidence=${work}")
  return()
endif()
execute_process(COMMAND "${CMAKE_COMMAND}" "-DSOURCE_DIR=${SOURCE_DIR}" "-DMODULE_DIR=${MODULE_DIR}"
  "-DCLANG64_PREFIX=${CLANG64_PREFIX}" "-DPURE_PREFIX=${PURE_PREFIX}" "-DRUNNER=${RUNNER}"
  -DPATH_RED_ONLY=ON -P "${SOURCE_DIR}/tests/source_dist_contract.cmake"
  RESULT_VARIABLE paths_rc OUTPUT_VARIABLE paths_out ERROR_VARIABLE paths_err)
if(NOT paths_rc EQUAL 0)
  message(FATAL_ERROR "Source path mutation matrix failed: ${paths_out}${paths_err}")
endif()
message(STATUS "${paths_out}")
foreach(target diffs deb distcheck)
  foreach(variant unsupported caller)
    set(extra)
    if(variant STREQUAL "caller")
      set(extra "dist=../outside-workflow")
    endif()
    file(MAKE_DIRECTORY "${work}/outside-workflow" "${checkout}/xxx" "${checkout}/yyy")
    foreach(dir "${work}/outside-workflow" "${checkout}/xxx" "${checkout}/yyy")
      file(WRITE "${dir}/sentinel" "WORKFLOW-SENTINEL\n")
    endforeach()
    execute_process(COMMAND "${CLANG64_PREFIX}/bin/mingw32-make.exe"
      "SHELL=${CLANG64_PREFIX}/../usr/bin/sh.exe" "DIST_CMAKE=${CMAKE_COMMAND}" "DIST_AUDIT_BUILD=" ${extra} "${target}"
      WORKING_DIRECTORY "${checkout}" RESULT_VARIABLE target_rc OUTPUT_VARIABLE target_out ERROR_VARIABLE target_err)
    if(target_rc EQUAL 0 OR NOT "${target_out}${target_err}" MATCHES "requires the literal|requires the POSIX|requires DIST_AUDIT_BUILD")
      message(FATAL_ERROR "Direct ${target}/${variant} did not fail with actionable preflight: ${target_out}${target_err}")
    endif()
    foreach(dir "${work}/outside-workflow" "${checkout}/xxx" "${checkout}/yyy")
      file(READ "${dir}/sentinel" sentinel)
      if(NOT sentinel STREQUAL "WORKFLOW-SENTINEL\n")
        message(FATAL_ERROR "Legacy package target changed pre-existing outside bytes")
      endif()
    endforeach()
  endforeach()
endforeach()
message(STATUS "SOURCE_DIST_TARGETS_OK negatives=6 outside_unchanged=6")
# Non-production CMake seam: import only the actual platform-neutral function
# declarations, then exercise their behavior with independent arguments. This
# is not a claim that a native POSIX toolchain ran on this Windows host.
file(READ "${SOURCE_DIR}/cmake/SourceWorkflow.cmake" workflow)
set(declarations "cmake_minimum_required(VERSION 3.25)\n")
foreach(name source_workflow_debuild_flags source_workflow_validate_leaf)
  string(FIND "${workflow}" "function(${name} " begin)
  if(begin LESS 0)
    message(FATAL_ERROR "Actual source workflow helper ${name} missing")
  endif()
  string(SUBSTRING "${workflow}" ${begin} -1 tail)
  string(FIND "${tail}" "endfunction()" end)
  if(end LESS 0)
    message(FATAL_ERROR "Incomplete source workflow helper")
  endif()
  math(EXPR length "${end}+13")
  string(SUBSTRING "${tail}" 0 ${length} declaration)
  string(APPEND declarations "${declaration}\n")
endforeach()
file(WRITE "${work}/workflow-functions.cmake" "${declarations}")
set(literal_root "${work}/literal[owner]+")
file(MAKE_DIRECTORY "${literal_root}/run-Ab12")
file(WRITE "${work}/workflow-parent.cmake"
  "include([==[${work}/workflow-functions.cmake]==])\nsource_workflow_validate_leaf([==[${literal_root}]==] \"\${LEAF}\")\n")
foreach(case valid foreign invalid-name)
  if(case STREQUAL "valid")
    set(leaf "${literal_root}/run-Ab12")
  elseif(case STREQUAL "foreign")
    set(leaf "${work}/literalowner/run-Ab12")
  else()
    set(leaf "${literal_root}/not-owned")
  endif()
  execute_process(COMMAND "${CMAKE_COMMAND}" "-DLEAF=${leaf}" -P "${work}/workflow-parent.cmake"
    RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
  if(case STREQUAL "valid")
    if(NOT rc EQUAL 0)
      message(FATAL_ERROR "Literal metacharacter parent rejected: ${out}${err}")
    endif()
  elseif(rc EQUAL 0 OR NOT err MATCHES "wrong literal parent/name")
    message(FATAL_ERROR "Foreign/invalid workflow leaf was not rejected: ${out}${err}")
  endif()
endforeach()
file(WRITE "${work}/workflow-flags.cmake"
  "include([==[${work}/workflow-functions.cmake]==])\nsource_workflow_debuild_flags(actual)\nif(NOT actual STREQUAL [==[-us;-uc;--build-option=two words]==])\nmessage(FATAL_ERROR \"DEBUILD_FLAGS were lost or split incorrectly: \${actual}\")\nendif()\n")
file(WRITE "${work}/workflow-flags.mk"
  ".PHONY: source-workflow-flags\nsource-workflow-flags:\n\t\"${CMAKE_COMMAND}\" -P \"${work}/workflow-flags.cmake\"\n")
execute_process(COMMAND "${CLANG64_PREFIX}/bin/mingw32-make.exe" -f Makefile -f "${work}/workflow-flags.mk"
  "SHELL=${CLANG64_PREFIX}/../usr/bin/sh.exe" "DLL=.dll"
  "DEBUILD_FLAGS=-us -uc \"--build-option=two words\"" source-workflow-flags
  WORKING_DIRECTORY "${checkout}" RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "Real Make DEBUILD_FLAGS transport failed: ${out}${err}")
endif()
message(STATUS "SOURCE_DIST_WORKFLOW_COMPAT_OK negatives=2 controls=2 native_posix=unavailable")
execute_process(COMMAND "${CLANG64_PREFIX}/bin/mingw32-make.exe"
  "SHELL=${CLANG64_PREFIX}/../usr/bin/sh.exe" "DLL=.dll"
  "DIST_CMAKE=${CMAKE_COMMAND}" dist
  WORKING_DIRECTORY "${checkout}" RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 90)
file(WRITE "${work}/make-dist.log" "${out}${err}")
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "Real make dist failed (${work}): ${rc}\n${out}${err}")
endif()
set(archive "${checkout}/pure-audio-0.6.tar.gz")
set(ps C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe)
set(test_tools "${SOURCE_DIR}/tests/source_dist_tools.ps1")
set(source_tools "${SOURCE_DIR}/cmake/SourceArchiveTools.ps1")
execute_process(COMMAND "${ps}" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${test_tools}"
  -Mode VerifyArchive -Directory "${extracted}" -Archive "${archive}"
  -Snapshot "${work}/expected-source-sha256.tsv" -SourceTools "${source_tools}"
  RESULT_VARIABLE verify_rc OUTPUT_VARIABLE verify_out ERROR_VARIABLE verify_err)
if(NOT verify_rc EQUAL 0)
  message(FATAL_ERROR "Independent archive validation failed: ${verify_out}${verify_err}")
endif()
message(STATUS "${verify_out}")
foreach(case endpoint ancestor)
  set(junction "${work}/verify-${case}-junction")
  if(case STREQUAL "endpoint")
    set(candidate "${junction}")
  else()
    set(candidate "${junction}/pure-audio-0.6.tar.gz")
  endif()
  execute_process(COMMAND "${ps}" -NoProfile -NonInteractive -Command
    "New-Item -ItemType Junction -Path '${junction}' -Target '${checkout}' -ErrorAction Stop | Out-Null; if(-not ((Get-Item -LiteralPath '${junction}' -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid junction fixture' }"
    RESULT_VARIABLE setup)
  if(NOT setup EQUAL 0)
    message(FATAL_ERROR "Cannot create archive verifier junction fixture")
  endif()
  execute_process(COMMAND "${ps}" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${test_tools}"
    -Mode VerifyArchive -Directory "${extracted}" -Archive "${candidate}"
    -Snapshot "${work}/expected-source-sha256.tsv" -SourceTools "${source_tools}"
    RESULT_VARIABLE rejected OUTPUT_VARIABLE out ERROR_VARIABLE err)
  execute_process(COMMAND "${ps}" -NoProfile -NonInteractive -Command "[IO.Directory]::Delete('${junction}')" RESULT_VARIABLE cleanup)
  if(NOT cleanup EQUAL 0 OR rejected EQUAL 0 OR NOT "${out}${err}" MATCHES "Expected regular archive input|Archive reparse component")
    message(FATAL_ERROR "Archive verifier did not reject actual ${case} junction: ${out}${err}")
  endif()
endforeach()
message(STATUS "SOURCE_DIST_ARCHIVE_PATHS_OK negatives=2")
execute_process(COMMAND "${CLANG64_PREFIX}/../usr/bin/tar.exe" --force-local -tvzf "${archive}"
  RESULT_VARIABLE metadata_rc OUTPUT_VARIABLE metadata ERROR_VARIABLE metadata_error)
if(NOT metadata_rc EQUAL 0 OR NOT metadata MATCHES "-rwxr-xr-x [^\n]*pure-audio-0.6/debian/rules")
  message(FATAL_ERROR "Archive lost executable debian/rules: ${metadata_error}\n${metadata}")
endif()
file(ARCHIVE_EXTRACT INPUT "${archive}" DESTINATION "${extracted}")
set(source "${extracted}/pure-audio-0.6")
file(GLOB_RECURSE actual LIST_DIRECTORIES FALSE RELATIVE "${source}" "${source}/*")
list(SORT actual)
if(NOT actual STREQUAL expected_files)
  set(missing ${expected_files})
  set(extra ${actual})
  list(REMOVE_ITEM missing ${actual})
  list(REMOVE_ITEM extra ${expected_files})
  message(FATAL_ERROR "Real archive differs from independent exact manifest (${work})\nmissing: ${missing}\nextra: ${extra}")
endif()
foreach(row IN LISTS expected_rows)
  string(REPLACE "|" ";" fields "${row}")
  list(GET fields 0 path)
  list(GET fields 1 expected)
  file(SHA256 "${source}/${path}" actual)
  if(NOT actual STREQUAL expected)
    message(FATAL_ERROR "Extracted source hash differs: ${path} (${work})")
  endif()
endforeach()
list(LENGTH expected_files count)
message(STATUS "SOURCE_DIST_ARCHIVE_OK files=${count} hashes=${count} pristine=1 evidence=${work}")
foreach(mode Attributes ScannerSelfTest BuildSelfTest)
  if(mode STREQUAL "BuildSelfTest")
    set(test_directory "${MODULE_DIR}")
  else()
    set(test_directory "${work}")
  endif()
  execute_process(COMMAND "${ps}" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${test_tools}"
    -Mode "${mode}" -Directory "${test_directory}" -Work "${work}" -SourceTools "${source_tools}"
    RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
  if(NOT rc EQUAL 0)
    message(FATAL_ERROR "${mode}: ${out}${err}")
  endif()
  message(STATUS "${out}")
endforeach()
foreach(case extra omitted hash)
  set(output_dir "${work}/archive-${case}")
  file(MAKE_DIRECTORY "${output_dir}")
  set(mutated_names ${expected_files})
  if(case STREQUAL "extra")
    file(WRITE "${checkout}/unexpected-input.txt" "undeclared\n")
    list(APPEND mutated_names unexpected-input.txt)
  elseif(case STREQUAL "omitted")
    list(REMOVE_ITEM mutated_names tests/audio_fault_harness.c)
  else()
    file(APPEND "${checkout}/audio.c" "\n/* mutation */\n")
  endif()
  list(JOIN mutated_names " " manifest)
  execute_process(COMMAND "${CMAKE_COMMAND}" "-DDIST_SOURCE_ROOT=${checkout}"
    "-DDIST_OUTPUT_DIRECTORY=${output_dir}" -DDIST_ARCHIVE_BASENAME=pure-audio-0.6
    "-DDIST_FILES=${manifest}" "-DDIST_TAR=${CLANG64_PREFIX}/../usr/bin/tar.exe"
    -P "${checkout}/cmake/CreateSourceArchive.cmake" RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
  if(NOT rc EQUAL 0)
    message(FATAL_ERROR "Cannot create actual ${case} archive: ${out}${err}")
  endif()
  execute_process(COMMAND "${ps}" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${test_tools}"
    -Mode VerifyArchive -Directory "${extracted}" -Archive "${output_dir}/pure-audio-0.6.tar.gz"
    -Snapshot "${work}/expected-source-sha256.tsv" -SourceTools "${source_tools}"
    RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
  file(WRITE "${work}/archive-${case}.log" "${out}${err}")
  if(rc EQUAL 0 OR NOT "${out}${err}" MATCHES "Unexpected/duplicate archive input|Omitted archive input|Archive hash mismatch")
    message(FATAL_ERROR "Actual ${case} archive was not rejected for its content: ${out}${err}")
  endif()
endforeach()
file(COPY_FILE "${SOURCE_DIR}/audio.c" "${checkout}/audio.c")
file(RENAME "${checkout}/audio_test_api.h" "${checkout}/saved-api.h")
file(MAKE_DIRECTORY "${work}/missing-source")
execute_process(COMMAND "${CLANG64_PREFIX}/bin/mingw32-make.exe"
  "SHELL=${CLANG64_PREFIX}/../usr/bin/sh.exe" "DIST_CMAKE=${CMAKE_COMMAND}"
  "DIST_OUTPUT_DIRECTORY=${work}/missing-source" dist WORKING_DIRECTORY "${checkout}"
  RESULT_VARIABLE rejected OUTPUT_VARIABLE out ERROR_VARIABLE err)
file(RENAME "${checkout}/saved-api.h" "${checkout}/audio_test_api.h")
if(rejected EQUAL 0 OR EXISTS "${work}/missing-source/pure-audio-0.6.tar.gz" OR NOT "${out}${err}" MATCHES "Archive preflight failed")
  message(FATAL_ERROR "Public archive producer accepted an omitted source input")
endif()
message(STATUS "SOURCE_DIST_MISSING_SOURCE_OK negatives=1 unpublished=1")
file(MAKE_DIRECTORY "${work}/repeat")
execute_process(COMMAND "${CLANG64_PREFIX}/bin/mingw32-make.exe"
  "SHELL=${CLANG64_PREFIX}/../usr/bin/sh.exe" "DIST_CMAKE=${CMAKE_COMMAND}"
  "DIST_OUTPUT_DIRECTORY=${work}/repeat" dist WORKING_DIRECTORY "${checkout}"
  RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "Repeat archive failed: ${out}${err}")
endif()
file(SHA256 "${archive}" first_hash)
file(SHA256 "${work}/repeat/pure-audio-0.6.tar.gz" second_hash)
if(NOT first_hash STREQUAL second_hash)
  message(FATAL_ERROR "Archive is not byte-deterministic")
endif()
message(STATUS "SOURCE_DIST_MUTATIONS_OK archive_negative=3 scanner_negative=4 reparse_seam_negative=1 deterministic=1 sha256=${first_hash}")
# Invoke the public target with hostile ambient tool options in a child-only
# environment. The archive must be identical and every declared source must
# retain its exact bytes, even if tar would normally honor --remove-files.
file(MAKE_DIRECTORY "${work}/poisoned-archive")
execute_process(COMMAND "${CMAKE_COMMAND}" -E env
  "TAR_OPTIONS=--remove-files" "GZIP=--definitely-invalid-audio-option"
  "${CLANG64_PREFIX}/bin/mingw32-make.exe"
  "SHELL=${CLANG64_PREFIX}/../usr/bin/sh.exe" "DIST_CMAKE=${CMAKE_COMMAND}"
  "DIST_OUTPUT_DIRECTORY=${work}/poisoned-archive" dist WORKING_DIRECTORY "${checkout}"
  RESULT_VARIABLE poison_rc OUTPUT_VARIABLE poison_out ERROR_VARIABLE poison_err)
file(WRITE "${work}/poisoned-archive.log" "${poison_out}${poison_err}")
foreach(row IN LISTS expected_rows)
  string(REPLACE "|" ";" fields "${row}")
  list(GET fields 0 path)
  list(GET fields 1 expected)
  if(NOT EXISTS "${checkout}/${path}" OR IS_DIRECTORY "${checkout}/${path}")
    message(FATAL_ERROR "Ambient archive options removed a declared source: ${path} (${work})")
  endif()
  file(SHA256 "${checkout}/${path}" actual)
  if(NOT actual STREQUAL expected)
    message(FATAL_ERROR "Ambient archive options changed source bytes: ${path} (${work})")
  endif()
endforeach()
if(NOT poison_rc EQUAL 0)
  message(FATAL_ERROR "Public archive inherited ambient options: ${poison_out}${poison_err}")
endif()
file(SHA256 "${work}/poisoned-archive/pure-audio-0.6.tar.gz" poison_hash)
if(NOT poison_hash STREQUAL first_hash)
  message(FATAL_ERROR "Ambient archive options changed the exact archive hash")
endif()
message(STATUS "SOURCE_DIST_ENVIRONMENT_OK negatives=1 source_hashes_unchanged=${count} exact_archive_hash=1")
# A GNU-identifying tool without the required capability must be rejected
# before reservation/creation. This executable test double models that boundary
# only; actual archive payload checks below always use the real GNU tools.
set(capability_tools "${work}/unsupported archive tool")
set(capability_output "${work}/unsupported-capability-output")
file(MAKE_DIRECTORY "${capability_tools}" "${capability_output}")
file(COPY_FILE "${CLANG64_PREFIX}/../usr/bin/gzip.exe" "${capability_tools}/gzip.exe")
file(WRITE "${capability_tools}/tar.cmd" [==[@echo off
if "%~1"=="--version" goto version
if "%~1"=="--help" goto help
> "%~dp0unexpected-archive-invocation" echo archive-command
exit /b 23
:version
echo tar ^(GNU tar^) 1.35
exit /b 0
:help
echo No declared hardlink capability
exit /b 0
]==])
execute_process(COMMAND "${CLANG64_PREFIX}/bin/mingw32-make.exe"
  "SHELL=${CLANG64_PREFIX}/../usr/bin/sh.exe" "DIST_CMAKE=${CMAKE_COMMAND}"
  "DIST_TAR=${capability_tools}/tar.cmd" "DIST_OUTPUT_DIRECTORY=${capability_output}"
  dist WORKING_DIRECTORY "${checkout}" RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
file(WRITE "${work}/unsupported-capability.log" "${out}${err}")
file(GLOB capability_entries "${capability_output}/*" "${capability_output}/.*")
if(rc EQUAL 0 OR NOT "${out}${err}" MATCHES "requires GNU tar --hard-dereference capability" OR
   EXISTS "${capability_tools}/unexpected-archive-invocation" OR capability_entries)
  message(FATAL_ERROR "Missing GNU capability did not fail before archive writes: ${out}${err} (${work})")
endif()
message(STATUS "SOURCE_DIST_TAR_CAPABILITY_OK negatives=1 preflight_only=1")
# Compare identical declared bytes under two real filesystem topologies. The
# independent control uses separate files; the mutation uses a proven native
# hardlink pair, which must still become regular archive members.
set(link_source "${work}/hardlinked source")
foreach(path IN LISTS expected_files)
  get_filename_component(parent "${link_source}/${path}" DIRECTORY)
  file(MAKE_DIRECTORY "${parent}")
  file(COPY_FILE "${checkout}/${path}" "${link_source}/${path}")
endforeach()
file(COPY_FILE "${link_source}/README" "${link_source}/WINDOWS.md")
set(link_rows)
foreach(path IN LISTS expected_files)
  file(SHA256 "${link_source}/${path}" hash)
  list(APPEND link_rows "${path}|${hash}")
endforeach()
list(JOIN link_rows "\n" link_snapshot)
file(WRITE "${work}/hardlink-source-sha256.tsv" "${link_snapshot}\n")
foreach(topology independent linked)
  if(topology STREQUAL "linked")
    execute_process(COMMAND "${ps}" -NoProfile -NonInteractive -ExecutionPolicy Bypass
      -File "${test_tools}" -Mode SourceHardlink -Directory "${link_source}"
      -SourceTools "${source_tools}" -CreateLink RESULT_VARIABLE setup OUTPUT_VARIABLE out ERROR_VARIABLE err)
    if(NOT setup EQUAL 0 OR NOT out MATCHES "links=2 same_file_identity=1")
      message(FATAL_ERROR "Invalid native hardlink fixture: ${out}${err}")
    endif()
  endif()
  set(link_output "${work}/topology-${topology}")
  file(MAKE_DIRECTORY "${link_output}")
  execute_process(COMMAND "${CLANG64_PREFIX}/bin/mingw32-make.exe"
    "SHELL=${CLANG64_PREFIX}/../usr/bin/sh.exe" "DIST_CMAKE=${CMAKE_COMMAND}"
    "DIST_OUTPUT_DIRECTORY=${link_output}" dist WORKING_DIRECTORY "${link_source}"
    RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
  file(WRITE "${work}/topology-${topology}.log" "${out}${err}")
  if(NOT rc EQUAL 0)
    message(FATAL_ERROR "Public ${topology} source archive failed: ${out}${err}")
  endif()
  execute_process(COMMAND "${ps}" -NoProfile -NonInteractive -ExecutionPolicy Bypass
    -File "${test_tools}" -Mode VerifyArchive -Directory "${extracted}"
    -Archive "${link_output}/pure-audio-0.6.tar.gz" -Snapshot "${work}/hardlink-source-sha256.tsv"
    -SourceTools "${source_tools}" RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
  if(NOT rc EQUAL 0)
    message(FATAL_ERROR "Public ${topology} archive violates regular-member/hash contract: ${out}${err} (${work})")
  endif()
  foreach(row IN LISTS link_rows)
    string(REPLACE "|" ";" fields "${row}")
    list(GET fields 0 path)
    list(GET fields 1 expected)
    file(SHA256 "${link_source}/${path}" actual)
    if(NOT actual STREQUAL expected)
      message(FATAL_ERROR "Archive changed ${topology} source bytes: ${path}")
    endif()
  endforeach()
  file(SHA256 "${link_output}/pure-audio-0.6.tar.gz" ${topology}_hash)
endforeach()
if(NOT independent_hash STREQUAL linked_hash)
  message(FATAL_ERROR "Archive SHA depends on source inode topology")
endif()
execute_process(COMMAND "${ps}" -NoProfile -NonInteractive -ExecutionPolicy Bypass
  -File "${test_tools}" -Mode SourceHardlink -Directory "${link_source}"
  -SourceTools "${source_tools}" RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "Archive changed native source hardlink identity: ${out}${err}")
endif()
message(STATUS "SOURCE_DIST_HARDLINK_OK negatives=1 controls=1 regular_members=${count} source_hashes_unchanged=${count} topology_independent_sha=1")
# Integration regression against the actual driver. Only the disposable test
# copy narrows CTest to four real core tests; configure/build/PE, both component
# installs and the public installed verifier remain real. There is no flag in
# the production driver that can skip its ten mandatory tests.
set(postflight_failures)
foreach(mutation leak junction)
  set(post_work "${work}/postflight-${mutation}")
  set(post_source "${post_work}/source with spaces")
  file(MAKE_DIRECTORY "${post_work}/outside")
  file(WRITE "${post_work}/outside/sentinel" "POSTFLIGHT-OUTSIDE\n")
  foreach(path IN LISTS expected_files)
    get_filename_component(parent "${post_source}/${path}" DIRECTORY)
    file(MAKE_DIRECTORY "${parent}")
    file(COPY_FILE "${source}/${path}" "${post_source}/${path}")
  endforeach()
  file(READ "${post_source}/tests/source_dist_extracted.cmake" fixture_driver)
  set(full_filter [==[-E "^pure-audio-source-dist-contract$"]==])
  string(FIND "${fixture_driver}" "${full_filter}" filter_at)
  if(filter_at LESS 0)
    message(FATAL_ERROR "Cannot establish core-test-only integration fixture")
  endif()
  string(REPLACE "${full_filter}" [==[-R "^pure-audio-(fault-bounds|load|processing|public-bounds)$"]==]
    fixture_driver "${fixture_driver}")
  string(REPLACE "mandatory_tests=10" "core_fixture_tests=4" fixture_driver "${fixture_driver}")
  file(WRITE "${post_source}/tests/source_dist_extracted.cmake" "${fixture_driver}")
  file(APPEND "${post_source}/CMakeLists.txt" [====[

# Mutation-fixture-only configure side effect, after the driver's initial scan.
execute_process(COMMAND C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
  -NoProfile -NonInteractive -ExecutionPolicy Bypass
  -File "${CMAKE_CURRENT_SOURCE_DIR}/tests/source_dist_tools.ps1"
  -Mode GenerateSourceMutation -Directory "${CMAKE_CURRENT_SOURCE_DIR}"
  -SourceTools "${CMAKE_CURRENT_SOURCE_DIR}/cmake/SourceArchiveTools.ps1"
  -Mutation "$ENV{PURE_AUDIO_POST_SOURCE_KIND}"
  -Forbidden "$ENV{PURE_AUDIO_POST_SOURCE_FORBIDDEN}"
  -Work "$ENV{PURE_AUDIO_POST_SOURCE_OUTSIDE}"
  RESULT_VARIABLE mutation_rc OUTPUT_VARIABLE mutation_out ERROR_VARIABLE mutation_err)
if(NOT mutation_rc EQUAL 0)
  message(FATAL_ERROR "Cannot establish post-configure source fixture: ${mutation_err}")
endif()
message(STATUS "${mutation_out}")
]====])
  execute_process(COMMAND "${ps}" -NoProfile -NonInteractive -ExecutionPolicy Bypass
    -File "${test_tools}" -Mode ReserveBuild -Directory "${MODULE_DIR}"
    -Ticket "${post_work}/build.ticket" -SourceTools "${source_tools}"
    RESULT_VARIABLE rc OUTPUT_VARIABLE post_build ERROR_VARIABLE err OUTPUT_STRIP_TRAILING_WHITESPACE)
  if(NOT rc EQUAL 0)
    message(FATAL_ERROR "Cannot reserve integration build: ${err}")
  endif()
  execute_process(COMMAND "${CMAKE_COMMAND}" -E env
    "PURE_AUDIO_POST_SOURCE_KIND=${mutation}" "PURE_AUDIO_POST_SOURCE_FORBIDDEN=${SOURCE_DIR}"
    "PURE_AUDIO_POST_SOURCE_OUTSIDE=${post_work}/outside"
    "${ps}" -NoProfile -NonInteractive -ExecutionPolicy Bypass
    -File "${post_source}/tests/source_dist_tools.ps1" -Mode Isolate -Directory "${post_source}"
    -Work "${post_work}" -BuildDirectory "${post_build}" -Snapshot "${work}/expected-source-sha256.tsv"
    -Forbidden "${SOURCE_DIR}|${checkout}" -ClangPrefix "${CLANG64_PREFIX}" -PurePrefix "${PURE_PREFIX}"
    -CMake "${CMAKE_COMMAND}" RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
  file(WRITE "${post_work}/isolation.log" "${out}${err}")
  file(READ "${post_work}/isolated.stdout" child_out)
  file(READ "${post_work}/isolated.stderr" child_err)
  foreach(phase configure build pe tests install-runtime install-documentation installed-verifier)
    if(NOT child_out MATCHES "SOURCE_DIST_STEP_OK step=${phase} ")
      message(FATAL_ERROR "Postflight ${mutation} fixture failed before real ${phase}: ${child_out}${child_err}")
    endif()
  endforeach()
  file(READ "${post_work}/logs/tests.stdout" core_tests)
  file(READ "${post_work}/logs/installed-verifier.stdout" installed)
  if(NOT core_tests MATCHES "100% tests passed out of 4" OR
     NOT installed MATCHES "INSTALL_PACKAGE_OK" OR NOT installed MATCHES "PURE_AUDIO_DONE_[a-f0-9]+")
    message(FATAL_ERROR "Integration fixture did not execute real core tests/public verifier")
  endif()
  if(mutation STREQUAL "leak")
    set(expected_error "Checkout leak detected")
    file(SIZE "${post_source}/post-configure-leak.bin" leak_bytes)
    if(leak_bytes LESS 10485760)
      message(FATAL_ERROR "Post-initial-scan binary fixture does not cross the late chunk boundary")
    endif()
  else()
    set(expected_error "Leak scan refuses reparse entry")
    execute_process(COMMAND "${ps}" -NoProfile -NonInteractive -Command
      "if(-not ((Get-Item -LiteralPath '${post_source}/post-configure-junction' -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid post-configure junction' }; [IO.Directory]::Delete('${post_source}/post-configure-junction',$false)"
      RESULT_VARIABLE cleanup)
    if(NOT cleanup EQUAL 0)
      message(FATAL_ERROR "Cannot unlink the exact owned post-configure junction")
    endif()
  endif()
  file(READ "${post_work}/outside/sentinel" outside)
  if(NOT outside STREQUAL "POSTFLIGHT-OUTSIDE\n")
    message(FATAL_ERROR "Postflight fixture changed outside bytes")
  endif()
  # Prove failure teardown released both original/producer read exclusions.
  file(SHA256 "${SOURCE_DIR}/Makefile" released_source)
  file(SHA256 "${checkout}/Makefile" released_producer)
  if(rc EQUAL 0 OR NOT child_err MATCHES "${expected_error}" OR EXISTS "${post_work}/extracted-result.txt")
    list(APPEND postflight_failures "${mutation}")
  endif()
endforeach()
if(postflight_failures)
  message(FATAL_ERROR "Final extracted-source gate accepted post-configure mutations: ${postflight_failures} (${work})")
endif()
message(STATUS "SOURCE_DIST_POSTFLIGHT_OK negatives=2 real_core_tests=4 real_phases=7 late_binary=1 junction=1 released_roots=2")
if(FOCUSED_ONLY)
  return()
endif()
execute_process(COMMAND "${ps}" -NoProfile -NonInteractive -ExecutionPolicy Bypass
  -File "${test_tools}" -Mode ReserveBuild -Directory "${MODULE_DIR}" -Ticket "${work}/build.ticket"
  -SourceTools "${source_tools}" RESULT_VARIABLE rc OUTPUT_VARIABLE isolated_build ERROR_VARIABLE err
  OUTPUT_STRIP_TRAILING_WHITESPACE)
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "Cannot reserve short owned extracted build: ${err}")
endif()
execute_process(COMMAND "${ps}" -NoProfile -NonInteractive -ExecutionPolicy Bypass
  -File "${source}/tests/source_dist_tools.ps1" -Mode Isolate -Directory "${source}"
  -Work "${work}" -BuildDirectory "${isolated_build}" -Snapshot "${work}/expected-source-sha256.tsv"
  -Forbidden "${SOURCE_DIR}|${checkout}" -ClangPrefix "${CLANG64_PREFIX}" -PurePrefix "${PURE_PREFIX}"
  -CMake "${CMAKE_COMMAND}" RESULT_VARIABLE rc)
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "Extracted-source isolated contract failed: ${work}")
endif()
file(READ "${work}/extracted-result.txt" result)
message(STATUS "${result}")
