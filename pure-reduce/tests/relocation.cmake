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
  "${_build_dir}/relocated PureReduce Δοκιμή stage")
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
set(_leak_root "${_build_dir}/relocation prefix leak fixture")
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
file(COPY_FILE "${_build_dir}/PureReduceInventory.tsv"
  "${_leak_build}/PureReduceInventory.tsv")

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

# Installation ownership: an overlay may replace only manifest-owned files,
# and manifest-guided removal must preserve unrelated Pure prefix content.
set(_ownership_stage
  "${_build_dir}/ownership Pure prefix 日本語")
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
  file(STRINGS "${AUTHORITATIVE_MANIFEST}" _overlay_owned_lines)
  foreach(_owned_line IN LISTS _overlay_owned_lines)
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

file(STRINGS "${AUTHORITATIVE_MANIFEST}" _owned_lines)
set(_owned_paths)
foreach(_line IN LISTS _owned_lines)
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
