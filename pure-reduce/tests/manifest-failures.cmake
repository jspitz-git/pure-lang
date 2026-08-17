cmake_minimum_required(VERSION 3.25)
if(POLICY CMP0219)
  cmake_policy(SET CMP0219 NEW)
endif()

foreach(_required IN ITEMS
    BUILD_DIR
    STAGE_PREFIX
    AUTHORITATIVE_MANIFEST
    PURE_EXECUTABLE
    LLVM_READOBJ
    SOURCE_PREFIX
    VERIFIER
    ORACLE_GENERATOR)
  if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
    message(FATAL_ERROR "${_required} is required")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH BUILD_DIR NORMALIZE OUTPUT_VARIABLE _build_dir)
cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE _valid_stage)
cmake_path(ABSOLUTE_PATH AUTHORITATIVE_MANIFEST NORMALIZE
  OUTPUT_VARIABLE _manifest)
set(_test_root "${_build_dir}/manifest failure fixtures")
if(NOT MANIFEST_FAILURE_CHILD)
  if(NOT IS_DIRECTORY "${_valid_stage}")
    message(FATAL_ERROR "valid installed stage is missing: ${_valid_stage}")
  endif()
  file(GLOB_RECURSE _parent_valid_files LIST_DIRECTORIES FALSE
    "${_valid_stage}/*")
  set(_parent_valid_records)
  foreach(_valid_file IN LISTS _parent_valid_files)
    file(RELATIVE_PATH _valid_relative "${_valid_stage}" "${_valid_file}")
    string(REPLACE "\\" "/" _valid_relative "${_valid_relative}")
    file(SHA256 "${_valid_file}" _valid_sha)
    list(APPEND _parent_valid_records "${_valid_relative}|${_valid_sha}")
  endforeach()
  list(SORT _parent_valid_records COMPARE NATURAL CASE INSENSITIVE)
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DBUILD_DIR=${_build_dir}"
      "-DSTAGE_PREFIX=${_valid_stage}"
      "-DAUTHORITATIVE_MANIFEST=${_manifest}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DLLVM_READOBJ=${LLVM_READOBJ}"
      "-DSOURCE_PREFIX=${SOURCE_PREFIX}"
      "-DVERIFIER=${VERIFIER}"
      "-DORACLE_GENERATOR=${ORACLE_GENERATOR}"
      -DMANIFEST_FAILURE_CHILD=ON
      -P "${CMAKE_CURRENT_LIST_FILE}"
    RESULT_VARIABLE _child_result
    OUTPUT_VARIABLE _child_output
    ERROR_VARIABLE _child_error
    ENCODING UTF-8)
  file(REMOVE_RECURSE "${_test_root}")
  file(GLOB_RECURSE _parent_valid_files_after LIST_DIRECTORIES FALSE
    "${_valid_stage}/*")
  set(_parent_valid_records_after)
  foreach(_valid_file IN LISTS _parent_valid_files_after)
    file(RELATIVE_PATH _valid_relative "${_valid_stage}" "${_valid_file}")
    string(REPLACE "\\" "/" _valid_relative "${_valid_relative}")
    file(SHA256 "${_valid_file}" _valid_sha)
    list(APPEND _parent_valid_records_after
      "${_valid_relative}|${_valid_sha}")
  endforeach()
  list(SORT _parent_valid_records_after COMPARE NATURAL CASE INSENSITIVE)
  if(NOT _parent_valid_records_after STREQUAL _parent_valid_records)
    message(FATAL_ERROR
      "mutation child changed the shared valid installed stage")
  endif()
  if(NOT _child_result EQUAL 0)
    message(FATAL_ERROR
      "installed manifest mutation child failed (${_child_result})\n"
      "stdout:\n${_child_output}\nstderr:\n${_child_error}")
  endif()
  message("${_child_output}")
  return()
endif()
file(REMOVE_RECURSE "${_test_root}")
file(MAKE_DIRECTORY "${_test_root}")

foreach(_required_file IN ITEMS
    "${_manifest}"
    "${_build_dir}/PureReduceInstalledInventory.tsv"
    "${_build_dir}/PureReduceInventory.tsv")
  if(NOT EXISTS "${_required_file}")
    message(FATAL_ERROR "valid fixture input is missing: ${_required_file}")
  endif()
endforeach()
if(NOT IS_DIRECTORY "${_valid_stage}")
  message(FATAL_ERROR "valid installed stage is missing: ${_valid_stage}")
endif()

file(GLOB_RECURSE _valid_stage_files LIST_DIRECTORIES FALSE
  "${_valid_stage}/*")
set(_valid_stage_records)
foreach(_valid_file IN LISTS _valid_stage_files)
  file(RELATIVE_PATH _valid_relative "${_valid_stage}" "${_valid_file}")
  string(REPLACE "\\" "/" _valid_relative "${_valid_relative}")
  file(SHA256 "${_valid_file}" _valid_sha)
  list(APPEND _valid_stage_records "${_valid_relative}|${_valid_sha}")
endforeach()
list(SORT _valid_stage_records COMPARE NATURAL CASE INSENSITIVE)

set(_failures)

set(_oracle_cleanup_build "${_test_root}/oracle cleanup failure/build")
set(_oracle_cleanup_stage "${_oracle_cleanup_build}/partial stage")
file(MAKE_DIRECTORY "${_oracle_cleanup_build}")
file(WRITE "${_oracle_cleanup_build}/cmake_install.cmake"
  "file(MAKE_DIRECTORY \"\${CMAKE_INSTALL_PREFIX}\")\n"
  "file(WRITE \"\${CMAKE_INSTALL_PREFIX}/partial\" \"partial\\n\")\n"
  "message(FATAL_ERROR \"intentional oracle install failure\")\n")
execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DBUILD_DIR=${_oracle_cleanup_build}"
    "-DSTAGE_PREFIX=${_oracle_cleanup_stage}"
    -P "${ORACLE_GENERATOR}"
  RESULT_VARIABLE _oracle_cleanup_result
  OUTPUT_VARIABLE _oracle_cleanup_output
  ERROR_VARIABLE _oracle_cleanup_error
  ENCODING UTF-8)
set(_oracle_cleanup_combined
  "${_oracle_cleanup_output}\n${_oracle_cleanup_error}")
if(_oracle_cleanup_result EQUAL 0 OR EXISTS "${_oracle_cleanup_stage}" OR
    NOT _oracle_cleanup_combined MATCHES
      "package oracle generation install failed")
  list(APPEND _failures
    "oracle-generation-cleanup: failed install did not report its specific "
    "reason and remove its partial stage:\n${_oracle_cleanup_combined}")
endif()

foreach(_missing_name IN ITEMS
    PureReduceExpected.sha256
    PureReduceInventory.tsv
    PureReduceInstalledInventory.tsv)
  set(_missing_oracle_root
    "${_test_root}/missing preexisting ${_missing_name}")
  set(_missing_oracle_build "${_missing_oracle_root}/build")
  set(_missing_oracle_stage "${_missing_oracle_build}/stage")
  set(_install_marker "${_missing_oracle_build}/install-ran.marker")
  file(MAKE_DIRECTORY "${_missing_oracle_build}")
  foreach(_oracle_name IN ITEMS
      PureReduceExpected.sha256
      PureReduceInventory.tsv
      PureReduceInstalledInventory.tsv)
    if(NOT _oracle_name STREQUAL _missing_name)
      file(COPY_FILE "${_build_dir}/${_oracle_name}"
        "${_missing_oracle_build}/${_oracle_name}")
    endif()
  endforeach()
  file(WRITE "${_missing_oracle_build}/cmake_install.cmake"
    "file(WRITE \"${_install_marker}\" \"install executed\\n\")\n"
    "file(MAKE_DIRECTORY \"\${CMAKE_INSTALL_PREFIX}\")\n")
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DBUILD_DIR=${_missing_oracle_build}"
      "-DSTAGE_PREFIX=${_missing_oracle_stage}"
      "-DAUTHORITATIVE_MANIFEST=${_missing_oracle_build}/PureReduceExpected.sha256"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DLLVM_READOBJ=${LLVM_READOBJ}"
      "-DSOURCE_PREFIX=${SOURCE_PREFIX}"
      -P "${VERIFIER}"
    RESULT_VARIABLE _missing_oracle_result
    OUTPUT_VARIABLE _missing_oracle_output
    ERROR_VARIABLE _missing_oracle_error
    ENCODING UTF-8)
  set(_missing_oracle_combined
    "${_missing_oracle_output}\n${_missing_oracle_error}")
  string(REPLACE "." "\\." _missing_name_regex "${_missing_name}")
  if(_missing_oracle_result EQUAL 0 OR EXISTS "${_install_marker}" OR
      NOT _missing_oracle_combined MATCHES
        "trusted package oracle must preexist before install:" OR
      NOT _missing_oracle_combined MATCHES "${_missing_name_regex}")
    list(APPEND _failures
      "missing-preexisting-${_missing_name}: verifier did not reject the "
      "absent oracle before running install:\n${_missing_oracle_combined}")
  endif()
endforeach()

set(_regeneration_root "${_test_root}/payload regeneration attack")
set(_regeneration_build "${_regeneration_root}/build")
set(_regeneration_stage "${_regeneration_build}/stage")
file(MAKE_DIRECTORY "${_regeneration_build}")
foreach(_oracle_name IN ITEMS
    PureReduceExpected.sha256
    PureReduceInstalledInventory.tsv
    PureReduceInventory.tsv)
  file(COPY_FILE "${_build_dir}/${_oracle_name}"
    "${_regeneration_build}/${_oracle_name}")
endforeach()
set(_regeneration_install [=[
file(MAKE_DIRECTORY "${CMAKE_INSTALL_PREFIX}")
file(COPY "@VALID_STAGE@/" DESTINATION "${CMAKE_INSTALL_PREFIX}")
set(_mutated "${CMAKE_INSTALL_PREFIX}/share/doc/pure-reduce/README")
file(APPEND "${_mutated}" "regenerated payload\n")
file(SHA256 "${_mutated}" _mutated_sha)
file(STRINGS "@REGEN_BUILD@/PureReduceExpected.sha256" _lines)
file(WRITE "@REGEN_BUILD@/PureReduceExpected.sha256" "")
foreach(_line IN LISTS _lines)
  if(_line MATCHES "  share/doc/pure-reduce/README$")
    set(_line "${_mutated_sha}  share/doc/pure-reduce/README")
  endif()
  file(APPEND "@REGEN_BUILD@/PureReduceExpected.sha256" "${_line}\n")
endforeach()
]=])
set(VALID_STAGE "${_valid_stage}")
set(REGEN_BUILD "${_regeneration_build}")
string(CONFIGURE "${_regeneration_install}" _regeneration_install @ONLY)
file(WRITE "${_regeneration_build}/cmake_install.cmake"
  "${_regeneration_install}")
execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DBUILD_DIR=${_regeneration_build}"
    "-DSTAGE_PREFIX=${_regeneration_stage}"
    "-DAUTHORITATIVE_MANIFEST=${_regeneration_build}/PureReduceExpected.sha256"
    "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    "-DSOURCE_PREFIX=${SOURCE_PREFIX}"
    -P "${VERIFIER}"
  RESULT_VARIABLE _regeneration_result
  OUTPUT_VARIABLE _regeneration_output
  ERROR_VARIABLE _regeneration_error
  ENCODING UTF-8)
set(_regeneration_combined
  "${_regeneration_output}\n${_regeneration_error}")
if(_regeneration_result EQUAL 0 OR NOT _regeneration_combined MATCHES
    "component install changed trusted package oracle: PureReduceExpected\\.sha256")
  list(APPEND _failures
    "payload-regeneration: verifier did not reject oracle replacement for "
    "mutated installed bytes:\n${_regeneration_combined}")
endif()

macro(_run_mutation NAME EXPECTED_DIAGNOSTIC)
  set(_case_root "${_test_root}/${NAME}")
  set(_case_build "${_case_root}/build")
  set(_case_stage "${_case_root}/stage")
  file(MAKE_DIRECTORY "${_case_build}" "${_case_stage}")
  file(COPY "${_valid_stage}/" DESTINATION "${_case_stage}")
  foreach(_inventory_name IN ITEMS
      PureReduceExpected.sha256
      PureReduceInstalledInventory.tsv
      PureReduceInventory.tsv)
    file(COPY_FILE "${_build_dir}/${_inventory_name}"
      "${_case_build}/${_inventory_name}")
  endforeach()

  if("${NAME}" STREQUAL "missing-file")
    file(REMOVE "${_case_stage}/lib/pure/reduce.pure")
  elseif("${NAME}" STREQUAL "extra-file")
    file(WRITE "${_case_stage}/share/doc/pure-reduce/unowned-extra.txt"
      "not owned by PureReduce\n")
  elseif("${NAME}" STREQUAL "modified-file")
    file(APPEND "${_case_stage}/share/doc/pure-reduce/README" "X")
  elseif("${NAME}" STREQUAL "unsafe-manifest-path")
    file(STRINGS "${_case_build}/PureReduceExpected.sha256" _lines)
    list(POP_FRONT _lines _first_line)
    string(SUBSTRING "${_first_line}" 0 64 _first_sha)
    file(WRITE "${_case_build}/PureReduceExpected.sha256"
      "${_first_sha}  ../escape\n")
    foreach(_line IN LISTS _lines)
      file(APPEND "${_case_build}/PureReduceExpected.sha256" "${_line}\n")
    endforeach()
  elseif("${NAME}" STREQUAL "missing-license")
    file(REMOVE
      "${_case_stage}/share/doc/pure-reduce/licenses/REDUCE-LICENSE.txt")
  else()
    message(FATAL_ERROR "unknown manifest mutation: ${NAME}")
  endif()

  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DBUILD_DIR=${_case_build}"
      "-DSTAGE_PREFIX=${_case_stage}"
      "-DAUTHORITATIVE_MANIFEST=${_case_build}/PureReduceExpected.sha256"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DLLVM_READOBJ=${LLVM_READOBJ}"
      "-DSOURCE_PREFIX=${SOURCE_PREFIX}"
      -DVERIFY_ONLY=ON
      -DRUN_RUNTIME_TESTS=OFF
      -P "${VERIFIER}"
    RESULT_VARIABLE _result
    OUTPUT_VARIABLE _output
    ERROR_VARIABLE _error
    ENCODING UTF-8)
  set(_combined "${_output}\n${_error}")
  if(_result EQUAL 0)
    list(APPEND _failures
      "${NAME}: verifier unexpectedly accepted the mutation")
  elseif(NOT _combined MATCHES "${EXPECTED_DIAGNOSTIC}")
    list(APPEND _failures
      "${NAME}: verifier failed for the wrong reason; expected "
      "'${EXPECTED_DIAGNOSTIC}', got:\n${_combined}")
  endif()
endmacro()

_run_mutation("missing-file" "manifest entry is missing: lib/pure/reduce\\.pure")
_run_mutation("extra-file" "unexpected installed file: .*unowned-extra\\.txt")
_run_mutation("modified-file" "installed hash mismatch: .*README")
_run_mutation("unsafe-manifest-path" "unsafe authoritative manifest path: \.\./escape")
_run_mutation("missing-license" "required license is missing: REDUCE-LICENSE\\.txt")

file(GLOB_RECURSE _valid_stage_files_after LIST_DIRECTORIES FALSE
  "${_valid_stage}/*")
set(_valid_stage_records_after)
foreach(_valid_file IN LISTS _valid_stage_files_after)
  file(RELATIVE_PATH _valid_relative "${_valid_stage}" "${_valid_file}")
  string(REPLACE "\\" "/" _valid_relative "${_valid_relative}")
  file(SHA256 "${_valid_file}" _valid_sha)
  list(APPEND _valid_stage_records_after "${_valid_relative}|${_valid_sha}")
endforeach()
list(SORT _valid_stage_records_after COMPARE NATURAL CASE INSENSITIVE)
if(NOT _valid_stage_records_after STREQUAL _valid_stage_records)
  list(APPEND _failures
    "mutation probes changed the shared valid installed stage")
endif()

if(_failures)
  list(JOIN _failures "\n---\n" _failure_text)
  file(REMOVE_RECURSE "${_test_root}")
  message(FATAL_ERROR
    "installed manifest mutation contract failed:\n${_failure_text}")
endif()

file(REMOVE_RECURSE "${_test_root}")
message(STATUS "installed manifest mutations failed for their specific reasons")
