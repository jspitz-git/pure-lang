cmake_minimum_required(VERSION 3.25)

foreach(_required IN ITEMS
    BUILD_DIR STAGE_PREFIX AUTHORITATIVE_MANIFEST PURE_EXECUTABLE LLVM_READOBJ)
  if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
    message(FATAL_ERROR "${_required} is required")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH BUILD_DIR NORMALIZE OUTPUT_VARIABLE _build_dir)
cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE _stage)
cmake_path(ABSOLUTE_PATH AUTHORITATIVE_MANIFEST NORMALIZE
  OUTPUT_VARIABLE _manifest)
cmake_path(ABSOLUTE_PATH PURE_EXECUTABLE NORMALIZE
  OUTPUT_VARIABLE _pure_executable)
cmake_path(ABSOLUTE_PATH LLVM_READOBJ NORMALIZE
  OUTPUT_VARIABLE _llvm_readobj)

foreach(_file_var IN ITEMS _pure_executable _llvm_readobj)
  if(NOT EXISTS "${${_file_var}}" OR IS_DIRECTORY "${${_file_var}}")
    message(FATAL_ERROR "required verifier executable is missing: ${${_file_var}}")
  endif()
endforeach()

if(NOT VERIFY_ONLY)
  cmake_path(IS_PREFIX _build_dir "${_stage}" NORMALIZE _stage_is_owned)
  if(NOT _stage_is_owned OR _stage STREQUAL _build_dir)
    message(FATAL_ERROR
      "install verification stage must be a child of BUILD_DIR: ${_stage}")
  endif()
  file(REMOVE_RECURSE "${_stage}")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" --install "${_build_dir}"
      --prefix "${_stage}" --component PureReduce
    RESULT_VARIABLE _install_result
    OUTPUT_VARIABLE _install_output
    ERROR_VARIABLE _install_error
    ENCODING UTF-8)
  if(NOT _install_result EQUAL 0)
    message(FATAL_ERROR
      "PureReduce component installation failed (${_install_result})\n"
      "stdout:\n${_install_output}\nstderr:\n${_install_error}")
  endif()
endif()

if(NOT IS_DIRECTORY "${_stage}")
  message(FATAL_ERROR "installed PureReduce stage is missing: ${_stage}")
endif()
set(_expected_manifest "${_build_dir}/PureReduceExpected.sha256")
if(NOT EXISTS "${_manifest}" OR IS_DIRECTORY "${_manifest}")
  message(FATAL_ERROR "authoritative manifest is missing: ${_manifest}")
endif()
file(REAL_PATH "${_manifest}" _manifest_real)
file(REAL_PATH "${_expected_manifest}" _expected_manifest_real)
string(TOLOWER "${_manifest_real}" _manifest_real_lower)
string(TOLOWER "${_expected_manifest_real}" _expected_manifest_real_lower)
if(NOT _manifest_real_lower STREQUAL _expected_manifest_real_lower)
  message(FATAL_ERROR
    "authoritative manifest must be BUILD_DIR/PureReduceExpected.sha256")
endif()

file(READ "${_manifest}" _manifest_text)
string(ASCII 9 _tab)
string(ASCII 13 _carriage_return)
if(_manifest_text MATCHES "[;|]" OR
    _manifest_text MATCHES "${_tab}" OR
    _manifest_text MATCHES "${_carriage_return}")
  message(FATAL_ERROR "authoritative manifest contains a forbidden delimiter")
endif()
file(STRINGS "${_manifest}" _manifest_lines)
list(LENGTH _manifest_lines _manifest_count)
if(NOT _manifest_count EQUAL 80)
  message(FATAL_ERROR
    "authoritative manifest must contain exactly 80 payloads: ${_manifest_count}")
endif()

set(_expected_paths)
set(_expected_paths_lower)
foreach(_line IN LISTS _manifest_lines)
  string(LENGTH "${_line}" _line_length)
  if(_line_length LESS 67)
    message(FATAL_ERROR "malformed authoritative manifest line: ${_line}")
  endif()
  string(SUBSTRING "${_line}" 0 64 _expected_sha)
  string(SUBSTRING "${_line}" 64 2 _separator)
  string(SUBSTRING "${_line}" 66 -1 _relative)
  string(LENGTH "${_expected_sha}" _sha_length)
  if(NOT _sha_length EQUAL 64 OR
      NOT _expected_sha MATCHES "^[0-9a-f]+$" OR
      NOT _separator STREQUAL "  ")
    message(FATAL_ERROR "malformed authoritative manifest line: ${_line}")
  endif()
  set(_path "${_relative}")
  cmake_path(IS_ABSOLUTE _path _absolute)
  string(REPLACE "/" ";" _segments "${_relative}")
  if(_absolute OR _relative STREQUAL "" OR
      _relative MATCHES "^[./\\\\]" OR
      _relative MATCHES "\\\\" OR ".." IN_LIST _segments)
    message(FATAL_ERROR "unsafe authoritative manifest path: ${_relative}")
  endif()
  string(TOLOWER "${_relative}" _relative_lower)
  if(_relative_lower IN_LIST _expected_paths_lower)
    message(FATAL_ERROR
      "duplicate authoritative manifest path: ${_relative}")
  endif()
  list(APPEND _expected_paths "${_relative}")
  list(APPEND _expected_paths_lower "${_relative_lower}")
  set("_expected_sha_${_relative_lower}" "${_expected_sha}")
endforeach()

set(_installed_inventory_relative
  "share/doc/pure-reduce/PureReduceInventory.tsv")
foreach(_required_path IN ITEMS
    lib/pure/reduce.dll
    lib/pure/reduce.img
    lib/pure/reduce.pure
    share/doc/pure-reduce/pure-reduce-package-metrics.json
    share/doc/pure-reduce/tests/smoke.pure
    share/doc/pure-reduce/tests/lifecycle.pure
    "${_installed_inventory_relative}")
  if(NOT _required_path IN_LIST _expected_paths)
    message(FATAL_ERROR
      "required installed payload is absent from authoritative manifest: "
      "${_required_path}")
  endif()
endforeach()

set(_required_licenses
  CM-UNICODE-LICENSE.txt
  COMPILER-RT-LICENSE.txt
  CRLIBM-COPYING.LIB.txt
  CRLIBM-COPYING.txt
  CSL-COPYING.txt
  LIBCXX-LICENSE.txt
  LIBFFI-LICENSE.txt
  LIBUNWIND-LICENSE.txt
  MINGW-W64-CRT-COPYING.txt
  MINGW-W64-RUNTIME-COPYING.txt
  NCURSES-LICENSE.txt
  REDUCE-LICENSE.txt
  WINPTHREADS-COPYING.txt
  ZLIB-LICENSE.txt)
foreach(_license IN LISTS _required_licenses)
  set(_license_relative "share/doc/pure-reduce/licenses/${_license}")
  if(NOT _license_relative IN_LIST _expected_paths)
    message(FATAL_ERROR
      "required license is absent from authoritative manifest: ${_license_relative}")
  endif()
  if(NOT EXISTS "${_stage}/${_license_relative}" OR
      IS_DIRECTORY "${_stage}/${_license_relative}")
    message(FATAL_ERROR "required license is missing: ${_license}")
  endif()
endforeach()

foreach(_relative IN LISTS _expected_paths)
  set(_installed "${_stage}/${_relative}")
  if(NOT EXISTS "${_installed}" OR IS_DIRECTORY "${_installed}")
    message(FATAL_ERROR "manifest entry is missing: ${_relative}")
  endif()
  string(TOLOWER "${_relative}" _relative_lower)
  file(SHA256 "${_installed}" _actual_sha)
  string(TOLOWER "${_actual_sha}" _actual_sha)
  if(NOT _actual_sha STREQUAL "${_expected_sha_${_relative_lower}}")
    message(FATAL_ERROR "installed hash mismatch: ${_relative}")
  endif()
endforeach()

file(GLOB_RECURSE _installed_files LIST_DIRECTORIES FALSE "${_stage}/*")
set(_actual_paths)
foreach(_installed IN LISTS _installed_files)
  file(RELATIVE_PATH _relative "${_stage}" "${_installed}")
  string(REPLACE "\\" "/" _relative "${_relative}")
  string(TOLOWER "${_relative}" _relative_lower)
  if(NOT _relative_lower IN_LIST _expected_paths_lower)
    message(FATAL_ERROR "unexpected installed file: ${_relative}")
  endif()
  if(_relative_lower MATCHES "\\.(a|lib|o|obj|exe)$" OR
      _relative_lower MATCHES "(^|/)src/" OR
      _relative_lower MATCHES
        "\\.(asm\\.gz|tar|tar\\.gz|tar\\.bz2|tar\\.xz|zip)$" OR
      _relative_lower MATCHES
        "(^|/)(bash|sh|dash|zsh|fish|cmd|powershell|pwsh|make|ninja|pacman)(\\.exe)?$" OR
      _relative_lower MATCHES "(^|/)reduce\\.exe$")
    message(FATAL_ERROR "forbidden installed filename: ${_relative}")
  endif()
  list(APPEND _actual_paths "${_relative}")
endforeach()
list(LENGTH _actual_paths _actual_count)
if(NOT _actual_count EQUAL _manifest_count)
  message(FATAL_ERROR
    "installed file count differs from authoritative manifest: "
    "${_actual_count} vs ${_manifest_count}")
endif()

set(_build_installed_inventory
  "${_build_dir}/PureReduceInstalledInventory.tsv")
set(_installed_inventory "${_stage}/${_installed_inventory_relative}")
if(NOT EXISTS "${_build_installed_inventory}")
  message(FATAL_ERROR
    "build-tree installed inventory is missing: ${_build_installed_inventory}")
endif()
file(SHA256 "${_build_installed_inventory}" _build_inventory_sha)
file(SHA256 "${_installed_inventory}" _installed_inventory_sha)
if(NOT _build_inventory_sha STREQUAL _installed_inventory_sha)
  message(FATAL_ERROR
    "installed inventory differs from build-tree authoritative inventory")
endif()
file(STRINGS "${_installed_inventory}" _inventory_lines)
list(POP_FRONT _inventory_lines _inventory_header)
if(NOT _inventory_header STREQUAL
    "relative_path\tpurpose\torigin\tsha256\tbytes\tlicense")
  message(FATAL_ERROR "installed inventory header is malformed")
endif()
math(EXPR _expected_inventory_count "${_manifest_count} - 1")
list(LENGTH _inventory_lines _inventory_count)
if(NOT _inventory_count EQUAL _expected_inventory_count)
  message(FATAL_ERROR
    "installed inventory must describe exactly ${_expected_inventory_count} "
    "other payloads: ${_inventory_count}")
endif()
set(_inventory_paths)
foreach(_inventory_line IN LISTS _inventory_lines)
  string(REPLACE "${_tab}" ";" _fields "${_inventory_line}")
  list(LENGTH _fields _field_count)
  if(NOT _field_count EQUAL 6)
    message(FATAL_ERROR "malformed installed inventory row: ${_inventory_line}")
  endif()
  list(GET _fields 0 _relative)
  list(GET _fields 1 _purpose)
  list(GET _fields 2 _origin)
  list(GET _fields 3 _sha)
  list(GET _fields 4 _bytes)
  list(GET _fields 5 _license)
  if(_relative STREQUAL _installed_inventory_relative OR
      NOT _relative IN_LIST _expected_paths OR
      _purpose STREQUAL "" OR _origin STREQUAL "" OR _license STREQUAL "" OR
      NOT _sha MATCHES "^[0-9a-f]+$" OR NOT _bytes MATCHES "^[0-9]+$")
    message(FATAL_ERROR "invalid installed inventory row: ${_inventory_line}")
  endif()
  file(SHA256 "${_stage}/${_relative}" _actual_sha)
  file(SIZE "${_stage}/${_relative}" _actual_bytes)
  if(NOT _actual_sha STREQUAL _sha OR NOT _actual_bytes EQUAL _bytes)
    message(FATAL_ERROR
      "installed inventory metadata mismatch: ${_relative}")
  endif()
  list(APPEND _inventory_paths "${_relative}")
endforeach()
set(_inventory_expected_paths "${_expected_paths}")
list(REMOVE_ITEM _inventory_expected_paths "${_installed_inventory_relative}")
list(SORT _inventory_expected_paths COMPARE NATURAL CASE INSENSITIVE)
list(SORT _inventory_paths COMPARE NATURAL CASE INSENSITIVE)
if(NOT _inventory_paths STREQUAL _inventory_expected_paths)
  message(FATAL_ERROR
    "installed inventory paths do not exactly describe the other payloads")
endif()

set(_metrics
  "${_stage}/share/doc/pure-reduce/pure-reduce-package-metrics.json")
file(READ "${_metrics}" _metrics_json)
string(JSON _metrics_count ERROR_VARIABLE _metrics_error
  GET "${_metrics_json}" installed_file_count)
if(_metrics_error OR NOT _metrics_count EQUAL _manifest_count)
  message(FATAL_ERROR
    "installed metrics count differs from authoritative manifest")
endif()

set(_forbidden_prefixes "${_build_dir}" "${_stage}")
if(DEFINED SOURCE_PREFIX AND NOT "${SOURCE_PREFIX}" STREQUAL "")
  list(APPEND _forbidden_prefixes "${SOURCE_PREFIX}")
endif()
if(DEFINED ORIGINAL_STAGE_PREFIX AND
    NOT "${ORIGINAL_STAGE_PREFIX}" STREQUAL "")
  list(APPEND _forbidden_prefixes "${ORIGINAL_STAGE_PREFIX}")
endif()
set(_metadata_files)
foreach(_installed IN LISTS _installed_files)
  string(TOLOWER "${_installed}" _installed_lower)
  if(NOT _installed_lower MATCHES "\\.(dll|img|ttf|pfb|pfa|pfm)$")
    list(APPEND _metadata_files "${_installed}")
  endif()
endforeach()
foreach(_text_file IN LISTS _metadata_files)
  file(READ "${_text_file}" _text)
  string(REPLACE "\\" "/" _text_normalized "${_text}")
  string(TOLOWER "${_text_normalized}" _text_lower)
  if(_text_lower MATCHES "(^|[^a-z])msys2([^a-z]|$)" OR
      _text_lower MATCHES "[a-z]:/msys[0-9]*/")
    message(FATAL_ERROR
      "installed content contains a forbidden MSYS2 reference: ${_text_file}")
  endif()
  foreach(_prefix IN LISTS _forbidden_prefixes)
    file(TO_CMAKE_PATH "${_prefix}" _prefix_normalized)
    string(TOLOWER "${_prefix_normalized}" _prefix_lower)
    string(FIND "${_text_lower}" "${_prefix_lower}" _prefix_at)
    if(NOT _prefix_at EQUAL -1)
      message(FATAL_ERROR
        "installed content leaks a forbidden prefix: ${_text_file}")
    endif()
  endforeach()
endforeach()

set(PURE_REDUCE_LLVM_READOBJ "${_llvm_readobj}")
include("${CMAKE_CURRENT_LIST_DIR}/AuditWindowsDependencies.cmake")
set(_pe_search_dirs "${_stage}/lib/pure")
if(IS_DIRECTORY "${_stage}/bin")
  list(APPEND _pe_search_dirs "${_stage}/bin")
endif()
pure_reduce_audit_pe(
  "${_stage}/lib/pure/reduce.dll" "${_pe_search_dirs}" _pe_closure)
foreach(_pe_file IN LISTS _pe_closure)
  cmake_path(IS_PREFIX _stage "${_pe_file}" NORMALIZE _pe_is_staged)
  if(NOT _pe_is_staged)
    message(FATAL_ERROR "PE dependency resolved outside installed stage: ${_pe_file}")
  endif()
endforeach()

if(NOT DEFINED RUN_RUNTIME_TESTS OR RUN_RUNTIME_TESTS)
  cmake_path(GET _pure_executable PARENT_PATH _pure_bin)
  cmake_path(GET _pure_bin PARENT_PATH _pure_prefix)
  set(_pure_library "${_pure_prefix}/lib/pure")
  if(NOT IS_DIRECTORY "${_pure_library}")
    message(FATAL_ERROR "Pure library directory is missing: ${_pure_library}")
  endif()
  set(ENV{PATH}
    "${_stage}/bin;C:/Windows/System32/WindowsPowerShell/v1.0;C:/Windows/System32;C:/Windows")
  set(ENV{PURELIB} "")
  # Pure's Windows CLI cannot open a Unicode pathname supplied to -x/-I.
  # Execute byte-for-byte copies of the manifest-verified staged Pure sources
  # from a private ASCII build path. The DLL and image remain in the Unicode
  # installed prefix, exercising the production wide-character startup path.
  string(SHA256 _stage_key "${_stage}")
  set(_script_run_dir
    "${_build_dir}/installed-test-scripts-${_stage_key}")
  file(REMOVE_RECURSE "${_script_run_dir}")
  file(MAKE_DIRECTORY "${_script_run_dir}")
  file(COPY_FILE "${_stage}/lib/pure/reduce.pure"
    "${_script_run_dir}/reduce.pure")
  # Pure resolves lib:reduce through the Windows basename search after finding
  # the Pure source. Exercise the prescribed sanitized stage/bin PATH with a
  # transient runtime view made only from already hash-verified payload bytes.
  set(_stage_bin "${_stage}/bin")
  set(_stage_bin_existed FALSE)
  if(IS_DIRECTORY "${_stage_bin}")
    set(_stage_bin_existed TRUE)
  endif()
  foreach(_runtime_name IN ITEMS reduce.dll reduce.img)
    if(EXISTS "${_stage_bin}/${_runtime_name}")
      message(FATAL_ERROR
        "runtime verification would overwrite an installed file: "
        "bin/${_runtime_name}")
    endif()
  endforeach()
  file(MAKE_DIRECTORY "${_stage_bin}")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
      "${_stage}/lib/pure/reduce.dll"
      "${_stage}/lib/pure/reduce.img"
      "${_stage_bin}"
    RESULT_VARIABLE _runtime_copy_result
    OUTPUT_VARIABLE _runtime_copy_output
    ERROR_VARIABLE _runtime_copy_error
    ENCODING UTF-8)
  if(NOT _runtime_copy_result EQUAL 0)
    file(REMOVE "${_stage_bin}/reduce.dll" "${_stage_bin}/reduce.img")
    if(NOT _stage_bin_existed)
      file(REMOVE_RECURSE "${_stage_bin}")
    endif()
    message(FATAL_ERROR
      "unable to create sanitized runtime view (${_runtime_copy_result})\n"
      "stdout:\n${_runtime_copy_output}\n"
      "stderr:\n${_runtime_copy_error}")
  endif()
  set(_runtime_failure "")
  foreach(_test_name IN ITEMS smoke lifecycle)
    file(COPY_FILE
      "${_stage}/share/doc/pure-reduce/tests/${_test_name}.pure"
      "${_script_run_dir}/${_test_name}.pure")
    execute_process(
      COMMAND "${_pure_executable}" --norc -q
        -I "${_pure_library}"
        -I "${_script_run_dir}"
        -L "${_stage}/lib/pure"
        -x "${_script_run_dir}/${_test_name}.pure"
      WORKING_DIRECTORY "C:/Windows"
      RESULT_VARIABLE _test_result
      OUTPUT_VARIABLE _test_output
      ERROR_VARIABLE _test_error
      ENCODING UTF-8)
    if(NOT _test_result EQUAL 0 AND _runtime_failure STREQUAL "")
      string(CONCAT _runtime_failure
        "installed ${_test_name} failed (${_test_result})\n"
        "stdout:\n${_test_output}\nstderr:\n${_test_error}")
    elseif(NOT _test_error STREQUAL "" AND _runtime_failure STREQUAL "")
      string(CONCAT _runtime_failure
        "installed ${_test_name} emitted stderr\n"
        "stdout:\n${_test_output}\nstderr:\n${_test_error}")
    elseif(NOT _test_output MATCHES
        "(^|\r?\n)pure-reduce ${_test_name} passed(\r?\n|$)")
      if(_runtime_failure STREQUAL "")
        string(CONCAT _runtime_failure
          "installed ${_test_name} omitted its pass marker\n"
          "stdout:\n${_test_output}")
      endif()
    endif()
    string(TOLOWER "${_test_output}${_test_error}" _test_transcript_lower)
    if(_test_transcript_lower MATCHES "msys2" OR
        _test_transcript_lower MATCHES "[a-z]:[/\\\\]msys")
      if(_runtime_failure STREQUAL "")
        set(_runtime_failure
          "installed ${_test_name} exposed an MSYS2 directory at runtime")
      endif()
    endif()
  endforeach()
  file(REMOVE "${_stage_bin}/reduce.dll" "${_stage_bin}/reduce.img")
  if(NOT _stage_bin_existed)
    file(REMOVE_RECURSE "${_stage_bin}")
  endif()
  if(NOT _runtime_failure STREQUAL "")
    message(FATAL_ERROR "${_runtime_failure}")
  endif()
endif()

message(STATUS
  "verified installed PureReduce package: ${_manifest_count} files, "
  "${_pe_closure}")
