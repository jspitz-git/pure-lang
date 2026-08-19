cmake_minimum_required(VERSION 3.25)

include("${CMAKE_CURRENT_LIST_DIR}/PureBonjourPackageSafety.cmake")

function(pure_bonjour_package_fail token detail)
  message(FATAL_ERROR "${token}: ${detail}")
endfunction()

foreach(required IN ITEMS STAGE_PREFIX SOURCE_PREFIX BUILD_PREFIX PURE_PREFIX)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    pure_bonjour_package_fail(PACKAGE_INVENTORY "${required} is required")
  endif()
endforeach()

foreach(directory IN ITEMS STAGE_PREFIX SOURCE_PREFIX BUILD_PREFIX PURE_PREFIX)
  if(NOT IS_ABSOLUTE "${${directory}}" OR
      NOT EXISTS "${${directory}}" OR NOT IS_DIRECTORY "${${directory}}")
    pure_bonjour_package_fail(PACKAGE_SET
      "${directory} must name an existing absolute directory: ${${directory}}")
  endif()
endforeach()

# PowerShell is used for byte-accurate traversal and prefix properties which
# CMake cannot portably expose on Windows.
set(package_powershell
  "$ENV{SystemRoot}/System32/WindowsPowerShell/v1.0/powershell.exe")
if(NOT EXISTS "${package_powershell}")
  pure_bonjour_package_fail(PACKAGE_SET
    "Windows PowerShell is required for safe package traversal")
endif()

cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE stage_input)
string(SHA256 verify_id "${stage_input}")
# This pass uses the spelling supplied by the caller, so a reparse point at the
# stage root cannot disappear through canonicalization.
pure_bonjour_fs_action(inspect-tree "${stage_input}" "" PACKAGE_SET)

file(REAL_PATH "${stage_input}" stage)
file(REAL_PATH "${SOURCE_PREFIX}" source_prefix)
file(REAL_PATH "${BUILD_PREFIX}" build_prefix)
file(REAL_PATH "${PURE_PREFIX}" pure_prefix)

if(DEFINED PACKAGE_TEMP_ROOT AND NOT PACKAGE_TEMP_ROOT STREQUAL "")
  set(temp_root_input "${PACKAGE_TEMP_ROOT}")
else()
  set(temp_root_input "$ENV{TEMP}")
endif()
if(temp_root_input STREQUAL "" OR NOT IS_ABSOLUTE "${temp_root_input}" OR
    NOT EXISTS "${temp_root_input}" OR NOT IS_DIRECTORY "${temp_root_input}")
  pure_bonjour_package_fail(PACKAGE_SCRATCH
    "temporary root must be an existing absolute directory: ${temp_root_input}")
endif()
pure_bonjour_fs_action(inspect-dir "${temp_root_input}" "" PACKAGE_SCRATCH)
file(REAL_PATH "${temp_root_input}" temp_root)
foreach(protected IN ITEMS stage pure_prefix)
  cmake_path(IS_PREFIX ${protected} "${temp_root}" NORMALIZE
    temp_inside_protected)
  if(temp_inside_protected)
    pure_bonjour_package_fail(PACKAGE_SCRATCH
      "temporary root is inside ${protected}: ${temp_root}")
  endif()
endforeach()

set(oracle_input "${BUILD_PREFIX}/PureBonjourExpected.sha256")
pure_bonjour_parse_external_oracle("${oracle_input}" "${stage}"
  oracle oracle_paths oracle_identities oracle_hashes)

set(expected_paths "${pure_bonjour_expected_paths}")
set(inventory_relative
  "share/doc/pure-bonjour/PureBonjourInventory.tsv")

# Parse the installed inventory in isolation before consulting its hashes or
# using any path.  Its seven rows describe payload metadata but never deletion.
set(inventory "${stage}/${inventory_relative}")
if(NOT EXISTS "${inventory}" OR IS_DIRECTORY "${inventory}")
  pure_bonjour_package_fail(PACKAGE_SET
    "installed inventory is missing: ${inventory_relative}")
endif()
file(STRINGS "${inventory}" inventory_lines ENCODING UTF-8)
list(LENGTH inventory_lines inventory_line_count)
if(NOT inventory_line_count EQUAL 8)
  pure_bonjour_package_fail(PACKAGE_INVENTORY
    "installed inventory must contain one header and seven rows")
endif()
list(POP_FRONT inventory_lines inventory_header)
if(NOT inventory_header STREQUAL
    "relative_path\tpurpose\torigin\tversion\tsha256\tsize")
  pure_bonjour_package_fail(PACKAGE_INVENTORY
    "installed inventory header is malformed")
endif()
set(inventory_paths)
set(inventory_identities)
set(inventory_hashes)
set(inventory_sizes)
foreach(line IN LISTS inventory_lines)
  string(REPLACE "\t" ";" fields "${line}")
  list(LENGTH fields field_count)
  if(NOT field_count EQUAL 6)
    pure_bonjour_package_fail(PACKAGE_INVENTORY
      "installed inventory row must contain six fields: ${line}")
  endif()
  list(GET fields 0 relative)
  list(GET fields 1 purpose)
  list(GET fields 2 origin)
  list(GET fields 3 version)
  list(GET fields 4 expected_sha)
  list(GET fields 5 expected_size)
  string(LENGTH "${expected_sha}" sha_length)
  if(purpose STREQUAL "" OR origin STREQUAL "" OR version STREQUAL "" OR
      NOT sha_length EQUAL 64 OR NOT expected_sha MATCHES "^[0-9A-Fa-f]+$" OR
      NOT expected_size MATCHES "^[0-9]+$")
    pure_bonjour_package_fail(PACKAGE_INVENTORY
      "installed inventory row has malformed metadata: ${line}")
  endif()
  pure_bonjour_validate_relative_path(
    "${relative}" "installed inventory" normalized identity)
  if(identity IN_LIST inventory_identities)
    pure_bonjour_package_fail(PACKAGE_INVENTORY
      "installed inventory repeats a case-folded path: ${relative}")
  endif()
  string(TOLOWER "${expected_sha}" expected_sha)
  list(APPEND inventory_paths "${normalized}")
  list(APPEND inventory_identities "${identity}")
  list(APPEND inventory_hashes "${expected_sha}")
  list(APPEND inventory_sizes "${expected_size}")
endforeach()

set(expected_inventory_paths "${expected_paths}")
list(REMOVE_ITEM expected_inventory_paths "${inventory_relative}")
set(sorted_inventory_paths "${inventory_paths}")
list(SORT sorted_inventory_paths)
if(NOT sorted_inventory_paths STREQUAL expected_inventory_paths)
  pure_bonjour_package_fail(PACKAGE_SET
    "installed inventory differs from the exact seven payload paths: "
    "${sorted_inventory_paths}")
endif()

# All declared paths must be ordinary files.  The package-specific directory is
# closed to undeclared files/directories; lib/pure remains a shared namespace,
# where only case-colliding Bonjour names are rejected.
foreach(relative IN LISTS expected_paths)
  if(NOT EXISTS "${stage}/${relative}" OR IS_DIRECTORY "${stage}/${relative}")
    pure_bonjour_package_fail(PACKAGE_SET
      "declared package file is missing: ${relative}")
  endif()
endforeach()
set(expected_documentation_paths "${expected_paths}")
list(FILTER expected_documentation_paths INCLUDE REGEX "^share/doc/")
file(GLOB_RECURSE documentation_entries LIST_DIRECTORIES TRUE
  RELATIVE "${stage}" "${stage}/share/doc/pure-bonjour/*")
set(actual_documentation_paths)
foreach(relative IN LISTS documentation_entries)
  if(IS_DIRECTORY "${stage}/${relative}")
    if(NOT relative STREQUAL "share/doc/pure-bonjour/examples")
      pure_bonjour_package_fail(PACKAGE_SET
        "undeclared package-specific directory is installed: ${relative}")
    endif()
  else()
    list(APPEND actual_documentation_paths "${relative}")
  endif()
endforeach()
list(SORT actual_documentation_paths)
if(NOT actual_documentation_paths STREQUAL expected_documentation_paths)
  pure_bonjour_package_fail(PACKAGE_SET
    "package-specific documentation set is not exact: "
    "${actual_documentation_paths}")
endif()
file(GLOB shared_library_entries LIST_DIRECTORIES FALSE
  RELATIVE "${stage}" "${stage}/lib/pure/*")
foreach(relative IN LISTS shared_library_entries)
  get_filename_component(name "${relative}" NAME)
  string(TOLOWER "${name}" name_identity)
  if(name_identity STREQUAL "bonjour.dll" AND
      NOT relative STREQUAL "lib/pure/bonjour.dll")
    pure_bonjour_package_fail(PACKAGE_SET
      "case-colliding shared module path is installed: ${relative}")
  elseif(name_identity STREQUAL "bonjour.pure" AND
      NOT relative STREQUAL "lib/pure/bonjour.pure")
    pure_bonjour_package_fail(PACKAGE_SET
      "case-colliding shared wrapper path is installed: ${relative}")
  endif()
endforeach()

execute_process(
  COMMAND "${package_powershell}" -NoLogo -NoProfile -NonInteractive
    -File "${CMAKE_CURRENT_LIST_DIR}/PureBonjourPrefixScan.ps1"
    -Stage "${stage}" -SourcePrefix "${source_prefix}"
    -BuildPrefix "${build_prefix}" -StagePrefix "${stage}"
  RESULT_VARIABLE prefix_result
  OUTPUT_VARIABLE prefix_output
  ERROR_VARIABLE prefix_error
  ENCODING UTF-8)
if(NOT prefix_result EQUAL 0)
  pure_bonjour_package_fail(PACKAGE_PREFIX
    "stage contains a build-machine prefix: ${prefix_output}${prefix_error}")
endif()

# Inventory metadata and then the external oracle are checked independently.
# Prefix and reparse rejection have already happened before any file hash or PE
# runtime inspection.
set(total_bytes 0)
list(LENGTH inventory_paths inventory_count)
math(EXPR inventory_last "${inventory_count} - 1")
foreach(index RANGE 0 ${inventory_last})
  list(GET inventory_paths ${index} relative)
  list(GET inventory_hashes ${index} expected_sha)
  list(GET inventory_sizes ${index} expected_size)
  file(SHA256 "${stage}/${relative}" actual_sha)
  file(SIZE "${stage}/${relative}" actual_size)
  string(TOLOWER "${actual_sha}" actual_sha)
  if(NOT actual_sha STREQUAL expected_sha OR
      NOT actual_size EQUAL expected_size)
    pure_bonjour_package_fail(PACKAGE_HASH
      "installed inventory metadata mismatch: ${relative}")
  endif()
endforeach()

list(LENGTH oracle_paths oracle_count)
math(EXPR oracle_last "${oracle_count} - 1")
foreach(index RANGE 0 ${oracle_last})
  list(GET oracle_paths ${index} relative)
  list(GET oracle_hashes ${index} expected_sha)
  file(SHA256 "${stage}/${relative}" actual_sha)
  file(SIZE "${stage}/${relative}" actual_size)
  string(TOLOWER "${actual_sha}" actual_sha)
  if(NOT actual_sha STREQUAL expected_sha)
    pure_bonjour_package_fail(PACKAGE_HASH
      "external oracle hash mismatch: ${relative}")
  endif()
  math(EXPR total_bytes "${total_bytes} + ${actual_size}")
endforeach()
file(SHA256 "${inventory}" inventory_sha256)
string(TOLOWER "${inventory_sha256}" inventory_sha256)

set(dependency_verifier "${source_prefix}/cmake/VerifyWindowsDependencies.cmake")
set(smoke_runner "${source_prefix}/cmake/RunSmokeTest.cmake")
set(smoke_source "${source_prefix}/tests/smoke.pure")
if(NOT EXISTS "${dependency_verifier}")
  set(dependency_verifier
    "${source_prefix}/pure-bonjour/cmake/VerifyWindowsDependencies.cmake")
  set(smoke_runner "${source_prefix}/pure-bonjour/cmake/RunSmokeTest.cmake")
  set(smoke_source "${source_prefix}/pure-bonjour/tests/smoke.pure")
endif()
foreach(required_file IN ITEMS dependency_verifier smoke_runner smoke_source)
  if(NOT EXISTS "${${required_file}}" OR IS_DIRECTORY "${${required_file}}")
    pure_bonjour_package_fail(PACKAGE_SET
      "verification support file is missing: ${${required_file}}")
  endif()
endforeach()

# Scratch ownership begins at an ordinary canonical root outside both audited
# prefixes.  A caller-selected pre-existing reparse entry is unlinked itself and
# rejected; it is never traversed or recursively removed.
if(DEFINED PACKAGE_SCRATCH_ROOT AND NOT PACKAGE_SCRATCH_ROOT STREQUAL "")
  set(scratch_root_input "${PACKAGE_SCRATCH_ROOT}")
else()
  set(scratch_root_input "${build_prefix}/PureBonjourPackageScratch")
endif()
if(NOT IS_ABSOLUTE "${scratch_root_input}")
  pure_bonjour_package_fail(PACKAGE_SCRATCH
    "scratch root must be absolute: ${scratch_root_input}")
endif()
cmake_path(ABSOLUTE_PATH scratch_root_input NORMALIZE
  OUTPUT_VARIABLE scratch_root_input)
foreach(protected IN ITEMS stage pure_prefix)
  pure_bonjour_require_outside("${scratch_root_input}" "${${protected}}"
    PACKAGE_SCRATCH)
endforeach()
get_filename_component(scratch_parent_input "${scratch_root_input}" DIRECTORY)
get_filename_component(scratch_basename "${scratch_root_input}" NAME)
if(scratch_basename STREQUAL "")
  pure_bonjour_package_fail(PACKAGE_SCRATCH
    "scratch root must have a child basename: ${scratch_root_input}")
endif()

# Canonicalize only the existing ordinary parent first.  Combining that trusted
# parent with the final basename proves the entry location before an existing
# reparse is unlinked or a missing child is created.
pure_bonjour_fs_action(inspect-dir "${scratch_parent_input}" ""
  PACKAGE_SCRATCH)
file(REAL_PATH "${scratch_parent_input}" scratch_parent)
set(scratch_location "${scratch_parent}/${scratch_basename}")
cmake_path(NORMAL_PATH scratch_location)
foreach(protected IN ITEMS stage pure_prefix)
  pure_bonjour_require_outside("${scratch_location}" "${${protected}}"
    PACKAGE_SCRATCH)
endforeach()

pure_bonjour_probe_entry("${scratch_root_input}" PACKAGE_SCRATCH
  scratch_entry_kind)
if(scratch_entry_kind STREQUAL "REPARSE")
  file(REAL_PATH "${scratch_root_input}" scratch_entry_canonical)
  foreach(protected IN ITEMS stage pure_prefix)
    pure_bonjour_require_outside("${scratch_entry_canonical}"
      "${${protected}}" PACKAGE_SCRATCH)
  endforeach()
  pure_bonjour_try_unlink_reparse(
    "${scratch_root_input}" scratch_reparse_unlinked scratch_probe_detail)
  if(NOT scratch_reparse_unlinked)
    pure_bonjour_package_fail(PACKAGE_SCRATCH
      "could not safely unlink pre-existing scratch reparse entry: "
      "${scratch_root_input}; ${scratch_probe_detail}")
  endif()
  pure_bonjour_package_fail(PACKAGE_SCRATCH
    "pre-existing scratch reparse entry was safely unlinked and rejected: "
    "${scratch_root_input}")
elseif(scratch_entry_kind STREQUAL "DIRECTORY")
  pure_bonjour_fs_action(inspect-dir "${scratch_root_input}" ""
    PACKAGE_SCRATCH)
  file(REAL_PATH "${scratch_root_input}" scratch_root)
  foreach(protected IN ITEMS stage pure_prefix)
    pure_bonjour_require_outside("${scratch_root}" "${${protected}}"
      PACKAGE_SCRATCH)
  endforeach()
elseif(scratch_entry_kind STREQUAL "MISSING")
  file(MAKE_DIRECTORY "${scratch_location}")
  pure_bonjour_fs_action(inspect-dir "${scratch_location}"
    "${scratch_parent}" PACKAGE_SCRATCH)
  file(REAL_PATH "${scratch_location}" scratch_root)
else()
  pure_bonjour_package_fail(PACKAGE_SCRATCH
    "scratch root is not an ordinary directory: ${scratch_root_input}")
endif()
string(RANDOM LENGTH 20 ALPHABET 0123456789abcdef scratch_nonce)
set(package_verify_work_dir
  "${scratch_root}/verify-${verify_id}-${scratch_nonce}")
if(EXISTS "${package_verify_work_dir}" OR
    IS_SYMLINK "${package_verify_work_dir}")
  pure_bonjour_package_fail(PACKAGE_SCRATCH
    "unique scratch child unexpectedly exists: ${package_verify_work_dir}")
endif()
file(MAKE_DIRECTORY "${package_verify_work_dir}")
pure_bonjour_fs_action(inspect-dir "${package_verify_work_dir}"
  "${scratch_root}"
  PACKAGE_SCRATCH)
file(REAL_PATH "${package_verify_work_dir}" package_verify_work_dir)

get_filename_component(cmake_program_directory "${CMAKE_COMMAND}" DIRECTORY)
find_program(package_llvm_readobj NAMES llvm-readobj.exe llvm-readobj
  HINTS "${cmake_program_directory}")
if(NOT package_llvm_readobj)
  pure_bonjour_package_fail(PACKAGE_SET "llvm-readobj is required")
endif()
set(LLVM_READOBJ "${package_llvm_readobj}")
set(MODULE "${stage}/lib/pure/bonjour.dll")
set(PURE_PREFIX "${pure_prefix}")
set(VERIFY_WORK_DIR "${package_verify_work_dir}/dependency-audit")
set(DEPENDENCY_REPORT
  "${package_verify_work_dir}/PureBonjourDependencies.tsv")
include("${dependency_verifier}")

set(pure_executable "${pure_prefix}/bin/pure.exe")
if(NOT EXISTS "${pure_executable}" OR IS_DIRECTORY "${pure_executable}")
  pure_bonjour_package_fail(PACKAGE_SET
    "installed Pure executable is missing: ${pure_executable}")
endif()
string(RANDOM LENGTH 20 ALPHABET 0123456789abcdef smoke_nonce)
set(smoke_session "${temp_root}/PureBonjourSmoke-${verify_id}-${smoke_nonce}")
if(EXISTS "${smoke_session}" OR IS_SYMLINK "${smoke_session}")
  pure_bonjour_package_fail(PACKAGE_SCRATCH
    "unique smoke session unexpectedly exists: ${smoke_session}")
endif()
file(MAKE_DIRECTORY "${smoke_session}")
pure_bonjour_fs_action(inspect-dir "${smoke_session}" "${temp_root}"
  PACKAGE_SCRATCH)
file(REAL_PATH "${smoke_session}" smoke_session)
set(package_smoke_root "${smoke_session}/runner")
file(MAKE_DIRECTORY "${package_smoke_root}")
pure_bonjour_fs_action(inspect-dir "${package_smoke_root}"
  "${smoke_session}" PACKAGE_SCRATCH)
file(COPY_FILE "${smoke_source}" "${package_smoke_root}/smoke.pure"
  ONLY_IF_DIFFERENT)
set(stage_alias "${smoke_session}/stage")
set(runtime_alias "${smoke_session}/runtime")

function(pure_bonjour_create_alias alias target kind result_output
    detail_output)
  if(DEFINED PACKAGE_ALIAS_SCRIPT AND NOT PACKAGE_ALIAS_SCRIPT STREQUAL "")
    execute_process(
      COMMAND "${package_powershell}" -NoLogo -NoProfile -NonInteractive
        -File "${PACKAGE_ALIAS_SCRIPT}" "${alias}" "${target}" "${kind}"
        "${PACKAGE_ALIAS_LOG}" "${PACKAGE_ALIAS_WRONG_TARGET}"
      RESULT_VARIABLE result
      OUTPUT_VARIABLE output
      ERROR_VARIABLE error
      ENCODING UTF-8)
  else()
    cmake_path(NATIVE_PATH alias NORMALIZE alias_native)
    cmake_path(NATIVE_PATH target NORMALIZE target_native)
    execute_process(
      COMMAND "$ENV{COMSPEC}" /d /c mklink /J
        "${alias_native}" "${target_native}"
      RESULT_VARIABLE result
      OUTPUT_VARIABLE output
      ERROR_VARIABLE error
      ENCODING UTF-8)
  endif()
  set(${result_output} "${result}" PARENT_SCOPE)
  set(${detail_output} "${output}${error}" PARENT_SCOPE)
endfunction()

function(pure_bonjour_cleanup_smoke cleanup_output)
  set(cleanup_errors)
  foreach(alias IN ITEMS "${runtime_alias}" "${stage_alias}")
    # Probe unconditionally so a dangling reparse entry is not hidden by
    # CMake's target-following EXISTS semantics.
    pure_bonjour_try_unlink_reparse(
      "${alias}" alias_removed alias_remove_detail)
    if((NOT alias_removed) AND
        (EXISTS "${alias}" OR IS_SYMLINK "${alias}"))
      list(APPEND cleanup_errors
        "alias leftover ${alias}: ${alias_remove_detail}")
    endif()
  endforeach()
  if(EXISTS "${smoke_session}" OR IS_SYMLINK "${smoke_session}")
    execute_process(
      COMMAND "${package_powershell}" -NoLogo -NoProfile -NonInteractive
        -File "${pure_bonjour_filesystem_safety}" -Mode remove-tree
        -Path "${smoke_session}" -Root "${temp_root}"
      RESULT_VARIABLE session_result
      OUTPUT_VARIABLE session_output
      ERROR_VARIABLE session_error
      ENCODING UTF-8)
    if(NOT session_result EQUAL 0 OR EXISTS "${smoke_session}" OR
        IS_SYMLINK "${smoke_session}")
      list(APPEND cleanup_errors
        "smoke-session leftover ${smoke_session}: ${session_output}${session_error}")
    endif()
  endif()
  if(EXISTS "${package_verify_work_dir}" OR
      IS_SYMLINK "${package_verify_work_dir}")
    execute_process(
      COMMAND "${package_powershell}" -NoLogo -NoProfile -NonInteractive
        -File "${pure_bonjour_filesystem_safety}" -Mode remove-tree
        -Path "${package_verify_work_dir}" -Root "${scratch_root}"
      RESULT_VARIABLE scratch_result
      OUTPUT_VARIABLE scratch_output
      ERROR_VARIABLE scratch_error
      ENCODING UTF-8)
    if(NOT scratch_result EQUAL 0 OR
        EXISTS "${package_verify_work_dir}" OR
        IS_SYMLINK "${package_verify_work_dir}")
      list(APPEND cleanup_errors
        "scratch leftover ${package_verify_work_dir}: "
        "${scratch_output}${scratch_error}")
    endif()
  endif()
  string(JOIN " | " cleanup_detail ${cleanup_errors})
  set(${cleanup_output} "${cleanup_detail}" PARENT_SCOPE)
endfunction()

function(pure_bonjour_require_alias_target alias intended kind)
  if(NOT EXISTS "${alias}" AND NOT IS_SYMLINK "${alias}")
    pure_bonjour_cleanup_smoke(cleanup_detail)
    pure_bonjour_package_fail(PACKAGE_ALIAS
      "${kind} alias was not created; cleanup=[${cleanup_detail}]")
  endif()
  file(REAL_PATH "${alias}" alias_canonical)
  file(REAL_PATH "${intended}" intended_canonical)
  string(TOLOWER "${alias_canonical}" alias_identity)
  string(TOLOWER "${intended_canonical}" intended_identity)
  if(NOT alias_identity STREQUAL intended_identity)
    pure_bonjour_cleanup_smoke(cleanup_detail)
    pure_bonjour_package_fail(PACKAGE_ALIAS
      "${kind} alias canonical mismatch: ${alias_canonical} != "
      "${intended_canonical}; cleanup=[${cleanup_detail}]")
  endif()
endfunction()

pure_bonjour_create_alias("${stage_alias}" "${stage}" stage
  stage_alias_result stage_alias_detail)
if(NOT stage_alias_result EQUAL 0)
  pure_bonjour_cleanup_smoke(cleanup_detail)
  pure_bonjour_package_fail(PACKAGE_ALIAS
    "stage alias creation failed: ${stage_alias_detail}; "
    "cleanup=[${cleanup_detail}]")
endif()
pure_bonjour_require_alias_target("${stage_alias}" "${stage}" stage)

pure_bonjour_create_alias("${runtime_alias}" "${pure_prefix}" runtime
  runtime_alias_result runtime_alias_detail)
if(NOT runtime_alias_result EQUAL 0)
  pure_bonjour_cleanup_smoke(cleanup_detail)
  pure_bonjour_package_fail(PACKAGE_ALIAS
    "runtime alias creation failed: ${runtime_alias_detail}; "
    "cleanup=[${cleanup_detail}]")
endif()
pure_bonjour_require_alias_target("${runtime_alias}" "${pure_prefix}" runtime)

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DPURE_EXECUTABLE=${runtime_alias}/bin/pure.exe"
    "-DMODULE_PATH=${stage_alias}/lib/pure/bonjour.dll"
    "-DWRAPPER_PATH=${stage_alias}/lib/pure/bonjour.pure"
    "-DSMOKE_SCRIPT=${package_smoke_root}/smoke.pure"
    "-DSMOKE_ROOT=${package_smoke_root}"
    -DSMOKE_OUTER_TIMEOUT_SECONDS=30
    -DSMOKE_PORT_PROBE_TIMEOUT_SECONDS=3
    -DSMOKE_PURE_CHILD_TIMEOUT_SECONDS=20
    -DSMOKE_SETUP_CLEANUP_RESERVE_SECONDS=5
    -P "${smoke_runner}"
  RESULT_VARIABLE package_smoke_result
  OUTPUT_VARIABLE package_smoke_output
  ERROR_VARIABLE package_smoke_error
  ENCODING UTF-8)
file(STRINGS "${DEPENDENCY_REPORT}" dependency_lines ENCODING UTF-8)
pure_bonjour_cleanup_smoke(cleanup_detail)
if(NOT cleanup_detail STREQUAL "")
  pure_bonjour_package_fail(PACKAGE_ALIAS
    "scoped smoke cleanup left controlled entries: ${cleanup_detail}")
endif()
if(NOT package_smoke_result EQUAL 0)
  pure_bonjour_package_fail(PACKAGE_SMOKE
    "installed sanitized smoke failed: "
    "${package_smoke_output}${package_smoke_error}")
endif()

message(STATUS
  "PureBonjour installed package accepted: 8 files, ${total_bytes} bytes, "
  "inventory ${inventory_sha256}; dependency closure ${dependency_lines}")
