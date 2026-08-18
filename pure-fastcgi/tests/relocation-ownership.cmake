cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS BUILD_DIR STAGE_BASE STAGE_PREFIX SOURCE_DIR PURE_RUNTIME_ROOT
    LLVM_READOBJ POWERSHELL_EXECUTABLE PROTOCOL_HARNESS PROTOCOL_WORKER
    VERIFY_SCRIPT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH BUILD_DIR NORMALIZE OUTPUT_VARIABLE build_dir)
cmake_path(ABSOLUTE_PATH STAGE_BASE NORMALIZE OUTPUT_VARIABLE stage_base)
cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE test_root)
file(REAL_PATH "${build_dir}" canonical_build_identity)
string(TOLOWER "${canonical_build_identity}" canonical_build_identity)
string(SHA256 build_identity_hash "${canonical_build_identity}")
string(SUBSTRING "${build_identity_hash}" 0 20 build_identity_token)
string(TOLOWER "${build_dir}-independent-checkout" other_build_identity)
string(SHA256 other_build_identity_hash "${other_build_identity}")
string(SUBSTRING "${other_build_identity_hash}" 0 20 other_build_token)
if(build_identity_token STREQUAL other_build_token)
  message(FATAL_ERROR "independent build roots derived a colliding token")
endif()
set(other_test_root
  "${stage_base}/PureFastCGI-relocation-${other_build_token}")
if(test_root STREQUAL other_test_root)
  message(FATAL_ERROR "independent BUILD_DIR values derived the same root")
endif()
get_filename_component(test_root_name "${test_root}" NAME)
if(NOT test_root_name STREQUAL
    "PureFastCGI-relocation-${build_identity_token}")
  message(FATAL_ERROR
    "relocation root is not owned by this canonical BUILD_DIR: ${test_root}")
endif()
cmake_path(IS_PREFIX stage_base "${test_root}" NORMALIZE
  test_root_beneath_stage_base)
if(NOT test_root_beneath_stage_base OR test_root STREQUAL stage_base)
  message(FATAL_ERROR "relocation root escaped its dedicated stage base")
endif()
set(stage "${test_root}/stage with spaces")
set(relocated "${test_root}/relocated 日本語 PureFastCGI")
file(REMOVE_RECURSE "${test_root}")

execute_process(
  COMMAND "${CMAKE_COMMAND}" --install "${build_dir}"
    --prefix "${stage}" --component PureFastCGI
  RESULT_VARIABLE install_result
  OUTPUT_VARIABLE install_output
  ERROR_VARIABLE install_error
  ENCODING UTF-8)
if(NOT install_result EQUAL 0)
  message(FATAL_ERROR
    "initial component install failed (${install_result})\n"
    "stdout:\n${install_output}\nstderr:\n${install_error}")
endif()

# Copy a clean package so exact verification remains meaningful at the
# relocated destination. Ownership sentinels belong only to the overlay stage.
file(COPY "${stage}/" DESTINATION "${relocated}")
execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DBUILD_DIR=${build_dir}"
    "-DSTAGE_PREFIX=${relocated}"
    "-DSOURCE_PREFIX=${SOURCE_DIR}"
    "-DORIGINAL_BUILD_PREFIX=${build_dir}"
    "-DORIGINAL_STAGE_PREFIX=${stage}"
    "-DPURE_RUNTIME_ROOT=${PURE_RUNTIME_ROOT}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    "-DPOWERSHELL_EXECUTABLE=${POWERSHELL_EXECUTABLE}"
    "-DPROTOCOL_HARNESS=${PROTOCOL_HARNESS}"
    "-DPROTOCOL_WORKER=${PROTOCOL_WORKER}"
    -DRUN_RUNTIME_TESTS=ON
    -P "${VERIFY_SCRIPT}"
  RESULT_VARIABLE relocated_result
  OUTPUT_VARIABLE relocated_output
  ERROR_VARIABLE relocated_error
  ENCODING UTF-8)
if(NOT relocated_result EQUAL 0)
  message(FATAL_ERROR
    "relocated PureFastCGI verification failed (${relocated_result})\n"
    "stdout:\n${relocated_output}\nstderr:\n${relocated_error}")
endif()
string(REPLACE "\\" "/" relocated_module_dir "${relocated}/lib/pure")
if(NOT relocated_output MATCHES
      "RUNTIME_MODULE_DIR=${relocated_module_dir}([\r\n]|$)")
  message(FATAL_ERROR
    "relocated runtime did not prove direct payload lookup\n${relocated_output}")
endif()
string(REPLACE "\\" "/" original_module
  "${build_dir}/fastcgi.dll")
string(REPLACE "\\" "/" original_source "${SOURCE_DIR}")
if(relocated_output MATCHES "${original_module}" OR
     relocated_output MATCHES "${original_source}" OR
     relocated_output MATCHES "[Cc]:/msys64")
  message(FATAL_ERROR
    "relocated runtime trace contains an original build/source/MSYS path\n"
    "${relocated_output}")
endif()

file(WRITE "${stage}/unrelated-sentinel.txt" "keep\n")
file(WRITE "${stage}/lib/pure/unrelated-module.pure" "keep-module\n")
file(SHA256 "${stage}/unrelated-sentinel.txt" root_sentinel_before)
file(SHA256 "${stage}/lib/pure/unrelated-module.pure" module_sentinel_before)

# Exercise a real overlay before removal.
execute_process(
  COMMAND "${CMAKE_COMMAND}" --install "${build_dir}"
    --prefix "${stage}" --component PureFastCGI
  RESULT_VARIABLE overlay_result
  OUTPUT_VARIABLE overlay_output
  ERROR_VARIABLE overlay_error
  ENCODING UTF-8)
if(NOT overlay_result EQUAL 0)
  message(FATAL_ERROR
    "component overlay failed (${overlay_result})\n"
    "stdout:\n${overlay_output}\nstderr:\n${overlay_error}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DBUILD_DIR=${build_dir}"
    "-DSTAGE_PREFIX=${stage}"
    "-DSOURCE_PREFIX=${SOURCE_DIR}"
    "-DORIGINAL_BUILD_PREFIX=${build_dir}"
    "-DORIGINAL_STAGE_PREFIX=${stage}"
    "-DPURE_RUNTIME_ROOT=${PURE_RUNTIME_ROOT}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    "-DPOWERSHELL_EXECUTABLE=${POWERSHELL_EXECUTABLE}"
    -DREMOVE_OWNED=ON
    -P "${VERIFY_SCRIPT}"
  RESULT_VARIABLE removal_result
  OUTPUT_VARIABLE removal_output
  ERROR_VARIABLE removal_error
  ENCODING UTF-8)
if(NOT removal_result EQUAL 0)
  message(FATAL_ERROR
    "owned-file removal failed (${removal_result})\n"
    "stdout:\n${removal_output}\nstderr:\n${removal_error}")
endif()

file(SHA256 "${stage}/unrelated-sentinel.txt" root_sentinel_after)
file(SHA256 "${stage}/lib/pure/unrelated-module.pure" module_sentinel_after)
if(NOT root_sentinel_after STREQUAL root_sentinel_before OR
    NOT module_sentinel_after STREQUAL module_sentinel_before)
  message(FATAL_ERROR "ownership removal changed an unrelated sentinel")
endif()
foreach(owned IN ITEMS
    lib/pure/fastcgi.dll
    lib/pure/fastcgi.pure
    share/doc/pure-fastcgi/README
    share/doc/pure-fastcgi/THIRD_PARTY.md
    share/doc/pure-fastcgi/LICENSE.fcgi2
    share/doc/pure-fastcgi/PureFastCGIInventory.tsv)
  if(EXISTS "${stage}/${owned}")
    message(FATAL_ERROR "owned payload remains after removal: ${owned}")
  endif()
endforeach()
if(NOT IS_DIRECTORY "${stage}/lib/pure" OR
    NOT IS_DIRECTORY "${stage}/share/doc")
  message(FATAL_ERROR "shared package directories were removed")
endif()
if(IS_DIRECTORY "${stage}/share/doc/pure-fastcgi")
  message(FATAL_ERROR "empty component documentation directory remains")
endif()

set(adversarial_stage "${test_root}/adversarial overlay")
  set(adversarial_oracles "${test_root}/adversarial oracles")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" --install "${build_dir}"
      --prefix "${adversarial_stage}" --component PureFastCGI
    RESULT_VARIABLE adversarial_install_result)
  if(NOT adversarial_install_result EQUAL 0)
    message(FATAL_ERROR "adversarial component install failed")
  endif()
  file(MAKE_DIRECTORY "${adversarial_oracles}")
  file(COPY
    "${build_dir}/PureFastCGIExpected.sha256"
    "${build_dir}/PureFastCGIInventory.tsv"
    DESTINATION "${adversarial_oracles}")
  set(adversarial_relative "unrelated-adversarial-sentinel.txt")
  set(adversarial_file "${adversarial_stage}/${adversarial_relative}")
  file(WRITE "${adversarial_file}" "adversarial-keep\n")
  file(SHA256 "${adversarial_file}" adversarial_sha)
  file(SIZE "${adversarial_file}" adversarial_size)
  string(TOLOWER "${adversarial_sha}" adversarial_sha)
  file(APPEND "${adversarial_oracles}/PureFastCGIExpected.sha256"
    "${adversarial_sha}  ${adversarial_relative}\n")
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DBUILD_DIR=${adversarial_oracles}"
      "-DSTAGE_PREFIX=${adversarial_stage}"
      "-DSOURCE_PREFIX=${SOURCE_DIR}"
      "-DORIGINAL_BUILD_PREFIX=${build_dir}"
      "-DORIGINAL_STAGE_PREFIX=${stage}"
      "-DPURE_RUNTIME_ROOT=${PURE_RUNTIME_ROOT}"
      "-DLLVM_READOBJ=${LLVM_READOBJ}"
      "-DPOWERSHELL_EXECUTABLE=${POWERSHELL_EXECUTABLE}"
      -DREMOVE_OWNED=ON
      -P "${VERIFY_SCRIPT}"
    RESULT_VARIABLE adversarial_result
    OUTPUT_VARIABLE adversarial_output
    ERROR_VARIABLE adversarial_error
    ENCODING UTF-8)
  if(adversarial_result EQUAL 0 OR
      NOT "${adversarial_output}\n${adversarial_error}" MATCHES
        "INVENTORY_FILE_SET_MISMATCH")
    message(FATAL_ERROR
      "subject-only ownership forgery was not rejected\n"
      "${adversarial_output}\n${adversarial_error}")
  endif()
  if(NOT EXISTS "${adversarial_file}")
    message(FATAL_ERROR
      "subject-only manifest entry deleted an unrelated sentinel")
  endif()

  set(installed_forgery_stage "${test_root}/installed inventory forgery")
  set(installed_forgery_oracles "${test_root}/installed inventory oracles")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" --install "${build_dir}"
      --prefix "${installed_forgery_stage}" --component PureFastCGI
    RESULT_VARIABLE installed_forgery_install_result)
  if(NOT installed_forgery_install_result EQUAL 0)
    message(FATAL_ERROR "installed-inventory forgery install failed")
  endif()
  file(MAKE_DIRECTORY "${installed_forgery_oracles}")
  file(COPY
    "${build_dir}/PureFastCGIExpected.sha256"
    "${build_dir}/PureFastCGIInventory.tsv"
    DESTINATION "${installed_forgery_oracles}")
  set(installed_forgery_relative "unrelated-installed-inventory-sentinel.txt")
  set(installed_forgery_file
    "${installed_forgery_stage}/${installed_forgery_relative}")
  file(WRITE "${installed_forgery_file}" "installed-inventory-keep\n")
  file(SHA256 "${installed_forgery_file}" installed_forgery_sha)
  file(SIZE "${installed_forgery_file}" installed_forgery_size)
  string(TOLOWER "${installed_forgery_sha}" installed_forgery_sha)
  file(APPEND
    "${installed_forgery_stage}/share/doc/pure-fastcgi/PureFastCGIInventory.tsv"
    "${installed_forgery_relative}\tforged sentinel\tstage subject\t0\t"
    "${installed_forgery_sha}\t${installed_forgery_size}\n")
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DBUILD_DIR=${installed_forgery_oracles}"
      "-DSTAGE_PREFIX=${installed_forgery_stage}"
      "-DSOURCE_PREFIX=${SOURCE_DIR}"
      "-DORIGINAL_BUILD_PREFIX=${build_dir}"
      "-DORIGINAL_STAGE_PREFIX=${stage}"
      "-DPURE_RUNTIME_ROOT=${PURE_RUNTIME_ROOT}"
      "-DLLVM_READOBJ=${LLVM_READOBJ}"
      "-DPOWERSHELL_EXECUTABLE=${POWERSHELL_EXECUTABLE}"
      -DREMOVE_OWNED=ON
      -P "${VERIFY_SCRIPT}"
    RESULT_VARIABLE installed_forgery_result
    OUTPUT_VARIABLE installed_forgery_output
    ERROR_VARIABLE installed_forgery_error
    ENCODING UTF-8)
  if(installed_forgery_result EQUAL 0 OR
      NOT "${installed_forgery_output}\n${installed_forgery_error}" MATCHES
        "INVENTORY_ORACLE_MISMATCH")
    message(FATAL_ERROR
      "subject-only installed inventory forgery was not rejected\n"
      "${installed_forgery_output}\n${installed_forgery_error}")
  endif()
if(NOT EXISTS "${installed_forgery_file}")
  message(FATAL_ERROR
    "installed inventory forgery deleted an unrelated sentinel")
endif()

set(timeout_helper "${test_root}/runtime-timeout-helper.cmd")
file(WRITE "${timeout_helper}"
  "@echo off\r\n"
  ":pure_fastcgi_timeout_loop\r\n"
  "goto pure_fastcgi_timeout_loop\r\n")
execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DBUILD_DIR=${build_dir}"
    "-DSTAGE_PREFIX=${relocated}"
    "-DSOURCE_PREFIX=${SOURCE_DIR}"
    "-DORIGINAL_BUILD_PREFIX=${build_dir}"
    "-DORIGINAL_STAGE_PREFIX=${stage}"
    "-DPURE_RUNTIME_ROOT=${PURE_RUNTIME_ROOT}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    "-DPOWERSHELL_EXECUTABLE=${POWERSHELL_EXECUTABLE}"
    "-DPROTOCOL_HARNESS=${timeout_helper}"
    "-DPROTOCOL_WORKER=${PROTOCOL_WORKER}"
    -DRUNTIME_TIMEOUT_SECONDS=0.2
    -DRUN_RUNTIME_TESTS=ON
    -P "${VERIFY_SCRIPT}"
  RESULT_VARIABLE timeout_probe_result
  OUTPUT_VARIABLE timeout_probe_output
  ERROR_VARIABLE timeout_probe_error
  ENCODING UTF-8)
set(timeout_probe_log "${timeout_probe_output}\n${timeout_probe_error}")
if(timeout_probe_result EQUAL 0 OR
    NOT timeout_probe_log MATCHES
      "RUNTIME_SMOKE_TIMEOUT: deadline expired;[ \r\n]*alias=([^\r\n]+)")
  message(FATAL_ERROR
    "runtime timeout did not fail with its stable category\n${timeout_probe_log}")
endif()
set(timeout_alias "${CMAKE_MATCH_1}")
string(STRIP "${timeout_alias}" timeout_alias)
if(EXISTS "${timeout_alias}")
  message(FATAL_ERROR "runtime timeout leaked its alias: ${timeout_alias}")
endif()

message(STATUS "PureFastCGI relocation and ownership passed")
