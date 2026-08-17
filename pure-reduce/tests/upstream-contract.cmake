cmake_minimum_required(VERSION 3.25)

if(NOT DEFINED PURE_REDUCE_SOURCE_DIR)
  message(FATAL_ERROR "PURE_REDUCE_SOURCE_DIR is required")
endif()
if(NOT DEFINED PURE_REDUCE_UPSTREAM_BINARY_DIR)
  set(PURE_REDUCE_UPSTREAM_BINARY_DIR
    "${CMAKE_CURRENT_BINARY_DIR}/pure-reduce-upstream-contract")
endif()

include("${CMAKE_CURRENT_LIST_DIR}/../cmake/ReduceSource.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/../cmake/ReduceUpstream.cmake")

pure_reduce_verify_source(
  "${PURE_REDUCE_SOURCE_DIR}"
  PURE_REDUCE_VERIFIED_COMMIT
  PURE_REDUCE_SOURCE_TREE_SHA256)
pure_reduce_define_upstream_build()

list(FIND PURE_REDUCE_CSL_LINK_INPUTS
  "${PURE_REDUCE_UPSTREAM_BINARY_DIR}/artifacts/link/libreduce-csl.a"
  _csl_archive)
if(_csl_archive EQUAL -1)
  message(FATAL_ERROR
    "current CSL object closure archive is absent from link inputs")
endif()

set(_canonical_fixture
  "${CMAKE_CURRENT_BINARY_DIR}/pure-reduce-canonical-fixture")
file(REMOVE_RECURSE "${_canonical_fixture}")
set(_canonical_probe "libraries/libedit-20140620-3.1/src/shlib_version")
_pure_reduce_checkout_pinned_files(
  "${PURE_REDUCE_SOURCE_DIR}" "${_canonical_fixture}" "${_canonical_probe}")
execute_process(
  COMMAND git -C "${PURE_REDUCE_SOURCE_DIR}" cat-file blob
    "HEAD:${_canonical_probe}"
  RESULT_VARIABLE _blob_result
  OUTPUT_FILE "${_canonical_fixture}/expected-blob")
if(NOT _blob_result EQUAL 0)
  message(FATAL_ERROR "could not read canonical pinned probe blob")
endif()
file(SHA256 "${_canonical_fixture}/${_canonical_probe}" _checkout_hash)
file(SHA256 "${_canonical_fixture}/expected-blob" _blob_hash)
file(REMOVE_RECURSE "${_canonical_fixture}")
if(NOT _checkout_hash STREQUAL _blob_hash)
  message(FATAL_ERROR
    "private materialization applied host-dependent line-ending conversion")
endif()

set(_patch_fixture
  "${CMAKE_CURRENT_BINARY_DIR}/pure-reduce-patch-fixture")
file(REMOVE_RECURSE "${_patch_fixture}")
_pure_reduce_checkout_pinned_files(
  "${PURE_REDUCE_SOURCE_DIR}" "${_patch_fixture}"
  csl/cslbase/winsupport.cpp)
_pure_reduce_apply_private_source_patch(
  "${_patch_fixture}"
  "${CMAKE_CURRENT_LIST_DIR}/../patches/0001-csl-winsupport-define-nil.patch"
  "${PURE_REDUCE_SOURCE_TREE_SHA256}"
  "${_patch_fixture}/patches.log"
  _patch_json)
file(SHA256 "${_patch_fixture}/csl/cslbase/winsupport.cpp" _patched_hash)
if(NOT _patched_hash STREQUAL
    "8721a10c8ba5d9a82b5b0f5d2d83a46a4b98d87bb5519f92ce37940d15f936e0")
  message(FATAL_ERROR "private source patch produced unexpected bytes")
endif()
string(JSON _patch_target GET "${_patch_json}" target)
if(NOT _patch_target STREQUAL "csl/cslbase/winsupport.cpp")
  message(FATAL_ERROR "source-patch provenance names the wrong target")
endif()
file(READ "${_patch_fixture}/patches.log" _patch_transcript)
if(NOT _patch_transcript MATCHES
    "source_tree_sha256=${PURE_REDUCE_SOURCE_TREE_SHA256}")
  message(FATAL_ERROR "source-patch transcript omits the verified tree hash")
endif()
file(REMOVE_RECURSE "${_patch_fixture}")

set(_size_fixture "${CMAKE_CURRENT_BINARY_DIR}/pure-reduce-size-fixture")
file(MAKE_DIRECTORY "${_size_fixture}")
file(WRITE "${_size_fixture}/tracked;name" "1234")
_pure_reduce_tree_bytes(
  "${_size_fixture}" "${PURE_REDUCE_MSYS2_BASH}" _fixture_bytes)
file(REMOVE_RECURSE "${_size_fixture}")
if(NOT _fixture_bytes EQUAL 4)
  message(FATAL_ERROR
    "source byte counter mishandled a valid Git filename: ${_fixture_bytes}")
endif()

set(_configuration_fixture
  "${CMAKE_CURRENT_BINARY_DIR}/pure-reduce-configuration-fixture")
file(MAKE_DIRECTORY
  "${_configuration_fixture}/cslbuild/native/csl"
  "${_configuration_fixture}/cslbuild/windows/csl")
file(WRITE "${_configuration_fixture}/cslbuild/native/csl/config.h"
  "#define HOST_CPU \"x86_64\"\n"
  "#define HOST_OS \"mingw64\"\n"
  "#define RAW_CYGWIN 1\n")
file(WRITE "${_configuration_fixture}/cslbuild/windows/csl/config.h"
  "#define HOST_CPU \"x86_64\"\n"
  "#define HOST_OS \"mingw32\"\n"
  "/* #undef RAW_CYGWIN */\n")
file(WRITE "${_configuration_fixture}/cslbuild/windows/Makefile" "all:\n")
_pure_reduce_select_windows_configuration(
  "${_configuration_fixture}" _selected_configuration)
file(REMOVE_RECURSE "${_configuration_fixture}")

set(_closure_fixture
  "${CMAKE_CURRENT_BINARY_DIR}/pure-reduce-current-closure-fixture/csl")
file(MAKE_DIRECTORY "${_closure_fixture}")
file(WRITE "${_closure_fixture}/Makefile"
  "reduce.exe: alpha.o reduce-csl.o omega.o\n")
foreach(_object IN ITEMS alpha.o reduce-csl.o reduce_web-csl.o omega.o)
  file(WRITE "${_closure_fixture}/${_object}" "fixture")
endforeach()
_pure_reduce_discover_current_link_closure(
  "${_closure_fixture}" "${PURE_REDUCE_MSYS2_BASH}"
  "${PURE_REDUCE_MAKE}" _current_closure)
list(LENGTH _current_closure _current_closure_count)
if(NOT _current_closure_count EQUAL 3)
  message(FATAL_ERROR
    "current generated object closure has wrong size: ${_current_closure}")
endif()
list(FIND _current_closure "${_closure_fixture}/reduce-csl.o" _startup_object)
list(FIND _current_closure "${_closure_fixture}/reduce_web-csl.o" _embedded_object)
if(NOT _startup_object EQUAL -1 OR _embedded_object EQUAL -1)
  message(FATAL_ERROR
    "current closure did not replace exactly one startup object")
endif()
file(REMOVE_RECURSE
  "${CMAKE_CURRENT_BINARY_DIR}/pure-reduce-current-closure-fixture")
if(NOT _selected_configuration MATCHES "/cslbuild/windows$")
  message(FATAL_ERROR
    "selected the wrong complete CSL configuration: ${_selected_configuration}")
endif()

file(MAKE_DIRECTORY
  "${_configuration_fixture}/cslbuild/windows/csl"
  "${_configuration_fixture}/cslbuild/bootstrap/csl")
file(WRITE "${_configuration_fixture}/cslbuild/windows/csl/reduce.img" "target")
file(WRITE "${_configuration_fixture}/cslbuild/bootstrap/csl/reduce.img" "bootstrap")
_pure_reduce_select_configuration_image(
  "${_configuration_fixture}/cslbuild/windows" _selected_image)
if(NOT _selected_image MATCHES "/cslbuild/windows/csl/reduce[.]img$")
  message(FATAL_ERROR "selected an image from a different CSL configuration")
endif()
file(REMOVE_RECURSE "${_configuration_fixture}")

set(_restore_fixture
  "${CMAKE_CURRENT_BINARY_DIR}/pure-reduce-restore-fixture")
file(MAKE_DIRECTORY "${_restore_fixture}/pinned" "${_restore_fixture}/private")
set(_expected_restored_files
  Makefile.in aclocal.m4 compile config.guess config.sub configure depcomp
  install-sh ltmain.sh missing)
foreach(_name IN LISTS _expected_restored_files)
  file(WRITE "${_restore_fixture}/pinned/${_name}" "pinned ${_name}\n")
  if(NOT _name STREQUAL "depcomp")
    file(WRITE "${_restore_fixture}/private/${_name}" "regenerated ${_name}\n")
  endif()
endforeach()
_pure_reduce_restore_top_level_generated_files(
  "${_restore_fixture}/pinned"
  "${_restore_fixture}/private"
  "${_restore_fixture}/restored.log"
  _restored_json)
foreach(_name IN LISTS _expected_restored_files)
  file(SHA256 "${_restore_fixture}/pinned/${_name}" _pinned_hash)
  file(SHA256 "${_restore_fixture}/private/${_name}" _private_hash)
  if(NOT _private_hash STREQUAL _pinned_hash)
    message(FATAL_ERROR "restored ${_name} does not match the pinned bytes")
  endif()
  file(READ "${_restore_fixture}/restored.log" _restore_transcript)
  if(NOT _restore_transcript MATCHES "${_pinned_hash}  ${_name}")
    message(FATAL_ERROR "restore transcript omits ${_name} and its SHA-256")
  endif()
endforeach()
string(JSON _restored_count LENGTH "${_restored_json}")
list(LENGTH _expected_restored_files _expected_restored_count)
if(NOT _restored_count EQUAL _expected_restored_count)
  message(FATAL_ERROR "restored-file JSON has the wrong entry count")
endif()
file(REMOVE_RECURSE "${_restore_fixture}")

foreach(path IN ITEMS
    "${PURE_REDUCE_CSL_IMAGE}"
    ${PURE_REDUCE_CSL_LINK_INPUTS}
    ${PURE_REDUCE_RUNTIME_DATA})
  if(NOT IS_ABSOLUTE "${path}")
    message(FATAL_ERROR "upstream artifact is not absolute: ${path}")
  endif()
  cmake_path(IS_PREFIX PURE_REDUCE_UPSTREAM_BINARY_DIR "${path}"
    NORMALIZE is_build_artifact)
  if(NOT is_build_artifact)
    message(FATAL_ERROR "artifact escapes upstream build: ${path}")
  endif()
endforeach()

if(NOT PURE_REDUCE_CSL_LINK_INPUTS)
  message(FATAL_ERROR "current CSL link inputs are empty")
endif()
if(NOT PURE_REDUCE_RUNTIME_DATA)
  message(FATAL_ERROR "CSL runtime data is empty")
endif()

set(_artifact_contract_log
  "${PURE_REDUCE_UPSTREAM_BINARY_DIR}/logs/artifact-contract.log")
if(EXISTS "${PURE_REDUCE_UPSTREAM_BINARY_DIR}/pure-reduce-upstream.stamp")
  if(NOT EXISTS "${_artifact_contract_log}")
    message(FATAL_ERROR "built upstream omits artifact link/symbol assertions")
  endif()
  file(READ "${_artifact_contract_log}" _artifact_contract)
  foreach(_assertion IN ITEMS
      "PROC_clear_stack=defined"
      "CSL_LISP::cslstart=defined"
      "non_system_runtime_imports=none")
    if(NOT _artifact_contract MATCHES "${_assertion}")
      message(FATAL_ERROR
        "built upstream artifact assertion is missing: ${_assertion}")
    endif()
  endforeach()
endif()

message(STATUS "pure-reduce upstream contract passed")
