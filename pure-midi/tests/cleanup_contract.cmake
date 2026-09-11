cmake_minimum_required(VERSION 3.25)
if(BASELINE)
  # Only this dedicated contract leaf is offered to the legacy deleter.
  file(MAKE_DIRECTORY "${CONTRACT_ROOT}/unowned-baseline")
  file(WRITE "${CONTRACT_ROOT}/unowned-baseline/keep.txt" "not owned\n")
  file(WRITE "${CONTRACT_ROOT}/pristine.pure" "pristine\n")
  execute_process(COMMAND "${CMAKE_COMMAND}" "-DPURE_EXECUTABLE=${FIXTURE_EXE}"
    "-DPURE_SOURCE_DIR=${SOURCE_DIR}" "-DMODULE_DIR=${SOURCE_DIR}"
    "-DTEST_SCRIPT=${CONTRACT_ROOT}/pristine.pure"
    "-DTEST_DIRECTORY=${CONTRACT_ROOT}/unowned-baseline"
    -P "${SOURCE_DIR}/cmake/RunPureTest.cmake"
    RESULT_VARIABLE result OUTPUT_QUIET ERROR_QUIET)
  if(NOT EXISTS "${CONTRACT_ROOT}/unowned-baseline/keep.txt")
    message(FATAL_ERROR "unowned leaf was recursively deleted without a sentinel")
  endif()
  message(FATAL_ERROR "baseline failed for an unexpected reason: ${result}")
endif()

function(reserve leaf_var nonce_var)
  execute_process(COMMAND "${RUNNER}" --owned-create RESULT_VARIABLE result OUTPUT_VARIABLE out ERROR_VARIABLE err)
  if(NOT result EQUAL 0)
    message(FATAL_ERROR "reservation failed: ${out}${err}")
  endif()
  string(REPLACE "\r" "" out "${out}")
  string(REGEX MATCH "leaf=([^\n]+)\nnonce=([0-9a-f]+)" match "${out}")
  if(NOT match)
    message(FATAL_ERROR "invalid reservation: ${out}")
  endif()
  set(${leaf_var} "${CMAKE_MATCH_1}" PARENT_SCOPE)
  set(${nonce_var} "${CMAKE_MATCH_2}" PARENT_SCOPE)
  message(STATUS "owned cleanup reservation: ${CMAKE_MATCH_1}")
endfunction()

function(reject name leaf nonce guard)
  execute_process(COMMAND "${RUNNER}" --owned-clean --cwd "${leaf}" --token "${nonce}"
    RESULT_VARIABLE result OUTPUT_VARIABLE out ERROR_VARIABLE err)
  if(NOT result EQUAL 125 OR NOT EXISTS "${guard}")
    message(FATAL_ERROR "unsafe cleanup ${name}: result=${result} guard=${guard}\n${out}${err}")
  endif()
endfunction()

reserve(leaf nonce)
reserve(other other_nonce)
execute_process(COMMAND "${POWERSHELL}" -NoProfile -Command
  "$ErrorActionPreference='Stop'; $a=Start-Process -WindowStyle Hidden -FilePath '${RUNNER}' -ArgumentList '--owned-create' -PassThru -RedirectStandardOutput '${leaf}/reserve-a.txt'; $b=Start-Process -WindowStyle Hidden -FilePath '${RUNNER}' -ArgumentList '--owned-create' -PassThru -RedirectStandardOutput '${leaf}/reserve-b.txt'; $a.WaitForExit(); $b.WaitForExit()"
  RESULT_VARIABLE result)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "parallel reservations failed")
endif()
set(previous "")
foreach(record IN ITEMS a b)
  file(READ "${leaf}/reserve-${record}.txt" reservation)
  string(REPLACE "\r" "" reservation "${reservation}")
  string(REGEX MATCH "leaf=([^\n]+)\nnonce=([0-9a-f]+)" match "${reservation}")
  if(NOT match OR CMAKE_MATCH_1 STREQUAL previous)
    message(FATAL_ERROR "parallel reservations collided or malformed output")
  endif()
  set(previous "${CMAKE_MATCH_1}")
  message(STATUS "parallel owned cleanup: ${CMAKE_MATCH_1}")
  execute_process(COMMAND "${RUNNER}" --owned-clean --cwd "${CMAKE_MATCH_1}" --token "${CMAKE_MATCH_2}"
    RESULT_VARIABLE result)
  if(NOT result EQUAL 0 OR EXISTS "${previous}")
    message(FATAL_ERROR "parallel leaf cleanup failed")
  endif()
endforeach()
message(STATUS "PASS parallel reservations: two distinct owned leaves")
if(MAKE_EXE AND SOURCE_DIR)
  get_filename_component(make_bin "${MAKE_SHELL}" DIRECTORY)
  set(ENV{PATH} "${make_bin};${RUNTIME_DIR};$ENV{SystemRoot}/System32;$ENV{SystemRoot}")
  file(MAKE_DIRECTORY "${leaf}/make/midifile" "${leaf}/make/pmlib.dll.directory")
  file(COPY "${SOURCE_DIR}/Makefile" DESTINATION "${leaf}/make")
  file(COPY "${SOURCE_DIR}/midifile/Makefile" DESTINATION "${leaf}/make/midifile")
  foreach(file IN ITEMS pmdev.o pmlib.dll unrelated.o unrelated.dll pmlib.dll.note midi.pure portmidi.pure
      midifile/midifile.dll midifile/unrelated.o midifile/unrelated.dll pmlib.dll.directory/keep)
    file(WRITE "${leaf}/make/${file}" "keep unless enumerated\n")
  endforeach()
  foreach(suffix IN ITEMS "" ".bad" ".dll .so" ".dll ")
    execute_process(COMMAND "${MAKE_EXE}" clean "DLL=${suffix}" "SHELL=${MAKE_SHELL}"
      WORKING_DIRECTORY "${leaf}/make" RESULT_VARIABLE result OUTPUT_VARIABLE out ERROR_VARIABLE err)
    if(result EQUAL 0 OR NOT EXISTS "${leaf}/make/pmlib.dll")
      message(FATAL_ERROR "Make clean accepted invalid suffix '${suffix}': ${out}${err}")
    endif()
  endforeach()
  execute_process(COMMAND "${MAKE_EXE}" clean DLL=.dll "SHELL=${MAKE_SHELL}"
    WORKING_DIRECTORY "${leaf}/make" RESULT_VARIABLE result OUTPUT_VARIABLE out ERROR_VARIABLE err)
  if(NOT result EQUAL 0 OR EXISTS "${leaf}/make/pmlib.dll" OR EXISTS "${leaf}/make/pmdev.o"
      OR EXISTS "${leaf}/make/midifile/midifile.dll")
    message(FATAL_ERROR "enumerated Make clean failed: ${out}${err}")
  endif()
  foreach(file IN ITEMS unrelated.o unrelated.dll pmlib.dll.note midi.pure portmidi.pure
      midifile/unrelated.o midifile/unrelated.dll pmlib.dll.directory/keep)
    if(NOT EXISTS "${leaf}/make/${file}")
      message(FATAL_ERROR "Make clean removed non-output: ${file}")
    endif()
  endforeach()
  message(STATUS "PASS Make cleanup: 4 invalid suffixes and exact named outputs")
endif()
file(WRITE "${leaf}/keep.txt" "guard\n")
file(WRITE "${other}/keep.txt" "independent\n")
reject(root "${CONTRACT_ROOT}" "${nonce}" "${leaf}/keep.txt")
reject(empty "" "${nonce}" "${leaf}/keep.txt")
# The outside candidate is still inside our dedicated contract tree.
file(MAKE_DIRECTORY "${CONTRACT_ROOT}/outside")
file(WRITE "${CONTRACT_ROOT}/outside/keep.txt" "outside owned leaves\n")
reject(outside "${CONTRACT_ROOT}/outside" "${nonce}" "${CONTRACT_ROOT}/outside/keep.txt")
reject(wrong-sentinel "${leaf}" "${other_nonce}" "${leaf}/keep.txt")
file(RENAME "${leaf}/.pure-midi-owner" "${leaf}/saved-owner")
reject(missing-sentinel "${leaf}" "${nonce}" "${leaf}/keep.txt")
file(RENAME "${leaf}/saved-owner" "${leaf}/.pure-midi-owner")
reject(other-owner "${other}" "${nonce}" "${other}/keep.txt")
# Sentinel symlink, junction endpoint, junction ancestor, and nested junction
# all fail before traversal can remove any object. Reparse targets stay within
# the fixed temporary contract root.
file(RENAME "${leaf}/.pure-midi-owner" "${leaf}/saved-owner")
file(CREATE_LINK "${leaf}/saved-owner" "${leaf}/.pure-midi-owner" SYMBOLIC RESULT result)
if(NOT result STREQUAL "0")
  # Directory reparse sentinels must be rejected too. File symlinks need a
  # Windows privilege which is not available on every mandatory-test host.
  execute_process(COMMAND "${POWERSHELL}" -NoProfile -Command
    "$ErrorActionPreference='Stop'; New-Item -ItemType Junction -Path '${leaf}/.pure-midi-owner' -Target '${other}' | Out-Null"
    RESULT_VARIABLE result)
  if(NOT result EQUAL 0)
    message(FATAL_ERROR "sentinel reparse setup failed")
  endif()
  set(sentinel_junction TRUE)
  message(STATUS "SKIP file symlink sentinel: Windows denies creation; directory reparse sentinel tested")
endif()
reject(sentinel-reparse "${leaf}" "${nonce}" "${leaf}/keep.txt")
if(sentinel_junction)
  execute_process(COMMAND "${POWERSHELL}" -NoProfile -Command
    "[System.IO.Directory]::Delete('${leaf}/.pure-midi-owner')" RESULT_VARIABLE result)
  if(NOT result EQUAL 0)
    message(FATAL_ERROR "sentinel junction unlink failed")
  endif()
else()
  file(REMOVE "${leaf}/.pure-midi-owner")
endif()
file(RENAME "${leaf}/saved-owner" "${leaf}/.pure-midi-owner")
execute_process(COMMAND "${POWERSHELL}" -NoProfile -Command
  "$ErrorActionPreference='Stop'; New-Item -ItemType Junction -Path '${CONTRACT_ROOT}/endpoint-junction' -Target '${leaf}' | Out-Null; New-Item -ItemType Junction -Path '${leaf}/nested-junction' -Target '${other}' | Out-Null"
  RESULT_VARIABLE result ERROR_VARIABLE err)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "junction setup failed: ${err}")
endif()
reject(endpoint-junction "${CONTRACT_ROOT}/endpoint-junction" "${nonce}" "${leaf}/keep.txt")
reject(ancestor-junction "${CONTRACT_ROOT}/endpoint-junction/nested-junction" "${other_nonce}" "${other}/keep.txt")
reject(nested-junction "${leaf}" "${nonce}" "${other}/keep.txt")
# Remove only the junction entry (no recursive flag); never traverse its target.
execute_process(COMMAND "${POWERSHELL}" -NoProfile -Command
  "[System.IO.Directory]::Delete('${leaf}/nested-junction'); [System.IO.Directory]::Delete('${CONTRACT_ROOT}/endpoint-junction')"
  RESULT_VARIABLE result)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "junction unlink failed")
endif()
execute_process(COMMAND "${RUNNER}" --owned-clean --cwd "${leaf}" --token "${nonce}"
  RESULT_VARIABLE result)
if(NOT result EQUAL 0 OR EXISTS "${leaf}" OR NOT EXISTS "${other}/keep.txt")
  message(FATAL_ERROR "valid cleanup did not remove exactly its own leaf")
endif()
execute_process(COMMAND "${RUNNER}" --owned-clean --cwd "${other}" --token "${other_nonce}"
  RESULT_VARIABLE result)
if(NOT result EQUAL 0 OR EXISTS "${other}")
  message(FATAL_ERROR "independent leaf cleanup failed")
endif()
message(STATUS "PASS cleanup contract: 12 ownership/reparse cases")
