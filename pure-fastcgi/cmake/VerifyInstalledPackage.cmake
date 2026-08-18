cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS
    BUILD_DIR
    STAGE_PREFIX
    SOURCE_PREFIX
    ORIGINAL_BUILD_PREFIX
    ORIGINAL_STAGE_PREFIX
    PURE_RUNTIME_ROOT
    LLVM_READOBJ
    POWERSHELL_EXECUTABLE)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "VERIFY_INPUT_MISSING: ${required} is required")
  endif()
endforeach()
if(NOT DEFINED RUN_RUNTIME_TESTS)
  set(RUN_RUNTIME_TESTS OFF)
endif()
if(NOT DEFINED RUNTIME_TIMEOUT_SECONDS)
  set(RUNTIME_TIMEOUT_SECONDS 18)
endif()
if(NOT RUNTIME_TIMEOUT_SECONDS MATCHES "^[0-9]+([.][0-9]+)?$" OR
    RUNTIME_TIMEOUT_SECONDS LESS_EQUAL 0 OR
    RUNTIME_TIMEOUT_SECONDS GREATER 18)
  message(FATAL_ERROR
    "RUNTIME_TIMEOUT_INVALID: expected a number greater than 0 and at most 18")
endif()

function(validate_absolute_prefixes variable out_prefixes)
  set(validated)
  foreach(prefix IN LISTS ${variable})
    cmake_path(IS_ABSOLUTE prefix is_absolute)
    cmake_path(NORMAL_PATH prefix OUTPUT_VARIABLE normalized_prefix)
    if(NOT is_absolute OR NOT prefix STREQUAL normalized_prefix)
      message(FATAL_ERROR
        "PREFIX_INPUT_INVALID: ${variable} must contain normalized absolute paths")
    endif()
    list(APPEND validated "${normalized_prefix}")
  endforeach()
  set(${out_prefixes} "${validated}" PARENT_SCOPE)
endfunction()

validate_absolute_prefixes(BUILD_DIR build_prefixes)
validate_absolute_prefixes(STAGE_PREFIX stage_prefixes)
validate_absolute_prefixes(SOURCE_PREFIX source_prefixes)
validate_absolute_prefixes(ORIGINAL_BUILD_PREFIX original_build_prefixes)
validate_absolute_prefixes(ORIGINAL_STAGE_PREFIX original_stage_prefixes)
list(GET build_prefixes 0 build_dir)
list(GET stage_prefixes 0 stage)
cmake_path(ABSOLUTE_PATH PURE_RUNTIME_ROOT NORMALIZE
  OUTPUT_VARIABLE runtime_root)
if(NOT IS_DIRECTORY "${stage}")
  message(FATAL_ERROR "VERIFY_INPUT_MISSING: staged package does not exist")
endif()
if(NOT IS_DIRECTORY "${runtime_root}")
  message(FATAL_ERROR "VERIFY_INPUT_MISSING: PURE_RUNTIME_ROOT does not exist")
endif()
cmake_path(IS_PREFIX stage "${runtime_root}" NORMALIZE runtime_beneath_stage)
cmake_path(IS_PREFIX runtime_root "${stage}" NORMALIZE stage_beneath_runtime)
if(runtime_beneath_stage OR stage_beneath_runtime)
  message(FATAL_ERROR
    "RUNTIME_ROOT_NOT_SEPARATE: PURE_RUNTIME_ROOT and stage must be separate")
endif()
if(NOT EXISTS "${LLVM_READOBJ}")
  message(FATAL_ERROR "VERIFY_INPUT_MISSING: llvm-readobj does not exist")
endif()
if(NOT EXISTS "${POWERSHELL_EXECUTABLE}")
  message(FATAL_ERROR "VERIFY_INPUT_MISSING: PowerShell does not exist")
endif()

set(expected_manifest "${build_dir}/PureFastCGIExpected.sha256")
set(external_inventory "${build_dir}/PureFastCGIInventory.tsv")
set(installed_inventory
  "${stage}/share/doc/pure-fastcgi/PureFastCGIInventory.tsv")
foreach(required_file IN ITEMS
    "${expected_manifest}" "${external_inventory}" "${installed_inventory}")
  if(NOT EXISTS "${required_file}" OR IS_DIRECTORY "${required_file}")
    message(FATAL_ERROR "VERIFY_INPUT_MISSING: missing package oracle ${required_file}")
  endif()
endforeach()

string(ASCII 9 tab)
set(inventory_header
  "relative_path\tpurpose\torigin\tversion_or_commit\tsha256\tsize")

function(validate_inventory inventory_file out_lines out_paths out_hashes out_sizes)
  file(STRINGS "${inventory_file}" lines ENCODING UTF-8)
  list(LENGTH lines line_count)
  if(line_count LESS 2)
    message(FATAL_ERROR "INVENTORY_MALFORMED: ${inventory_file} has no rows")
  endif()
  list(POP_FRONT lines header)
  if(NOT header STREQUAL inventory_header)
    message(FATAL_ERROR
      "INVENTORY_MALFORMED: unexpected header in ${inventory_file}")
  endif()

  set(paths)
  set(paths_lower)
  set(hashes)
  set(sizes)
  foreach(line IN LISTS lines)
    string(REPLACE "${tab}" ";" fields "${line}")
    list(LENGTH fields field_count)
    if(NOT field_count EQUAL 6)
      message(FATAL_ERROR "INVENTORY_MALFORMED: ${line}")
    endif()
    list(GET fields 0 relative)
    list(GET fields 1 purpose)
    list(GET fields 2 origin)
    list(GET fields 3 version)
    list(GET fields 4 sha256)
    list(GET fields 5 size)
    string(LENGTH "${sha256}" sha_length)
    if(relative STREQUAL "" OR purpose STREQUAL "" OR origin STREQUAL "" OR
        version STREQUAL "" OR size STREQUAL "" OR
        NOT sha_length EQUAL 64 OR NOT sha256 MATCHES "^[0-9a-f]+$" OR
        NOT size MATCHES "^[0-9]+$")
      message(FATAL_ERROR "INVENTORY_MALFORMED: ${line}")
    endif()
    if(relative MATCHES "\\\\" OR relative MATCHES "^[A-Za-z]:" OR
        relative MATCHES "^/")
      message(FATAL_ERROR "INVENTORY_UNSAFE_PATH: ${relative}")
    endif()
    cmake_path(IS_ABSOLUTE relative is_absolute)
    cmake_path(NORMAL_PATH relative OUTPUT_VARIABLE normalized_relative)
    string(REPLACE "/" ";" segments "${relative}")
    if(is_absolute OR "." IN_LIST segments OR ".." IN_LIST segments OR
        NOT normalized_relative STREQUAL relative)
      message(FATAL_ERROR "INVENTORY_UNSAFE_PATH: ${relative}")
    endif()
    if(relative IN_LIST paths)
      message(FATAL_ERROR "INVENTORY_DUPLICATE_PATH: ${relative}")
    endif()
    string(TOLOWER "${relative}" relative_lower)
    if(relative_lower IN_LIST paths_lower)
      message(FATAL_ERROR "INVENTORY_CASE_COLLISION: ${relative}")
    endif()
    list(APPEND paths "${relative}")
    list(APPEND paths_lower "${relative_lower}")
    list(APPEND hashes "${sha256}")
    list(APPEND sizes "${size}")
  endforeach()
  set(sorted_paths "${paths}")
  list(SORT sorted_paths COMPARE STRING CASE SENSITIVE ORDER ASCENDING)
  if(NOT paths STREQUAL sorted_paths)
    message(FATAL_ERROR
      "INVENTORY_ORDER_MISMATCH: paths are not in ordinal order")
  endif()
  set(${out_lines} "${lines}" PARENT_SCOPE)
  set(${out_paths} "${paths}" PARENT_SCOPE)
  set(${out_hashes} "${hashes}" PARENT_SCOPE)
  set(${out_sizes} "${sizes}" PARENT_SCOPE)
endfunction()

# Reject forbidden FastCGI DLLs before the exact-set check so this security
# boundary retains a stable diagnostic even when the DLL is undeclared.
file(GLOB_RECURSE installed_files LIST_DIRECTORIES FALSE "${stage}/*")
foreach(installed_file IN LISTS installed_files)
  get_filename_component(installed_name "${installed_file}" NAME)
  string(TOLOWER "${installed_name}" installed_name_lower)
  if(installed_name_lower MATCHES "^libfcgi.*\\.dll$")
    message(FATAL_ERROR "FORBIDDEN_FASTCGI_DLL: ${installed_file}")
  endif()
endforeach()

validate_inventory("${external_inventory}"
  external_lines inventory_paths inventory_hashes inventory_sizes)
validate_inventory("${installed_inventory}"
  installed_lines installed_inventory_paths installed_inventory_hashes
  installed_inventory_sizes)
if(NOT installed_lines STREQUAL external_lines)
  message(FATAL_ERROR
    "INVENTORY_ORACLE_MISMATCH: installed and authoritative inventories differ")
endif()

file(STRINGS "${expected_manifest}" manifest_lines ENCODING UTF-8)
if(NOT manifest_lines)
  message(FATAL_ERROR "MANIFEST_MALFORMED: authoritative manifest is empty")
endif()
set(manifest_paths)
set(manifest_paths_lower)
set(manifest_hashes)
foreach(line IN LISTS manifest_lines)
  string(LENGTH "${line}" line_length)
  if(line_length LESS 67)
    message(FATAL_ERROR "MANIFEST_MALFORMED: ${line}")
  endif()
  string(SUBSTRING "${line}" 0 64 sha256)
  string(SUBSTRING "${line}" 64 2 separator)
  string(SUBSTRING "${line}" 66 -1 relative)
  if(NOT sha256 MATCHES "^[0-9a-f]+$" OR NOT separator STREQUAL "  " OR
      relative STREQUAL "" OR relative MATCHES "\\\\" OR
      relative MATCHES "^[A-Za-z]:" OR relative MATCHES "^/")
    message(FATAL_ERROR "MANIFEST_MALFORMED: ${line}")
  endif()
  cmake_path(IS_ABSOLUTE relative is_absolute)
  cmake_path(NORMAL_PATH relative OUTPUT_VARIABLE normalized_relative)
  string(REPLACE "/" ";" segments "${relative}")
  if(is_absolute OR "." IN_LIST segments OR ".." IN_LIST segments OR
      NOT normalized_relative STREQUAL relative)
    message(FATAL_ERROR "MANIFEST_UNSAFE_PATH: ${relative}")
  endif()
  string(TOLOWER "${relative}" relative_lower)
  if(relative IN_LIST manifest_paths)
    message(FATAL_ERROR "MANIFEST_DUPLICATE_PATH: ${relative}")
  elseif(relative_lower IN_LIST manifest_paths_lower)
    message(FATAL_ERROR "MANIFEST_CASE_COLLISION: ${relative}")
  endif()
  list(APPEND manifest_paths "${relative}")
  list(APPEND manifest_paths_lower "${relative_lower}")
  list(APPEND manifest_hashes "${sha256}")
endforeach()

set(payload_manifest_paths "${manifest_paths}")
list(REMOVE_ITEM payload_manifest_paths
  "share/doc/pure-fastcgi/PureFastCGIInventory.tsv")
set(sorted_inventory_paths "${inventory_paths}")
list(SORT payload_manifest_paths COMPARE STRING CASE SENSITIVE ORDER ASCENDING)
list(SORT sorted_inventory_paths COMPARE STRING CASE SENSITIVE ORDER ASCENDING)
if(NOT payload_manifest_paths STREQUAL sorted_inventory_paths)
  message(FATAL_ERROR
    "INVENTORY_FILE_SET_MISMATCH: authoritative inventory and manifest differ")
endif()

if(REMOVE_OWNED)
  # Only the authoritative external inventory determines payload ownership.
  # The installed inventory file itself is a fixed component metadata path;
  # neither the external SHA manifest nor staged inventory can add ownership.
  set(owned_paths ${inventory_paths}
    "share/doc/pure-fastcgi/PureFastCGIInventory.tsv")
  foreach(relative IN LISTS owned_paths)
    set(owned_file "${stage}/${relative}")
    cmake_path(NORMAL_PATH owned_file OUTPUT_VARIABLE normalized_owned_file)
    cmake_path(IS_PREFIX stage "${normalized_owned_file}" NORMALIZE
      owned_file_beneath_stage)
    if(NOT owned_file_beneath_stage OR normalized_owned_file STREQUAL stage)
      message(FATAL_ERROR "REMOVAL_PATH_ESCAPE: ${relative}")
    endif()
    if(EXISTS "${normalized_owned_file}" AND
        NOT IS_DIRECTORY "${normalized_owned_file}")
      file(REMOVE "${normalized_owned_file}")
    endif()
  endforeach()

  # Only the component-specific documentation directory is exclusively owned.
  # Shared ancestors (lib, lib/pure, share, and share/doc) are never removed.
  set(owned_doc_dir "${stage}/share/doc/pure-fastcgi")
  if(IS_DIRECTORY "${owned_doc_dir}")
    file(GLOB owned_doc_entries LIST_DIRECTORIES TRUE "${owned_doc_dir}/*")
    if(NOT owned_doc_entries)
      set(ENV{PURE_FASTCGI_REMOVE_DIRECTORY} "${owned_doc_dir}")
      execute_process(
        COMMAND "${POWERSHELL_EXECUTABLE}"
          -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass
          -Command
            "[IO.Directory]::Delete(\$env:PURE_FASTCGI_REMOVE_DIRECTORY,\$false)"
        RESULT_VARIABLE remove_dir_result
        OUTPUT_VARIABLE remove_dir_output
        ERROR_VARIABLE remove_dir_error
        ENCODING UTF-8)
      unset(ENV{PURE_FASTCGI_REMOVE_DIRECTORY})
      if(NOT remove_dir_result EQUAL 0 OR IS_DIRECTORY "${owned_doc_dir}")
        message(FATAL_ERROR
          "OWNED_DIRECTORY_REMOVE_FAILED: ${owned_doc_dir}\n"
          "stdout:\n${remove_dir_output}\nstderr:\n${remove_dir_error}")
      endif()
    endif()
  endif()
  message(STATUS "Removed inventory-owned PureFastCGI files")
  return()
endif()

set(installed_paths)
foreach(installed_file IN LISTS installed_files)
  file(RELATIVE_PATH relative "${stage}" "${installed_file}")
  string(REPLACE "\\" "/" relative "${relative}")
  list(APPEND installed_paths "${relative}")
endforeach()
list(SORT installed_paths COMPARE STRING CASE SENSITIVE ORDER ASCENDING)
set(sorted_manifest_paths "${manifest_paths}")
list(SORT sorted_manifest_paths COMPARE STRING CASE SENSITIVE ORDER ASCENDING)
if(NOT installed_paths STREQUAL sorted_manifest_paths)
  message(FATAL_ERROR
    "PACKAGE_FILE_SET_MISMATCH: staged payload differs from the manifest\n"
    "staged: ${installed_paths}\nmanifest: ${sorted_manifest_paths}")
endif()

set(leak_prefixes
  ${build_prefixes}
  ${stage_prefixes}
  ${source_prefixes}
  ${original_build_prefixes}
  ${original_stage_prefixes})
list(REMOVE_DUPLICATES leak_prefixes)
set(prefix_scanner "${CMAKE_CURRENT_LIST_DIR}/ScanPrefixLeaks.ps1")
if(NOT EXISTS "${prefix_scanner}")
  message(FATAL_ERROR "VERIFY_INPUT_MISSING: prefix scanner does not exist")
endif()
foreach(prefix IN LISTS leak_prefixes)
  foreach(installed_file IN LISTS installed_files)
    execute_process(
      COMMAND "${POWERSHELL_EXECUTABLE}"
        -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass
        -File "${prefix_scanner}"
        -FilePath "${installed_file}"
        -Prefix "${prefix}"
      RESULT_VARIABLE scan_result
      OUTPUT_VARIABLE scan_output
      ERROR_VARIABLE scan_error
      ENCODING UTF-8)
    if(scan_result EQUAL 42)
      message(FATAL_ERROR
        "PACKAGE_PREFIX_LEAK: ${installed_file} contains ${prefix}")
    elseif(NOT scan_result EQUAL 0)
      message(FATAL_ERROR
        "PREFIX_SCAN_FAILED: ${installed_file} (${scan_result})\n"
        "stdout:\n${scan_output}\nstderr:\n${scan_error}")
    endif()
  endforeach()
endforeach()

list(LENGTH manifest_paths manifest_count)
math(EXPR manifest_last "${manifest_count} - 1")
foreach(index RANGE 0 ${manifest_last})
  list(GET manifest_paths ${index} relative)
  list(GET manifest_hashes ${index} expected_sha)
  file(SHA256 "${stage}/${relative}" actual_sha)
  string(TOLOWER "${actual_sha}" actual_sha)
  if(NOT actual_sha STREQUAL expected_sha)
    message(FATAL_ERROR "PACKAGE_HASH_MISMATCH: ${relative}")
  endif()
endforeach()

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
    message(FATAL_ERROR "INVENTORY_METADATA_MISMATCH: ${relative}")
  endif()
endforeach()

# Build case-insensitive maps of component-owned and explicitly declared
# external runtime DLLs. Every non-system import must resolve through one of
# these two maps, and the external map is rooted solely at PURE_RUNTIME_ROOT.
set(component_pe_names)
set(component_pe_paths)
foreach(installed_file IN LISTS installed_files)
  if(installed_file MATCHES "\\.(dll|exe)$")
    get_filename_component(name "${installed_file}" NAME)
    string(TOLOWER "${name}" name_lower)
    list(APPEND component_pe_names "${name_lower}")
    list(APPEND component_pe_paths "${installed_file}")
  endif()
endforeach()

set(declared_runtime_names
  libpure.dll
  libgmp-10.dll
  libmpfr-6.dll
  libpcreposix-0.dll
  libpcre-1.dll
  libwinpthread-1.dll
  libiconv-2.dll
  libc++.dll
  libgcc_s_seh-1.dll
  libstdc++-6.dll
  libunwind.dll
  zlib1.dll
  libzstd.dll)
file(GLOB runtime_dlls LIST_DIRECTORIES FALSE "${runtime_root}/*.dll")
set(runtime_names)
set(runtime_paths)
foreach(runtime_dll IN LISTS runtime_dlls)
  get_filename_component(name "${runtime_dll}" NAME)
  string(TOLOWER "${name}" name_lower)
  list(APPEND runtime_names "${name_lower}")
  list(APPEND runtime_paths "${runtime_dll}")
endforeach()

set(system_dlls
  advapi32.dll
  api-ms-win-crt-convert-l1-1-0.dll
  api-ms-win-crt-environment-l1-1-0.dll
  api-ms-win-crt-filesystem-l1-1-0.dll
  api-ms-win-crt-heap-l1-1-0.dll
  api-ms-win-crt-locale-l1-1-0.dll
  api-ms-win-crt-math-l1-1-0.dll
  api-ms-win-crt-multibyte-l1-1-0.dll
  api-ms-win-crt-private-l1-1-0.dll
  api-ms-win-crt-process-l1-1-0.dll
  api-ms-win-crt-runtime-l1-1-0.dll
  api-ms-win-crt-stdio-l1-1-0.dll
  api-ms-win-crt-string-l1-1-0.dll
  api-ms-win-crt-time-l1-1-0.dll
  api-ms-win-crt-utility-l1-1-0.dll
  kernel32.dll
  ntdll.dll
  ole32.dll
  shell32.dll
  ws2_32.dll)
set(pe_queue "${component_pe_paths}")
set(pe_seen)
include("${CMAKE_CURRENT_LIST_DIR}/ParseCoffImports.cmake")
while(pe_queue)
  list(POP_FRONT pe_queue pe_file)
  cmake_path(NORMAL_PATH pe_file OUTPUT_VARIABLE normalized_pe)
  string(TOLOWER "${normalized_pe}" normalized_pe_lower)
  if(normalized_pe_lower IN_LIST pe_seen)
    continue()
  endif()
  list(APPEND pe_seen "${normalized_pe_lower}")
  execute_process(
    COMMAND "${LLVM_READOBJ}" --coff-imports "${pe_file}"
    RESULT_VARIABLE read_result
    OUTPUT_VARIABLE read_output
    ERROR_VARIABLE read_error
    ENCODING UTF-8)
  if(NOT read_result EQUAL 0)
    message(FATAL_ERROR
      "PE_PARSE_FAILED: llvm-readobj rejected ${pe_file}: ${read_error}")
  endif()
  pure_fastcgi_parse_coff_imports(
    "${read_output}" import_names import_parse_error)
  if(NOT import_parse_error STREQUAL "")
    message(FATAL_ERROR
      "PE_PARSE_FAILED: malformed llvm-readobj output for ${pe_file}: "
      "${import_parse_error}")
  endif()
  foreach(import_name IN LISTS import_names)
    string(TOLOWER "${import_name}" import_lower)
    if(import_lower MATCHES "^libfcgi.*\\.dll$")
      message(FATAL_ERROR
        "FORBIDDEN_FASTCGI_DLL: ${pe_file} imports ${import_name}")
    endif()
    if(import_lower IN_LIST system_dlls)
      continue()
    endif()
    list(FIND component_pe_names "${import_lower}" component_index)
    if(NOT component_index EQUAL -1)
      list(GET component_pe_paths ${component_index} resolved_import)
      list(APPEND pe_queue "${resolved_import}")
      continue()
    endif()
    if(NOT import_lower IN_LIST declared_runtime_names)
      message(FATAL_ERROR
        "PE_UNDECLARED_IMPORT: ${pe_file} imports ${import_name}")
    endif()
    list(FIND runtime_names "${import_lower}" runtime_index)
    if(runtime_index EQUAL -1)
      message(FATAL_ERROR
        "PE_RUNTIME_MISSING: ${import_name} is not beneath PURE_RUNTIME_ROOT")
    endif()
    list(GET runtime_paths ${runtime_index} resolved_import)
    list(APPEND pe_queue "${resolved_import}")
  endforeach()
endwhile()

if(RUN_RUNTIME_TESTS)
  foreach(required IN ITEMS PROTOCOL_HARNESS PROTOCOL_WORKER)
    if(NOT DEFINED ${required} OR NOT EXISTS "${${required}}")
      message(FATAL_ERROR "VERIFY_INPUT_MISSING: ${required} is required")
    endif()
  endforeach()
  set(relocated_module_dir "${stage}/lib/pure")
  get_filename_component(worker_name "${PROTOCOL_WORKER}" NAME)
  set(relocated_worker "${relocated_module_dir}/${worker_name}")
  file(COPY_FILE "${PROTOCOL_WORKER}" "${relocated_worker}")
  string(RANDOM LENGTH 16 ALPHABET 0123456789abcdef runtime_alias_id)
  set(runtime_alias "$ENV{TEMP}/PureFastCGI-relocation-${runtime_alias_id}")
  set(ENV{PURE_FASTCGI_RUNTIME_ALIAS} "${runtime_alias}")
  set(ENV{PURE_FASTCGI_RUNTIME_TARGET} "${relocated_module_dir}")
  execute_process(
    COMMAND "${POWERSHELL_EXECUTABLE}"
      -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass
      -Command
        "New-Item -ItemType Junction -Path \$env:PURE_FASTCGI_RUNTIME_ALIAS -Target \$env:PURE_FASTCGI_RUNTIME_TARGET -ErrorAction Stop | Out-Null"
    RESULT_VARIABLE alias_result
    OUTPUT_VARIABLE alias_output
    ERROR_VARIABLE alias_error
    ENCODING UTF-8)
  unset(ENV{PURE_FASTCGI_RUNTIME_TARGET})
  if(NOT alias_result EQUAL 0 OR NOT IS_DIRECTORY "${runtime_alias}")
    file(REMOVE "${relocated_worker}")
    message(FATAL_ERROR
      "RUNTIME_ALIAS_FAILED: could not create relocation junction\n"
      "stdout:\n${alias_output}\nstderr:\n${alias_error}")
  endif()
  file(REAL_PATH "${runtime_alias}" runtime_alias_target)
  file(REAL_PATH "${relocated_module_dir}" relocated_module_real)
  if(NOT runtime_alias_target STREQUAL relocated_module_real)
    message(FATAL_ERROR "RUNTIME_ALIAS_FAILED: junction target mismatch")
  endif()
  set(ENV{PATH}
    "${runtime_alias};${runtime_root};$ENV{SystemRoot}\\System32;$ENV{SystemRoot};$ENV{SystemRoot}\\System32\\Wbem")
  unset(ENV{PURELIB})
  execute_process(
    COMMAND "${PROTOCOL_HARNESS}" "${runtime_root}/pure.exe"
      "${runtime_alias}" "${runtime_alias}/${worker_name}"
    RESULT_VARIABLE smoke_result
    OUTPUT_VARIABLE smoke_output
    ERROR_VARIABLE smoke_error
    TIMEOUT "${RUNTIME_TIMEOUT_SECONDS}"
    ENCODING UTF-8)
  file(REMOVE "${relocated_worker}")
  execute_process(
    COMMAND "${POWERSHELL_EXECUTABLE}"
      -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass
      -Command
        "[IO.Directory]::Delete(\$env:PURE_FASTCGI_RUNTIME_ALIAS,\$false)"
    RESULT_VARIABLE alias_remove_result
    ERROR_VARIABLE alias_remove_error
    ENCODING UTF-8)
  unset(ENV{PURE_FASTCGI_RUNTIME_ALIAS})
  if(NOT alias_remove_result EQUAL 0 OR EXISTS "${runtime_alias}")
    message(FATAL_ERROR
      "RUNTIME_ALIAS_FAILED: could not remove relocation junction\n"
      "${alias_remove_error}")
  endif()
  string(TOLOWER "${smoke_result}" smoke_result_lower)
  if(smoke_result_lower MATCHES "timeout")
    message(FATAL_ERROR
      "RUNTIME_SMOKE_TIMEOUT: deadline expired; alias=${runtime_alias}\n"
      "stdout:\n${smoke_output}\nstderr:\n${smoke_error}")
  endif()
  if(NOT smoke_result EQUAL 0)
    message(FATAL_ERROR
      "RUNTIME_SMOKE_FAILED: ${smoke_result}\n"
      "stdout:\n${smoke_output}\nstderr:\n${smoke_error}")
  endif()
  if(NOT smoke_output MATCHES "pure-fastcgi protocol smoke passed")
    message(FATAL_ERROR
      "RUNTIME_SMOKE_FAILED: success marker missing\n"
      "stdout:\n${smoke_output}\nstderr:\n${smoke_error}")
  endif()
  string(REPLACE "\\" "/" relocated_module_dir_display
    "${relocated_module_dir}")
  message(STATUS "RUNTIME_MODULE_DIR=${relocated_module_dir_display}")
endif()

list(LENGTH pe_seen pe_count)
message(STATUS
  "Verified installed PureFastCGI: ${manifest_count} exact files, "
  "${inventory_count} inventory rows, ${pe_count} recursively checked PEs")
