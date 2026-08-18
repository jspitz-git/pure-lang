include_guard(GLOBAL)

set(_PURE_REDUCE_TOOLCHAIN_PROVENANCE_HEADER
  "package\tversion\trole\tlink_input\tlink_input_sha256\towner\tsystem_notices\tsystem_notice_sha256s\tvendored_notices\tvendored_notice_sha256s")

# Registry fields are package, role, representative clang input, allowed
# relative input path, system notice path(s), and vendored notice name(s).
# Package versions are deliberately absent: they are captured from the rolling
# MSYS2 runner and compared as provenance, never treated as pinned policy.
set(_PURE_REDUCE_TOOLCHAIN_REGISTRY
  "mingw-w64-clang-x86_64-zlib|compression|libz.a|^lib/libz\\.a$|share/licenses/zlib/LICENSE|ZLIB-LICENSE.txt"
  "mingw-w64-clang-x86_64-ncurses|terminal handling|libncurses.a|^lib/libncurses\\.a$|share/licenses/ncurses/LICENSE|NCURSES-LICENSE.txt"
  "mingw-w64-clang-x86_64-winpthreads|POSIX threads|libpthread.a|^lib/libpthread\\.a$|share/licenses/winpthreads/COPYING|WINPTHREADS-COPYING.txt"
  "mingw-w64-clang-x86_64-libc++|C++ standard library|libc++.a|^lib/libc\\+\\+\\.a$|share/licenses/libc++/LICENSE|LIBCXX-LICENSE.txt"
  "mingw-w64-clang-x86_64-libunwind|stack unwinding|libunwind.a|^lib/libunwind\\.a$|share/licenses/libunwind/LICENSE|LIBUNWIND-LICENSE.txt"
  "mingw-w64-clang-x86_64-compiler-rt|compiler runtime|libclang_rt.builtins-x86_64.a|^lib/clang/[A-Za-z0-9._+~-]+/lib/windows/libclang_rt\\.builtins-x86_64\\.a$|share/licenses/compiler-rt/LICENSE|COMPILER-RT-LICENSE.txt"
  "mingw-w64-clang-x86_64-crt|C runtime startup|dllcrt2.o|^lib/dllcrt2\\.o$|share/licenses/crt/COPYING,share/licenses/crt/COPYING.MinGW-w64-runtime.txt|MINGW-W64-CRT-COPYING.txt,MINGW-W64-RUNTIME-COPYING.txt")

function(pure_reduce_toolchain_registry OUT_RECORDS)
  set(${OUT_RECORDS} "${_PURE_REDUCE_TOOLCHAIN_REGISTRY}" PARENT_SCOPE)
endfunction()

function(_pure_reduce_split_record RECORD EXPECTED_COUNT CONTEXT OUT_FIELDS)
  string(REPLACE "|" ";" _fields "${RECORD}")
  list(LENGTH _fields _field_count)
  if(NOT _field_count EQUAL EXPECTED_COUNT)
    message(FATAL_ERROR
      "${CONTEXT} has ${_field_count} fields; expected ${EXPECTED_COUNT}")
  endif()
  set(${OUT_FIELDS} "${_fields}" PARENT_SCOPE)
endfunction()

function(_pure_reduce_require_safe_relative PATH_VALUE CONTEXT)
  if("${PATH_VALUE}" STREQUAL "" OR
      "${PATH_VALUE}" MATCHES "[\\\\|;,[:space:]]" OR
      "${PATH_VALUE}" MATCHES "^/" OR
      "${PATH_VALUE}" MATCHES "^[A-Za-z]:" OR
      "${PATH_VALUE}" MATCHES "//" OR
      NOT "${PATH_VALUE}" MATCHES "^[A-Za-z0-9._+~/-]+$")
    message(FATAL_ERROR "${CONTEXT} is not a safe canonical relative path")
  endif()
  string(REPLACE "/" ";" _components "${PATH_VALUE}")
  foreach(_component IN LISTS _components)
    if(_component STREQUAL "" OR _component STREQUAL "." OR
        _component STREQUAL "..")
      message(FATAL_ERROR "${CONTEXT} is not a safe canonical relative path")
    endif()
  endforeach()
endfunction()

function(_pure_reduce_require_sha256 VALUE CONTEXT)
  string(LENGTH "${VALUE}" _length)
  if(NOT _length EQUAL 64 OR "${VALUE}" MATCHES "[^0-9a-f]")
    message(FATAL_ERROR "${CONTEXT} has malformed lowercase SHA256")
  endif()
endfunction()

function(_pure_reduce_csv_values CSV CONTEXT OUT_VALUES)
  if("${CSV}" STREQUAL "" OR "${CSV}" MATCHES "(^,|,$|,,)")
    message(FATAL_ERROR "${CONTEXT} is an empty or malformed CSV field")
  endif()
  string(REPLACE "," ";" _values "${CSV}")
  set(${OUT_VALUES} "${_values}" PARENT_SCOPE)
endfunction()

function(_pure_reduce_registry_packages OUT_PACKAGES)
  set(_packages)
  foreach(_registry_record IN LISTS _PURE_REDUCE_TOOLCHAIN_REGISTRY)
    _pure_reduce_split_record("${_registry_record}" 6
      "internal toolchain registry record" _registry_fields)
    list(GET _registry_fields 0 _package)
    list(APPEND _packages "${_package}")
  endforeach()
  set(${OUT_PACKAGES} "${_packages}" PARENT_SCOPE)
endfunction()

function(_pure_reduce_validate_toolchain_records RECORDS VENDORED_LICENSE_DIR)
  if(NOT "${VENDORED_LICENSE_DIR}" STREQUAL "" AND
      (NOT IS_ABSOLUTE "${VENDORED_LICENSE_DIR}" OR
       NOT IS_DIRECTORY "${VENDORED_LICENSE_DIR}"))
    message(FATAL_ERROR
      "vendored license directory must be an existing absolute directory")
  endif()

  _pure_reduce_registry_packages(_expected_packages)
  set(_seen_packages)
  foreach(_record IN LISTS RECORDS)
    _pure_reduce_split_record("${_record}" 10
      "toolchain provenance record" _fields)
    list(GET _fields 0 _package)
    if(_package IN_LIST _seen_packages)
      message(FATAL_ERROR
        "toolchain provenance contains duplicate package ${_package}")
    endif()
    if(NOT _package IN_LIST _expected_packages)
      message(FATAL_ERROR
        "toolchain provenance contains unexpected package ${_package}")
    endif()
    list(APPEND _seen_packages "${_package}")
  endforeach()
  foreach(_expected_package IN LISTS _expected_packages)
    if(NOT _expected_package IN_LIST _seen_packages)
      message(FATAL_ERROR
        "toolchain provenance is missing package ${_expected_package}")
    endif()
  endforeach()

  list(LENGTH RECORDS _record_count)
  list(LENGTH _PURE_REDUCE_TOOLCHAIN_REGISTRY _registry_count)
  if(NOT _record_count EQUAL _registry_count)
    message(FATAL_ERROR
      "toolchain provenance does not contain the exact registry set")
  endif()

  math(EXPR _last_record "${_record_count} - 1")
  foreach(_index RANGE 0 ${_last_record})
    list(GET RECORDS ${_index} _record)
    list(GET _PURE_REDUCE_TOOLCHAIN_REGISTRY ${_index} _registry_record)
    _pure_reduce_split_record("${_record}" 10
      "toolchain provenance record" _fields)
    _pure_reduce_split_record("${_registry_record}" 6
      "internal toolchain registry record" _registry_fields)

    list(GET _fields 0 _package)
    list(GET _fields 1 _version)
    list(GET _fields 2 _role)
    list(GET _fields 3 _link_input)
    list(GET _fields 4 _link_input_sha256)
    list(GET _fields 5 _owner)
    list(GET _fields 6 _system_notices_csv)
    list(GET _fields 7 _system_hashes_csv)
    list(GET _fields 8 _vendored_notices_csv)
    list(GET _fields 9 _vendored_hashes_csv)

    list(GET _registry_fields 0 _expected_package)
    list(GET _registry_fields 1 _expected_role)
    list(GET _registry_fields 3 _input_pattern)
    list(GET _registry_fields 4 _expected_system_notices_csv)
    list(GET _registry_fields 5 _expected_vendored_notices_csv)

    if(NOT _package STREQUAL _expected_package)
      message(FATAL_ERROR
        "toolchain provenance package order is not canonical at row ${_index}")
    endif()
    if("${_version}" STREQUAL "" OR
        NOT "${_version}" MATCHES "^[A-Za-z0-9][A-Za-z0-9._+~:-]*$")
      message(FATAL_ERROR
        "toolchain provenance version for ${_package} is empty or unsafe")
    endif()
    if(NOT _role STREQUAL _expected_role)
      message(FATAL_ERROR
        "toolchain provenance role does not match registry for ${_package}")
    endif()
    _pure_reduce_require_safe_relative("${_link_input}"
      "toolchain input for ${_package}")
    if(NOT "${_link_input}" MATCHES "${_input_pattern}")
      message(FATAL_ERROR
        "toolchain input does not match registry for ${_package}: ${_link_input}")
    endif()
    _pure_reduce_require_sha256("${_link_input_sha256}"
      "toolchain input for ${_package}")
    if(NOT _owner STREQUAL _package)
      message(FATAL_ERROR
        "toolchain provenance owner does not match package ${_package}")
    endif()
    if(NOT _system_notices_csv STREQUAL _expected_system_notices_csv OR
        NOT _vendored_notices_csv STREQUAL _expected_vendored_notices_csv)
      message(FATAL_ERROR
        "toolchain notice registry does not match package ${_package}")
    endif()

    _pure_reduce_csv_values("${_system_notices_csv}"
      "system notices for ${_package}" _system_notices)
    _pure_reduce_csv_values("${_system_hashes_csv}"
      "system notice hashes for ${_package}" _system_hashes)
    _pure_reduce_csv_values("${_vendored_notices_csv}"
      "vendored notices for ${_package}" _vendored_notices)
    _pure_reduce_csv_values("${_vendored_hashes_csv}"
      "vendored notice hashes for ${_package}" _vendored_hashes)
    list(LENGTH _system_notices _system_notice_count)
    list(LENGTH _system_hashes _system_hash_count)
    list(LENGTH _vendored_notices _vendored_notice_count)
    list(LENGTH _vendored_hashes _vendored_hash_count)
    if(NOT _system_notice_count EQUAL _system_hash_count OR
        NOT _system_notice_count EQUAL _vendored_notice_count OR
        NOT _system_notice_count EQUAL _vendored_hash_count)
      message(FATAL_ERROR
        "toolchain notice/hash counts differ for ${_package}")
    endif()

    math(EXPR _last_notice "${_system_notice_count} - 1")
    foreach(_notice_index RANGE 0 ${_last_notice})
      list(GET _system_notices ${_notice_index} _system_notice)
      list(GET _system_hashes ${_notice_index} _system_hash)
      list(GET _vendored_notices ${_notice_index} _vendored_notice)
      list(GET _vendored_hashes ${_notice_index} _vendored_hash)
      _pure_reduce_require_safe_relative("${_system_notice}"
        "system notice for ${_package}")
      _pure_reduce_require_safe_relative("${_vendored_notice}"
        "vendored notice for ${_package}")
      _pure_reduce_require_sha256("${_system_hash}"
        "system notice for ${_package}")
      _pure_reduce_require_sha256("${_vendored_hash}"
        "vendored notice for ${_package}")
      if(NOT _system_hash STREQUAL _vendored_hash)
        message(FATAL_ERROR
          "system/vendored notice hashes differ for ${_package}")
      endif()
      if(NOT "${VENDORED_LICENSE_DIR}" STREQUAL "")
        set(_vendored_path
          "${VENDORED_LICENSE_DIR}/${_vendored_notice}")
        if(NOT EXISTS "${_vendored_path}" OR IS_DIRECTORY "${_vendored_path}")
          message(FATAL_ERROR
            "vendored notice is missing for ${_package}: ${_vendored_notice}")
        endif()
        file(SHA256 "${_vendored_path}" _actual_vendored_hash)
        if(NOT _actual_vendored_hash STREQUAL _vendored_hash)
          message(FATAL_ERROR
            "vendored notice hash mismatch for ${_package}: ${_vendored_notice}")
        endif()
      endif()
    endforeach()
  endforeach()
endfunction()

function(pure_reduce_parse_toolchain_provenance SNAPSHOT_FILE OUT_RECORDS)
  if(NOT IS_ABSOLUTE "${SNAPSHOT_FILE}" OR
      NOT EXISTS "${SNAPSHOT_FILE}" OR IS_DIRECTORY "${SNAPSHOT_FILE}")
    message(FATAL_ERROR
      "toolchain provenance snapshot must be an existing absolute file")
  endif()
  file(READ "${SNAPSHOT_FILE}" _content)
  string(FIND "${_content}" ";" _semicolon)
  string(FIND "${_content}" "\r" _carriage_return)
  if(_semicolon GREATER -1 OR _carriage_return GREATER -1 OR
      "${_content}" STREQUAL "" OR NOT "${_content}" MATCHES "\n$")
    message(FATAL_ERROR
      "toolchain provenance snapshot has malformed canonical line encoding")
  endif()
  string(REGEX REPLACE "\n$" "" _without_final_newline "${_content}")
  string(REPLACE "\n" ";" _lines "${_without_final_newline}")
  list(POP_FRONT _lines _header)
  if(NOT _header STREQUAL _PURE_REDUCE_TOOLCHAIN_PROVENANCE_HEADER)
    message(FATAL_ERROR "toolchain provenance snapshot has unexpected schema")
  endif()
  set(_records)
  foreach(_line IN LISTS _lines)
    if(_line STREQUAL "" OR _line MATCHES "\\|")
      message(FATAL_ERROR "toolchain provenance snapshot has malformed row")
    endif()
    string(REPLACE "\t" "|" _record "${_line}")
    _pure_reduce_split_record("${_record}" 10
      "toolchain provenance row" _unused_fields)
    list(APPEND _records "${_record}")
  endforeach()
  _pure_reduce_validate_toolchain_records("${_records}" "")
  set(${OUT_RECORDS} "${_records}" PARENT_SCOPE)
endfunction()

function(pure_reduce_toolchain_provenance_tsv RECORDS OUT_CONTENT)
  _pure_reduce_validate_toolchain_records("${RECORDS}" "")
  set(_content "${_PURE_REDUCE_TOOLCHAIN_PROVENANCE_HEADER}\n")
  foreach(_record IN LISTS RECORDS)
    string(REPLACE "|" "\t" _line "${_record}")
    string(APPEND _content "${_line}\n")
  endforeach()
  set(${OUT_CONTENT} "${_content}" PARENT_SCOPE)
endfunction()

function(pure_reduce_toolchain_provenance_json RECORDS OUT_JSON)
  _pure_reduce_validate_toolchain_records("${RECORDS}" "")
  set(_json "[")
  set(_record_separator "")
  foreach(_record IN LISTS RECORDS)
    _pure_reduce_split_record("${_record}" 10
      "toolchain provenance record" _fields)
    list(GET _fields 0 _package)
    list(GET _fields 1 _version)
    list(GET _fields 2 _role)
    list(GET _fields 3 _link_input)
    list(GET _fields 4 _link_input_sha256)
    list(GET _fields 5 _owner)
    list(GET _fields 6 _system_notices_csv)
    list(GET _fields 8 _vendored_notices_csv)
    list(GET _fields 9 _notice_hashes_csv)
    _pure_reduce_csv_values("${_system_notices_csv}"
      "system notices for ${_package}" _system_notices)
    _pure_reduce_csv_values("${_vendored_notices_csv}"
      "vendored notices for ${_package}" _vendored_notices)
    _pure_reduce_csv_values("${_notice_hashes_csv}"
      "notice hashes for ${_package}" _notice_hashes)

    string(APPEND _json "${_record_separator}"
      "{\"package\":\"${_package}\","
      "\"version\":\"${_version}\","
      "\"role\":\"${_role}\","
      "\"link_input\":{\"path\":\"${_link_input}\","
      "\"sha256\":\"${_link_input_sha256}\","
      "\"owner\":\"${_owner}\"},\"notices\":[")
    list(LENGTH _system_notices _notice_count)
    math(EXPR _last_notice "${_notice_count} - 1")
    set(_notice_separator "")
    foreach(_notice_index RANGE 0 ${_last_notice})
      list(GET _system_notices ${_notice_index} _system_notice)
      list(GET _vendored_notices ${_notice_index} _vendored_notice)
      list(GET _notice_hashes ${_notice_index} _notice_hash)
      string(APPEND _json "${_notice_separator}"
        "{\"system_path\":\"${_system_notice}\","
        "\"vendored_path\":\"${_vendored_notice}\","
        "\"sha256\":\"${_notice_hash}\"}")
      set(_notice_separator ",")
    endforeach()
    string(APPEND _json "]}")
    set(_record_separator ",")
  endforeach()
  string(APPEND _json "]")
  set(${OUT_JSON} "${_json}" PARENT_SCOPE)
endfunction()

function(pure_reduce_validate_toolchain_provenance_json
    JSON_ARRAY VENDORED_LICENSE_DIR OUT_RECORDS)
  string(JSON _array_type ERROR_VARIABLE _json_error TYPE "${JSON_ARRAY}")
  if(_json_error OR NOT _array_type STREQUAL "ARRAY")
    message(FATAL_ERROR "toolchain provenance JSON must be an array")
  endif()
  string(JSON _record_count LENGTH "${JSON_ARRAY}")
  list(LENGTH _PURE_REDUCE_TOOLCHAIN_REGISTRY _expected_count)
  if(NOT _record_count EQUAL _expected_count)
    message(FATAL_ERROR
      "toolchain provenance JSON must contain exactly ${_expected_count} records")
  endif()

  set(_records)
  math(EXPR _last_record "${_record_count} - 1")
  foreach(_index RANGE 0 ${_last_record})
    string(JSON _record_type ERROR_VARIABLE _json_error
      TYPE "${JSON_ARRAY}" ${_index})
    string(JSON _member_count ERROR_VARIABLE _json_error
      LENGTH "${JSON_ARRAY}" ${_index})
    if(_json_error OR NOT _record_type STREQUAL "OBJECT" OR
       NOT _member_count EQUAL 5)
      message(FATAL_ERROR
        "toolchain provenance JSON record ${_index} has unexpected schema")
    endif()
    set(_member_names)
    math(EXPR _last_member "${_member_count} - 1")
    foreach(_member_index RANGE 0 ${_last_member})
      string(JSON _member_name MEMBER "${JSON_ARRAY}"
        ${_index} ${_member_index})
      list(APPEND _member_names "${_member_name}")
    endforeach()
    list(SORT _member_names)
    if(NOT _member_names STREQUAL
        "link_input;notices;package;role;version")
      message(FATAL_ERROR
        "toolchain provenance JSON record ${_index} has unexpected members")
    endif()

    foreach(_field IN ITEMS package version role)
      string(JSON _value ERROR_VARIABLE _json_error GET
        "${JSON_ARRAY}" ${_index} "${_field}")
      if(_json_error)
        message(FATAL_ERROR
          "toolchain provenance JSON record ${_index} omits ${_field}")
      endif()
      set("_${_field}" "${_value}")
    endforeach()

    string(JSON _input_type ERROR_VARIABLE _json_error TYPE
      "${JSON_ARRAY}" ${_index} link_input)
    string(JSON _input_member_count ERROR_VARIABLE _json_error LENGTH
      "${JSON_ARRAY}" ${_index} link_input)
    if(_json_error OR NOT _input_type STREQUAL "OBJECT" OR
       NOT _input_member_count EQUAL 3)
      message(FATAL_ERROR
        "toolchain provenance JSON record ${_index} has malformed link_input")
    endif()
    set(_input_member_names)
    foreach(_member_index RANGE 0 2)
      string(JSON _member_name MEMBER "${JSON_ARRAY}"
        ${_index} link_input ${_member_index})
      list(APPEND _input_member_names "${_member_name}")
    endforeach()
    list(SORT _input_member_names)
    if(NOT _input_member_names STREQUAL "owner;path;sha256")
      message(FATAL_ERROR
        "toolchain provenance JSON record ${_index} has unexpected link_input members")
    endif()
    foreach(_field IN ITEMS path sha256 owner)
      string(JSON _value ERROR_VARIABLE _json_error GET
        "${JSON_ARRAY}" ${_index} link_input "${_field}")
      if(_json_error)
        message(FATAL_ERROR
          "toolchain provenance JSON record ${_index} omits link_input.${_field}")
      endif()
      set("_input_${_field}" "${_value}")
    endforeach()

    string(JSON _notices_type ERROR_VARIABLE _json_error TYPE
      "${JSON_ARRAY}" ${_index} notices)
    string(JSON _notice_count ERROR_VARIABLE _json_error LENGTH
      "${JSON_ARRAY}" ${_index} notices)
    if(_json_error OR NOT _notices_type STREQUAL "ARRAY" OR
       _notice_count LESS 1)
      message(FATAL_ERROR
        "toolchain provenance JSON record ${_index} has malformed notices")
    endif()
    set(_system_notices)
    set(_vendored_notices)
    set(_notice_hashes)
    math(EXPR _last_notice "${_notice_count} - 1")
    foreach(_notice_index RANGE 0 ${_last_notice})
      string(JSON _notice_type ERROR_VARIABLE _json_error TYPE
        "${JSON_ARRAY}" ${_index} notices ${_notice_index})
      string(JSON _notice_member_count ERROR_VARIABLE _json_error LENGTH
        "${JSON_ARRAY}" ${_index} notices ${_notice_index})
      if(_json_error OR NOT _notice_type STREQUAL "OBJECT" OR
         NOT _notice_member_count EQUAL 3)
        message(FATAL_ERROR
          "toolchain provenance JSON notice ${_index}/${_notice_index} has unexpected schema")
      endif()
      set(_notice_member_names)
      foreach(_member_index RANGE 0 2)
        string(JSON _member_name MEMBER "${JSON_ARRAY}"
          ${_index} notices ${_notice_index} ${_member_index})
        list(APPEND _notice_member_names "${_member_name}")
      endforeach()
      list(SORT _notice_member_names)
      if(NOT _notice_member_names STREQUAL
          "sha256;system_path;vendored_path")
        message(FATAL_ERROR
          "toolchain provenance JSON notice ${_index}/${_notice_index} has unexpected members")
      endif()
      foreach(_field IN ITEMS system_path vendored_path sha256)
        string(JSON _value ERROR_VARIABLE _json_error GET
          "${JSON_ARRAY}" ${_index} notices ${_notice_index} "${_field}")
        if(_json_error)
          message(FATAL_ERROR
            "toolchain provenance JSON notice ${_index}/${_notice_index} omits ${_field}")
        endif()
        set("_notice_${_field}" "${_value}")
      endforeach()
      list(APPEND _system_notices "${_notice_system_path}")
      list(APPEND _vendored_notices "${_notice_vendored_path}")
      list(APPEND _notice_hashes "${_notice_sha256}")
    endforeach()
    _pure_reduce_append_csv("${_system_notices}" _system_notices_csv)
    _pure_reduce_append_csv("${_vendored_notices}" _vendored_notices_csv)
    _pure_reduce_append_csv("${_notice_hashes}" _notice_hashes_csv)
    list(APPEND _records
      "${_package}|${_version}|${_role}|${_input_path}|${_input_sha256}|${_input_owner}|${_system_notices_csv}|${_notice_hashes_csv}|${_vendored_notices_csv}|${_notice_hashes_csv}")
  endforeach()
  _pure_reduce_validate_toolchain_records(
    "${_records}" "${VENDORED_LICENSE_DIR}")
  set(${OUT_RECORDS} "${_records}" PARENT_SCOPE)
endfunction()

function(pure_reduce_serialize_toolchain_provenance RECORDS OUTPUT_FILE)
  if(NOT IS_ABSOLUTE "${OUTPUT_FILE}" OR IS_DIRECTORY "${OUTPUT_FILE}")
    message(FATAL_ERROR
      "toolchain provenance output must be an absolute non-directory path")
  endif()
  pure_reduce_toolchain_provenance_tsv("${RECORDS}" _content)
  cmake_path(GET OUTPUT_FILE PARENT_PATH _output_parent)
  if(NOT IS_DIRECTORY "${_output_parent}")
    message(FATAL_ERROR
      "toolchain provenance output parent directory does not exist")
  endif()
  file(WRITE "${OUTPUT_FILE}" "${_content}")
endfunction()

function(pure_reduce_validate_toolchain_provenance
    SNAPSHOT_FILE VENDORED_LICENSE_DIR OUT_RECORDS)
  pure_reduce_parse_toolchain_provenance("${SNAPSHOT_FILE}" _records)
  _pure_reduce_validate_toolchain_records(
    "${_records}" "${VENDORED_LICENSE_DIR}")
  set(${OUT_RECORDS} "${_records}" PARENT_SCOPE)
endfunction()

function(pure_reduce_compare_toolchain_provenance
    CACHED_SNAPSHOT LIVE_SNAPSHOT VENDORED_LICENSE_DIR)
  pure_reduce_validate_toolchain_provenance(
    "${CACHED_SNAPSHOT}" "${VENDORED_LICENSE_DIR}" _cached_records)
  pure_reduce_validate_toolchain_provenance(
    "${LIVE_SNAPSHOT}" "${VENDORED_LICENSE_DIR}" _live_records)
  file(READ "${CACHED_SNAPSHOT}" _cached_content)
  file(READ "${LIVE_SNAPSHOT}" _live_content)
  if(NOT _cached_content STREQUAL _live_content)
    message(FATAL_ERROR "cached/live toolchain provenance mismatch")
  endif()
endfunction()

function(_pure_reduce_run_toolchain_query COMMAND_VALUE DESCRIPTION OUT_VALUE)
  execute_process(
    COMMAND ${COMMAND_VALUE} ${ARGN}
    RESULT_VARIABLE _result
    OUTPUT_VARIABLE _output
    ERROR_VARIABLE _error
    ENCODING UTF-8)
  if(NOT _result EQUAL 0)
    message(FATAL_ERROR
      "${DESCRIPTION} failed (${_result})\n"
      "stdout:\n${_output}\nstderr:\n${_error}")
  endif()
  string(STRIP "${_output}" _output)
  if(_output STREQUAL "" OR _output MATCHES "[\r\n]")
    message(FATAL_ERROR "${DESCRIPTION} returned malformed output")
  endif()
  set(${OUT_VALUE} "${_output}" PARENT_SCOPE)
endfunction()

function(_pure_reduce_append_csv LIST_VALUE OUT_CSV)
  if("${LIST_VALUE}" STREQUAL "")
    set(_csv "")
  else()
    string(REPLACE ";" "," _csv "${LIST_VALUE}")
  endif()
  set(${OUT_CSV} "${_csv}" PARENT_SCOPE)
endfunction()

function(pure_reduce_capture_toolchain_provenance
    PACMAN_COMMAND CLANG_COMMAND VENDORED_LICENSE_DIR OUTPUT_FILE)
  if("${PACMAN_COMMAND}" STREQUAL "" OR "${CLANG_COMMAND}" STREQUAL "")
    message(FATAL_ERROR "pacman and clang commands are required")
  endif()
  if(NOT IS_ABSOLUTE "${VENDORED_LICENSE_DIR}" OR
      NOT IS_DIRECTORY "${VENDORED_LICENSE_DIR}")
    message(FATAL_ERROR
      "vendored license directory must be an existing absolute directory")
  endif()

  set(_records)
  unset(_toolchain_prefix)
  foreach(_registry_record IN LISTS _PURE_REDUCE_TOOLCHAIN_REGISTRY)
    _pure_reduce_split_record("${_registry_record}" 6
      "internal toolchain registry record" _registry_fields)
    list(GET _registry_fields 0 _package)
    list(GET _registry_fields 1 _role)
    list(GET _registry_fields 2 _requested_input)
    list(GET _registry_fields 4 _system_notices_csv)
    list(GET _registry_fields 5 _vendored_notices_csv)

    _pure_reduce_run_toolchain_query("${PACMAN_COMMAND}"
      "pacman version query for ${_package}" _package_query -Q "${_package}")
    string(FIND "${_package_query}" " " _version_separator)
    if(_version_separator LESS 1)
      message(FATAL_ERROR
        "pacman version query returned malformed output for ${_package}")
    endif()
    string(SUBSTRING "${_package_query}" 0 ${_version_separator}
      _reported_package)
    math(EXPR _version_start "${_version_separator} + 1")
    string(SUBSTRING "${_package_query}" ${_version_start} -1 _version)
    if(NOT _reported_package STREQUAL _package OR
        "${_version}" STREQUAL "" OR
        NOT "${_version}" MATCHES "^[A-Za-z0-9][A-Za-z0-9._+~:-]*$")
      message(FATAL_ERROR
        "pacman version query returned unsafe or mismatched data for ${_package}")
    endif()

    _pure_reduce_run_toolchain_query("${CLANG_COMMAND}"
      "clang input query for ${_package}" _reported_input
      "-print-file-name=${_requested_input}")
    if(NOT IS_ABSOLUTE "${_reported_input}" OR
        NOT EXISTS "${_reported_input}" OR IS_DIRECTORY "${_reported_input}")
      message(FATAL_ERROR
        "clang input query did not resolve an existing absolute file for ${_package}")
    endif()
    file(REAL_PATH "${_reported_input}" _canonical_input)
    if(NOT DEFINED _toolchain_prefix)
      cmake_path(GET _canonical_input PARENT_PATH _input_directory)
      cmake_path(GET _input_directory PARENT_PATH _toolchain_prefix)
      file(REAL_PATH "${_toolchain_prefix}" _toolchain_prefix)
    endif()
    file(RELATIVE_PATH _relative_input
      "${_toolchain_prefix}" "${_canonical_input}")
    file(TO_CMAKE_PATH "${_relative_input}" _relative_input)
    _pure_reduce_require_safe_relative("${_relative_input}"
      "toolchain input for ${_package}")

    _pure_reduce_run_toolchain_query("${PACMAN_COMMAND}"
      "pacman owner query for ${_package}" _owner
      -Qqo "${_canonical_input}")
    if(NOT _owner STREQUAL _package)
      message(FATAL_ERROR
        "toolchain input owner query does not match package ${_package}")
    endif()
    file(SHA256 "${_canonical_input}" _input_hash)

    _pure_reduce_csv_values("${_system_notices_csv}"
      "system notice registry for ${_package}" _system_notices)
    _pure_reduce_csv_values("${_vendored_notices_csv}"
      "vendored notice registry for ${_package}" _vendored_notices)
    list(LENGTH _system_notices _system_notice_count)
    list(LENGTH _vendored_notices _vendored_notice_count)
    if(NOT _system_notice_count EQUAL _vendored_notice_count)
      message(FATAL_ERROR
        "internal notice registry counts differ for ${_package}")
    endif()
    set(_system_hashes)
    set(_vendored_hashes)
    math(EXPR _last_notice "${_system_notice_count} - 1")
    foreach(_notice_index RANGE 0 ${_last_notice})
      list(GET _system_notices ${_notice_index} _system_notice)
      list(GET _vendored_notices ${_notice_index} _vendored_notice)
      set(_system_path "${_toolchain_prefix}/${_system_notice}")
      set(_vendored_path "${VENDORED_LICENSE_DIR}/${_vendored_notice}")
      if(NOT EXISTS "${_system_path}" OR IS_DIRECTORY "${_system_path}")
        message(FATAL_ERROR
          "system notice is missing for ${_package}: ${_system_notice}")
      endif()
      if(NOT EXISTS "${_vendored_path}" OR IS_DIRECTORY "${_vendored_path}")
        message(FATAL_ERROR
          "vendored notice is missing for ${_package}: ${_vendored_notice}")
      endif()
      file(REAL_PATH "${_system_path}" _canonical_system_path)
      _pure_reduce_run_toolchain_query("${PACMAN_COMMAND}"
        "pacman notice owner query for ${_package}" _notice_owner
        -Qqo "${_canonical_system_path}")
      if(NOT _notice_owner STREQUAL _package)
        message(FATAL_ERROR
          "system notice owner query does not match package ${_package}")
      endif()
      file(SHA256 "${_canonical_system_path}" _system_hash)
      file(SHA256 "${_vendored_path}" _vendored_hash)
      if(NOT _system_hash STREQUAL _vendored_hash)
        message(FATAL_ERROR
          "system/vendored notice mismatch for ${_package}: ${_system_notice}")
      endif()
      list(APPEND _system_hashes "${_system_hash}")
      list(APPEND _vendored_hashes "${_vendored_hash}")
    endforeach()
    _pure_reduce_append_csv("${_system_hashes}" _system_hashes_csv)
    _pure_reduce_append_csv("${_vendored_hashes}" _vendored_hashes_csv)
    list(APPEND _records
      "${_package}|${_version}|${_role}|${_relative_input}|${_input_hash}|${_owner}|${_system_notices_csv}|${_system_hashes_csv}|${_vendored_notices_csv}|${_vendored_hashes_csv}")
  endforeach()

  _pure_reduce_validate_toolchain_records(
    "${_records}" "${VENDORED_LICENSE_DIR}")
  pure_reduce_serialize_toolchain_provenance("${_records}" "${OUTPUT_FILE}")
endfunction()
