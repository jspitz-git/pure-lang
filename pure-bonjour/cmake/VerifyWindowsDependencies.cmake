cmake_minimum_required(VERSION 3.25)

set(pure_bonjour_system_dlls
  advapi32.dll
  bcrypt.dll
  cfgmgr32.dll
  comdlg32.dll
  crypt32.dll
  dnsapi.dll
  gdi32.dll
  imm32.dll
  kernel32.dll
  kernelbase.dll
  ntdll.dll
  ole32.dll
  oleaut32.dll
  psapi.dll
  rpcrt4.dll
  sechost.dll
  setupapi.dll
  shell32.dll
  shlwapi.dll
  ucrtbase.dll
  user32.dll
  version.dll
  winmm.dll
  ws2_32.dll)

set(pure_bonjour_runtime_dlls
  libc++.dll
  libgcc_s_seh-1.dll
  libgmp-10.dll
  libiconv-2.dll
  libmpfr-6.dll
  libpcre-1.dll
  libpcreposix-0.dll
  libpure.dll
  libstdc++-6.dll
  libunwind.dll
  libwinpthread-1.dll
  libzstd.dll
  zlib1.dll)

function(pure_bonjour_fail token detail)
  message(FATAL_ERROR "${token}: ${detail}")
endfunction()

function(pure_bonjour_is_system_dll import_name output_variable)
  string(TOLOWER "${import_name}" import_lower)
  if(import_lower IN_LIST pure_bonjour_system_dlls OR
      import_lower MATCHES "^(api|ext)-ms-win-[a-z0-9-]+\\.dll$")
    set(${output_variable} TRUE PARENT_SCOPE)
  else()
    set(${output_variable} FALSE PARENT_SCOPE)
  endif()
endfunction()

function(pure_bonjour_check_forbidden import_name owner)
  string(TOLOWER "${import_name}" import_lower)
  if(import_lower STREQUAL "dnssd.dll" OR
      import_lower MATCHES "(apple|bonjour|mdnsresponder)" OR
      import_lower MATCHES "^msys-[^/\\\\]*\\.dll$" OR
      import_lower MATCHES "^cygwin[^/\\\\]*\\.dll$")
    pure_bonjour_fail(IMPORT_FORBIDDEN
      "${owner} imports forbidden Apple/MSYS2 runtime ${import_name}")
  endif()
endfunction()

function(pure_bonjour_parse_import_listing listing_file expected_owner
    output_imports)
  if(NOT EXISTS "${listing_file}" OR IS_DIRECTORY "${listing_file}")
    pure_bonjour_fail(IMPORTS_MISSING "listing does not exist: ${listing_file}")
  endif()

  file(STRINGS "${listing_file}" lines ENCODING UTF-8)
  list(FILTER lines EXCLUDE REGEX "^$")
  list(LENGTH lines line_count)
  if(line_count LESS 4)
    pure_bonjour_fail(IMPORTS_MALFORMED
      "${expected_owner} listing has an incomplete header")
  endif()

  list(GET lines 0 file_line)
  list(GET lines 1 format_line)
  list(GET lines 2 arch_line)
  list(GET lines 3 address_line)
  if(NOT file_line MATCHES "^File: (.+)$" OR
      NOT format_line STREQUAL "Format: COFF-x86-64" OR
      NOT arch_line STREQUAL "Arch: x86_64" OR
      NOT address_line STREQUAL "AddressSize: 64bit")
    pure_bonjour_fail(IMPORTS_MALFORMED
      "${expected_owner} listing has an invalid llvm-readobj header")
  endif()
  set(listed_file "${CMAKE_MATCH_1}")
  get_filename_component(listed_name "${listed_file}" NAME)
  get_filename_component(expected_name "${expected_owner}" NAME)
  string(TOLOWER "${listed_name}" listed_name_lower)
  string(TOLOWER "${expected_name}" expected_name_lower)
  if(NOT listed_name_lower STREQUAL expected_name_lower)
    pure_bonjour_fail(IMPORTS_MALFORMED
      "listing names ${listed_name}, expected ${expected_name}")
  endif()

  set(imports)
  set(import_identities)
  set(index 4)
  while(index LESS line_count)
    list(GET lines ${index} line)
    if(NOT line STREQUAL "Import {")
      pure_bonjour_fail(IMPORTS_MALFORMED
        "${expected_owner} has unexpected record start: ${line}")
    endif()
    math(EXPR index "${index} + 1")
    if(index GREATER_EQUAL line_count)
      pure_bonjour_fail(IMPORTS_MALFORMED
        "${expected_owner} has a truncated import record")
    endif()
    list(GET lines ${index} name_line)
    if(NOT name_line MATCHES
        "^  Name: ([A-Za-z0-9_.+-]+\\.([Dd][Ll][Ll]|[Ee][Xx][Ee]))$")
      pure_bonjour_fail(IMPORTS_MALFORMED
        "${expected_owner} has an invalid import name record: ${name_line}")
    endif()
    set(import_name "${CMAKE_MATCH_1}")
    string(TOLOWER "${import_name}" import_lower)
    if(import_lower IN_LIST import_identities)
      pure_bonjour_fail(IMPORT_AMBIGUOUS
        "${expected_owner} repeats case-folded import ${import_name}")
    endif()
    list(APPEND imports "${import_name}")
    list(APPEND import_identities "${import_lower}")

    math(EXPR index "${index} + 1")
    if(index GREATER_EQUAL line_count)
      pure_bonjour_fail(IMPORTS_MALFORMED
        "${expected_owner} has a truncated import record")
    endif()
    list(GET lines ${index} lookup_line)
    if(NOT lookup_line MATCHES
        "^  ImportLookupTableRVA: 0x[0-9A-Fa-f]+$")
      pure_bonjour_fail(IMPORTS_MALFORMED
        "${expected_owner} has an invalid lookup-table record: ${lookup_line}")
    endif()

    math(EXPR index "${index} + 1")
    if(index GREATER_EQUAL line_count)
      pure_bonjour_fail(IMPORTS_MALFORMED
        "${expected_owner} has a truncated import record")
    endif()
    list(GET lines ${index} address_table_line)
    if(NOT address_table_line MATCHES
        "^  ImportAddressTableRVA: 0x[0-9A-Fa-f]+$")
      pure_bonjour_fail(IMPORTS_MALFORMED
        "${expected_owner} has an invalid address-table record: ${address_table_line}")
    endif()

    set(symbol_count 0)
    math(EXPR index "${index} + 1")
    while(index LESS line_count)
      list(GET lines ${index} symbol_line)
      if(symbol_line STREQUAL "}")
        break()
      endif()
      if(NOT symbol_line MATCHES "^  Symbol: .+ \\([0-9]+\\)$")
        pure_bonjour_fail(IMPORTS_MALFORMED
          "${expected_owner} has an invalid import symbol: ${symbol_line}")
      endif()
      math(EXPR symbol_count "${symbol_count} + 1")
      math(EXPR index "${index} + 1")
    endwhile()
    if(symbol_count EQUAL 0 OR index GREATER_EQUAL line_count)
      pure_bonjour_fail(IMPORTS_MALFORMED
        "${expected_owner} has an empty or unterminated import record")
    endif()
    math(EXPR index "${index} + 1")
  endwhile()

  if(NOT imports)
    pure_bonjour_fail(IMPORTS_MISSING
      "${expected_owner} has no import records")
  endif()
  set(${output_imports} "${imports}" PARENT_SCOPE)
endfunction()

function(pure_bonjour_validate_root_imports imports owner)
  set(required_names dnsapi.dll ws2_32.dll libpure.dll)
  set(seen_names)
  foreach(import_name IN LISTS imports)
    pure_bonjour_check_forbidden("${import_name}" "${owner}")
    string(TOLOWER "${import_name}" import_lower)
    pure_bonjour_is_system_dll("${import_name}" is_system)
    if(NOT is_system AND NOT import_lower STREQUAL "libpure.dll")
      pure_bonjour_fail(IMPORT_UNKNOWN
        "${owner} has undeclared direct dependency ${import_name}")
    endif()
    list(APPEND seen_names "${import_lower}")
  endforeach()
  foreach(required_name IN LISTS required_names)
    if(NOT required_name IN_LIST seen_names)
      pure_bonjour_fail(IMPORT_REQUIRED_MISSING
        "${owner} does not import ${required_name}")
    endif()
  endforeach()
endfunction()

if(DEFINED PURE_BONJOUR_IMPORT_FIXTURE_ONLY)
  foreach(required IN ITEMS IMPORT_LISTING_FILE IMPORT_OWNER)
    if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
      pure_bonjour_fail(VERIFY_INPUT_MISSING "${required} is required")
    endif()
  endforeach()
  pure_bonjour_parse_import_listing(
    "${IMPORT_LISTING_FILE}" "${IMPORT_OWNER}" fixture_imports)
  pure_bonjour_validate_root_imports("${fixture_imports}" "${IMPORT_OWNER}")
  message(STATUS "PureBonjour synthetic import listing accepted")
  return()
endif()

foreach(required IN ITEMS LLVM_READOBJ MODULE PURE_PREFIX)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    pure_bonjour_fail(VERIFY_INPUT_MISSING "${required} is required")
  endif()
endforeach()
if(NOT EXISTS "${LLVM_READOBJ}" OR IS_DIRECTORY "${LLVM_READOBJ}")
  pure_bonjour_fail(VERIFY_INPUT_MISSING
    "llvm-readobj does not exist: ${LLVM_READOBJ}")
endif()
if(NOT EXISTS "${MODULE}" OR IS_DIRECTORY "${MODULE}")
  pure_bonjour_fail(VERIFY_INPUT_MISSING "module does not exist: ${MODULE}")
endif()

cmake_path(ABSOLUTE_PATH MODULE NORMALIZE OUTPUT_VARIABLE module_path)
set(pure_bin "${PURE_PREFIX}/bin")
cmake_path(ABSOLUTE_PATH pure_bin NORMALIZE OUTPUT_VARIABLE pure_bin)
if(NOT IS_DIRECTORY "${pure_bin}")
  pure_bonjour_fail(IMPORT_PATH_MISSING
    "Pure runtime directory does not exist: ${pure_bin}")
endif()

file(GLOB runtime_paths LIST_DIRECTORIES FALSE "${pure_bin}/*.dll")
set(runtime_names)
set(normalized_runtime_paths)
foreach(runtime_path IN LISTS runtime_paths)
  cmake_path(ABSOLUTE_PATH runtime_path NORMALIZE
    OUTPUT_VARIABLE normalized_runtime_path)
  cmake_path(IS_PREFIX pure_bin "${normalized_runtime_path}" NORMALIZE
    is_inside_pure_bin)
  if(NOT is_inside_pure_bin)
    pure_bonjour_fail(IMPORT_PATH_OUTSIDE
      "runtime path escapes PURE_PREFIX/bin: ${normalized_runtime_path}")
  endif()
  get_filename_component(runtime_name "${normalized_runtime_path}" NAME)
  string(TOLOWER "${runtime_name}" runtime_lower)
  if(runtime_lower IN_LIST runtime_names)
    pure_bonjour_fail(IMPORT_PATH_AMBIGUOUS
      "duplicate case-folded runtime path for ${runtime_name}")
  endif()
  list(APPEND runtime_names "${runtime_lower}")
  list(APPEND normalized_runtime_paths "${normalized_runtime_path}")
endforeach()

if(DEFINED VERIFY_WORK_DIR AND NOT VERIFY_WORK_DIR STREQUAL "")
  cmake_path(ABSOLUTE_PATH VERIFY_WORK_DIR NORMALIZE
    OUTPUT_VARIABLE verify_work_dir)
else()
  set(verify_work_dir "${CMAKE_CURRENT_BINARY_DIR}/PureBonjourDependencyAudit")
endif()
file(MAKE_DIRECTORY "${verify_work_dir}")

set(pe_queue "${module_path}")
set(pe_seen)
set(pe_count 0)
set(import_edge_count 0)
set(root_pending TRUE)
while(pe_queue)
  list(POP_FRONT pe_queue pe_path)
  cmake_path(ABSOLUTE_PATH pe_path NORMALIZE OUTPUT_VARIABLE pe_path)
  string(TOLOWER "${pe_path}" pe_identity)
  if(pe_identity IN_LIST pe_seen)
    continue()
  endif()
  list(APPEND pe_seen "${pe_identity}")
  math(EXPR pe_count "${pe_count} + 1")

  string(SHA256 listing_id "${pe_identity}")
  set(listing_file "${verify_work_dir}/${listing_id}.imports.txt")
  execute_process(
    COMMAND "${LLVM_READOBJ}" --coff-imports "${pe_path}"
    RESULT_VARIABLE read_result
    OUTPUT_VARIABLE read_output
    ERROR_VARIABLE read_error
    ENCODING UTF-8)
  if(NOT read_result EQUAL 0)
    pure_bonjour_fail(IMPORTS_MALFORMED
      "llvm-readobj rejected ${pe_path}: ${read_error}")
  endif()
  file(WRITE "${listing_file}" "${read_output}")
  pure_bonjour_parse_import_listing(
    "${listing_file}" "${pe_path}" imports)

  if(root_pending)
    pure_bonjour_validate_root_imports("${imports}" "${pe_path}")
    set(root_pending FALSE)
  endif()

  foreach(import_name IN LISTS imports)
    math(EXPR import_edge_count "${import_edge_count} + 1")
    pure_bonjour_check_forbidden("${import_name}" "${pe_path}")
    pure_bonjour_is_system_dll("${import_name}" is_system)
    if(is_system)
      continue()
    endif()

    string(TOLOWER "${import_name}" import_lower)
    if(NOT import_lower IN_LIST pure_bonjour_runtime_dlls)
      pure_bonjour_fail(IMPORT_UNKNOWN
        "${pe_path} imports undeclared runtime ${import_name}")
    endif()
    list(FIND runtime_names "${import_lower}" runtime_index)
    if(runtime_index EQUAL -1)
      pure_bonjour_fail(IMPORT_PATH_MISSING
        "${import_name} is not beneath PURE_PREFIX/bin")
    endif()
    list(GET normalized_runtime_paths ${runtime_index} resolved_path)
    cmake_path(IS_PREFIX pure_bin "${resolved_path}" NORMALIZE
      resolved_inside_pure_bin)
    if(NOT resolved_inside_pure_bin)
      pure_bonjour_fail(IMPORT_PATH_OUTSIDE
        "resolved import escapes PURE_PREFIX/bin: ${resolved_path}")
    endif()
    list(APPEND pe_queue "${resolved_path}")
  endforeach()
endwhile()

execute_process(
  COMMAND "${LLVM_READOBJ}" --coff-exports "${module_path}"
  RESULT_VARIABLE export_result
  OUTPUT_VARIABLE export_output
  ERROR_VARIABLE export_error
  ENCODING UTF-8)
if(NOT export_result EQUAL 0)
  pure_bonjour_fail(EXPORTS_MALFORMED
    "llvm-readobj rejected ${module_path}: ${export_error}")
endif()
string(REGEX MATCHALL "  Name: [^\r\n]+" export_lines
  "${export_output}")
set(export_names)
foreach(export_line IN LISTS export_lines)
  string(REGEX REPLACE "^  Name: " "" export_name "${export_line}")
  string(STRIP "${export_name}" export_name)
  list(APPEND export_names "${export_name}")
endforeach()
list(SORT export_names)
set(expected_exports
  bonjour_avail
  bonjour_browse
  bonjour_check
  bonjour_close
  bonjour_get
  bonjour_publish
  bonjour_unpublish)
list(SORT expected_exports)
if(NOT export_names STREQUAL expected_exports)
  pure_bonjour_fail(EXPORT_SET_MISMATCH
    "expected ${expected_exports}; found ${export_names}")
endif()

if(DEFINED DEPENDENCY_REPORT AND NOT DEPENDENCY_REPORT STREQUAL "")
  file(WRITE "${DEPENDENCY_REPORT}"
    "pe_files\t${pe_count}\nimport_edges\t${import_edge_count}\n")
endif()
message(STATUS
  "PureBonjour dependency audit passed: ${pe_count} PE files, "
  "${import_edge_count} import edges, seven exact exports")
