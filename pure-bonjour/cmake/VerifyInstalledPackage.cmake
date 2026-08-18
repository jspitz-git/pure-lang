cmake_minimum_required(VERSION 3.25)

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

# PowerShell is used only for byte-accurate traversal properties which CMake
# cannot portably expose on Windows: every reparse point is rejected without
# following it, and prefix bytes are searched as UTF-8/ASCII and UTF-16LE.
set(package_powershell
  "$ENV{SystemRoot}/System32/WindowsPowerShell/v1.0/powershell.exe")
if(NOT EXISTS "${package_powershell}")
  pure_bonjour_package_fail(PACKAGE_SET
    "Windows PowerShell is required for safe package traversal")
endif()

cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE stage_input)
string(SHA256 verify_id "${stage_input}")
set(verify_work_dir
  "${CMAKE_CURRENT_BINARY_DIR}/PureBonjourPackageVerify-${verify_id}")
file(REMOVE_RECURSE "${verify_work_dir}")
file(MAKE_DIRECTORY "${verify_work_dir}")
set(stage_scanner "${verify_work_dir}/scan-stage.ps1")
file(WRITE "${stage_scanner}" [=[
param(
  [Parameter(Mandatory=$true)][string]$Stage,
  [Parameter(Mandatory=$true)][ValidateSet('reparse','prefix')][string]$Mode,
  [string]$PrefixFile = ''
)
$ErrorActionPreference = 'Stop'

function Stop-Scan([string]$Kind, [string]$Path) {
  [Console]::Error.WriteLine(('{0}|{1}' -f $Kind, $Path))
  exit 73
}

$byteEncoding = [Text.Encoding]::GetEncoding(28591)
$patterns = [Collections.Generic.List[Text.RegularExpressions.Regex]]::new()
$patternNames = [Collections.Generic.List[string]]::new()
$patternKeys = [Collections.Generic.HashSet[string]]::new(
  [StringComparer]::Ordinal)
if ($Mode -eq 'prefix') {
  if (-not (Test-Path -LiteralPath $PrefixFile -PathType Leaf)) {
    Stop-Scan 'PREFIX_INPUT' $PrefixFile
  }
  foreach ($prefix in [IO.File]::ReadAllLines($PrefixFile,
      [Text.Encoding]::UTF8)) {
    if ([String]::IsNullOrWhiteSpace($prefix)) { continue }
    $variants = @(
      $prefix,
      $prefix.Replace('/', '\'),
      $prefix.Replace('\', '/'))
    foreach ($variant in $variants) {
      foreach ($encoding in @([Text.Encoding]::UTF8, [Text.Encoding]::Unicode)) {
        $bytes = $encoding.GetBytes($variant)
        $key = [Convert]::ToBase64String($bytes)
        if ($patternKeys.Add($key)) {
          $expression = [Text.StringBuilder]::new()
          foreach ($value in $bytes) {
            if (($value -ge 65 -and $value -le 90) -or
                ($value -ge 97 -and $value -le 122)) {
              $lower = $value
              if ($lower -le 90) { $lower += 32 }
              $upper = $lower - 32
              [void]$expression.Append(('[{0}{1}]' -f
                [char]$upper, [char]$lower))
            } else {
              [void]$expression.Append(('\x{0:X2}' -f $value))
            }
          }
          $options = [Text.RegularExpressions.RegexOptions]::Compiled -bor
            [Text.RegularExpressions.RegexOptions]::CultureInvariant
          $patterns.Add([Text.RegularExpressions.Regex]::new(
            $expression.ToString(), $options))
          $patternNames.Add($variant)
        }
      }
    }
  }
}

$root = Get-Item -LiteralPath $Stage -Force
if (($root.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
  Stop-Scan 'REPARSE' $root.FullName
}
if (-not $root.PSIsContainer) { Stop-Scan 'NOT_DIRECTORY' $root.FullName }
$pending = [Collections.Generic.Stack[IO.DirectoryInfo]]::new()
$pending.Push([IO.DirectoryInfo]$root)
while ($pending.Count -gt 0) {
  $directory = $pending.Pop()
  foreach ($entry in $directory.EnumerateFileSystemInfos()) {
    if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      Stop-Scan 'REPARSE' $entry.FullName
    }
    if (($entry.Attributes -band [IO.FileAttributes]::Directory) -ne 0) {
      $pending.Push([IO.DirectoryInfo]$entry)
      continue
    }
    if ($Mode -eq 'prefix') {
      $contents = $byteEncoding.GetString(
        [IO.File]::ReadAllBytes($entry.FullName))
      for ($patternIndex = 0; $patternIndex -lt $patterns.Count;
          ++$patternIndex) {
        if ($patterns[$patternIndex].IsMatch($contents)) {
          Stop-Scan ('PREFIX:' + $patternNames[$patternIndex]) $entry.FullName
        }
      }
    }
  }
}
]=])

function(pure_bonjour_scan_stage mode prefix_file)
  execute_process(
    COMMAND "${package_powershell}" -NoLogo -NoProfile -NonInteractive
      -File "${stage_scanner}" -Stage "${stage_input}" -Mode "${mode}"
      -PrefixFile "${prefix_file}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8)
  if(NOT result EQUAL 0)
    if(mode STREQUAL "prefix")
      pure_bonjour_package_fail(PACKAGE_PREFIX
        "stage contains a build-machine prefix: ${output}${error}")
    else()
      pure_bonjour_package_fail(PACKAGE_SET
        "stage contains a reparse point or unsafe entry: ${output}${error}")
    endif()
  endif()
endfunction()

# This pass uses the spelling supplied by the caller, so a reparse point at the
# stage root cannot disappear through canonicalization.
pure_bonjour_scan_stage(reparse "")

file(REAL_PATH "${stage_input}" stage)
file(REAL_PATH "${SOURCE_PREFIX}" source_prefix)
file(REAL_PATH "${BUILD_PREFIX}" build_prefix)
file(REAL_PATH "${PURE_PREFIX}" pure_prefix)

set(oracle_input "${BUILD_PREFIX}/PureBonjourExpected.sha256")
if(NOT EXISTS "${oracle_input}" OR IS_DIRECTORY "${oracle_input}" OR
    IS_SYMLINK "${oracle_input}")
  pure_bonjour_package_fail(PACKAGE_INVENTORY
    "external expected-hash oracle is missing or indirect: ${oracle_input}")
endif()
file(REAL_PATH "${oracle_input}" oracle)
cmake_path(IS_PREFIX stage "${oracle}" NORMALIZE oracle_inside_stage)
if(oracle_inside_stage)
  pure_bonjour_package_fail(PACKAGE_INVENTORY
    "deletion/hash authority must remain outside the mutable stage: ${oracle}")
endif()

set(expected_paths
  lib/pure/bonjour.dll
  lib/pure/bonjour.pure
  share/doc/pure-bonjour/COPYING
  share/doc/pure-bonjour/COPYING.LESSER
  share/doc/pure-bonjour/PureBonjourInventory.tsv
  share/doc/pure-bonjour/README
  share/doc/pure-bonjour/WINDOWS.md
  share/doc/pure-bonjour/examples/bonjour_examp.pure)
list(SORT expected_paths)
set(inventory_relative
  "share/doc/pure-bonjour/PureBonjourInventory.tsv")

function(pure_bonjour_validate_relative_path relative context path_output
    identity_output)
  if(relative STREQUAL "" OR IS_ABSOLUTE "${relative}" OR
      relative MATCHES "^[A-Za-z]:" OR relative MATCHES "^[/\\\\]" OR
      relative MATCHES "(^|[/\\\\])\\.\\.([/\\\\]|$)" OR
      relative MATCHES "(^|[/\\\\])\\.([/\\\\]|$)" OR
      relative MATCHES "//|\\\\|:|[*?]" OR
      NOT relative MATCHES "^[A-Za-z0-9._/+ -]+$")
    pure_bonjour_package_fail(PACKAGE_INVENTORY
      "${context} contains unsafe relative path: ${relative}")
  endif()
  set(normalized "${relative}")
  cmake_path(NORMAL_PATH normalized)
  if(NOT normalized STREQUAL relative)
    pure_bonjour_package_fail(PACKAGE_INVENTORY
      "${context} path is not canonical: ${relative}")
  endif()
  string(TOLOWER "${normalized}" identity)
  set(${path_output} "${normalized}" PARENT_SCOPE)
  set(${identity_output} "${identity}" PARENT_SCOPE)
endfunction()

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

# Parse the external oracle separately.  It authenticates all eight installed
# files, including the mutable inventory, but its contents are never installed.
file(STRINGS "${oracle}" oracle_lines ENCODING UTF-8)
list(LENGTH oracle_lines oracle_line_count)
if(NOT oracle_line_count EQUAL 8)
  pure_bonjour_package_fail(PACKAGE_INVENTORY
    "external expected-hash oracle must contain exactly eight rows")
endif()
set(oracle_paths)
set(oracle_identities)
set(oracle_hashes)
foreach(line IN LISTS oracle_lines)
  string(LENGTH "${line}" line_length)
  if(line_length LESS 67)
    pure_bonjour_package_fail(PACKAGE_INVENTORY
      "external expected-hash oracle row is malformed: ${line}")
  endif()
  string(SUBSTRING "${line}" 0 64 expected_sha)
  string(SUBSTRING "${line}" 64 2 separator)
  string(SUBSTRING "${line}" 66 -1 relative)
  string(LENGTH "${expected_sha}" sha_length)
  if(NOT sha_length EQUAL 64 OR
      NOT expected_sha MATCHES "^[0-9A-Fa-f]+$" OR
      NOT separator STREQUAL "  ")
    pure_bonjour_package_fail(PACKAGE_INVENTORY
      "external expected-hash oracle row is malformed: ${line}")
  endif()
  pure_bonjour_validate_relative_path(
    "${relative}" "external expected-hash oracle" normalized identity)
  if(identity IN_LIST oracle_identities)
    pure_bonjour_package_fail(PACKAGE_INVENTORY
      "external expected-hash oracle repeats a case-folded path: ${relative}")
  endif()
  string(TOLOWER "${expected_sha}" expected_sha)
  list(APPEND oracle_paths "${normalized}")
  list(APPEND oracle_identities "${identity}")
  list(APPEND oracle_hashes "${expected_sha}")
endforeach()

set(sorted_oracle_paths "${oracle_paths}")
list(SORT sorted_oracle_paths)
if(NOT sorted_oracle_paths STREQUAL expected_paths)
  pure_bonjour_package_fail(PACKAGE_SET
    "external oracle ownership set differs from the exact eight paths: "
    "${sorted_oracle_paths}")
endif()
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

set(prefix_file "${verify_work_dir}/forbidden-prefixes.txt")
file(WRITE "${prefix_file}"
  "${source_prefix}\n${build_prefix}\n${stage}\n")
pure_bonjour_scan_stage(prefix "${prefix_file}")

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

get_filename_component(cmake_program_directory "${CMAKE_COMMAND}" DIRECTORY)
find_program(package_llvm_readobj NAMES llvm-readobj.exe llvm-readobj
  HINTS "${cmake_program_directory}")
if(NOT package_llvm_readobj)
  pure_bonjour_package_fail(PACKAGE_SET "llvm-readobj is required")
endif()
set(LLVM_READOBJ "${package_llvm_readobj}")
set(MODULE "${stage}/lib/pure/bonjour.dll")
set(PURE_PREFIX "${pure_prefix}")
set(VERIFY_WORK_DIR "${verify_work_dir}/dependency-audit")
set(DEPENDENCY_REPORT "${verify_work_dir}/PureBonjourDependencies.tsv")
include("${dependency_verifier}")

set(pure_executable "${pure_prefix}/bin/pure.exe")
if(NOT EXISTS "${pure_executable}" OR IS_DIRECTORY "${pure_executable}")
  pure_bonjour_package_fail(PACKAGE_SET
    "installed Pure executable is missing: ${pure_executable}")
endif()
set(temp_root "$ENV{TEMP}")
if(temp_root STREQUAL "" OR NOT IS_ABSOLUTE "${temp_root}")
  set(temp_root "${verify_work_dir}")
endif()
set(package_smoke_root "${temp_root}/PureBonjourPackageSmoke-${verify_id}")
file(REMOVE_RECURSE "${package_smoke_root}")
file(MAKE_DIRECTORY "${package_smoke_root}")
file(COPY_FILE "${smoke_source}" "${package_smoke_root}/smoke.pure"
  ONLY_IF_DIFFERENT)

# Pure 0.68 and cmake -E env exchange PATH through narrow Windows strings.  A
# controlled ASCII junction outside the already-audited stage lets the existing
# sanitized runner exercise the same physical relocated files even when their
# canonical prefix contains non-ASCII characters.  These aliases are never
# used for ownership, hash, or dependency decisions and are explicitly removed.
string(RANDOM LENGTH 12 ALPHABET 0123456789abcdef smoke_alias_nonce)
set(stage_alias
  "${temp_root}/PureBonjourStageAlias-${verify_id}-${smoke_alias_nonce}")
set(runtime_alias
  "${temp_root}/PureBonjourRuntimeAlias-${verify_id}-${smoke_alias_nonce}")
cmake_path(NATIVE_PATH stage_alias NORMALIZE stage_alias_native)
cmake_path(NATIVE_PATH runtime_alias NORMALIZE runtime_alias_native)
cmake_path(NATIVE_PATH stage NORMALIZE stage_native)
cmake_path(NATIVE_PATH pure_prefix NORMALIZE pure_prefix_native)
execute_process(
  COMMAND "$ENV{COMSPEC}" /d /c mklink /J
    "${stage_alias_native}" "${stage_native}"
  RESULT_VARIABLE stage_alias_result
  OUTPUT_VARIABLE stage_alias_output
  ERROR_VARIABLE stage_alias_error
  ENCODING UTF-8)
if(NOT stage_alias_result EQUAL 0)
  file(REMOVE_RECURSE "${package_smoke_root}")
  pure_bonjour_package_fail(PACKAGE_SET
    "could not create scoped installed-stage smoke alias: "
    "${stage_alias_output}${stage_alias_error}")
endif()
execute_process(
  COMMAND "$ENV{COMSPEC}" /d /c mklink /J
    "${runtime_alias_native}" "${pure_prefix_native}"
  RESULT_VARIABLE runtime_alias_result
  OUTPUT_VARIABLE runtime_alias_output
  ERROR_VARIABLE runtime_alias_error
  ENCODING UTF-8)
if(NOT runtime_alias_result EQUAL 0)
  execute_process(
    COMMAND "$ENV{COMSPEC}" /d /c rmdir "${stage_alias_native}")
  file(REMOVE_RECURSE "${package_smoke_root}")
  pure_bonjour_package_fail(PACKAGE_SET
    "could not create scoped Pure-runtime smoke alias: "
    "${runtime_alias_output}${runtime_alias_error}")
endif()

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
execute_process(
  COMMAND "$ENV{COMSPEC}" /d /c rmdir "${runtime_alias_native}"
  RESULT_VARIABLE runtime_alias_remove_result
  OUTPUT_VARIABLE runtime_alias_remove_output
  ERROR_VARIABLE runtime_alias_remove_error
  ENCODING UTF-8)
execute_process(
  COMMAND "$ENV{COMSPEC}" /d /c rmdir "${stage_alias_native}"
  RESULT_VARIABLE stage_alias_remove_result
  OUTPUT_VARIABLE stage_alias_remove_output
  ERROR_VARIABLE stage_alias_remove_error
  ENCODING UTF-8)
file(REMOVE_RECURSE "${package_smoke_root}")
if(NOT runtime_alias_remove_result EQUAL 0 OR
    NOT stage_alias_remove_result EQUAL 0)
  pure_bonjour_package_fail(PACKAGE_SET
    "could not remove scoped smoke aliases: "
    "${runtime_alias_remove_output}${runtime_alias_remove_error}"
    "${stage_alias_remove_output}${stage_alias_remove_error}")
endif()
if(NOT package_smoke_result EQUAL 0)
  pure_bonjour_package_fail(PACKAGE_SMOKE
    "installed sanitized smoke failed: "
    "${package_smoke_output}${package_smoke_error}")
endif()

file(STRINGS "${DEPENDENCY_REPORT}" dependency_lines ENCODING UTF-8)
message(STATUS
  "PureBonjour installed package accepted: 8 files, ${total_bytes} bytes, "
  "inventory ${inventory_sha256}; dependency closure ${dependency_lines}")
