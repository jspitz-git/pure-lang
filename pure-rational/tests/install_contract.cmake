cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS
    SOURCE_DIR BINARY_DIR PURE_EXECUTABLE TEST_ROOT SMOKE_SCRIPT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

if(NOT EXISTS "${PURE_EXECUTABLE}")
  message(FATAL_ERROR "PURE_EXECUTABLE does not exist: ${PURE_EXECUTABLE}")
endif()

get_filename_component(binary_root "${BINARY_DIR}" ABSOLUTE)
get_filename_component(test_root "${TEST_ROOT}" ABSOLUTE)
cmake_path(IS_PREFIX binary_root "${test_root}" NORMALIZE test_root_is_safe)
if(NOT test_root_is_safe OR test_root STREQUAL binary_root)
  message(FATAL_ERROR "TEST_ROOT must be a child of BINARY_DIR")
endif()

get_filename_component(pure_bin_dir "${PURE_EXECUTABLE}" DIRECTORY)
get_filename_component(runtime_prefix "${pure_bin_dir}" DIRECTORY)
get_filename_component(pure_bin_name "${pure_bin_dir}" NAME)
if(NOT pure_bin_name STREQUAL "bin" OR
    NOT EXISTS "${runtime_prefix}/lib/pure/math.pure" OR
    NOT EXISTS "${runtime_prefix}/lib/pure/dict.pure")
  message(FATAL_ERROR
    "PURE_EXECUTABLE must belong to an installed Pure runtime prefix")
endif()
set(package_stage "${TEST_ROOT}/package stage")
set(runtime_stage "${TEST_ROOT}/runtime stage")
set(poison_dir "${TEST_ROOT}/poison PURELIB")
file(REMOVE_RECURSE "${TEST_ROOT}")
file(MAKE_DIRECTORY "${package_stage}" "${poison_dir}")

execute_process(
  COMMAND "${CMAKE_COMMAND}" --install "${BINARY_DIR}"
    --prefix "${package_stage}"
  RESULT_VARIABLE install_result
  OUTPUT_VARIABLE install_stdout
  ERROR_VARIABLE install_stderr
)
if(NOT install_result EQUAL 0)
  message(FATAL_ERROR
    "Package-only install failed:\n${install_stdout}\n${install_stderr}")
endif()

file(GLOB_RECURSE installed_files
  LIST_DIRECTORIES FALSE
  RELATIVE "${package_stage}"
  "${package_stage}/*")
list(TRANSFORM installed_files REPLACE "\\\\" "/")
list(SORT installed_files)
set(expected_files
  "lib/pure/rat_interval.pure"
  "lib/pure/rational.pure"
  "share/doc/pure-rational/COPYING"
  "share/doc/pure-rational/README")
if(NOT installed_files STREQUAL expected_files)
  message(FATAL_ERROR
    "Unexpected package manifest. Expected '${expected_files}', got "
    "'${installed_files}'")
endif()

foreach(pair IN ITEMS
    "lib/pure/rational.pure|rational.pure"
    "lib/pure/rat_interval.pure|rat_interval.pure"
    "share/doc/pure-rational/COPYING|COPYING")
  string(REPLACE "|" ";" pair_parts "${pair}")
  list(GET pair_parts 0 installed_relative)
  list(GET pair_parts 1 source_relative)
  file(SHA256 "${package_stage}/${installed_relative}" installed_hash)
  file(SHA256 "${SOURCE_DIR}/${source_relative}" source_hash)
  if(NOT installed_hash STREQUAL source_hash)
    message(FATAL_ERROR "Installed ${installed_relative} differs from its source")
  endif()
endforeach()
file(SHA256 "${package_stage}/share/doc/pure-rational/README" installed_readme_hash)
file(SHA256 "${BINARY_DIR}/README" configured_readme_hash)
if(NOT installed_readme_hash STREQUAL configured_readme_hash)
  message(FATAL_ERROR "Installed README differs from the configured README")
endif()

file(TO_CMAKE_PATH "${SOURCE_DIR}" normalized_source_dir)
file(TO_CMAKE_PATH "${BINARY_DIR}" normalized_binary_dir)
foreach(installed_relative IN LISTS installed_files)
  file(READ "${package_stage}/${installed_relative}" installed_content)
  string(REPLACE "\\" "/" normalized_content "${installed_content}")
  foreach(forbidden IN ITEMS
      "${normalized_source_dir}" "${normalized_binary_dir}"
      "C:/msys64" "@version@")
    string(FIND "${normalized_content}" "${forbidden}" forbidden_offset)
    if(NOT forbidden_offset EQUAL -1)
      message(FATAL_ERROR
        "Installed ${installed_relative} contains forbidden text: ${forbidden}")
    endif()
  endforeach()
endforeach()

execute_process(
  COMMAND "${CMAKE_COMMAND}" -E copy_directory
    "${runtime_prefix}" "${runtime_stage}"
  RESULT_VARIABLE copy_result
)
if(NOT copy_result EQUAL 0)
  message(FATAL_ERROR "Could not copy the staged Pure runtime")
endif()
execute_process(
  COMMAND "${CMAKE_COMMAND}" --install "${BINARY_DIR}"
    --prefix "${runtime_stage}"
  RESULT_VARIABLE runtime_install_result
)
if(NOT runtime_install_result EQUAL 0)
  message(FATAL_ERROR "Could not install pure-rational into the staged runtime")
endif()

file(WRITE "${poison_dir}/rational.pure"
  "unexpected token proving inherited PURELIB was used;\n")
file(WRITE "${poison_dir}/rat_interval.pure"
  "unexpected token proving inherited PURELIB was used;\n")

set(system_root "$ENV{SystemRoot}")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    --unset=PURELIB
    "PATH=${runtime_stage}/bin;${system_root}/System32;${system_root}"
    "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${runtime_stage}/bin/pure.exe"
      "-DSMOKE_SCRIPT=${SMOKE_SCRIPT}"
      -P "${SOURCE_DIR}/tests/run_staged_smoke.cmake"
  RESULT_VARIABLE smoke_result
  OUTPUT_VARIABLE smoke_stdout
  ERROR_VARIABLE smoke_stderr
)
if(NOT smoke_result EQUAL 0)
  message(FATAL_ERROR
    "Sanitized staged smoke test failed:\n${smoke_stdout}\n${smoke_stderr}")
endif()
