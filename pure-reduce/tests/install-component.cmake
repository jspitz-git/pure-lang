cmake_minimum_required(VERSION 3.25)

foreach(_required IN ITEMS BUILD_DIR STAGE_PREFIX)
  if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
    message(FATAL_ERROR "${_required} is required")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH BUILD_DIR NORMALIZE OUTPUT_VARIABLE _build_dir)
cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE _stage)
set(_default_stage "${_stage}-default-install")
file(REMOVE_RECURSE "${_stage}" "${_default_stage}")

execute_process(
  COMMAND "${CMAKE_COMMAND}" --install "${_build_dir}"
    --prefix "${_default_stage}"
  RESULT_VARIABLE _default_result
  OUTPUT_VARIABLE _default_output
  ERROR_VARIABLE _default_error
  ENCODING UTF-8)
if(NOT _default_result EQUAL 0)
  message(FATAL_ERROR
    "default install failed (${_default_result})\n"
    "stdout:\n${_default_output}\nstderr:\n${_default_error}")
endif()
file(GLOB_RECURSE _default_files LIST_DIRECTORIES FALSE "${_default_stage}/*")
if(_default_files)
  message(FATAL_ERROR
    "PureReduce leaked into the default install: ${_default_files}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" --install "${_build_dir}"
    --prefix "${_stage}" --component PureReduce
  RESULT_VARIABLE _install_result
  OUTPUT_VARIABLE _install_output
  ERROR_VARIABLE _install_error
  ENCODING UTF-8)
if(NOT _install_result EQUAL 0)
  message(FATAL_ERROR
    "PureReduce component install failed (${_install_result})\n"
    "stdout:\n${_install_output}\nstderr:\n${_install_error}")
endif()

set(_expected_manifest "${_build_dir}/PureReduceExpected.sha256")
set(_inventory "${_build_dir}/PureReduceInventory.tsv")
foreach(_required_file IN ITEMS "${_expected_manifest}" "${_inventory}")
  if(NOT EXISTS "${_required_file}")
    message(FATAL_ERROR "missing authoritative inventory: ${_required_file}")
  endif()
endforeach()

file(STRINGS "${_expected_manifest}" _expected_lines)
file(STRINGS "${_inventory}" _inventory_lines)
list(POP_FRONT _inventory_lines _inventory_header)
if(NOT _inventory_header STREQUAL
    "relative_path\tpurpose\torigin\tsha256\tbytes\tlicense")
  message(FATAL_ERROR "malformed inventory header: ${_inventory_header}")
endif()

set(_expected_relative)
foreach(_line IN LISTS _expected_lines)
  string(LENGTH "${_line}" _line_length)
  if(_line_length LESS 67)
    message(FATAL_ERROR "malformed expected-manifest line: ${_line}")
  endif()
  string(SUBSTRING "${_line}" 0 64 _expected_sha)
  string(SUBSTRING "${_line}" 64 2 _separator)
  string(SUBSTRING "${_line}" 66 -1 _relative)
  if(NOT _expected_sha MATCHES "^[0-9a-f]+$" OR
      NOT _separator STREQUAL "  ")
    message(FATAL_ERROR "malformed expected-manifest line: ${_line}")
  endif()
  cmake_path(IS_ABSOLUTE _relative _absolute)
  string(REPLACE "/" ";" _segments "${_relative}")
  if(_absolute OR ".." IN_LIST _segments)
    message(FATAL_ERROR "unsafe expected-manifest path: ${_relative}")
  endif()
  if(NOT EXISTS "${_stage}/${_relative}" OR
      IS_DIRECTORY "${_stage}/${_relative}")
    message(FATAL_ERROR "manifest entry was not installed: ${_relative}")
  endif()
  file(SHA256 "${_stage}/${_relative}" _actual_sha)
  string(TOLOWER "${_actual_sha}" _actual_sha)
  if(NOT _actual_sha STREQUAL _expected_sha)
    message(FATAL_ERROR "installed hash mismatch: ${_relative}")
  endif()
  list(APPEND _expected_relative "${_relative}")
endforeach()
list(LENGTH _expected_relative _expected_count)
list(LENGTH _inventory_lines _inventory_count)
if(NOT _expected_count EQUAL _inventory_count)
  message(FATAL_ERROR
    "inventory and SHA manifest counts differ: "
    "${_inventory_count} vs ${_expected_count}")
endif()
string(ASCII 9 _tab)
foreach(_inventory_line IN LISTS _inventory_lines)
  string(REPLACE "${_tab}" ";" _fields "${_inventory_line}")
  list(LENGTH _fields _field_count)
  if(NOT _field_count EQUAL 6)
    message(FATAL_ERROR "malformed inventory row: ${_inventory_line}")
  endif()
  list(GET _fields 0 _inventory_relative)
  list(GET _fields 1 _inventory_purpose)
  list(GET _fields 2 _inventory_origin)
  list(GET _fields 3 _inventory_sha)
  list(GET _fields 4 _inventory_bytes)
  list(GET _fields 5 _inventory_license)
  if(NOT _inventory_relative IN_LIST _expected_relative OR
      _inventory_purpose STREQUAL "" OR _inventory_origin STREQUAL "" OR
      _inventory_license STREQUAL "" OR
      NOT _inventory_sha MATCHES "^[0-9a-f]+$" OR
      NOT _inventory_bytes MATCHES "^[0-9]+$")
    message(FATAL_ERROR "incomplete inventory row: ${_inventory_line}")
  endif()
  file(SHA256 "${_stage}/${_inventory_relative}" _installed_sha)
  file(SIZE "${_stage}/${_inventory_relative}" _installed_bytes)
  if(NOT _installed_sha STREQUAL _inventory_sha OR
      NOT _installed_bytes EQUAL _inventory_bytes)
    message(FATAL_ERROR
      "inventory metadata differs from installed file: ${_inventory_relative}")
  endif()
endforeach()

foreach(_required_relative IN ITEMS
    lib/pure/reduce.dll
    lib/pure/reduce.img
    lib/pure/reduce.pure
    lib/pure/reduce.resources/mma.awk
    lib/pure/reduce.resources/qepcad.awk
    share/doc/pure-reduce/README
    share/doc/pure-reduce/COPYING
    share/doc/pure-reduce/THIRD_PARTY.md
    share/doc/pure-reduce/PureReduceInventory.tsv
    share/doc/pure-reduce/pure-reduce-package-metrics.json
    share/doc/pure-reduce/runtime/reduce.resources.manifest
    share/doc/pure-reduce/runtime/reduce.fonts.manifest
    share/doc/pure-reduce/licenses/REDUCE-LICENSE.txt
    share/doc/pure-reduce/tests/smoke.pure
    share/doc/pure-reduce/tests/lifecycle.pure)
  if(NOT _required_relative IN_LIST _expected_relative)
    message(FATAL_ERROR
      "required PureReduce payload is missing: ${_required_relative}")
  endif()
endforeach()

file(GLOB_RECURSE _installed_files LIST_DIRECTORIES FALSE "${_stage}/*")
set(_installed_relative)
foreach(_installed IN LISTS _installed_files)
  file(RELATIVE_PATH _relative "${_stage}" "${_installed}")
  string(REPLACE "\\" "/" _relative "${_relative}")
  string(TOLOWER "${_relative}" _relative_lower)
  if(_relative_lower MATCHES "\\.(a|lib|o|obj|exe)$" OR
      _relative_lower MATCHES "(^|/)src/" OR
      _relative_lower MATCHES "\\.(asm\\.gz|tar|tar\\.gz|tar\\.bz2|tar\\.xz|zip)$" OR
      _relative_lower MATCHES
        "(^|/)(bash|sh|dash|zsh|fish|cmd|powershell|pwsh|make|ninja|pacman)(\\.exe)?$" OR
      _relative_lower MATCHES "(^|/)reduce\\.exe$")
    message(FATAL_ERROR "forbidden installed build tool/frontend: ${_relative}")
  endif()
  list(APPEND _installed_relative "${_relative}")
endforeach()
list(SORT _installed_relative COMPARE NATURAL CASE INSENSITIVE)
list(SORT _expected_relative COMPARE NATURAL CASE INSENSITIVE)
if(NOT _installed_relative STREQUAL _expected_relative)
  message(FATAL_ERROR
    "installed inventory differs from authoritative manifest\n"
    "installed: ${_installed_relative}\nexpected: ${_expected_relative}")
endif()

set(_installed_inventory
  "${_stage}/share/doc/pure-reduce/PureReduceInventory.tsv")
file(STRINGS "${_installed_inventory}" _installed_inventory_lines)
list(POP_FRONT _installed_inventory_lines _installed_inventory_header)
if(NOT _installed_inventory_header STREQUAL _inventory_header)
  message(FATAL_ERROR "installed inventory header differs")
endif()
math(EXPR _remaining_payload_count "${_expected_count} - 1")
list(LENGTH _installed_inventory_lines _installed_inventory_count)
if(NOT _installed_inventory_count EQUAL _remaining_payload_count)
  message(FATAL_ERROR
    "installed inventory must describe the remaining payload: "
    "${_installed_inventory_count} vs ${_remaining_payload_count}")
endif()
set(_expected_installed_inventory_lines)
foreach(_line IN LISTS _inventory_lines)
  if(NOT _line MATCHES
      "^share/doc/pure-reduce/PureReduceInventory\\.tsv\t")
    list(APPEND _expected_installed_inventory_lines "${_line}")
  endif()
endforeach()
if(NOT _installed_inventory_lines STREQUAL
    _expected_installed_inventory_lines)
  message(FATAL_ERROR
    "installed inventory does not exactly describe the remaining payload")
endif()

set(_required_reduce_dll_licenses
  REDUCE-LICENSE.txt
  COPYING
  CRLIBM-COPYING.LIB.txt
  LIBFFI-LICENSE.txt
  ZLIB-LICENSE.txt
  NCURSES-LICENSE.txt
  WINPTHREADS-COPYING.txt
  LIBCXX-LICENSE.txt
  LIBUNWIND-LICENSE.txt
  COMPILER-RT-LICENSE.txt
  MINGW-W64-CRT-COPYING.txt
  MINGW-W64-RUNTIME-COPYING.txt)
set(_reduce_dll_inventory_line "")
foreach(_line IN LISTS _inventory_lines)
  if(_line MATCHES "^lib/pure/reduce\\.dll\t")
    set(_reduce_dll_inventory_line "${_line}")
  endif()
endforeach()
foreach(_license_name IN LISTS _required_reduce_dll_licenses)
  if(NOT _reduce_dll_inventory_line MATCHES "${_license_name}")
    message(FATAL_ERROR
      "reduce.dll inventory omits applicable license: ${_license_name}")
  endif()
endforeach()

set(_metrics
  "${_stage}/share/doc/pure-reduce/pure-reduce-package-metrics.json")
file(READ "${_metrics}" _metrics_json)
foreach(_metric_key IN ITEMS
    commit source_tree_sha256 upstream_build_elapsed_seconds
    upstream_source_bytes upstream_build_tree_bytes link_object_count
    runtime_resource_count runtime_font_count installed_file_count)
  string(JSON _metric_value ERROR_VARIABLE _metric_error
    GET "${_metrics_json}" "${_metric_key}")
  if(_metric_error)
    message(FATAL_ERROR "package metrics omit ${_metric_key}: ${_metric_error}")
  endif()
endforeach()
if(_metrics_json MATCHES
    "(source_materialization|source_patches|tool_versions|logs|[A-Za-z]:[/\\\\])")
  message(FATAL_ERROR "package metrics contain non-deterministic path/build data")
endif()
string(JSON _metrics_installed_count GET
  "${_metrics_json}" installed_file_count)
if(NOT _metrics_installed_count EQUAL _expected_count)
  message(FATAL_ERROR
    "package metrics installed count differs: "
    "${_metrics_installed_count} vs ${_expected_count}")
endif()

set(_forbidden_prefixes "${_build_dir}" "${_stage}")
if(DEFINED SOURCE_PREFIX AND NOT "${SOURCE_PREFIX}" STREQUAL "")
  list(APPEND _forbidden_prefixes "${SOURCE_PREFIX}")
endif()
file(GLOB_RECURSE _installed_text_files LIST_DIRECTORIES FALSE
  "${_stage}/*.md" "${_stage}/*.txt" "${_stage}/*.json"
  "${_stage}/*.tsv" "${_stage}/*.manifest" "${_stage}/*.pure"
  "${_stage}/*.awk" "${_stage}/README" "${_stage}/COPYING")
foreach(_text_file IN LISTS _installed_text_files)
  file(READ "${_text_file}" _text)
  foreach(_prefix IN LISTS _forbidden_prefixes)
    file(TO_CMAKE_PATH "${_prefix}" _prefix_normalized)
    string(REPLACE "\\" "/" _text_normalized "${_text}")
    string(FIND "${_text_normalized}" "${_prefix_normalized}" _prefix_at)
    if(NOT _prefix_at EQUAL -1)
      message(FATAL_ERROR
        "installed text leaks source/build/stage prefix in ${_text_file}")
    endif()
  endforeach()
endforeach()

foreach(_runtime_var IN ITEMS PURE_EXECUTABLE PURE_LIBRARY_DIR TEST_DRIVER)
  if(NOT DEFINED ${_runtime_var} OR "${${_runtime_var}}" STREQUAL "")
    message(FATAL_ERROR "${_runtime_var} is required for installed smoke")
  endif()
endforeach()
execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
    "-DPURE_LIBRARY_DIR=${PURE_LIBRARY_DIR}"
    "-DPURE_SOURCE_DIR=${_stage}/lib/pure"
    "-DMODULE_DIR=${_stage}/lib/pure"
    "-DTEST_SCRIPT=${_stage}/share/doc/pure-reduce/tests/smoke.pure"
    "-DEXPECTED_MARKER=pure-reduce smoke passed"
    -P "${TEST_DRIVER}"
  RESULT_VARIABLE _smoke_result
  OUTPUT_VARIABLE _smoke_output
  ERROR_VARIABLE _smoke_error
  ENCODING UTF-8)
if(NOT _smoke_result EQUAL 0)
  message(FATAL_ERROR
    "installed PureReduce smoke failed (${_smoke_result})\n"
    "stdout:\n${_smoke_output}\nstderr:\n${_smoke_error}")
endif()

message(STATUS
  "verified optional PureReduce install: ${_expected_count} files and smoke")
