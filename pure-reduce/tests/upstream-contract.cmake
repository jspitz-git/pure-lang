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

if(NOT EXISTS
    "${PURE_REDUCE_UPSTREAM_BINARY_DIR}/pure-reduce-upstream.stamp")
  message(FATAL_ERROR
    "upstream artifacts must be built before running the contract: "
    "${PURE_REDUCE_UPSTREAM_BINARY_DIR}")
endif()

list(FIND PURE_REDUCE_CSL_LINK_INPUTS
  "${PURE_REDUCE_UPSTREAM_BINARY_DIR}/artifacts/link/libreduce-csl.a"
  _csl_archive)
if(_csl_archive EQUAL -1)
  message(FATAL_ERROR
    "current CSL object closure archive is absent from link inputs")
endif()

set(_expected_link_tail
  -Wl,-Bstatic -lz -lncurses -lstdc++ -lpthread -static-libgcc
  -lcomctl32 -lgdi32 -lws2_32 -lwsock32 -lwinspool -lmpr
  -Wl,--subsystem,console)
if(NOT PURE_REDUCE_CSL_LINK_ARTIFACTS)
  message(FATAL_ERROR "verified CSL link artifacts are not exported")
endif()
set(_expected_link_interface
  ${PURE_REDUCE_CSL_LINK_ARTIFACTS} ${_expected_link_tail})
if(NOT PURE_REDUCE_CSL_LINK_INTERFACE STREQUAL _expected_link_interface OR
   NOT PURE_REDUCE_CSL_LINK_INPUTS STREQUAL _expected_link_interface)
  message(FATAL_ERROR
    "complete ordered CSL link interface is not exported:\n"
    "${PURE_REDUCE_CSL_LINK_INTERFACE}")
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

set(_tampered_fixture
  "${CMAKE_CURRENT_BINARY_DIR}/pure-reduce-tampered-patch-fixture")
file(REMOVE_RECURSE "${_tampered_fixture}")
file(MAKE_DIRECTORY "${_tampered_fixture}")
_pure_reduce_checkout_pinned_files(
  "${PURE_REDUCE_SOURCE_DIR}" "${_tampered_fixture}/private"
  csl/cslbase/winsupport.cpp)
file(COPY
  "${CMAKE_CURRENT_LIST_DIR}/../patches/0001-csl-winsupport-define-nil.patch"
  DESTINATION "${_tampered_fixture}")
set(_tampered_patch
  "${_tampered_fixture}/0001-csl-winsupport-define-nil.patch")
file(APPEND "${_tampered_patch}" "\n# unapproved extra bytes\n")
file(TO_CMAKE_PATH "${CMAKE_CURRENT_LIST_DIR}/../cmake/ReduceUpstream.cmake"
  _module_path)
file(TO_CMAKE_PATH "${_tampered_fixture}/private" _private_path)
file(TO_CMAKE_PATH "${_tampered_patch}" _tampered_patch_path)
file(WRITE "${_tampered_fixture}/reject.cmake"
  "include(\"${_module_path}\")\n"
  "_pure_reduce_apply_private_source_patch(\n"
  "  \"${_private_path}\" \"${_tampered_patch_path}\"\n"
  "  \"${PURE_REDUCE_SOURCE_TREE_SHA256}\"\n"
  "  \"${_tampered_fixture}/patch.log\" _patch_json)\n")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -P "${_tampered_fixture}/reject.cmake"
  RESULT_VARIABLE _tampered_result
  OUTPUT_VARIABLE _tampered_output ERROR_VARIABLE _tampered_error)
file(REMOVE_RECURSE "${_tampered_fixture}")
if(_tampered_result EQUAL 0)
  message(FATAL_ERROR "approved patch registry accepted extra bytes")
endif()
if(NOT "${_tampered_output}${_tampered_error}" MATCHES
    "approved source patch SHA-256 mismatch")
  message(FATAL_ERROR
    "tampered patch failed for the wrong reason:\n"
    "${_tampered_output}${_tampered_error}")
endif()
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
file(REMOVE_RECURSE "${_configuration_fixture}")
file(MAKE_DIRECTORY
  "${_configuration_fixture}/cslbuild/x86_64-pc-cygwin-nogui/csl"
  "${_configuration_fixture}/cslbuild/x86_64-pc-windows-nogui/csl")
file(WRITE
  "${_configuration_fixture}/cslbuild/x86_64-pc-cygwin-nogui/csl/config.h"
  "#define RAW_CYGWIN 1\n")
file(WRITE
  "${_configuration_fixture}/cslbuild/x86_64-pc-windows-nogui/csl/config.h"
  "/* #undef RAW_CYGWIN */\n")
file(WRITE
  "${_configuration_fixture}/cslbuild/x86_64-pc-windows-nogui/Makefile"
  "all:\n")
_pure_reduce_select_windows_configuration(
  "${_configuration_fixture}" _selected_configuration)

file(MAKE_DIRECTORY
  "${_configuration_fixture}/cslbuild/x86_64-pc-windows-debug/csl")
file(WRITE
  "${_configuration_fixture}/cslbuild/x86_64-pc-windows-debug/csl/config.h"
  "/* #undef RAW_CYGWIN */\n")
file(WRITE
  "${_configuration_fixture}/cslbuild/x86_64-pc-windows-debug/Makefile"
  "all:\n")
file(TO_CMAKE_PATH "${CMAKE_CURRENT_LIST_DIR}/../cmake/ReduceUpstream.cmake"
  _negative_module)
file(TO_CMAKE_PATH "${_configuration_fixture}" _negative_configuration)
file(WRITE "${_configuration_fixture}/reject-multiple.cmake"
  "include(\"${_negative_module}\")\n"
  "_pure_reduce_select_windows_configuration(\n"
  "  \"${_negative_configuration}\" _selected)\n")
execute_process(
  COMMAND "${CMAKE_COMMAND}"
    -P "${_configuration_fixture}/reject-multiple.cmake"
  RESULT_VARIABLE _multiple_result
  OUTPUT_VARIABLE _multiple_output ERROR_VARIABLE _multiple_error)
if(_multiple_result EQUAL 0 OR
   NOT "${_multiple_output}${_multiple_error}" MATCHES
     "expected exactly one non-Cygwin x86-64 CSL build configuration")
  message(FATAL_ERROR
    "multiple complete CSL configurations did not fail closed:\n"
    "${_multiple_output}${_multiple_error}")
endif()
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
if(NOT _selected_configuration MATCHES
    "/cslbuild/x86_64-pc-windows-nogui$")
  message(FATAL_ERROR
    "selected the wrong complete CSL configuration: ${_selected_configuration}")
endif()

file(MAKE_DIRECTORY
  "${_configuration_fixture}/cslbuild/x86_64-pc-windows-nogui/csl"
  "${_configuration_fixture}/cslbuild/bootstrap/csl")
file(WRITE
  "${_configuration_fixture}/cslbuild/x86_64-pc-windows-nogui/csl/reduce.img"
  "target")
file(WRITE "${_configuration_fixture}/cslbuild/bootstrap/csl/reduce.img" "bootstrap")
_pure_reduce_select_configuration_image(
  "${_configuration_fixture}/cslbuild/x86_64-pc-windows-nogui"
  _selected_image)
if(NOT _selected_image MATCHES
    "/cslbuild/x86_64-pc-windows-nogui/csl/reduce[.]img$")
  message(FATAL_ERROR "selected an image from a different CSL configuration")
endif()
file(MAKE_DIRECTORY "${_configuration_fixture}/cslbuild/empty/csl")
file(TO_CMAKE_PATH
  "${_configuration_fixture}/cslbuild/empty" _empty_configuration)
file(WRITE "${_configuration_fixture}/reject-missing-image.cmake"
  "include(\"${_negative_module}\")\n"
  "_pure_reduce_select_configuration_image(\n"
  "  \"${_empty_configuration}\" _selected)\n")
execute_process(
  COMMAND "${CMAKE_COMMAND}"
    -P "${_configuration_fixture}/reject-missing-image.cmake"
  RESULT_VARIABLE _missing_image_result
  OUTPUT_VARIABLE _missing_image_output ERROR_VARIABLE _missing_image_error)
if(_missing_image_result EQUAL 0 OR
   NOT "${_missing_image_output}${_missing_image_error}" MATCHES
     "expected exactly one complete CSL image")
  message(FATAL_ERROR
    "missing selected-configuration image did not fail closed:\n"
    "${_missing_image_output}${_missing_image_error}")
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

set(_runtime_fixture
  "${CMAKE_CURRENT_BINARY_DIR}/pure-reduce-runtime-fixture")
set(_contract_upstream_root "${PURE_REDUCE_UPSTREAM_BINARY_DIR}")
file(REMOVE_RECURSE "${_runtime_fixture}")
file(MAKE_DIRECTORY
  "${_runtime_fixture}/source/cslbuild/x86_64-pc-windows-nogui/csl/reduce.resources"
  "${_runtime_fixture}/source/cslbuild/x86_64-pc-windows-nogui/csl/reduce.fonts")
file(WRITE
  "${_runtime_fixture}/source/cslbuild/x86_64-pc-windows-nogui/csl/config.h"
  "/* #undef RAW_CYGWIN */\n")
file(WRITE
  "${_runtime_fixture}/source/cslbuild/x86_64-pc-windows-nogui/Makefile"
  "all:\n")
file(WRITE
  "${_runtime_fixture}/source/cslbuild/x86_64-pc-windows-nogui/csl/reduce.img"
  "fixture image")
file(WRITE
  "${_runtime_fixture}/source/cslbuild/x86_64-pc-windows-nogui/csl/reduce.resources/data"
  "resource")
file(WRITE
  "${_runtime_fixture}/source/cslbuild/x86_64-pc-windows-nogui/csl/reduce.fonts/font"
  "font")
set(PURE_REDUCE_UPSTREAM_BINARY_DIR "${_runtime_fixture}")
_pure_reduce_run_runtime_artifact_refresh()
file(REMOVE_RECURSE
  "${_runtime_fixture}/artifacts/runtime/reduce.resources")
_pure_reduce_run_runtime_artifact_refresh()
if(NOT EXISTS
    "${_runtime_fixture}/artifacts/runtime/reduce.resources/data" OR
   NOT EXISTS
    "${_runtime_fixture}/artifacts/runtime/reduce.resources.manifest" OR
   NOT EXISTS
    "${_runtime_fixture}/artifacts/runtime/reduce.fonts.manifest")
  message(FATAL_ERROR "runtime manifest contract did not restore deleted data")
endif()
file(REMOVE_RECURSE "${_runtime_fixture}")
set(PURE_REDUCE_UPSTREAM_BINARY_DIR "${_contract_upstream_root}")

foreach(path IN ITEMS
    "${PURE_REDUCE_CSL_IMAGE}"
    ${PURE_REDUCE_CSL_LINK_ARTIFACTS}
    ${PURE_REDUCE_RUNTIME_MANIFESTS}
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
if(NOT PURE_REDUCE_RUNTIME_MANIFESTS)
  message(FATAL_ERROR "CSL runtime manifests are empty")
endif()
if(NOT PURE_REDUCE_RUNTIME_DATA)
  message(FATAL_ERROR "CSL runtime data is empty")
endif()

set(_artifact_contract_log
  "${PURE_REDUCE_UPSTREAM_BINARY_DIR}/logs/artifact-contract.log")
  foreach(_artifact IN ITEMS
      "${PURE_REDUCE_CSL_IMAGE}"
      ${PURE_REDUCE_CSL_LINK_ARTIFACTS}
      ${PURE_REDUCE_RUNTIME_MANIFESTS}
      "${PURE_REDUCE_UPSTREAM_METRICS}"
      "${PURE_REDUCE_UPSTREAM_BINARY_DIR}/logs/artifact-contract-probe.exe")
    if(NOT EXISTS "${_artifact}" OR IS_DIRECTORY "${_artifact}")
      message(FATAL_ERROR "built upstream artifact is missing: ${_artifact}")
    endif()
    file(SIZE "${_artifact}" _artifact_size)
    if(_artifact_size LESS 16)
      message(FATAL_ERROR "built upstream artifact is empty: ${_artifact}")
    endif()
  endforeach()
  if(NOT EXISTS "${PURE_REDUCE_CSL_IMAGE}")
    message(FATAL_ERROR "built upstream image is missing")
  endif()
  file(SIZE "${PURE_REDUCE_CSL_IMAGE}" _image_size)
  if(_image_size LESS 1000000)
    message(FATAL_ERROR "built upstream image is not a complete CSL image")
  endif()
  foreach(_runtime IN LISTS PURE_REDUCE_RUNTIME_DATA)
    if(NOT IS_DIRECTORY "${_runtime}")
      message(FATAL_ERROR "built upstream runtime directory is missing: ${_runtime}")
    endif()
    file(GLOB_RECURSE _runtime_files LIST_DIRECTORIES FALSE "${_runtime}/*")
    if(NOT _runtime_files)
      message(FATAL_ERROR "built upstream runtime directory is empty: ${_runtime}")
    endif()
  endforeach()
  file(READ "${PURE_REDUCE_UPSTREAM_METRICS}" _metrics)
  string(JSON _metrics_commit GET "${_metrics}" commit)
  string(JSON _metrics_tree GET "${_metrics}" source_tree_sha256)
  string(JSON _object_count GET "${_metrics}" link_closure object_count)
  if(NOT _metrics_commit STREQUAL PURE_REDUCE_VERIFIED_COMMIT OR
      NOT _metrics_tree STREQUAL PURE_REDUCE_SOURCE_TREE_SHA256 OR
      _object_count LESS 50)
    message(FATAL_ERROR "built upstream metrics do not describe the verified build")
  endif()
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
  if(NOT _artifact_contract MATCHES "imports:[\r\n]+[^\r\n]+[.]dll")
    message(FATAL_ERROR "artifact import assertion has no inspected DLLs")
  endif()
  set(_consumer_source
    "${CMAKE_CURRENT_BINARY_DIR}/pure-reduce-link-interface-consumer.cpp")
  set(_consumer_executable
    "${CMAKE_CURRENT_BINARY_DIR}/pure-reduce-link-interface-consumer.exe")
  file(WRITE "${_consumer_source}" [=[
extern "C" int PROC_clear_stack();
namespace CSL_LISP {
using character_writer = int(int);
void cslstart(int, const char*[], character_writer*);
}
int main() {
  void (*volatile start)(int, const char*[], CSL_LISP::character_writer*) =
      &CSL_LISP::cslstart;
  return PROC_clear_stack() + (start == nullptr);
}
]=])
  set(_consumer_script [=[
set -eu
export MSYSTEM=CLANG64
export PATH=/clang64/bin:/usr/bin
source_file=$(cygpath -u "$1")
output_file=$(cygpath -u "$2")
shift 2
args=()
for arg in "$@"; do
  case "$arg" in
    [A-Za-z]:/*) args+=("$(cygpath -u "$arg")") ;;
    *) args+=("$arg") ;;
  esac
done
clang++ -std=gnu++26 -flto -O3 "$source_file" "${args[@]}" -o "$output_file"
llvm-nm -C --defined-only "$output_file" | grep -q 'PROC_clear_stack$'
llvm-nm -C --defined-only "$output_file" | grep -q 'CSL_LISP::cslstart('
imports=$(llvm-readobj --coff-imports "$output_file" | sed -n 's/^  Name: //p')
if printf '%s\n' "$imports" | grep -Eiq \
    '(^|/)(msys|cygwin|zlib|libstdc\+\+|libwinpthread|ncurses)'; then
  exit 1
fi
printf 'ordered_link_interface=linked\n'
printf 'PROC_clear_stack=defined\n'
printf 'CSL_LISP::cslstart=defined\n'
printf 'non_system_runtime_imports=none\n'
]=])
  execute_process(
    COMMAND "${PURE_REDUCE_MSYS2_BASH}" --noprofile --norc -c
      "${_consumer_script}" pure-reduce
      "${_consumer_source}" "${_consumer_executable}"
      ${PURE_REDUCE_CSL_LINK_INTERFACE}
    RESULT_VARIABLE _consumer_result
    OUTPUT_VARIABLE _consumer_output ERROR_VARIABLE _consumer_error)
  file(REMOVE "${_consumer_source}" "${_consumer_executable}")
  if(NOT _consumer_result EQUAL 0 OR
     NOT _consumer_output MATCHES "ordered_link_interface=linked" OR
     NOT _consumer_output MATCHES "non_system_runtime_imports=none")
    message(FATAL_ERROR
      "exported CSL link interface is not independently consumable:\n"
      "${_consumer_output}${_consumer_error}")
  endif()
  foreach(_manifest IN LISTS PURE_REDUCE_RUNTIME_MANIFESTS)
    file(STRINGS "${_manifest}" _manifest_lines LIMIT_COUNT 1)
    string(REGEX MATCH "^[0-9a-f]+" _manifest_hash "${_manifest_lines}")
    string(LENGTH "${_manifest_hash}" _manifest_hash_length)
    if(NOT _manifest_hash_length EQUAL 64)
      message(FATAL_ERROR "runtime manifest has no SHA-256 entries: ${_manifest}")
    endif()
  endforeach()

message(STATUS "pure-reduce upstream contract passed")
