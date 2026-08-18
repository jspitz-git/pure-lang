cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS BUILD_DIR STAGE_PREFIX)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH BUILD_DIR NORMALIZE OUTPUT_VARIABLE build_dir)
cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE stage)
set(default_stage "${stage}-default")
file(REMOVE_RECURSE "${default_stage}" "${stage}")

# The compile-contract test deliberately performs a clean-first fcgi2 build.
# Rebuild the package input here so this test is independent of test order.
execute_process(
  COMMAND "${CMAKE_COMMAND}" --build "${build_dir}"
    --target pure-fastcgi-package-oracles
  RESULT_VARIABLE build_result
  OUTPUT_VARIABLE build_output
  ERROR_VARIABLE build_error
  ENCODING UTF-8)
if(NOT build_result EQUAL 0)
  message(FATAL_ERROR
    "PureFastCGI module build failed (${build_result})\n"
    "stdout:\n${build_output}\nstderr:\n${build_error}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" --install "${build_dir}"
    --prefix "${default_stage}"
  RESULT_VARIABLE default_result
  OUTPUT_VARIABLE default_output
  ERROR_VARIABLE default_error
  ENCODING UTF-8)
if(NOT default_result EQUAL 0)
  message(FATAL_ERROR
    "default install failed (${default_result})\n"
    "stdout:\n${default_output}\nstderr:\n${default_error}")
endif()
file(GLOB_RECURSE default_files LIST_DIRECTORIES FALSE "${default_stage}/*")
if(default_files)
  message(FATAL_ERROR "PureFastCGI leaked into default install: ${default_files}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" --install "${build_dir}"
    --prefix "${stage}" --component PureFastCGI
  RESULT_VARIABLE install_result
  OUTPUT_VARIABLE install_output
  ERROR_VARIABLE install_error
  ENCODING UTF-8)
if(NOT install_result EQUAL 0)
  message(FATAL_ERROR
    "PureFastCGI component install failed (${install_result})\n"
    "stdout:\n${install_output}\nstderr:\n${install_error}")
endif()

foreach(required IN ITEMS
    lib/pure/fastcgi.dll
    lib/pure/fastcgi.pure
    share/doc/pure-fastcgi/README
    share/doc/pure-fastcgi/THIRD_PARTY.md
    share/doc/pure-fastcgi/LICENSE.fcgi2
    share/doc/pure-fastcgi/PureFastCGIInventory.tsv)
  if(NOT EXISTS "${stage}/${required}")
    message(FATAL_ERROR "missing PureFastCGI payload: ${required}")
  endif()
endforeach()

file(GLOB_RECURSE forbidden LIST_DIRECTORIES FALSE "${stage}/*fcgi*.dll")
list(FILTER forbidden EXCLUDE REGEX "[/\\\\]fastcgi\\.dll$")
if(forbidden)
  message(FATAL_ERROR "separate FastCGI DLL installed: ${forbidden}")
endif()

set(manifest "${build_dir}/PureFastCGIExpected.sha256")
if(NOT EXISTS "${manifest}")
  message(FATAL_ERROR "missing authoritative SHA manifest: ${manifest}")
endif()
file(STRINGS "${manifest}" manifest_lines)
foreach(line IN LISTS manifest_lines)
  string(LENGTH "${line}" line_length)
  if(line_length LESS 67)
    message(FATAL_ERROR "malformed authoritative SHA manifest row: ${line}")
  endif()
  string(SUBSTRING "${line}" 0 64 expected_sha)
  string(SUBSTRING "${line}" 64 2 separator)
  string(SUBSTRING "${line}" 66 -1 relative)
  if(NOT expected_sha MATCHES "^[0-9a-f]+$" OR
      NOT separator STREQUAL "  ")
    message(FATAL_ERROR "malformed authoritative SHA manifest row: ${line}")
  endif()
  if(NOT EXISTS "${stage}/${relative}")
    message(FATAL_ERROR "manifest entry was not installed: ${relative}")
  endif()
  file(SHA256 "${stage}/${relative}" actual_sha)
  string(TOLOWER "${actual_sha}" actual_sha)
  if(NOT actual_sha STREQUAL expected_sha)
    message(FATAL_ERROR "installed hash mismatch: ${relative}")
  endif()
endforeach()
