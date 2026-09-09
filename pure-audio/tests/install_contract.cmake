cmake_minimum_required(VERSION 3.25)

# Independent fixture paths and tree hashes; never derive expected ownership
# from the install producer or verifier under test.
foreach(required SOURCE_DIR MODULE_DIR CLANG64_PREFIX PURE_PREFIX RUNNER)
  if(NOT DEFINED ${required})
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()
set(PURE_AUDIO_RUNNER "${RUNNER}")
set(PURE_AUDIO_RUNNER_HELPERS_ONLY ON)
include("${SOURCE_DIR}/cmake/RunPureTest.cmake")
pure_audio_create_leaf(work)
function(fixture_tree root output)
  file(GLOB_RECURSE files LIST_DIRECTORIES FALSE RELATIVE "${root}" "${root}/*")
  list(SORT files)
  set(rows)
  foreach(path IN LISTS files)
    file(SHA256 "${root}/${path}" hash)
    list(APPEND rows "${path}|${hash}")
  endforeach()
  set(${output} "${rows}" PARENT_SCOPE)
endfunction()
set(stage "${work}/collision")
file(COPY "${PURE_PREFIX}/" DESTINATION "${stage}")
file(WRITE "${stage}/lib/pure/audio.pure" "DO NOT OVERWRITE THIS BASELINE\n")
fixture_tree("${stage}" before)
execute_process(COMMAND "${CMAKE_COMMAND}" --install "${MODULE_DIR}"
  --prefix "${stage}" --component runtime
  RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 90)
fixture_tree("${stage}" after)
file(WRITE "${work}/collision.log" "${out}\n${err}")
if(rc EQUAL 0 OR NOT before STREQUAL after)
  message(FATAL_ERROR "RED: install accepted a non-identical collision or partially wrote the prefix (${work})")
endif()
if(RED_ONLY)
  pure_audio_cleanup_leaf("${work}")
  return()
endif()

set(negative 1)
set(positive 0)
set(context "${MODULE_DIR}/windows-install-context.cmake")
set(verifier "${SOURCE_DIR}/cmake/VerifyInstalledPackage.cmake")
# A redirected context must be rejected before its executable CMake payload
# runs. The marker is fixture-owned and is the independent behavioral oracle.
file(READ "${context}" context_text)
file(WRITE "${work}/context-target/context.cmake"
  "file(WRITE [==[${work}/context-executed]==] UNEXPECTED)\n${context_text}")
execute_process(COMMAND C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
  -NoProfile -NonInteractive -Command
  "$ErrorActionPreference='Stop'; New-Item -ItemType Junction -Path '${work}/context-link' -Target '${work}/context-target' | Out-Null"
  RESULT_VARIABLE rc ERROR_VARIABLE err)
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "Cannot create context junction: ${err}")
endif()
execute_process(COMMAND "${CMAKE_COMMAND}" "-DAUDIO_INSTALL_CONTEXT=${work}/context-link/context.cmake"
  -DAUDIO_INSTALL_MODE=seal -P "${verifier}"
  RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 30)
file(WRITE "${work}/redirected-context.log" "${out}${err}")
execute_process(COMMAND C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
  -NoProfile -NonInteractive -Command
  "$ErrorActionPreference='Stop'; $i=Get-Item -LiteralPath '${work}/context-link' -Force; if(($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { throw 'not a junction' }; [IO.Directory]::Delete('${work}/context-link')"
  RESULT_VARIABLE cleanup_rc)
if(rc EQUAL 0 OR EXISTS "${work}/context-executed" OR NOT cleanup_rc EQUAL 0)
  message(FATAL_ERROR "RED: redirected context executed before reparse rejection (${work})")
endif()
math(EXPR negative "${negative}+1")
if(CONTEXT_RED_ONLY)
  pure_audio_cleanup_leaf("${work}")
  return()
endif()
# Strict fixed layout must not narrow ordinary upstream relative paths.
set(saved_msystem "$ENV{MSYSTEM_PREFIX}")
set(saved_pkgconfig "$ENV{PKG_CONFIG_PATH}")
set(ENV{MSYSTEM_PREFIX} "${CLANG64_PREFIX}")
set(ENV{PKG_CONFIG_PATH} "${PURE_PREFIX}/lib/pkgconfig;${CLANG64_PREFIX}/lib/pkgconfig")
execute_process(COMMAND "${CMAKE_COMMAND}" -S "${SOURCE_DIR}" -B "${work}/normal-configure"
  -G Ninja "-DCMAKE_C_COMPILER=${CLANG64_PREFIX}/bin/clang.exe"
  "-DCMAKE_MAKE_PROGRAM=${CLANG64_PREFIX}/bin/ninja.exe"
  "-DPKG_CONFIG_EXECUTABLE=${CLANG64_PREFIX}/bin/pkgconf.exe"
  "-DPURE_DOCUMENTATION_INSTALL_DIR=share/doc/audio docs"
  RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 60)
set(ENV{MSYSTEM_PREFIX} "${saved_msystem}")
set(ENV{PKG_CONFIG_PATH} "${saved_pkgconfig}")
file(WRITE "${work}/normal-configure.log" "${out}${err}")
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "Non-strict relative path compatibility failed: ${out}${err}")
endif()
set(runtime_names
  lib/pure/audio.dll lib/pure/fftw.dll lib/pure/srcprocess.dll
  lib/pure/sfinfo.dll lib/pure/realtime.dll lib/pure/audio.pure
  lib/pure/portaudio.pure lib/pure/fftw.pure lib/pure/samplerate.pure
  lib/pure/sndfile.pure lib/pure/realtime.pure
  bin/libportaudio.dll bin/libfftw3-3.dll bin/libsamplerate-0.dll
  bin/libsndfile-1.dll bin/libogg-0.dll bin/libvorbisenc-2.dll
  bin/libFLAC.dll bin/libopus-0.dll bin/libmpg123-0.dll
  bin/libmp3lame-0.dll bin/libvorbis-0.dll)
set(doc_names README COPYING WINDOWS.md THIRD_PARTY.md
  examples/audio_examp.pure examples/audio_test.pd
  tests/load.pure tests/smoke.pure tests/hardware.pure
  tests/hardware-playback.pure tests/hardware-capture.pure
  licenses/PortAudio.txt licenses/FFTW-COPYING.txt licenses/FFTW-COPYRIGHT.txt
  licenses/libsamplerate.txt licenses/libsndfile.txt licenses/libogg.txt
  licenses/Vorbis-COPYING.txt licenses/FLAC-Xiph.txt licenses/Opus.txt
  licenses/mpg123.txt licenses/LAME-COPYING.txt licenses/winpthreads.txt
  licenses/libcxx.txt licenses/origins.tsv)
list(TRANSFORM doc_names PREPEND "share/doc/pure-audio/")
list(SORT runtime_names)
list(SORT doc_names)
set(all_names ${runtime_names} ${doc_names})
list(SORT all_names)

function(run_verifier name expected pattern)
  execute_process(COMMAND "${CMAKE_COMMAND}" "-DAUDIO_INSTALL_CONTEXT=${context}"
    "-DSTAGE_PREFIX=${stage}" -P "${verifier}"
    RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 150)
  file(WRITE "${work}/${name}.log" "${out}\n${err}")
  string(REGEX REPLACE "[ \t\r\n]+" " " diagnostic "${out}${err}")
  if((expected STREQUAL "pass" AND NOT rc EQUAL 0) OR
      (expected STREQUAL "fail" AND rc EQUAL 0) OR
      NOT diagnostic MATCHES "${pattern}")
    message(FATAL_ERROR "${name}: expected ${expected}/${pattern}, got ${rc}\n${out}${err}\nEvidence: ${work}")
  endif()
  if(expected STREQUAL "fail")
    math(EXPR negative "${negative}+1")
    set(negative "${negative}" PARENT_SCOPE)
  else()
    math(EXPR positive "${positive}+1")
    set(positive "${positive}" PARENT_SCOPE)
  endif()
endfunction()
function(install_component component)
  execute_process(COMMAND "${CMAKE_COMMAND}" --install "${MODULE_DIR}"
    --prefix "${stage}" --component "${component}"
    RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 90)
  if(NOT rc EQUAL 0)
    message(FATAL_ERROR "${component} install failed\n${out}${err}\nEvidence: ${work}")
  endif()
  file(STRINGS "${MODULE_DIR}/install_manifest_${component}.txt" manifest)
  set(expected)
  if(component STREQUAL "runtime")
    set(names "${runtime_names}")
  else()
    set(names "${doc_names}")
  endif()
  foreach(name IN LISTS names)
    if(NOT name IN_LIST preseeded)
      list(APPEND expected "${stage}/${name}")
    endif()
  endforeach()
  list(SORT manifest)
  if(NOT manifest STREQUAL expected)
    message(FATAL_ERROR "Independent ${component} manifest mismatch")
  endif()
endfunction()
function(collision name destination directory)
  set(stage "${work}/${name}")
  file(COPY "${PURE_PREFIX}/" DESTINATION "${stage}")
  if(directory)
    file(MAKE_DIRECTORY "${stage}/${destination}")
  else()
    file(WRITE "${stage}/${destination}" "CONFLICT\n")
  endif()
  fixture_tree("${stage}" before)
  execute_process(COMMAND "${CMAKE_COMMAND}" --install "${MODULE_DIR}"
    --prefix "${stage}" --component runtime
    RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 90)
  fixture_tree("${stage}" after)
  file(WRITE "${work}/${name}.log" "${out}${err}")
  if(rc EQUAL 0 OR NOT before STREQUAL after OR NOT "${out}${err}" MATCHES "collision|ancestor")
    message(FATAL_ERROR "${name}: collision did not fail before any prefix write (${work})\n${out}${err}")
  endif()
  math(EXPR negative "${negative}+1")
  set(negative "${negative}" PARENT_SCOPE)
endfunction()
collision(module-collision lib/pure/audio.dll FALSE)
collision(late-license-collision share/doc/pure-audio/licenses/LAME-COPYING.txt FALSE)
collision(directory-collision lib/pure/audio.dll TRUE)
collision(ancestor-collision share/doc/pure-audio FALSE)

foreach(kind endpoint ancestor root)
  set(real_stage "${work}/reparse-${kind}-real")
  file(COPY "${PURE_PREFIX}/" DESTINATION "${real_stage}")
  file(MAKE_DIRECTORY "${work}/reparse-${kind}-target")
  set(stage "${real_stage}")
  if(kind STREQUAL "endpoint")
    set(link "${stage}/lib/pure/audio.dll")
    set(target "${work}/reparse-${kind}-target")
  elseif(kind STREQUAL "ancestor")
    file(MAKE_DIRECTORY "${stage}/share/doc")
    set(link "${stage}/share/doc/pure-audio")
    set(target "${work}/reparse-${kind}-target")
  else()
    set(link "${work}/reparse-root-link")
    set(target "${real_stage}")
    set(stage "${link}")
  endif()
  fixture_tree("${real_stage}" before)
  execute_process(COMMAND C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
    -NoProfile -NonInteractive -Command
    "$ErrorActionPreference='Stop'; New-Item -ItemType Junction -Path '${link}' -Target '${target}' | Out-Null"
    RESULT_VARIABLE rc ERROR_VARIABLE err)
  if(NOT rc EQUAL 0)
    message(FATAL_ERROR "Cannot create reparse fixture: ${err}")
  endif()
  execute_process(COMMAND "${CMAKE_COMMAND}" --install "${MODULE_DIR}"
    --prefix "${stage}" --component runtime
    RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 90)
  file(WRITE "${work}/reparse-${kind}.log" "${out}${err}")
  # Delete only the verified junction object, never recurse through its target.
  execute_process(COMMAND C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
    -NoProfile -NonInteractive -Command
    "$ErrorActionPreference='Stop'; $i=Get-Item -LiteralPath '${link}' -Force; if(($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { throw 'not a junction' }; [IO.Directory]::Delete('${link}')"
    RESULT_VARIABLE cleanup_rc ERROR_VARIABLE cleanup_err)
  fixture_tree("${real_stage}" after)
  if(rc EQUAL 0 OR NOT before STREQUAL after OR NOT cleanup_rc EQUAL 0 OR
      NOT "${out}${err}" MATCHES "reparse|redirected")
    message(FATAL_ERROR "Reparse ${kind} contract failed: ${out}${err}${cleanup_err}")
  endif()
  math(EXPR negative "${negative}+1")
endforeach()

set(stage "${work}/pristine")
file(COPY "${PURE_PREFIX}/" DESTINATION "${stage}")
file(WRITE "${stage}/baseline-marker.txt" "Unrelated baseline stays byte-identical.\n")
fixture_tree("${stage}" baseline)
install_component(runtime)
install_component(documentation)
fixture_tree("${stage}" installed)
set(delta "${installed}")
foreach(row IN LISTS baseline)
  if(NOT row IN_LIST installed)
    message(FATAL_ERROR "Baseline changed")
  endif()
  list(REMOVE_ITEM delta "${row}")
endforeach()
set(actual_names)
foreach(row IN LISTS delta)
  string(REPLACE "|" ";" fields "${row}")
  list(GET fields 0 name)
  list(APPEND actual_names "${name}")
endforeach()
if(NOT actual_names STREQUAL all_names)
  message(FATAL_ERROR "Independent complete delta inventory mismatch")
endif()
run_verifier(pristine pass "INSTALL_PACKAGE_OK artifacts=47 runtime=22 documentation=25 delta=47 pe=29 license_payloads=13 mapped_dlls=13")
string(TOLOWER "${stage}" key)
string(SHA256 key "${key}")
set(session "${MODULE_DIR}/install-audits/${key}")

# One independent perturbation at a time, with byte-preserving restoration.
foreach(path IN LISTS all_names)
  file(RENAME "${stage}/${path}" "${work}/saved-file")
  string(MAKE_C_IDENTIFIER "${path}" name)
  run_verifier("missing-${name}" fail "collision|baseline plus declared delta")
  file(RENAME "${work}/saved-file" "${stage}/${path}")
endforeach()
foreach(path bin/libportaudio.dll lib/pure/audio.dll
    share/doc/pure-audio/licenses/Vorbis-COPYING.txt baseline-marker.txt
    lib/pure/prelude.pure)
  file(RENAME "${stage}/${path}" "${work}/saved-file")
  file(WRITE "${stage}/${path}" "ALTERED\n")
  string(MAKE_C_IDENTIFIER "${path}" name)
  run_verifier("altered-${name}" fail "collision|baseline|declared delta")
  file(REMOVE "${stage}/${path}")
  file(RENAME "${work}/saved-file" "${stage}/${path}")
endforeach()
file(WRITE "${stage}/unrelated/nested/extra.txt" "EXTRA\n")
run_verifier(extra-anywhere fail "baseline plus declared delta")
file(REMOVE "${stage}/unrelated/nested/extra.txt")
file(COPY_FILE "${CLANG64_PREFIX}/bin/libportaudio.dll" "${stage}/lib/pure/libportaudio.dll")
run_verifier(wrong-pe-origin fail "baseline plus declared delta")
file(REMOVE "${stage}/lib/pure/libportaudio.dll")

foreach(component runtime documentation)
  file(READ "${session}/${component}.tsv" saved)
  file(RENAME "${session}/${component}.tsv" "${session}/${component}.saved")
  run_verifier("missing-${component}-manifest" fail "missing ${component} manifest")
  file(RENAME "${session}/${component}.saved" "${session}/${component}.tsv")
  string(REGEX MATCH "^[^\n]+\n" first "${saved}")
  string(REPLACE "${first}" "" missing "${saved}")
  file(WRITE "${session}/${component}.tsv" "${missing}")
  run_verifier("missing-${component}-entry" fail "manifest missing/duplicate/cross-component")
  file(WRITE "${session}/${component}.tsv" "${first}${saved}")
  run_verifier("duplicate-${component}-entry" fail "duplicate/malformed tree manifest")
  if(component STREQUAL "runtime")
    set(other documentation)
  else()
    set(other runtime)
  endif()
  file(READ "${session}/${other}.tsv" crossed)
  file(WRITE "${session}/${component}.tsv" "${crossed}")
  run_verifier("cross-component-${component}" fail "manifest missing/duplicate/cross-component")
  file(WRITE "${session}/${component}.tsv" "${saved}")
endforeach()

# Inventories are data, so corruption must never refresh hashes or expectations.
set(inventory "${MODULE_DIR}/windows-install-inventory.tsv")
file(READ "${inventory}" saved_inventory)
string(REGEX MATCH "^[^\n]+\n" first "${saved_inventory}")
string(REPLACE "${first}" "" mutation_missing "${saved_inventory}")
set(mutation_duplicate "${first}${saved_inventory}")
string(REPLACE "runtime|" "documentation|" mutation_component "${saved_inventory}")
string(REPLACE "licenses/PortAudio.txt" "licenses/Vorbis-COPYING.txt" mutation_mapping "${saved_inventory}")
foreach(kind missing duplicate component mapping)
  file(WRITE "${inventory}" "${mutation_${kind}}")
  run_verifier("inventory-${kind}" fail "frozen artifact inventory/source mismatch")
  file(WRITE "${inventory}" "${saved_inventory}")
endforeach()

# Exercise changed source and built bytes on private copies, never modify the
# user's checkout or CLANG64 payload. The trusted context is fixture-owned.
file(READ "${context}" original_context)
foreach(spec "source|${SOURCE_DIR}/audio.pure" "build|${MODULE_DIR}/audio.dll" "license|${SOURCE_DIR}/licenses/PortAudio.txt")
  string(REPLACE "|" ";" fields "${spec}")
  list(GET fields 0 name)
  list(GET fields 1 original)
  file(COPY_FILE "${original}" "${work}/private-${name}")
  string(REPLACE "${original}" "${work}/private-${name}" private_context "${original_context}")
  string(REPLACE "${inventory}" "${work}/private-${name}.tsv" private_context "${private_context}")
  string(REPLACE "${original}" "${work}/private-${name}" private_inventory "${saved_inventory}")
  file(WRITE "${work}/private-${name}.tsv" "${private_inventory}")
  string(SHA256 private_pin "${private_inventory}")
  file(WRITE "${work}/private-${name}.tsv.sha256" "${private_pin}\n")
  file(WRITE "${work}/private-${name}.cmake" "${private_context}")
  set(context "${work}/private-${name}.cmake")
  execute_process(COMMAND "${CMAKE_COMMAND}" "-DAUDIO_INSTALL_CONTEXT=${context}"
    -DAUDIO_INSTALL_MODE=seal -P "${verifier}" RESULT_VARIABLE rc
    OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 30)
  if(NOT rc EQUAL 0)
    message(FATAL_ERROR "Private ${name} unchanged-byte control failed: ${out}${err}")
  endif()
  file(WRITE "${work}/private-${name}" "ALTERED SOURCE\n")
  run_verifier("changed-${name}" fail "configured source hash mismatch|frozen artifact inventory/source mismatch")
endforeach()
set(context "${MODULE_DIR}/windows-install-context.cmake")

# Host pollution is deliberately present: neither verifier nor native runner
# can borrow a missing installed interface or DLL from checkout/CLANG64.
set(ENV{PURE_INCLUDE} "${SOURCE_DIR}")
set(ENV{PURE_LIBRARY} "${MODULE_DIR}")
set(ENV{PURELIB} "${SOURCE_DIR}")
set(ENV{PATH} "${CLANG64_PREFIX}/bin;${PURE_PREFIX}/bin;$ENV{PATH}")
foreach(path lib/pure/audio.pure bin/libportaudio.dll)
  file(RENAME "${stage}/${path}" "${work}/saved-file")
  string(MAKE_C_IDENTIFIER "${path}" name)
  run_verifier("host-rescue-${name}" fail "baseline plus declared delta")
  execute_process(COMMAND "${CMAKE_COMMAND}"
    "-DPURE_AUDIO_RUNNER=${RUNNER}" "-DPURE_EXECUTABLE=${stage}/bin/pure.exe"
    "-DPURE_SOURCE_DIR=${stage}/lib/pure" "-DMODULE_DIR=${stage}/lib/pure"
    "-DTEST_SCRIPT=${stage}/share/doc/pure-audio/tests/smoke.pure"
    "-DRUNTIME_DIRS=${stage}/bin;C:/Windows/System32;C:/Windows"
    -P "${SOURCE_DIR}/cmake/RunPureTest.cmake"
    RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 75)
  file(WRITE "${work}/native-host-rescue-${name}.log" "${out}${err}")
  if(rc EQUAL 0 OR NOT "${out}${err}" MATCHES "Pure fixture failed")
    message(FATAL_ERROR "Native host-rescue mutation passed: ${path}\n${out}${err}")
  endif()
  math(EXPR negative "${negative}+1")
  file(RENAME "${work}/saved-file" "${stage}/${path}")
endforeach()
run_verifier(restored-pristine pass "INSTALL_PACKAGE_OK.*delta=47")

# Reverse component order, with an identical pre-existing audio interface.
set(stage "${work}/identical baseline with spaces")
file(COPY "${PURE_PREFIX}/" DESTINATION "${stage}")
file(COPY_FILE "${SOURCE_DIR}/audio.pure" "${stage}/lib/pure/audio.pure")
set(preseeded lib/pure/audio.pure)
install_component(documentation)
install_component(runtime)
run_verifier(identical-reversed-pristine pass "INSTALL_PACKAGE_OK.*delta=46")
message(STATUS "INSTALL_CONTRACT_OK negatives=${negative} pristine=${positive} controls=4 artifacts=47 runtime=22 documentation=25 standard_delta=47 identical_delta=46 pe=29 license_payloads=13 mapped_dlls=13 evidence=${work}")
if(NOT KEEP_EVIDENCE)
  pure_audio_cleanup_leaf("${work}")
endif()
