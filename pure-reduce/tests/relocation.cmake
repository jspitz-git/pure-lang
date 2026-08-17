cmake_minimum_required(VERSION 3.25)

foreach(_required IN ITEMS
    BUILD_DIR
    STAGE_PREFIX
    AUTHORITATIVE_MANIFEST
    PURE_EXECUTABLE
    LLVM_READOBJ
    SOURCE_PREFIX
    VERIFIER)
  if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
    message(FATAL_ERROR "${_required} is required")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH BUILD_DIR NORMALIZE OUTPUT_VARIABLE _build_dir)
cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE _original_stage)
set(_relocated_stage
  "${_build_dir}/relocated PureReduce package stage")
set(_leak_root "${_build_dir}/relocation prefix leak fixture")
set(_binary_leak_root "${_build_dir}/relocation binary leak fixture")
set(_ownership_stage
  "${_build_dir}/ownership Pure prefix stage")
set(_ownership_oracle_root
  "${_build_dir}/ownership trusted oracle snapshot")
if(NOT RELOCATION_CHILD)
  if(NOT IS_DIRECTORY "${_original_stage}")
    message(FATAL_ERROR
      "original installed stage is missing: ${_original_stage}")
  endif()
  file(GLOB_RECURSE _original_files LIST_DIRECTORIES FALSE
    "${_original_stage}/*")
  set(_original_records)
  foreach(_original_file IN LISTS _original_files)
    file(RELATIVE_PATH _original_relative
      "${_original_stage}" "${_original_file}")
    string(REPLACE "\\" "/" _original_relative "${_original_relative}")
    file(SHA256 "${_original_file}" _original_sha)
    list(APPEND _original_records "${_original_relative}|${_original_sha}")
  endforeach()
  list(SORT _original_records COMPARE NATURAL CASE INSENSITIVE)
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DBUILD_DIR=${_build_dir}"
      "-DSTAGE_PREFIX=${_original_stage}"
      "-DAUTHORITATIVE_MANIFEST=${AUTHORITATIVE_MANIFEST}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DLLVM_READOBJ=${LLVM_READOBJ}"
      "-DSOURCE_PREFIX=${SOURCE_PREFIX}"
      "-DVERIFIER=${VERIFIER}"
      -DRELOCATION_CHILD=ON
      -P "${CMAKE_CURRENT_LIST_FILE}"
    RESULT_VARIABLE _child_result
    ENCODING UTF-8)
  file(REMOVE_RECURSE
    "${_relocated_stage}" "${_leak_root}"
    "${_binary_leak_root}" "${_ownership_stage}"
    "${_ownership_oracle_root}")
  file(GLOB_RECURSE _original_files_after LIST_DIRECTORIES FALSE
    "${_original_stage}/*")
  set(_original_records_after)
  foreach(_original_file IN LISTS _original_files_after)
    file(RELATIVE_PATH _original_relative
      "${_original_stage}" "${_original_file}")
    string(REPLACE "\\" "/" _original_relative "${_original_relative}")
    file(SHA256 "${_original_file}" _original_sha)
    list(APPEND _original_records_after
      "${_original_relative}|${_original_sha}")
  endforeach()
  list(SORT _original_records_after COMPARE NATURAL CASE INSENSITIVE)
  if(NOT _original_records_after STREQUAL _original_records)
    message(FATAL_ERROR
      "relocation child changed the original installed stage")
  endif()
  if(NOT _child_result EQUAL 0)
    message(FATAL_ERROR
      "relocation verification child failed (${_child_result}); "
      "see the streamed child output above")
  endif()
  return()
endif()
message(STATUS "relocation phase: relocated package verification")
file(REMOVE_RECURSE "${_relocated_stage}")
file(MAKE_DIRECTORY "${_relocated_stage}")
file(COPY "${_original_stage}/" DESTINATION "${_relocated_stage}")

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DBUILD_DIR=${_build_dir}"
    "-DSTAGE_PREFIX=${_relocated_stage}"
    "-DAUTHORITATIVE_MANIFEST=${AUTHORITATIVE_MANIFEST}"
    "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    "-DSOURCE_PREFIX=${SOURCE_PREFIX}"
    "-DORIGINAL_STAGE_PREFIX=${_original_stage}"
    -DVERIFY_ONLY=ON
    -P "${VERIFIER}"
  RESULT_VARIABLE _relocation_result
  OUTPUT_VARIABLE _relocation_output
  ERROR_VARIABLE _relocation_error
  ENCODING UTF-8)
if(NOT _relocation_result EQUAL 0)
  message(FATAL_ERROR
    "relocated installed package verification failed (${_relocation_result})\n"
    "stdout:\n${_relocation_output}\nstderr:\n${_relocation_error}")
endif()

# Re-authorize a deliberately leaked original prefix all the way through the
# manifest and installed inventory. Only the content-policy check may reject
# this fixture.
message(STATUS "relocation phase: text prefix leak rejection")
set(_leak_build "${_leak_root}/build")
set(_leak_stage "${_leak_root}/stage")
set(_leak_relative
  "share/doc/pure-reduce/patches/0001-csl-winsupport-define-nil.patch")
file(REMOVE_RECURSE "${_leak_root}")
file(MAKE_DIRECTORY "${_leak_build}" "${_leak_stage}")
file(COPY "${_relocated_stage}/" DESTINATION "${_leak_stage}")
file(APPEND "${_leak_stage}/${_leak_relative}"
  "\nforbidden original prefix: ${_original_stage}\n")
file(SHA256 "${_leak_stage}/${_leak_relative}" _leak_sha)
file(SIZE "${_leak_stage}/${_leak_relative}" _leak_bytes)

set(_inventory_relative "share/doc/pure-reduce/PureReduceInventory.tsv")
file(STRINGS "${_leak_stage}/${_inventory_relative}" _inventory_lines)
set(_new_inventory_lines)
string(ASCII 9 _tab)
foreach(_line IN LISTS _inventory_lines)
  if(_line MATCHES "^${_leak_relative}${_tab}")
    string(REPLACE "${_tab}" ";" _fields "${_line}")
    list(GET _fields 0 _field_path)
    list(GET _fields 1 _field_purpose)
    list(GET _fields 2 _field_origin)
    list(GET _fields 5 _field_license)
    set(_line
      "${_field_path}${_tab}${_field_purpose}${_tab}${_field_origin}${_tab}${_leak_sha}${_tab}${_leak_bytes}${_tab}${_field_license}")
  endif()
  list(APPEND _new_inventory_lines "${_line}")
endforeach()
list(JOIN _new_inventory_lines "\n" _new_inventory_text)
file(WRITE "${_leak_stage}/${_inventory_relative}"
  "${_new_inventory_text}\n")
file(COPY_FILE "${_leak_stage}/${_inventory_relative}"
  "${_leak_build}/PureReduceInstalledInventory.tsv")
file(SHA256 "${_leak_stage}/${_inventory_relative}" _inventory_sha)
file(SIZE "${_leak_stage}/${_inventory_relative}" _inventory_bytes)

file(STRINGS "${AUTHORITATIVE_MANIFEST}" _manifest_lines)
set(_new_manifest_lines)
foreach(_line IN LISTS _manifest_lines)
  if(_line MATCHES "  ${_leak_relative}$")
    set(_line "${_leak_sha}  ${_leak_relative}")
  elseif(_line MATCHES "  ${_inventory_relative}$")
    set(_line "${_inventory_sha}  ${_inventory_relative}")
  endif()
  list(APPEND _new_manifest_lines "${_line}")
endforeach()
list(JOIN _new_manifest_lines "\n" _new_manifest_text)
file(WRITE "${_leak_build}/PureReduceExpected.sha256"
  "${_new_manifest_text}\n")
file(STRINGS "${_build_dir}/PureReduceInventory.tsv" _external_lines)
set(_new_external_lines)
foreach(_line IN LISTS _external_lines)
  if(_line MATCHES "^${_leak_relative}${_tab}")
    string(REPLACE "${_tab}" ";" _fields "${_line}")
    list(GET _fields 0 _field_path)
    list(GET _fields 1 _field_purpose)
    list(GET _fields 2 _field_origin)
    list(GET _fields 5 _field_license)
    set(_line
      "${_field_path}${_tab}${_field_purpose}${_tab}${_field_origin}${_tab}${_leak_sha}${_tab}${_leak_bytes}${_tab}${_field_license}")
  elseif(_line MATCHES "^${_inventory_relative}${_tab}")
    string(REPLACE "${_tab}" ";" _fields "${_line}")
    list(GET _fields 0 _field_path)
    list(GET _fields 1 _field_purpose)
    list(GET _fields 2 _field_origin)
    list(GET _fields 5 _field_license)
    set(_line
      "${_field_path}${_tab}${_field_purpose}${_tab}${_field_origin}${_tab}${_inventory_sha}${_tab}${_inventory_bytes}${_tab}${_field_license}")
  endif()
  list(APPEND _new_external_lines "${_line}")
endforeach()
list(JOIN _new_external_lines "\n" _new_external_text)
file(WRITE "${_leak_build}/PureReduceInventory.tsv"
  "${_new_external_text}\n")

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DBUILD_DIR=${_leak_build}"
    "-DSTAGE_PREFIX=${_leak_stage}"
    "-DAUTHORITATIVE_MANIFEST=${_leak_build}/PureReduceExpected.sha256"
    "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    "-DSOURCE_PREFIX=${SOURCE_PREFIX}"
    "-DORIGINAL_STAGE_PREFIX=${_original_stage}"
    -DVERIFY_ONLY=ON
    -DRUN_RUNTIME_TESTS=OFF
    -P "${VERIFIER}"
  RESULT_VARIABLE _leak_result
  OUTPUT_VARIABLE _leak_output
  ERROR_VARIABLE _leak_error
  ENCODING UTF-8)
set(_leak_combined "${_leak_output}\n${_leak_error}")
if(_leak_result EQUAL 0)
  message(FATAL_ERROR "verifier accepted an authorized original-prefix leak")
endif()
if(NOT _leak_combined MATCHES
    "installed content leaks a forbidden prefix")
  message(FATAL_ERROR
    "prefix leak failed for the wrong reason\n${_leak_combined}")
endif()

# Re-authorize mixed-case narrow and UTF-16LE prefix leaks in installed
# binaries. Hash and inventory validation must succeed before the byte-level
# policy rejects either Windows-equivalent spelling.
message(STATUS "relocation phase: binary prefix leak rejection")
set(_binary_leak_relative "lib/pure/reduce.fonts/cmex7.ttf")
file(REMOVE_RECURSE "${_binary_leak_root}")
file(TO_CMAKE_PATH "${SOURCE_PREFIX}" _source_prefix_forward)
if(NOT _source_prefix_forward MATCHES "^([A-Za-z]):(/.*)$")
  message(FATAL_ERROR
    "binary MSYS-prefix fixture requires a Windows drive path: ${SOURCE_PREFIX}")
endif()
string(TOLOWER "${CMAKE_MATCH_1}" _source_drive_lower)
set(_source_drive_tail "${CMAKE_MATCH_2}")
string(TOLOWER "${_source_drive_tail}" _source_drive_tail_lower)
string(TOLOWER "${_source_prefix_forward}" _source_prefix_lower)
set(_mixed_windows_prefix "${_source_prefix_lower}")
set(_ascii_lower a b c d e f g h i j k l m n o p q r s t u v w x y z)
set(_ascii_upper A B C D E F G H I J K L M N O P Q R S T U V W X Y Z)
foreach(_letter_index RANGE 0 25)
  list(GET _ascii_lower ${_letter_index} _lower_letter)
  string(FIND "${_mixed_windows_prefix}" "${_lower_letter}" _letter_at)
  if(_letter_at GREATER 2)
    list(GET _ascii_upper ${_letter_index} _upper_letter)
    string(SUBSTRING "${_mixed_windows_prefix}" 0 ${_letter_at} _case_before)
    math(EXPR _case_after_at "${_letter_at} + 1")
    string(SUBSTRING "${_mixed_windows_prefix}" ${_case_after_at} -1 _case_after)
    set(_mixed_windows_prefix
      "${_case_before}${_upper_letter}${_case_after}")
    break()
  endif()
endforeach()
if(NOT _mixed_windows_prefix MATCHES "[A-Z]")
  message(FATAL_ERROR
    "binary mixed-case fixture requires an ASCII path letter: ${SOURCE_PREFIX}")
endif()
set(_mixed_windows_path "${_mixed_windows_prefix}")
if(NOT _mixed_windows_path MATCHES "^([A-Za-z]):(/.*)$")
  message(FATAL_ERROR "mixed Windows prefix lost its drive syntax")
endif()
set(_mixed_msys_tail "${CMAKE_MATCH_2}")
set(_mixed_msys_prefix "/${_source_drive_lower}${_mixed_msys_tail}")
if(_mixed_windows_prefix STREQUAL _source_prefix_forward OR
    _mixed_msys_prefix STREQUAL
      "/${_source_drive_lower}${_source_drive_tail_lower}")
  message(FATAL_ERROR
    "binary mixed-case fixtures could not vary SOURCE_PREFIX: ${SOURCE_PREFIX}")
endif()
set(_binary_leak_failures)
foreach(_binary_case IN ITEMS narrow utf16le unicode_utf16le odd_nibble)
  message(STATUS "relocation binary fixture: ${_binary_case}")
  set(_binary_case_root "${_binary_leak_root}/${_binary_case}")
  set(_binary_leak_build "${_binary_case_root}/build")
  set(_binary_leak_stage "${_binary_case_root}/stage")
  file(MAKE_DIRECTORY "${_binary_leak_build}" "${_binary_leak_stage}")
  file(COPY "${_relocated_stage}/" DESTINATION "${_binary_leak_stage}")
  set(ENV{PURE_REDUCE_BINARY_LEAK_FILE}
    "${_binary_leak_stage}/${_binary_leak_relative}")
  if(_binary_case STREQUAL "narrow")
    set(ENV{PURE_REDUCE_BINARY_LEAK_TEXT} "${_mixed_windows_prefix}")
    set(_binary_case_source_prefix "${SOURCE_PREFIX}")
    set(_append_script
      "$p=$env:PURE_REDUCE_BINARY_LEAK_FILE; $n=(Get-Item -LiteralPath $p).Length; $b=([Math]::Floor($n/1048576)+1)*1048576; if(($b-$n)-le 5){$b+=1048576}; $pad=[int]($b-$n-5); $s=[IO.File]::Open($p,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::None); try { if($pad -gt 0){$s.Write((New-Object byte[] $pad),0,$pad)}; $v=(New-Object Text.UTF8Encoding($false)).GetBytes($env:PURE_REDUCE_BINARY_LEAK_TEXT); $s.Write($v,0,$v.Length) } finally { $s.Dispose() }")
  elseif(_binary_case STREQUAL "utf16le")
    set(ENV{PURE_REDUCE_BINARY_LEAK_TEXT} "${_mixed_msys_prefix}")
    set(_binary_case_source_prefix "${SOURCE_PREFIX}")
    set(_append_script
      "[IO.File]::AppendAllText($env:PURE_REDUCE_BINARY_LEAK_FILE, $env:PURE_REDUCE_BINARY_LEAK_TEXT, [Text.Encoding]::Unicode)")
  elseif(_binary_case STREQUAL "unicode_utf16le")
    set(_binary_case_source_prefix "C:/Tést-Prefix/Alpha")
    set(ENV{PURE_REDUCE_BINARY_LEAK_TEXT} "c:/tést-pREFIX/aLPHA")
    set(_append_script
      "[IO.File]::AppendAllText($env:PURE_REDUCE_BINARY_LEAK_FILE, $env:PURE_REDUCE_BINARY_LEAK_TEXT, [Text.Encoding]::Unicode)")
  else()
    set(_binary_case_source_prefix "c:/")
    set(ENV{PURE_REDUCE_BINARY_LEAK_TEXT} "")
    set(_append_script
      "$p=$env:PURE_REDUCE_BINARY_LEAK_FILE; $s=[IO.File]::Open($p,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::None); try { $v=[byte[]](0x06,0x33,0xa2,0xf0); $s.Write($v,0,$v.Length) } finally { $s.Dispose() }")
  endif()
  execute_process(
    COMMAND "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
      -NoProfile -NonInteractive -Command
      "${_append_script}"
    RESULT_VARIABLE _binary_append_result
    OUTPUT_VARIABLE _binary_append_output
    ERROR_VARIABLE _binary_append_error
    ENCODING UTF-8)
  unset(ENV{PURE_REDUCE_BINARY_LEAK_FILE})
  unset(ENV{PURE_REDUCE_BINARY_LEAK_TEXT})
  if(NOT _binary_append_result EQUAL 0)
    message(FATAL_ERROR
      "unable to create ${_binary_case} binary leak (${_binary_append_result})\n"
      "stdout:\n${_binary_append_output}\n"
      "stderr:\n${_binary_append_error}")
  endif()
file(SHA256 "${_binary_leak_stage}/${_binary_leak_relative}"
  _binary_leak_sha)
file(SIZE "${_binary_leak_stage}/${_binary_leak_relative}"
  _binary_leak_bytes)
file(STRINGS "${_binary_leak_stage}/${_inventory_relative}"
  _binary_inventory_lines)
set(_new_binary_inventory_lines)
foreach(_line IN LISTS _binary_inventory_lines)
  if(_line MATCHES "^${_binary_leak_relative}${_tab}")
    string(REPLACE "${_tab}" ";" _fields "${_line}")
    list(GET _fields 0 _field_path)
    list(GET _fields 1 _field_purpose)
    list(GET _fields 2 _field_origin)
    list(GET _fields 5 _field_license)
    set(_line
      "${_field_path}${_tab}${_field_purpose}${_tab}${_field_origin}${_tab}${_binary_leak_sha}${_tab}${_binary_leak_bytes}${_tab}${_field_license}")
  endif()
  list(APPEND _new_binary_inventory_lines "${_line}")
endforeach()
list(JOIN _new_binary_inventory_lines "\n" _new_binary_inventory_text)
file(WRITE "${_binary_leak_stage}/${_inventory_relative}"
  "${_new_binary_inventory_text}\n")
file(COPY_FILE "${_binary_leak_stage}/${_inventory_relative}"
  "${_binary_leak_build}/PureReduceInstalledInventory.tsv")
file(SHA256 "${_binary_leak_stage}/${_inventory_relative}"
  _binary_inventory_sha)
file(SIZE "${_binary_leak_stage}/${_inventory_relative}"
  _binary_inventory_bytes)
file(STRINGS "${AUTHORITATIVE_MANIFEST}" _binary_manifest_lines)
set(_new_binary_manifest_lines)
foreach(_line IN LISTS _binary_manifest_lines)
  if(_line MATCHES "  ${_binary_leak_relative}$")
    set(_line "${_binary_leak_sha}  ${_binary_leak_relative}")
  elseif(_line MATCHES "  ${_inventory_relative}$")
    set(_line "${_binary_inventory_sha}  ${_inventory_relative}")
  endif()
  list(APPEND _new_binary_manifest_lines "${_line}")
endforeach()
list(JOIN _new_binary_manifest_lines "\n" _new_binary_manifest_text)
file(WRITE "${_binary_leak_build}/PureReduceExpected.sha256"
  "${_new_binary_manifest_text}\n")
file(STRINGS "${_build_dir}/PureReduceInventory.tsv"
  _binary_external_lines)
set(_new_binary_external_lines)
foreach(_line IN LISTS _binary_external_lines)
  if(_line MATCHES "^${_binary_leak_relative}${_tab}")
    string(REPLACE "${_tab}" ";" _fields "${_line}")
    list(GET _fields 0 _field_path)
    list(GET _fields 1 _field_purpose)
    list(GET _fields 2 _field_origin)
    list(GET _fields 5 _field_license)
    set(_line
      "${_field_path}${_tab}${_field_purpose}${_tab}${_field_origin}${_tab}${_binary_leak_sha}${_tab}${_binary_leak_bytes}${_tab}${_field_license}")
  elseif(_line MATCHES "^${_inventory_relative}${_tab}")
    string(REPLACE "${_tab}" ";" _fields "${_line}")
    list(GET _fields 0 _field_path)
    list(GET _fields 1 _field_purpose)
    list(GET _fields 2 _field_origin)
    list(GET _fields 5 _field_license)
    set(_line
      "${_field_path}${_tab}${_field_purpose}${_tab}${_field_origin}${_tab}${_binary_inventory_sha}${_tab}${_binary_inventory_bytes}${_tab}${_field_license}")
  endif()
  list(APPEND _new_binary_external_lines "${_line}")
endforeach()
list(JOIN _new_binary_external_lines "\n" _new_binary_external_text)
file(WRITE "${_binary_leak_build}/PureReduceInventory.tsv"
  "${_new_binary_external_text}\n")
execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DBUILD_DIR=${_binary_leak_build}"
    "-DSTAGE_PREFIX=${_binary_leak_stage}"
    "-DAUTHORITATIVE_MANIFEST=${_binary_leak_build}/PureReduceExpected.sha256"
    "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    "-DSOURCE_PREFIX=${_binary_case_source_prefix}"
    "-DORIGINAL_STAGE_PREFIX=${_original_stage}"
    -DVERIFY_ONLY=ON
    -DRUN_RUNTIME_TESTS=OFF
    -P "${VERIFIER}"
  RESULT_VARIABLE _binary_leak_result
  OUTPUT_VARIABLE _binary_leak_output
  ERROR_VARIABLE _binary_leak_error
  ENCODING UTF-8)
set(_binary_leak_combined
  "${_binary_leak_output}\n${_binary_leak_error}")
if(_binary_case STREQUAL "odd_nibble")
  if(NOT _binary_leak_result EQUAL 0)
    list(APPEND _binary_leak_failures
      "verifier falsely rejected aligned bytes 06 33 a2 f0 as c:/\n"
      "${_binary_leak_combined}")
  endif()
else()
  if(_binary_leak_result EQUAL 0)
    list(APPEND _binary_leak_failures
      "verifier accepted a hash-authorized mixed-case ${_binary_case} binary prefix leak")
  elseif(NOT _binary_leak_combined MATCHES
      "installed binary content leaks a forbidden prefix")
    list(APPEND _binary_leak_failures
      "${_binary_case} binary prefix leak failed for the wrong reason\n"
      "${_binary_leak_combined}")
  endif()
endif()
endforeach()
if(_binary_leak_failures)
  list(JOIN _binary_leak_failures "\n---\n" _binary_leak_failure_text)
  message(FATAL_ERROR "${_binary_leak_failure_text}")
endif()

# Installation ownership: an overlay may replace only manifest-owned files,
# and manifest-guided removal must preserve unrelated Pure prefix content.
message(STATUS "relocation phase: overlay and removal ownership")
file(REMOVE_RECURSE "${_ownership_oracle_root}")
file(MAKE_DIRECTORY "${_ownership_oracle_root}")
foreach(_oracle_name IN ITEMS
    PureReduceExpected.sha256
    PureReduceInventory.tsv
    PureReduceInstalledInventory.tsv)
  file(COPY_FILE "${_build_dir}/${_oracle_name}"
    "${_ownership_oracle_root}/${_oracle_name}")
  file(SHA256 "${_ownership_oracle_root}/${_oracle_name}"
    "_ownership_oracle_sha_${_oracle_name}")
endforeach()
file(STRINGS "${_ownership_oracle_root}/PureReduceExpected.sha256"
  _ownership_trusted_lines)
file(REMOVE_RECURSE "${_ownership_stage}")
file(MAKE_DIRECTORY
  "${_ownership_stage}/share/unrelated"
  "${_ownership_stage}/lib/pure")
set(_sentinel "${_ownership_stage}/share/unrelated/sentinel.txt")
set(_other_pure "${_ownership_stage}/lib/pure/preexisting-runtime.pure")
file(WRITE "${_sentinel}" "unrelated sentinel\n")
file(WRITE "${_other_pure}" "// pre-existing Pure payload\n")
file(SHA256 "${_sentinel}" _sentinel_sha)
file(SHA256 "${_other_pure}" _other_pure_sha)

foreach(_install_round RANGE 1 2)
  execute_process(
    COMMAND "${CMAKE_COMMAND}" --install "${_build_dir}"
      --prefix "${_ownership_stage}" --component PureReduce
    RESULT_VARIABLE _install_result
    OUTPUT_VARIABLE _install_output
    ERROR_VARIABLE _install_error
    ENCODING UTF-8)
  if(NOT _install_result EQUAL 0)
    message(FATAL_ERROR
      "ownership install round ${_install_round} failed (${_install_result})\n"
      "stdout:\n${_install_output}\nstderr:\n${_install_error}")
  endif()
  foreach(_oracle_name IN ITEMS
      PureReduceExpected.sha256
      PureReduceInventory.tsv
      PureReduceInstalledInventory.tsv)
    foreach(_oracle_root IN ITEMS "${_build_dir}" "${_ownership_oracle_root}")
      set(_oracle_file "${_oracle_root}/${_oracle_name}")
      if(NOT EXISTS "${_oracle_file}" OR IS_DIRECTORY "${_oracle_file}")
        message(FATAL_ERROR
          "ownership install round ${_install_round} removed trusted oracle: "
          "${_oracle_name}")
      endif()
      file(SHA256 "${_oracle_file}" _oracle_sha_after)
      if(NOT _oracle_sha_after STREQUAL
          "${_ownership_oracle_sha_${_oracle_name}}")
        message(FATAL_ERROR
          "ownership install round ${_install_round} changed trusted oracle: "
          "${_oracle_name}")
      endif()
    endforeach()
  endforeach()
  foreach(_unowned IN ITEMS "${_sentinel}" "${_other_pure}")
    file(SHA256 "${_unowned}" _unowned_sha)
    if(_unowned STREQUAL _sentinel AND
        NOT _unowned_sha STREQUAL _sentinel_sha)
      message(FATAL_ERROR "component install modified the unrelated sentinel")
    elseif(_unowned STREQUAL _other_pure AND
        NOT _unowned_sha STREQUAL _other_pure_sha)
      message(FATAL_ERROR "component install modified another Pure file")
    endif()
  endforeach()
  foreach(_owned_line IN LISTS _ownership_trusted_lines)
    string(SUBSTRING "${_owned_line}" 0 64 _owned_sha)
    string(SUBSTRING "${_owned_line}" 66 -1 _owned_relative)
    set(_owned_file "${_ownership_stage}/${_owned_relative}")
    if(NOT EXISTS "${_owned_file}" OR IS_DIRECTORY "${_owned_file}")
      message(FATAL_ERROR
        "owned payload is missing after install round ${_install_round}: "
        "${_owned_relative}")
    endif()
    file(SHA256 "${_owned_file}" _actual_owned_sha)
    if(NOT _actual_owned_sha STREQUAL _owned_sha)
      message(FATAL_ERROR
        "owned payload hash differs after install round ${_install_round}: "
        "${_owned_relative}")
    endif()
  endforeach()
endforeach()

set(_owned_paths)
foreach(_line IN LISTS _ownership_trusted_lines)
  string(SUBSTRING "${_line}" 66 -1 _relative)
  set(_relative_path "${_relative}")
  cmake_path(IS_ABSOLUTE _relative_path _absolute)
  string(REPLACE "/" ";" _segments "${_relative}")
  if(_absolute OR _relative MATCHES "^[./\\\\]" OR
      _relative MATCHES "\\\\" OR ".." IN_LIST _segments)
    message(FATAL_ERROR "unsafe owned removal path: ${_relative}")
  endif()
  set(_owned "${_ownership_stage}/${_relative}")
  cmake_path(IS_PREFIX _ownership_stage "${_owned}" NORMALIZE _inside_stage)
  if(NOT _inside_stage OR NOT EXISTS "${_owned}" OR IS_DIRECTORY "${_owned}")
    message(FATAL_ERROR "owned install path is missing before removal: ${_relative}")
  endif()
  list(APPEND _owned_paths "${_owned}")
endforeach()
foreach(_owned IN LISTS _owned_paths)
  file(REMOVE "${_owned}")
endforeach()
foreach(_owned IN LISTS _owned_paths)
  if(EXISTS "${_owned}")
    message(FATAL_ERROR "manifest-owned path remains after removal: ${_owned}")
  endif()
endforeach()
file(GLOB_RECURSE _remaining_files LIST_DIRECTORIES FALSE
  "${_ownership_stage}/*")
list(SORT _remaining_files COMPARE NATURAL CASE INSENSITIVE)
set(_expected_remaining "${_other_pure}" "${_sentinel}")
list(SORT _expected_remaining COMPARE NATURAL CASE INSENSITIVE)
if(NOT _remaining_files STREQUAL _expected_remaining)
  message(FATAL_ERROR
    "component removal left files outside the unowned seed set: "
    "${_remaining_files}")
endif()
file(SHA256 "${_sentinel}" _sentinel_after_sha)
file(SHA256 "${_other_pure}" _other_pure_after_sha)
if(NOT _sentinel_after_sha STREQUAL _sentinel_sha OR
    NOT _other_pure_after_sha STREQUAL _other_pure_sha)
  message(FATAL_ERROR "manifest removal modified unrelated Pure prefix files")
endif()

message(STATUS
  "verified PureReduce relocation, prefix leak rejection, overlay and removal ownership")
