cmake_minimum_required(VERSION 3.25)

foreach(_required IN ITEMS REDUCE_UPSTREAM_MODULE)
  if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
    message(FATAL_ERROR "${_required} is required")
  endif()
endforeach()

include("${REDUCE_UPSTREAM_MODULE}")

set(_commit "7efba90661139ae9c73c99fddd55f3fb2fabf69a")
set(_tree "134a68fdb10403d3a4c69051eb4e133803ff2659784f2d38ac4d94c7ee9f86d8")
if(PURE_REDUCE_IDENTITY_PROBE STREQUAL "install")
  pure_reduce_verify_upstream_install_contract(
    "${PURE_REDUCE_IDENTITY_PROBE_ROOT}" "${_commit}" "${_tree}"
    "${PURE_REDUCE_IDENTITY_PROBE_IMAGE}")
  return()
endif()
set(_root "$ENV{TEMP}/pure-reduce-upstream-cache-identity")
if(_root STREQUAL "/pure-reduce-upstream-cache-identity")
  set(_root "${CMAKE_CURRENT_BINARY_DIR}/pure-reduce-upstream-cache-identity")
endif()
get_filename_component(_root "${_root}" ABSOLUTE)

set(_static_relatives
  artifacts/reduce.img
  artifacts/include/proc.h
  artifacts/link/libreduce-csl.a
  artifacts/link/libcrlibm.a
  artifacts/link/libffi.a
  artifacts/install-inputs/csl/cslbase/COPYING
  artifacts/install-inputs/csl/cslbase/cm-unicode/LICENSE
  artifacts/install-inputs/libraries/crlibm/COPYING
  artifacts/install-inputs/libraries/crlibm/COPYING.LIB
  artifacts/install-inputs/libraries/libffi/LICENSE
  artifacts/runtime/reduce.resources/mma.awk
  artifacts/runtime/reduce.resources.manifest
  artifacts/runtime/reduce.fonts/fonts.dir
  artifacts/runtime/reduce.fonts.manifest
  toolchain-packages.tsv
  reduce-upstream-metrics.json
  pure-reduce-upstream.stamp
  pure-reduce-upstream.recipe
  logs/artifact-contract-probe.exe
  logs/artifact-contract.log)

function(_write_payload ROOT RELATIVE MARKER)
  set(_path "${ROOT}/${RELATIVE}")
  cmake_path(GET _path PARENT_PATH _parent)
  file(MAKE_DIRECTORY "${_parent}")
  string(LENGTH "${MARKER}" _length)
  string(REPEAT "x" 64 _padding)
  file(WRITE "${_path}" "${MARKER}:${_padding}\n")
endfunction()

function(_write_fixture ROOT)
  file(REMOVE_RECURSE "${ROOT}")
  foreach(_relative IN LISTS _static_relatives)
    _write_payload("${ROOT}" "${_relative}" "golden-${_relative}")
  endforeach()
  _pure_reduce_write_directory_manifest(
    "${ROOT}/artifacts/runtime/reduce.resources"
    "${ROOT}/artifacts/runtime/reduce.resources.manifest")
  _pure_reduce_write_directory_manifest(
    "${ROOT}/artifacts/runtime/reduce.fonts"
    "${ROOT}/artifacts/runtime/reduce.fonts.manifest")
  _pure_reduce_expected_upstream_stamp("${_commit}" "${_tree}" _stamp)
  file(WRITE "${ROOT}/pure-reduce-upstream.stamp" "${_stamp}")
  file(WRITE "${ROOT}/pure-reduce-upstream.recipe"
    "${_PURE_REDUCE_BUILD_RECIPE_VERSION}\n")
  file(COPY_FILE "${ROOT}/toolchain-packages.tsv"
    "${ROOT}/toolchain-provenance-test-override.tsv")
  if(COMMAND _pure_reduce_write_upstream_identity)
    _pure_reduce_write_upstream_identity("${ROOT}")
  endif()
endfunction()

set_property(GLOBAL PROPERTY PURE_REDUCE_IDENTITY_REBUILDS 0)
function(_pure_reduce_run_upstream_build)
  get_property(_count GLOBAL PROPERTY PURE_REDUCE_IDENTITY_REBUILDS)
  math(EXPR _count "${_count} + 1")
  set_property(GLOBAL PROPERTY PURE_REDUCE_IDENTITY_REBUILDS "${_count}")
  _write_fixture("${PURE_REDUCE_UPSTREAM_BINARY_DIR}")
endfunction()

function(_ensure EXPECTED_REBUILDS LABEL)
  _pure_reduce_run_upstream_build_ensure()
  get_property(_actual GLOBAL PROPERTY PURE_REDUCE_IDENTITY_REBUILDS)
  if(NOT _actual EQUAL EXPECTED_REBUILDS)
    message(FATAL_ERROR
      "${LABEL}: expected ${EXPECTED_REBUILDS} rebuild(s), got ${_actual}")
  endif()
endfunction()

function(_same_size_substitute PATH)
  file(SIZE "${PATH}" _bytes)
  string(REPEAT "z" ${_bytes} _replacement)
  file(WRITE "${PATH}" "${_replacement}")
endfunction()

function(_expect_install_rejection ROOT IMAGE EXPECTED)
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DREDUCE_UPSTREAM_MODULE=${REDUCE_UPSTREAM_MODULE}"
      -DPURE_REDUCE_IDENTITY_PROBE=install
      "-DPURE_REDUCE_IDENTITY_PROBE_ROOT=${ROOT}"
      "-DPURE_REDUCE_IDENTITY_PROBE_IMAGE=${IMAGE}"
      -P "${CMAKE_CURRENT_LIST_FILE}"
    RESULT_VARIABLE _result
    OUTPUT_VARIABLE _output
    ERROR_VARIABLE _error
    ENCODING UTF-8)
  if(_result EQUAL 0 OR NOT "${_output}\n${_error}" MATCHES "${EXPECTED}")
    message(FATAL_ERROR
      "expected direct-install identity rejection '${EXPECTED}'\n"
      "stdout:\n${_output}\nstderr:\n${_error}")
  endif()
endfunction()

set(PURE_REDUCE_UPSTREAM_BINARY_DIR "${_root}")
set(PURE_REDUCE_SOURCE_DIR "${_root}/unused-source")
set(PURE_REDUCE_MSYS2_BASH "unused-bash")
set(PURE_REDUCE_MAKE "unused-make")
set(PURE_REDUCE_VERIFIED_COMMIT "${_commit}")
set(PURE_REDUCE_SOURCE_TREE_SHA256 "${_tree}")
# Unit tests inject a stable live snapshot when the rolling provenance
# comparison is integrated into the build ensure path.
set(PURE_REDUCE_TOOLCHAIN_PROVENANCE_TEST_OVERRIDE
  "${_root}/toolchain-provenance-test-override.tsv")

foreach(_relative IN LISTS _static_relatives)
  _write_fixture("${_root}")
  set_property(GLOBAL PROPERTY PURE_REDUCE_IDENTITY_REBUILDS 0)
  _ensure(0 "intact cache for ${_relative}")
  _same_size_substitute("${_root}/${_relative}")
  _ensure(1 "same-size corruption for ${_relative}")
  _ensure(1 "revalidated cache for ${_relative}")
endforeach()

_write_fixture("${_root}")
set_property(GLOBAL PROPERTY PURE_REDUCE_IDENTITY_REBUILDS 0)
_same_size_substitute("${PURE_REDUCE_TOOLCHAIN_PROVENANCE_TEST_OVERRIDE}")
_ensure(1 "cached/live rolling toolchain mismatch")
_ensure(1 "revalidated cache after rolling toolchain mismatch")

_write_fixture("${_root}")
set_property(GLOBAL PROPERTY PURE_REDUCE_IDENTITY_REBUILDS 0)
_write_payload("${_root}" "artifacts/unexpected.bin" "unexpected")
_ensure(1 "unexpected artifacts entry")
_ensure(1 "revalidated cache after unexpected entry")

if(COMMAND _pure_reduce_write_upstream_identity)
  foreach(_identity_relative IN ITEMS
      pure-reduce-upstream-inputs.manifest
      pure-reduce-upstream.complete)
    _write_fixture("${_root}")
    set_property(GLOBAL PROPERTY PURE_REDUCE_IDENTITY_REBUILDS 0)
    _same_size_substitute("${_root}/${_identity_relative}")
    _ensure(1 "same-size ${_identity_relative} corruption")
    _ensure(1 "revalidated cache after ${_identity_relative} corruption")
  endforeach()

  _write_fixture("${_root}")
  set_property(GLOBAL PROPERTY PURE_REDUCE_IDENTITY_REBUILDS 0)
  file(REMOVE "${_root}/pure-reduce-upstream-inputs.manifest")
  _ensure(1 "missing identity manifest")
  _ensure(1 "revalidated cache after missing manifest")
endif()

_write_fixture("${_root}")
pure_reduce_verify_upstream_install_contract(
  "${_root}" "${_commit}" "${_tree}"
  "${_root}/artifacts/reduce.img")
file(COPY_FILE "${_root}/artifacts/reduce.img"
  "${_root}/outside-image.img")
_expect_install_rejection(
  "${_root}" "${_root}/outside-image.img" "does not match")

_write_fixture("${_root}")
_same_size_substitute("${_root}/pure-reduce-upstream.stamp")
_pure_reduce_write_upstream_identity("${_root}")
_expect_install_rejection(
  "${_root}" "${_root}/artifacts/reduce.img" "source/patch stamp")

_write_fixture("${_root}")
_same_size_substitute("${_root}/pure-reduce-upstream.recipe")
_pure_reduce_write_upstream_identity("${_root}")
_expect_install_rejection(
  "${_root}" "${_root}/artifacts/reduce.img" "exact build recipe")

file(REMOVE_RECURSE "${_root}")
message(STATUS "upstream cache content identity contract passed")
