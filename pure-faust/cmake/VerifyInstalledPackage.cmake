foreach(required IN ITEMS STAGE_PREFIX EXPECT_DEVELOPER)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

include("${CMAKE_CURRENT_LIST_DIR}/FaustToolchain.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/AuditStagedContent.cmake")

if(NOT EXPECT_DEVELOPER STREQUAL "ON" AND NOT EXPECT_DEVELOPER STREQUAL "OFF")
  message(FATAL_ERROR "EXPECT_DEVELOPER must be ON or OFF")
endif()

cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE stage)

if(DEFINED BUILD_DIR AND NOT "${BUILD_DIR}" STREQUAL "")
  cmake_path(ABSOLUTE_PATH BUILD_DIR NORMALIZE OUTPUT_VARIABLE build_dir)
  file(REMOVE_RECURSE "${stage}")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" --install "${build_dir}"
      --prefix "${stage}" --component Runtime
    RESULT_VARIABLE install_result
    OUTPUT_VARIABLE install_output
    ERROR_VARIABLE install_error
    ENCODING UTF-8)
  if(NOT install_result EQUAL 0)
    message(FATAL_ERROR
      "Runtime install failed (${install_result})\\n"
      "stdout:\\n${install_output}\\nstderr:\\n${install_error}")
  endif()
  if(EXPECT_DEVELOPER STREQUAL "ON")
    execute_process(
      COMMAND "${CMAKE_COMMAND}" --install "${build_dir}"
        --prefix "${stage}" --component FaustDeveloper
      RESULT_VARIABLE developer_install_result
      OUTPUT_VARIABLE developer_install_output
      ERROR_VARIABLE developer_install_error
      ENCODING UTF-8)
    if(NOT developer_install_result EQUAL 0)
      message(FATAL_ERROR
        "FaustDeveloper install failed (${developer_install_result})\\n"
        "stdout:\\n${developer_install_output}\\n"
        "stderr:\\n${developer_install_error}")
    endif()
  endif()
endif()

if(NOT DEFINED build_dir)
  cmake_path(GET stage PARENT_PATH build_dir)
endif()

set(expected_relative_files
  "lib/pure/faust2.pure"
  "share/doc/pure-faust/COPYING"
  "share/doc/pure-faust/COPYING.LESSER"
  "share/doc/pure-faust/WINDOWS.md"
  "share/doc/pure-faust/tests/reference.bc")
if(EXPECT_DEVELOPER STREQUAL "ON")
  set(developer_allowlist
    "${stage}/${PURE_FAUST_DEVELOPER_ALLOWLIST_RELATIVE}")
  if(NOT EXISTS "${developer_allowlist}")
    message(FATAL_ERROR "Missing installed FaustDeveloper allowlist")
  endif()
  file(STRINGS "${developer_allowlist}" allowlist_lines)
  set(saw_allowlist_self OFF)
  foreach(line IN LISTS allowlist_lines)
    if(line STREQUAL "# SELF  ${PURE_FAUST_DEVELOPER_ALLOWLIST_RELATIVE}")
      set(saw_allowlist_self ON)
      continue()
    endif()
    if(line MATCHES "^#")
      continue()
    endif()
    string(SUBSTRING "${line}" 0 64 expected_sha256)
    string(SUBSTRING "${line}" 66 -1 relative_file)
    string(LENGTH "${expected_sha256}" sha_length)
    if(NOT sha_length EQUAL 64 OR NOT expected_sha256 MATCHES "^[0-9a-f]+$")
      message(FATAL_ERROR "Malformed developer allowlist line: ${line}")
    endif()
    cmake_path(IS_ABSOLUTE relative_file is_absolute)
    string(REPLACE "/" ";" path_segments "${relative_file}")
    if(is_absolute OR ".." IN_LIST path_segments)
      message(FATAL_ERROR "Unsafe developer allowlist path: ${relative_file}")
    endif()
    file(SHA256 "${stage}/${relative_file}" actual_sha256)
    string(TOLOWER "${actual_sha256}" actual_sha256)
    if(NOT actual_sha256 STREQUAL expected_sha256)
      message(FATAL_ERROR
        "Developer allowlist hash mismatch for ${relative_file}")
    endif()
    list(APPEND expected_relative_files "${relative_file}")
  endforeach()
  if(NOT saw_allowlist_self)
    message(FATAL_ERROR "Installed developer allowlist omits its own path")
  endif()
  list(APPEND expected_relative_files
    "${PURE_FAUST_DEVELOPER_ALLOWLIST_RELATIVE}")
endif()
foreach(relative_file IN LISTS expected_relative_files)
  if(NOT EXISTS "${stage}/${relative_file}")
    message(FATAL_ERROR
      "Missing installed pure-faust file: ${stage}/${relative_file}")
  endif()
endforeach()

file(GLOB_RECURSE installed_files LIST_DIRECTORIES FALSE "${stage}/*")
set(installed_relative_files)
foreach(installed_file IN LISTS installed_files)
  file(RELATIVE_PATH relative_file "${stage}" "${installed_file}")
  list(APPEND installed_relative_files "${relative_file}")
endforeach()
list(SORT expected_relative_files)
list(SORT installed_relative_files)

set(forbidden_basenames
  faust.dll
  faust.pure
  pure.cpp
  msys-2.0.dll)
if(EXPECT_DEVELOPER STREQUAL "OFF")
  list(APPEND forbidden_basenames faust.exe clang.exe opt.exe)
endif()
foreach(installed_file IN LISTS installed_files)
  file(RELATIVE_PATH installed_relative "${stage}" "${installed_file}")
  string(REPLACE "\\" "/" installed_relative "${installed_relative}")
  cmake_path(GET installed_file FILENAME basename)
  string(TOLOWER "${basename}" basename_lower)
  if(basename_lower IN_LIST forbidden_basenames)
    message(FATAL_ERROR
      "Forbidden pure-faust runtime file: ${installed_file}")
  endif()
  if(installed_relative MATCHES "(^|/)(bash|sh|dash|pacman)(\\.exe)?$" OR
      installed_relative MATCHES "(^|/)var/lib/pacman(/|$)" OR
      installed_relative MATCHES "\\.(a|lib)$")
    message(FATAL_ERROR
      "Forbidden developer compiler payload: ${installed_relative}")
  endif()
endforeach()

if(NOT installed_relative_files STREQUAL expected_relative_files)
  message(FATAL_ERROR
    "Unexpected pure-faust runtime inventory: ${installed_relative_files}")
endif()

if(EXPECT_DEVELOPER STREQUAL "ON")
  foreach(entry IN LISTS PURE_FAUST_LICENSE_SHA256)
    string(REPLACE "=" ";" fields "${entry}")
    list(GET fields 0 relative_license)
    list(GET fields 1 expected_license_sha256)
    file(SHA256 "${stage}/${relative_license}" actual_license_sha256)
    string(TOLOWER "${actual_license_sha256}" actual_license_sha256)
    if(NOT actual_license_sha256 STREQUAL expected_license_sha256)
      message(FATAL_ERROR
        "Installed license hash mismatch for ${relative_license}: "
        "${actual_license_sha256}")
    endif()
  endforeach()
  foreach(tool IN ITEMS faust clang opt)
    execute_process(
      COMMAND "${stage}/bin/${tool}.exe" --version
      RESULT_VARIABLE version_result
      OUTPUT_VARIABLE version_output
      ERROR_VARIABLE version_error
      ENCODING UTF-8)
    if(NOT version_result EQUAL 0)
      message(FATAL_ERROR
        "Installed ${tool} version check failed (${version_result})\n"
        "stdout:\n${version_output}\nstderr:\n${version_error}")
    endif()
    set(version_transcript "${version_output}\n${version_error}")
    if(tool STREQUAL "faust")
      set(expected_version "FAUST Version 2.85.9")
    elseif(tool STREQUAL "clang")
      set(expected_version "clang version 22")
    else()
      set(expected_version "LLVM version 22")
    endif()
    string(FIND "${version_transcript}" "${expected_version}" version_match)
    if(version_match EQUAL -1)
      message(FATAL_ERROR
        "Installed ${tool} has the wrong version; expected '${expected_version}'\n"
        "${version_transcript}")
    endif()
  endforeach()

  if(NOT DEFINED SOURCE_DIR OR
      NOT EXISTS "${SOURCE_DIR}/tests/reference.dsp")
    message(FATAL_ERROR "SOURCE_DIR with tests/reference.dsp is required")
  endif()
  set(helper_work "${build_dir}/installed developer helper work with spaces")
  file(REMOVE_RECURSE "${helper_work}")
  file(MAKE_DIRECTORY "${helper_work}")
  execute_process(
    COMMAND powershell.exe -NoProfile -File "${stage}/tools/faust2pure.ps1"
      -InputPath "${SOURCE_DIR}/tests/reference.dsp"
      -OutputPath "${helper_work}/reference.bc"
    RESULT_VARIABLE helper_result
    OUTPUT_VARIABLE helper_output
    ERROR_VARIABLE helper_error
    ENCODING UTF-8)
  if(NOT helper_result EQUAL 0)
    message(FATAL_ERROR
      "Installed Faust helper failed (${helper_result})\n"
      "stdout:\n${helper_output}\nstderr:\n${helper_error}")
  endif()
  execute_process(
    COMMAND "${stage}/bin/opt.exe" -passes=verify -S -
      -o "${helper_work}/reference.ll"
    INPUT_FILE "${helper_work}/reference.bc"
    RESULT_VARIABLE verify_result
    OUTPUT_VARIABLE verify_output
    ERROR_VARIABLE verify_error
    ENCODING UTF-8)
  if(NOT verify_result EQUAL 0)
    message(FATAL_ERROR
      "Installed helper bitcode verification failed (${verify_result})\n"
      "stdout:\n${verify_output}\nstderr:\n${verify_error}")
  endif()
  set(PURE_FAUST_AUDIT_FORBIDDEN_PATHS
    "${SOURCE_DIR}" "${build_dir}")
  pure_faust_audit_staged_content(
    "${stage}" "${helper_work}/reference.ll")
  foreach(required_runtime IN ITEMS
      PURE_EXECUTABLE PURE_PREFIX RUNTIME_SMOKE_SCRIPT)
    if(NOT DEFINED ${required_runtime} OR "${${required_runtime}}" STREQUAL "")
      message(FATAL_ERROR "${required_runtime} is required for developer smoke")
    endif()
  endforeach()
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DBUILD_DIR=${build_dir}"
      "-DSTAGE_PREFIX=${build_dir}/developer generated runtime stage with spaces"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPURE_PREFIX=${PURE_PREFIX}"
      "-DFIXTURE_BASE=${helper_work}/reference"
      "-DRUNTIME_SMOKE_SCRIPT=${RUNTIME_SMOKE_SCRIPT}"
      -P "${CMAKE_CURRENT_LIST_DIR}/RunRuntimeSmoke.cmake"
    RESULT_VARIABLE runtime_result
    OUTPUT_VARIABLE runtime_output
    ERROR_VARIABLE runtime_error
    ENCODING UTF-8)
  if(NOT runtime_result EQUAL 0 OR NOT "${runtime_error}" STREQUAL "" OR
      NOT runtime_output MATCHES "Pure runtime smoke passed")
    message(FATAL_ERROR
      "Installed helper runtime smoke failed (${runtime_result})\n"
      "stdout:\n${runtime_output}\nstderr:\n${runtime_error}")
  endif()
endif()

message(STATUS
  "Verified installed pure-faust runtime: ${stage} "
  "(${EXPECT_DEVELOPER} developer component expected)")
