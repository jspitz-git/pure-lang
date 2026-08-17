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
    VERIFIER)
  if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
    message(FATAL_ERROR "${_required} is required")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH BUILD_DIR NORMALIZE OUTPUT_VARIABLE _build_dir)
cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE _valid_stage)
cmake_path(ABSOLUTE_PATH AUTHORITATIVE_MANIFEST NORMALIZE
  OUTPUT_VARIABLE _manifest)
set(_test_root "${_build_dir}/manifest failure fixtures")
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

set(_failures)
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

if(_failures)
  list(JOIN _failures "\n---\n" _failure_text)
  message(FATAL_ERROR
    "installed manifest mutation contract failed:\n${_failure_text}")
endif()

message(STATUS "installed manifest mutations failed for their specific reasons")
