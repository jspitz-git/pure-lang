cmake_minimum_required(VERSION 3.25)

set(required_directories
  STAGE_PREFIX WINDOWS_DIRECTORY PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY)
set(required_files
  LLVM_READOBJ ODBC_MODULE GMP_DLL PURE_RUNTIME_DLL PURE_EXECUTABLE
  SYSTEM_ODBC_DLL)
foreach(required IN LISTS required_directories required_files)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
  cmake_path(ABSOLUTE_PATH ${required} NORMALIZE OUTPUT_VARIABLE normalized)
  set(${required} "${normalized}")
endforeach()
foreach(required IN LISTS required_directories)
  if(NOT IS_DIRECTORY "${${required}}")
    message(FATAL_ERROR
      "${required} must be an existing directory: ${${required}}")
  endif()
endforeach()
foreach(required IN LISTS required_files)
  if(NOT EXISTS "${${required}}" OR IS_DIRECTORY "${${required}}" OR
      IS_SYMLINK "${${required}}")
    message(FATAL_ERROR
      "${required} must be an existing regular file: ${${required}}")
  endif()
endforeach()

include("${CMAKE_CURRENT_LIST_DIR}/../tests/ContractTestRoot.cmake")
set(windows_directory_input "${WINDOWS_DIRECTORY}")
set(authoritative_windows_directory_input
  "${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}")
file(REAL_PATH "${windows_directory_input}" canonical_windows_directory)
file(REAL_PATH "${authoritative_windows_directory_input}"
  canonical_authoritative_windows_directory)
_pure_odbc_fold_path("${canonical_windows_directory}"
  folded_windows_directory)
_pure_odbc_fold_path("${canonical_authoritative_windows_directory}"
  folded_authoritative_windows_directory)
if(NOT folded_windows_directory STREQUAL
    folded_authoritative_windows_directory)
  message(FATAL_ERROR
    "WINDOWS_DIRECTORY does not match the authoritative Windows directory\n"
    "WINDOWS_DIRECTORY: ${canonical_windows_directory}\n"
    "authoritative: ${canonical_authoritative_windows_directory}")
endif()

_pure_odbc_require_no_reparse("${STAGE_PREFIX}" "STAGE_PREFIX" TRUE)
_pure_odbc_require_no_reparse(
  "${windows_directory_input}" "WINDOWS_DIRECTORY" FALSE)
_pure_odbc_require_no_reparse("${authoritative_windows_directory_input}"
  "PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY" FALSE)
foreach(required IN LISTS required_files)
  _pure_odbc_require_no_reparse("${${required}}" "${required}" FALSE)
endforeach()

file(REAL_PATH "${STAGE_PREFIX}" STAGE_PREFIX)
set(WINDOWS_DIRECTORY "${canonical_windows_directory}")
set(PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY
  "${canonical_authoritative_windows_directory}")
foreach(required IN LISTS required_files)
  file(REAL_PATH "${${required}}" canonical)
  set(${required} "${canonical}")
endforeach()

function(require_exact_path label actual expected)
  cmake_path(ABSOLUTE_PATH expected NORMALIZE OUTPUT_VARIABLE expected)
  if(NOT EXISTS "${expected}" OR IS_DIRECTORY "${expected}")
    message(FATAL_ERROR "Expected ${label} does not exist: ${expected}")
  endif()
  file(REAL_PATH "${expected}" expected)
  _pure_odbc_fold_path("${actual}" folded_actual)
  _pure_odbc_fold_path("${expected}" folded_expected)
  if(NOT folded_actual STREQUAL folded_expected)
    message(FATAL_ERROR
      "${label} path mismatch\nexpected: ${expected}\nactual: ${actual}")
  endif()
endfunction()

require_exact_path("GMP_DLL" "${GMP_DLL}"
  "${STAGE_PREFIX}/bin/libgmp-10.dll")
require_exact_path("PURE_RUNTIME_DLL" "${PURE_RUNTIME_DLL}"
  "${STAGE_PREFIX}/bin/libpure.dll")
require_exact_path("PURE_EXECUTABLE" "${PURE_EXECUTABLE}"
  "${STAGE_PREFIX}/bin/pure.exe")
require_exact_path("SYSTEM_ODBC_DLL" "${SYSTEM_ODBC_DLL}"
  "${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}/System32/odbc32.dll")

function(expected_imports filename output)
  string(TOLOWER "${filename}" filename)
  if(filename STREQUAL "odbc.dll")
    set(expected
      api-ms-win-crt-heap-l1-1-0.dll
      api-ms-win-crt-private-l1-1-0.dll
      api-ms-win-crt-runtime-l1-1-0.dll
      api-ms-win-crt-stdio-l1-1-0.dll
      api-ms-win-crt-string-l1-1-0.dll
      kernel32.dll libgmp-10.dll libpure.dll odbc32.dll)
  elseif(filename STREQUAL "pure.exe")
    set(expected
      api-ms-win-crt-convert-l1-1-0.dll
      api-ms-win-crt-environment-l1-1-0.dll
      api-ms-win-crt-filesystem-l1-1-0.dll
      api-ms-win-crt-heap-l1-1-0.dll
      api-ms-win-crt-locale-l1-1-0.dll
      api-ms-win-crt-math-l1-1-0.dll
      api-ms-win-crt-private-l1-1-0.dll
      api-ms-win-crt-runtime-l1-1-0.dll
      api-ms-win-crt-stdio-l1-1-0.dll
      api-ms-win-crt-string-l1-1-0.dll
      kernel32.dll libc++.dll libpure.dll libreadline8.dll)
  elseif(filename STREQUAL "libpure.dll")
    set(expected
      advapi32.dll
      api-ms-win-crt-convert-l1-1-0.dll
      api-ms-win-crt-environment-l1-1-0.dll
      api-ms-win-crt-filesystem-l1-1-0.dll
      api-ms-win-crt-heap-l1-1-0.dll
      api-ms-win-crt-locale-l1-1-0.dll
      api-ms-win-crt-math-l1-1-0.dll
      api-ms-win-crt-private-l1-1-0.dll
      api-ms-win-crt-process-l1-1-0.dll
      api-ms-win-crt-runtime-l1-1-0.dll
      api-ms-win-crt-stdio-l1-1-0.dll
      api-ms-win-crt-string-l1-1-0.dll
      api-ms-win-crt-time-l1-1-0.dll
      api-ms-win-crt-utility-l1-1-0.dll
      kernel32.dll libc++.dll libgmp-10.dll libiconv-2.dll libmpfr-6.dll
      libpcreposix-0.dll libwinpthread-1.dll libzstd.dll ntdll.dll ole32.dll
      shell32.dll zlib1.dll)
  elseif(filename STREQUAL "libc++.dll")
    set(expected
      api-ms-win-crt-convert-l1-1-0.dll
      api-ms-win-crt-environment-l1-1-0.dll
      api-ms-win-crt-filesystem-l1-1-0.dll
      api-ms-win-crt-heap-l1-1-0.dll
      api-ms-win-crt-locale-l1-1-0.dll
      api-ms-win-crt-math-l1-1-0.dll
      api-ms-win-crt-multibyte-l1-1-0.dll
      api-ms-win-crt-private-l1-1-0.dll
      api-ms-win-crt-runtime-l1-1-0.dll
      api-ms-win-crt-stdio-l1-1-0.dll
      api-ms-win-crt-string-l1-1-0.dll
      api-ms-win-crt-time-l1-1-0.dll
      api-ms-win-crt-utility-l1-1-0.dll kernel32.dll)
  elseif(filename STREQUAL "libgmp-10.dll")
    set(expected
      api-ms-win-crt-convert-l1-1-0.dll
      api-ms-win-crt-environment-l1-1-0.dll
      api-ms-win-crt-filesystem-l1-1-0.dll
      api-ms-win-crt-heap-l1-1-0.dll
      api-ms-win-crt-locale-l1-1-0.dll
      api-ms-win-crt-private-l1-1-0.dll
      api-ms-win-crt-runtime-l1-1-0.dll
      api-ms-win-crt-stdio-l1-1-0.dll
      api-ms-win-crt-string-l1-1-0.dll
      api-ms-win-crt-time-l1-1-0.dll
      api-ms-win-crt-utility-l1-1-0.dll kernel32.dll)
  elseif(filename STREQUAL "libiconv-2.dll")
    set(expected
      api-ms-win-crt-convert-l1-1-0.dll
      api-ms-win-crt-heap-l1-1-0.dll
      api-ms-win-crt-locale-l1-1-0.dll
      api-ms-win-crt-private-l1-1-0.dll
      api-ms-win-crt-runtime-l1-1-0.dll
      api-ms-win-crt-stdio-l1-1-0.dll
      api-ms-win-crt-string-l1-1-0.dll
      api-ms-win-crt-utility-l1-1-0.dll kernel32.dll)
  elseif(filename STREQUAL "libmpfr-6.dll")
    set(expected
      api-ms-win-crt-convert-l1-1-0.dll
      api-ms-win-crt-filesystem-l1-1-0.dll
      api-ms-win-crt-heap-l1-1-0.dll
      api-ms-win-crt-locale-l1-1-0.dll
      api-ms-win-crt-private-l1-1-0.dll
      api-ms-win-crt-runtime-l1-1-0.dll
      api-ms-win-crt-stdio-l1-1-0.dll
      api-ms-win-crt-string-l1-1-0.dll
      api-ms-win-crt-utility-l1-1-0.dll kernel32.dll libgmp-10.dll)
  elseif(filename STREQUAL "libpcre-1.dll")
    set(expected
      api-ms-win-crt-heap-l1-1-0.dll
      api-ms-win-crt-private-l1-1-0.dll
      api-ms-win-crt-runtime-l1-1-0.dll
      api-ms-win-crt-stdio-l1-1-0.dll
      api-ms-win-crt-string-l1-1-0.dll
      api-ms-win-crt-utility-l1-1-0.dll kernel32.dll)
  elseif(filename STREQUAL "libpcreposix-0.dll")
    set(expected
      api-ms-win-crt-convert-l1-1-0.dll
      api-ms-win-crt-heap-l1-1-0.dll
      api-ms-win-crt-locale-l1-1-0.dll
      api-ms-win-crt-private-l1-1-0.dll
      api-ms-win-crt-runtime-l1-1-0.dll
      api-ms-win-crt-stdio-l1-1-0.dll
      api-ms-win-crt-string-l1-1-0.dll
      api-ms-win-crt-utility-l1-1-0.dll kernel32.dll libpcre-1.dll)
  elseif(filename STREQUAL "libreadline8.dll")
    set(expected
      api-ms-win-crt-convert-l1-1-0.dll
      api-ms-win-crt-environment-l1-1-0.dll
      api-ms-win-crt-filesystem-l1-1-0.dll
      api-ms-win-crt-heap-l1-1-0.dll
      api-ms-win-crt-locale-l1-1-0.dll
      api-ms-win-crt-math-l1-1-0.dll
      api-ms-win-crt-private-l1-1-0.dll
      api-ms-win-crt-runtime-l1-1-0.dll
      api-ms-win-crt-stdio-l1-1-0.dll
      api-ms-win-crt-string-l1-1-0.dll
      api-ms-win-crt-utility-l1-1-0.dll kernel32.dll libtermcap-0.dll user32.dll)
  elseif(filename STREQUAL "libtermcap-0.dll")
    set(expected
      api-ms-win-crt-convert-l1-1-0.dll
      api-ms-win-crt-environment-l1-1-0.dll
      api-ms-win-crt-filesystem-l1-1-0.dll
      api-ms-win-crt-heap-l1-1-0.dll
      api-ms-win-crt-locale-l1-1-0.dll
      api-ms-win-crt-private-l1-1-0.dll
      api-ms-win-crt-runtime-l1-1-0.dll
      api-ms-win-crt-stdio-l1-1-0.dll
      api-ms-win-crt-string-l1-1-0.dll
      api-ms-win-crt-time-l1-1-0.dll kernel32.dll)
  elseif(filename STREQUAL "libwinpthread-1.dll")
    set(expected
      api-ms-win-crt-convert-l1-1-0.dll
      api-ms-win-crt-heap-l1-1-0.dll
      api-ms-win-crt-private-l1-1-0.dll
      api-ms-win-crt-runtime-l1-1-0.dll
      api-ms-win-crt-stdio-l1-1-0.dll
      api-ms-win-crt-string-l1-1-0.dll
      api-ms-win-crt-utility-l1-1-0.dll kernel32.dll)
  elseif(filename STREQUAL "libzstd.dll")
    set(expected
      api-ms-win-crt-convert-l1-1-0.dll
      api-ms-win-crt-filesystem-l1-1-0.dll
      api-ms-win-crt-heap-l1-1-0.dll
      api-ms-win-crt-locale-l1-1-0.dll
      api-ms-win-crt-private-l1-1-0.dll
      api-ms-win-crt-runtime-l1-1-0.dll
      api-ms-win-crt-stdio-l1-1-0.dll
      api-ms-win-crt-string-l1-1-0.dll
      api-ms-win-crt-time-l1-1-0.dll
      api-ms-win-crt-utility-l1-1-0.dll kernel32.dll)
  elseif(filename STREQUAL "zlib1.dll")
    set(expected
      api-ms-win-crt-convert-l1-1-0.dll
      api-ms-win-crt-heap-l1-1-0.dll
      api-ms-win-crt-locale-l1-1-0.dll
      api-ms-win-crt-private-l1-1-0.dll
      api-ms-win-crt-runtime-l1-1-0.dll
      api-ms-win-crt-stdio-l1-1-0.dll
      api-ms-win-crt-string-l1-1-0.dll
      api-ms-win-crt-utility-l1-1-0.dll kernel32.dll)
  else()
    message(FATAL_ERROR "Unknown staged PE manifest: ${filename}")
  endif()
  list(SORT expected)
  set(${output} "${expected}" PARENT_SCOPE)
endfunction()

function(inspect_pe module output_imports)
  execute_process(
    COMMAND "${LLVM_READOBJ}" --file-headers --coff-imports "${module}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8
  )
  if(NOT result EQUAL 0 OR NOT error STREQUAL "")
    message(FATAL_ERROR
      "Unable to inspect ${module} (${result})\n"
      "stdout:\n${output}\nstderr:\n${error}")
  endif()
  string(REPLACE "\r\n" "\n" output "${output}")
  string(REPLACE "\r" "\n" output "${output}")

  foreach(required_pattern IN ITEMS
      "(^|\n)File: [^\n]+"
      "(^|\n)Format: [^\n]+"
      "(^|\n)Arch: [^\n]+"
      "(^|\n)AddressSize: [^\n]+"
      "(^|\n)  Machine: [^\n]+")
    string(REGEX MATCHALL "${required_pattern}" matches "${output}")
    list(LENGTH matches match_count)
    if(NOT match_count EQUAL 1)
      message(FATAL_ERROR
        "Malformed llvm-readobj output for ${module}; expected exactly one "
        "'${required_pattern}' record (found ${match_count})")
    endif()
  endforeach()
  if(NOT output MATCHES "(^|\n)Format: COFF-x86-64(\n|$)" OR
      NOT output MATCHES "(^|\n)Arch: x86_64(\n|$)" OR
      NOT output MATCHES "(^|\n)AddressSize: 64bit(\n|$)" OR
      NOT output MATCHES
        "(^|\n)  Machine: IMAGE_FILE_MACHINE_AMD64 \\(0x8664\\)(\n|$)")
    message(FATAL_ERROR
      "AMD64 PE required for ${module}; llvm-readobj header was:\n${output}")
  endif()

  string(REGEX MATCHALL
    "(^|\n)(Import|DelayImport|[A-Za-z][A-Za-z0-9_-]+Import) \\{"
    import_record_starts "${output}")
  string(REGEX MATCHALL
    "(^|\n)(Import|DelayImport|[A-Za-z][A-Za-z0-9_-]+Import) \\{[^}]*\\}"
    import_blocks "${output}")
  list(LENGTH import_record_starts record_count)
  list(LENGTH import_blocks block_count)
  if(NOT record_count EQUAL block_count)
    message(FATAL_ERROR
      "Malformed llvm-readobj output for ${module}; ${record_count} import "
      "records but ${block_count} complete import blocks")
  endif()

  set(imports)
  foreach(block IN LISTS import_blocks)
    string(REGEX MATCH "^\n?[A-Za-z][A-Za-z0-9_-]* \\{" record "${block}")
    string(REGEX REPLACE "^\n?([^ ]+) \\{$" "\\1" record_name "${record}")
    if(NOT record_name STREQUAL "Import" AND
        NOT record_name STREQUAL "DelayImport")
      message(FATAL_ERROR
        "Unknown llvm-readobj record '${record_name}' for ${module}")
    endif()

    string(REGEX MATCHALL "(^|\n)  Name: [^\n]+" block_name_lines "${block}")
    list(LENGTH block_name_lines block_name_count)
    if(NOT block_name_count EQUAL 1)
      message(FATAL_ERROR
        "Malformed llvm-readobj output for ${module}; expected exactly one "
        "Name in import block '${record_name}' (found ${block_name_count})")
    endif()
    list(GET block_name_lines 0 line)
    string(REGEX REPLACE "^\n?  Name: " "" name "${line}")
    if(NOT name MATCHES "^[A-Za-z0-9_+.-]+\\.[Dd][Ll][Ll]$")
      message(FATAL_ERROR
        "Malformed llvm-readobj import name for ${module}: ${name}")
    endif()
    string(TOLOWER "${name}" name)
    list(FIND imports "${name}" duplicate_index)
    if(NOT duplicate_index EQUAL -1)
      message(FATAL_ERROR "${module} has duplicate import ${name}")
    endif()
    list(APPEND imports "${name}")
  endforeach()

  string(REGEX MATCHALL "(^|\n)  Name: [^\n]+" all_name_lines "${output}")
  list(LENGTH all_name_lines name_count)
  if(NOT record_count EQUAL name_count)
    message(FATAL_ERROR
      "Malformed llvm-readobj output for ${module}; ${record_count} import "
      "records but ${name_count} names")
  endif()
  list(SORT imports)
  set(${output_imports} "${imports}" PARENT_SCOPE)
endfunction()

function(require_exact_imports module actual)
  cmake_path(GET module FILENAME filename)
  string(TOLOWER "${filename}" filename)
  expected_imports("${filename}" expected)
  if(NOT actual STREQUAL expected)
    set(missing "${expected}")
    foreach(name IN LISTS actual)
      list(REMOVE_ITEM missing "${name}")
    endforeach()
    set(unexpected "${actual}")
    foreach(name IN LISTS expected)
      list(REMOVE_ITEM unexpected "${name}")
    endforeach()
    message(FATAL_ERROR
      "${module} import mismatch\n"
      "expected: ${expected}\nactual: ${actual}\n"
      "missing: ${missing}\nunexpected: ${unexpected}")
  endif()
endfunction()

function(is_system_import name output)
  if(name MATCHES "^api-ms-win-.*\\.dll$" OR
      name MATCHES "^(advapi32|kernel32|ntdll|ole32|shell32|user32)\\.dll$")
    set(${output} TRUE PARENT_SCOPE)
  else()
    set(${output} FALSE PARENT_SCOPE)
  endif()
endfunction()

function(resolve_staged_import name output)
  file(GLOB staged_entries LIST_DIRECTORIES FALSE "${STAGE_PREFIX}/bin/*")
  set(matches)
  foreach(entry IN LISTS staged_entries)
    cmake_path(GET entry FILENAME basename)
    string(TOLOWER "${basename}" basename)
    if(basename STREQUAL name)
      list(APPEND matches "${entry}")
    endif()
  endforeach()
  list(LENGTH matches match_count)
  if(NOT match_count EQUAL 1)
    message(FATAL_ERROR
      "Unresolved staged dependency ${name}; expected exactly one regular "
      "file beneath ${STAGE_PREFIX}/bin, found ${match_count}: ${matches}")
  endif()
  list(GET matches 0 resolved)
  if(IS_SYMLINK "${resolved}" OR IS_DIRECTORY "${resolved}")
    message(FATAL_ERROR "Resolved staged dependency is not regular: ${resolved}")
  endif()
  _pure_odbc_require_no_reparse("${resolved}" "staged dependency" FALSE)
  set(${output} "${resolved}" PARENT_SCOPE)
endfunction()

function(classify_forbidden basename manager_output driver_output)
  string(TOLOWER "${basename}" basename)
  if(basename MATCHES
      "^(odbc32|libodbc|libodbc32|libiodbc|unixodbc)([-_.0-9]*)\\.dll$")
    set(manager TRUE)
  else()
    set(manager FALSE)
  endif()
  if(basename MATCHES
      "^(msodbcsql[0-9]*|sqlncli[0-9]*|myodbc.*|psqlodbc.*|sqlite3?odbc.*|odbcjt32|aceodbc)\\.dll$")
    set(driver TRUE)
  else()
    set(driver FALSE)
  endif()
  set(${manager_output} "${manager}" PARENT_SCOPE)
  set(${driver_output} "${driver}" PARENT_SCOPE)
endfunction()

file(GLOB_RECURSE stage_files LIST_DIRECTORIES FALSE RELATIVE "${STAGE_PREFIX}"
  "${STAGE_PREFIX}/*")
foreach(relative IN LISTS stage_files)
  cmake_path(CONVERT "${relative}" TO_CMAKE_PATH_LIST relative NORMALIZE)
  string(TOLOWER "${relative}" lower_relative)
  if(lower_relative STREQUAL "lib/pure/odbc.dll")
    continue()
  endif()
  cmake_path(GET relative FILENAME basename)
  classify_forbidden("${basename}" is_manager is_driver)
  if(is_manager)
    message(FATAL_ERROR "Found bundled ODBC manager: ${relative}")
  endif()
  if(is_driver)
    message(FATAL_ERROR "Found bundled ODBC driver: ${relative}")
  endif()
endforeach()

inspect_pe("${SYSTEM_ODBC_DLL}" unused_system_imports)

set(queue "${ODBC_MODULE}" "${PURE_EXECUTABLE}")
set(visited)
while(queue)
  list(POP_FRONT queue module)
  cmake_path(GET module FILENAME filename)
  string(TOLOWER "${filename}" filename)
  list(FIND visited "${filename}" visited_index)
  if(NOT visited_index EQUAL -1)
    continue()
  endif()
  if(NOT EXISTS "${module}" OR IS_DIRECTORY "${module}" OR
      IS_SYMLINK "${module}")
    message(FATAL_ERROR "PE closure member is not a regular file: ${module}")
  endif()
  _pure_odbc_require_no_reparse("${module}" "PE closure member" FALSE)
  inspect_pe("${module}" actual_imports)
  require_exact_imports("${module}" "${actual_imports}")
  list(APPEND visited "${filename}")

  foreach(import IN LISTS actual_imports)
    if(import STREQUAL "odbc32.dll")
      continue()
    endif()
    is_system_import("${import}" system_import)
    if(system_import)
      continue()
    endif()
    classify_forbidden("${import}" is_manager is_driver)
    if(is_manager OR is_driver)
      message(FATAL_ERROR
        "PE closure imports forbidden ODBC component ${import} from ${module}")
    endif()
    resolve_staged_import("${import}" resolved)
    list(APPEND queue "${resolved}")
  endforeach()
endwhile()

list(LENGTH visited verified_count)
message(STATUS
  "Verified exact pure-odbc PE imports and recursive AMD64 closure for "
  "${verified_count} staged binaries; ODBC32 resolves only to "
  "${SYSTEM_ODBC_DLL}")
