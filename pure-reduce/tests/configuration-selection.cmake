cmake_minimum_required(VERSION 3.25)

if(NOT DEFINED REDUCE_UPSTREAM_MODULE OR
    "${REDUCE_UPSTREAM_MODULE}" STREQUAL "")
  message(FATAL_ERROR "REDUCE_UPSTREAM_MODULE is required")
endif()

include("${REDUCE_UPSTREAM_MODULE}")
string(SHA256 _root_key "${CMAKE_CURRENT_BINARY_DIR}")
file(TO_CMAKE_PATH
  "$ENV{TEMP}/pure reduce configuration selection-${_root_key}" _root)
file(REMOVE_RECURSE "${_root}")

set(_cygwin "${_root}/cslbuild/x86_64-pc-cygwin-nogui/cyg64")
set(_windows "${_root}/cslbuild/x86_64-pc-windows-nogui/win64")
set(_legacy_windows "${_root}/cslbuild/x86_64-pc-windows-legacy")
file(MAKE_DIRECTORY "${_cygwin}/csl" "${_windows}/csl")
file(WRITE "${_cygwin}/csl/config.h" "#define RAW_CYGWIN 1\n")
file(WRITE "${_cygwin}/Makefile" "all:\n")
file(WRITE "${_windows}/csl/config.h" "/* #undef RAW_CYGWIN */\n")
file(WRITE "${_windows}/Makefile" "all:\n")
file(MAKE_DIRECTORY "${_legacy_windows}/csl")
file(WRITE "${_legacy_windows}/csl/config.h" "/* #undef RAW_CYGWIN */\n")
file(WRITE "${_legacy_windows}/Makefile" "all:\n")

_pure_reduce_select_windows_configuration("${_root}" _selected)
if(NOT _selected STREQUAL _windows)
  file(REMOVE_RECURSE "${_root}")
  message(FATAL_ERROR
    "selected the wrong pinned REDUCE Windows configuration: ${_selected}")
endif()

file(REMOVE "${_windows}/Makefile")
file(TO_CMAKE_PATH "${REDUCE_UPSTREAM_MODULE}" _module)
file(WRITE "${_root}/reject-incomplete.cmake"
  "include(\"${_module}\")\n"
  "_pure_reduce_select_windows_configuration(\n"
  "  \"${_root}\" _selected)\n")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -P "${_root}/reject-incomplete.cmake"
  RESULT_VARIABLE _incomplete_result
  OUTPUT_VARIABLE _incomplete_output
  ERROR_VARIABLE _incomplete_error
  ENCODING UTF-8)
if(_incomplete_result EQUAL 0 OR
    NOT "${_incomplete_output}${_incomplete_error}" MATCHES
      "x86_64-pc-windows-nogui/win64: config.h=yes, Makefile=no")
  file(REMOVE_RECURSE "${_root}")
  message(FATAL_ERROR
    "incomplete-configuration diagnostic omitted candidate evidence:\n"
    "${_incomplete_output}${_incomplete_error}")
endif()

file(REMOVE_RECURSE "${_root}")
