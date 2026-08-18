cmake_minimum_required(VERSION 3.25)

foreach(_required IN ITEMS REDUCE_UPSTREAM_MODULE MSYS2_BASH)
  if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
    message(FATAL_ERROR "${_required} is required")
  endif()
endforeach()
include("${REDUCE_UPSTREAM_MODULE}")
set(PURE_REDUCE_MSYS2_BASH "${MSYS2_BASH}")
_pure_reduce_msys2_toolchain_commands(
  "${PURE_REDUCE_MSYS2_BASH}" _live_pacman _live_clang)
string(SHA256 _key "${CMAKE_CURRENT_BINARY_DIR}")
set(_driver_source
  "$ENV{TEMP}/pure-reduce-shared-driver-${_key}.cpp")
set(_driver_output_file
  "$ENV{TEMP}/pure-reduce-shared-driver-${_key}.dll")
file(WRITE "${_driver_source}" "int pure_reduce_driver_probe;\n")
execute_process(
  COMMAND "${_live_clang}" "-###" -shared "${_driver_source}"
    -o "${_driver_output_file}"
  RESULT_VARIABLE _driver_result
  OUTPUT_VARIABLE _driver_output
  ERROR_VARIABLE _driver_error
  ENCODING UTF-8)
if(NOT _driver_result EQUAL 0 OR
   NOT "${_driver_output}\n${_driver_error}" MATCHES
     "dllcrt2[.]o")
  message(FATAL_ERROR
    "CLANG64 shared-link driver trace does not select dllcrt2.o\n"
    "stdout:\n${_driver_output}\nstderr:\n${_driver_error}")
endif()
file(REMOVE "${_driver_source}" "${_driver_output_file}")
set(_snapshot "$ENV{TEMP}/pure-reduce-live-toolchain-${_key}.tsv")
if(_snapshot MATCHES "^/pure-reduce-live-toolchain-")
  set(_snapshot
    "${CMAKE_CURRENT_BINARY_DIR}/pure-reduce-live-toolchain-${_key}.tsv")
endif()
get_filename_component(_snapshot "${_snapshot}" ABSOLUTE)
file(REMOVE "${_snapshot}")
_pure_reduce_capture_live_toolchain_provenance("${_snapshot}")
pure_reduce_validate_toolchain_provenance(
  "${_snapshot}" "${CMAKE_CURRENT_LIST_DIR}/../licenses" _records)
foreach(_record IN LISTS _records)
  string(REPLACE "|" ";" _fields "${_record}")
  list(GET _fields 0 _package)
  list(GET _fields 1 _version)
  message(STATUS "live toolchain package ${_package}=${_version}")
endforeach()
file(REMOVE "${_snapshot}")
message(STATUS "live rolling CLANG64 toolchain provenance passed")
