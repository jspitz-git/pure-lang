cmake_minimum_required(VERSION 3.25)

foreach(_required IN ITEMS SOURCE_DIR RUNTIME_ROOT TEST_ROOT)
  if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
    message(FATAL_ERROR "${_required} is required")
  endif()
endforeach()

set(PURE_REDUCE_INSTALL_CONTRACT_ONLY ON)
include("${SOURCE_DIR}/cmake/Install.cmake")

if(PURE_REDUCE_CONTRACT_PROBE STREQUAL "manifest")
  pure_reduce_verify_runtime_manifest(
    "${PROBE_DIRECTORY}" "${PROBE_MANIFEST}" _unused)
  message(FATAL_ERROR "runtime manifest mutation unexpectedly passed")
elseif(PURE_REDUCE_CONTRACT_PROBE STREQUAL "relative")
  _pure_reduce_validate_relative_path("${PROBE_VALUE}" "probe relative path")
  message(FATAL_ERROR "unsafe relative path unexpectedly passed")
elseif(PURE_REDUCE_CONTRACT_PROBE STREQUAL "source")
  _pure_reduce_validate_source_file("${PROBE_VALUE}" "probe source path")
  message(FATAL_ERROR "unsafe source path unexpectedly passed")
elseif(PURE_REDUCE_CONTRACT_PROBE STREQUAL "mapping-missing")
  _pure_reduce_lookup_runtime_dll(
    "${TEST_ROOT}/unmapped.dll" _origin _version _license _destination)
  message(FATAL_ERROR "unmapped runtime DLL unexpectedly passed")
elseif(PURE_REDUCE_CONTRACT_PROBE STREQUAL "mapping-unsafe")
  pure_reduce_register_runtime_dll(
    NAME fixture.dll
    ORIGIN "unsafe|origin"
    VERSION 1
    LICENSE_SOURCE "${SOURCE_DIR}/licenses/ZLIB-LICENSE.txt"
    LICENSE_DESTINATION share/doc/pure-reduce/licenses/ZLIB-LICENSE.txt)
  message(FATAL_ERROR "unsafe runtime DLL mapping unexpectedly passed")
elseif(PURE_REDUCE_CONTRACT_PROBE STREQUAL "licenses")
  pure_reduce_verify_vendored_toolchain_licenses("${PROBE_VALUE}")
  message(FATAL_ERROR "mutated vendored license unexpectedly passed")
endif()

foreach(_required IN ITEMS CXX_COMPILER LLVM_READOBJ REDUCE_IMAGE)
  if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
    message(FATAL_ERROR "${_required} is required")
  endif()
endforeach()

function(_expect_probe_rejection MODE EXPECTED)
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${SOURCE_DIR}"
      "-DRUNTIME_ROOT=${RUNTIME_ROOT}"
      "-DTEST_ROOT=${TEST_ROOT}"
      "-DPURE_REDUCE_CONTRACT_PROBE=${MODE}"
      "-DPROBE_DIRECTORY=${PROBE_DIRECTORY}"
      "-DPROBE_MANIFEST=${PROBE_MANIFEST}"
      "-DPROBE_VALUE=${PROBE_VALUE}"
      -P "${CMAKE_CURRENT_LIST_FILE}"
    RESULT_VARIABLE _result
    OUTPUT_VARIABLE _output
    ERROR_VARIABLE _error
    ENCODING UTF-8)
  if(_result EQUAL 0 OR NOT _error MATCHES "${EXPECTED}")
    message(FATAL_ERROR
      "expected ${MODE} rejection '${EXPECTED}'\n"
      "stdout:\n${_output}\nstderr:\n${_error}")
  endif()
endfunction()

function(_fresh_resource_fixture)
  file(REMOVE_RECURSE "${TEST_ROOT}/runtime")
  file(MAKE_DIRECTORY "${TEST_ROOT}/runtime")
  file(COPY "${RUNTIME_ROOT}/reduce.resources"
    DESTINATION "${TEST_ROOT}/runtime")
  file(COPY_FILE "${RUNTIME_ROOT}/reduce.resources.manifest"
    "${TEST_ROOT}/runtime/reduce.resources.manifest")
  set(PROBE_DIRECTORY "${TEST_ROOT}/runtime/reduce.resources" PARENT_SCOPE)
  set(PROBE_MANIFEST
    "${TEST_ROOT}/runtime/reduce.resources.manifest" PARENT_SCOPE)
endfunction()

_fresh_resource_fixture()
file(APPEND "${PROBE_DIRECTORY}/mma.awk" "mutation")
_expect_probe_rejection("manifest" "runtime manifest hash/size mismatch")

_fresh_resource_fixture()
file(REMOVE "${PROBE_DIRECTORY}/qepcad.awk")
_expect_probe_rejection("manifest" "runtime manifest file")

_fresh_resource_fixture()
file(WRITE "${PROBE_DIRECTORY}/extra.awk" "extra\n")
_expect_probe_rejection("manifest" "runtime manifest content mismatch")

_fresh_resource_fixture()
file(WRITE "${PROBE_DIRECTORY}/evil;source.asm.gz" "source\n")
_expect_probe_rejection("manifest"
  "forbidden serialization delimiter|runtime manifest content mismatch")

set(PROBE_VALUE "../escape")
_expect_probe_rejection("relative" "unsafe probe relative path")
set(PROBE_VALUE "safe;split")
_expect_probe_rejection("relative" "forbidden serialization delimiter")
set(PROBE_VALUE "safe|split")
_expect_probe_rejection("relative" "forbidden serialization delimiter")
set(PROBE_VALUE "C:/absolute/destination")
_expect_probe_rejection("relative" "unsafe probe relative path")
string(ASCII 9 _tab)
set(PROBE_VALUE "safe${_tab}split")
_expect_probe_rejection("relative" "forbidden serialization delimiter")
string(ASCII 13 _carriage_return)
set(PROBE_VALUE "safe${_carriage_return}split")
_expect_probe_rejection("relative" "forbidden serialization delimiter")
string(ASCII 10 _line_feed)
set(PROBE_VALUE "safe${_line_feed}split")
_expect_probe_rejection("relative" "forbidden serialization delimiter")
set(PROBE_VALUE "C:/unsafe;source.txt")
_expect_probe_rejection("source" "forbidden serialization delimiter")
set(PROBE_VALUE "${SOURCE_DIR}/licenses/../licenses/ZLIB-LICENSE.txt")
_expect_probe_rejection("source" "existing canonical absolute file")
set(PROBE_VALUE "")
_expect_probe_rejection("mapping-missing" "no explicit origin/version/license mapping")
_expect_probe_rejection("mapping-unsafe" "forbidden serialization delimiter")

file(REMOVE_RECURSE "${TEST_ROOT}/license fixture")
file(MAKE_DIRECTORY "${TEST_ROOT}/license fixture")
file(COPY "${SOURCE_DIR}/licenses"
  DESTINATION "${TEST_ROOT}/license fixture")
file(APPEND "${TEST_ROOT}/license fixture/licenses/ZLIB-LICENSE.txt" "mutation")
set(PROBE_VALUE "${TEST_ROOT}/license fixture")
_expect_probe_rejection("licenses" "vendored toolchain license hash mismatch")

pure_reduce_register_runtime_dll(
  NAME fixture.dll
  ORIGIN "fixture package"
  VERSION 1.2.3
  LICENSE_SOURCE "${SOURCE_DIR}/licenses/ZLIB-LICENSE.txt"
  LICENSE_DESTINATION share/doc/pure-reduce/licenses/FIXTURE-LICENSE.txt)
_pure_reduce_lookup_runtime_dll(
  "${TEST_ROOT}/fixture.dll"
  _origin _version _license_source _license_destination)
if(NOT _origin STREQUAL "fixture package" OR
    NOT _version STREQUAL "1.2.3" OR
    NOT _license_source STREQUAL
      "${SOURCE_DIR}/licenses/ZLIB-LICENSE.txt" OR
    NOT _license_destination STREQUAL
      "share/doc/pure-reduce/licenses/FIXTURE-LICENSE.txt")
  message(FATAL_ERROR "runtime DLL mapping lookup changed metadata")
endif()

set(_mapped_root "${TEST_ROOT}/mapped package root")
set(_mapped_upstream "${_mapped_root}/upstream")
set(_mapped_binary "${_mapped_root}/binary")
set(_mapped_stage "${_mapped_root}/stage")
file(REMOVE_RECURSE "${_mapped_root}")
file(MAKE_DIRECTORY
  "${_mapped_upstream}/artifacts"
  "${_mapped_upstream}/artifacts/install-inputs/csl/cslbase/cm-unicode"
  "${_mapped_upstream}/artifacts/install-inputs/libraries/crlibm"
  "${_mapped_upstream}/artifacts/install-inputs/libraries/libffi"
  "${_mapped_binary}")
file(COPY "${RUNTIME_ROOT}"
  DESTINATION "${_mapped_upstream}/artifacts")
file(COPY_FILE "${RUNTIME_ROOT}/../../reduce-upstream-metrics.json"
  "${_mapped_upstream}/reduce-upstream-metrics.json")
file(COPY_FILE
  "${RUNTIME_ROOT}/../install-inputs/csl/cslbase/COPYING"
  "${_mapped_upstream}/artifacts/install-inputs/csl/cslbase/COPYING")
file(COPY_FILE
  "${RUNTIME_ROOT}/../install-inputs/csl/cslbase/cm-unicode/LICENSE"
  "${_mapped_upstream}/artifacts/install-inputs/csl/cslbase/cm-unicode/LICENSE")
file(COPY_FILE
  "${RUNTIME_ROOT}/../install-inputs/libraries/crlibm/COPYING"
  "${_mapped_upstream}/artifacts/install-inputs/libraries/crlibm/COPYING")
file(COPY_FILE
  "${RUNTIME_ROOT}/../install-inputs/libraries/crlibm/COPYING.LIB"
  "${_mapped_upstream}/artifacts/install-inputs/libraries/crlibm/COPYING.LIB")
file(COPY_FILE
  "${RUNTIME_ROOT}/../install-inputs/libraries/libffi/LICENSE"
  "${_mapped_upstream}/artifacts/install-inputs/libraries/libffi/LICENSE")

set(_mapped_dependency_source "${_mapped_root}/mapped-dependency.cpp")
set(_mapped_root_source "${_mapped_root}/mapped-root.cpp")
set(_mapped_dependency "${_mapped_upstream}/synthetic+audit.dll")
set(_mapped_import "${_mapped_root}/synthetic+audit.dll.a")
set(_mapped_dll "${_mapped_root}/mapped-root.dll")
file(WRITE "${_mapped_dependency_source}"
  "extern \"C\" __declspec(dllexport) int mapped_value() { return 9; }\n")
file(WRITE "${_mapped_root_source}"
  "extern \"C\" __declspec(dllimport) int mapped_value();\n"
  "extern \"C\" __declspec(dllexport) int mapped_root() { return mapped_value(); }\n")
execute_process(
  COMMAND "${CXX_COMPILER}" -shared "${_mapped_dependency_source}"
    -o "${_mapped_dependency}" "-Wl,--out-implib,${_mapped_import}"
  RESULT_VARIABLE _mapped_dependency_result
  ERROR_VARIABLE _mapped_dependency_error
  ENCODING UTF-8)
if(NOT _mapped_dependency_result EQUAL 0)
  message(FATAL_ERROR
    "mapped dependency build failed: ${_mapped_dependency_error}")
endif()
execute_process(
  COMMAND "${CXX_COMPILER}" -shared "${_mapped_root_source}"
    "${_mapped_import}" -o "${_mapped_dll}"
  RESULT_VARIABLE _mapped_root_result
  ERROR_VARIABLE _mapped_root_error
  ENCODING UTF-8)
if(NOT _mapped_root_result EQUAL 0)
  message(FATAL_ERROR "mapped root build failed: ${_mapped_root_error}")
endif()
set(_mapped_mapping_file "${_mapped_root}/RuntimeDllMappings.cmake")
file(WRITE "${_mapped_mapping_file}"
  "pure_reduce_register_runtime_dll(\n"
  "  NAME synthetic+audit.dll\n"
  "  ORIGIN \"fixture package\"\n"
  "  VERSION 1.2.3\n"
  "  LICENSE_SOURCE \"${SOURCE_DIR}/licenses/ZLIB-LICENSE.txt\"\n"
  "  LICENSE_DESTINATION share/doc/pure-reduce/licenses/FIXTURE-LICENSE.txt)\n")
cmake_path(GET LLVM_READOBJ PARENT_PATH _clang_bin)
cmake_path(GET _clang_bin PARENT_PATH _clang_root)
execute_process(
  COMMAND "${CMAKE_COMMAND}"
    -DPURE_REDUCE_RUN_COMPONENT_INSTALL=ON
    "-DPURE_REDUCE_SOURCE_ROOT=${SOURCE_DIR}"
    "-DPURE_REDUCE_BINARY_ROOT=${_mapped_binary}"
    "-DPURE_REDUCE_UPSTREAM_BINARY_DIR=${_mapped_upstream}"
    "-DPURE_REDUCE_DLL=${_mapped_dll}"
    "-DPURE_REDUCE_IMAGE=${REDUCE_IMAGE}"
    "-DPURE_REDUCE_LLVM_READOBJ=${LLVM_READOBJ}"
    "-DPURE_REDUCE_CLANG64_ROOT=${_clang_root}"
    "-DPURE_REDUCE_RUNTIME_DLL_MAPPING_FILE=${_mapped_mapping_file}"
    "-DPURE_REDUCE_INSTALL_PREFIX=${_mapped_stage}"
    -DPURE_REDUCE_LIBRARY_INSTALL_DIR=lib/pure
    -DPURE_REDUCE_RUNTIME_INSTALL_DIR=bin
    -DPURE_REDUCE_DOCUMENTATION_INSTALL_DIR=share/doc/pure-reduce
    -P "${SOURCE_DIR}/cmake/Install.cmake"
  RESULT_VARIABLE _mapped_install_result
  OUTPUT_VARIABLE _mapped_install_output
  ERROR_VARIABLE _mapped_install_error
  ENCODING UTF-8)
if(NOT _mapped_install_result EQUAL 0)
  message(FATAL_ERROR
    "mapped runtime DLL package failed (${_mapped_install_result})\n"
    "stdout:\n${_mapped_install_output}\n"
    "stderr:\n${_mapped_install_error}")
endif()
foreach(_mapped_installed IN ITEMS
    "${_mapped_stage}/bin/synthetic+audit.dll"
    "${_mapped_stage}/share/doc/pure-reduce/licenses/FIXTURE-LICENSE.txt")
  if(NOT EXISTS "${_mapped_installed}")
    message(FATAL_ERROR "mapped runtime payload was not installed: ${_mapped_installed}")
  endif()
endforeach()
file(STRINGS "${_mapped_binary}/PureReduceExpected.sha256"
  _mapped_expected)
if(NOT _mapped_expected MATCHES "  bin/synthetic\\+audit\\.dll" OR
    NOT _mapped_expected MATCHES
      "  share/doc/pure-reduce/licenses/FIXTURE-LICENSE\\.txt")
  message(FATAL_ERROR "mapped runtime payload is absent from authoritative SHA")
endif()

message(STATUS
  "PureReduce runtime manifest, path, and DLL mapping mutations rejected")
