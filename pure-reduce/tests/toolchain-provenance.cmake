cmake_minimum_required(VERSION 3.25)

# The same script is used as a deterministic command double. The production
# capture code still executes its injected pacman/clang command boundaries;
# only the slow, host-global package database is replaced by this fixture.
if(DEFINED PURE_REDUCE_TOOLCHAIN_FAKE_COMMAND)
  set(_args)
  math(EXPR _last_arg "${CMAKE_ARGC} - 1")
  foreach(_index RANGE 0 ${_last_arg})
    list(APPEND _args "${CMAKE_ARGV${_index}}")
  endforeach()

  if(PURE_REDUCE_TOOLCHAIN_FAKE_COMMAND STREQUAL "clang")
    set(_requested)
    foreach(_arg IN LISTS _args)
      if(_arg MATCHES "^-print-file-name=(.+)$")
        set(_requested "${CMAKE_MATCH_1}")
      endif()
    endforeach()
    if(_requested STREQUAL "libclang_rt.builtins-x86_64.a")
      set(_path
        "${PURE_REDUCE_TOOLCHAIN_FIXTURE_ROOT}/prefix/lib/clang/99/lib/windows/${_requested}")
    else()
      set(_path
        "${PURE_REDUCE_TOOLCHAIN_FIXTURE_ROOT}/prefix/lib/${_requested}")
    endif()
    execute_process(COMMAND "${CMAKE_COMMAND}" -E echo "${_path}")
    return()
  endif()

  if(NOT PURE_REDUCE_TOOLCHAIN_FAKE_COMMAND STREQUAL "pacman")
    message(FATAL_ERROR "unknown fake command mode")
  endif()
  list(FIND _args "-Q" _query_index)
  list(FIND _args "-Qqo" _owner_index)
  if(NOT _query_index EQUAL -1)
    math(EXPR _value_index "${_query_index} + 1")
    list(GET _args ${_value_index} _package)
    if(PURE_REDUCE_TOOLCHAIN_GENERATION STREQUAL "new" AND
        _package STREQUAL "mingw-w64-clang-x86_64-zlib")
      set(_version "10.0.0-1")
    elseif(_package STREQUAL "mingw-w64-clang-x86_64-zlib")
      set(_version "9.0.0-1")
    elseif(_package STREQUAL "mingw-w64-clang-x86_64-ncurses")
      set(_version "7.1-2")
    elseif(_package STREQUAL "mingw-w64-clang-x86_64-winpthreads")
      set(_version "r999.gfuture-1")
    elseif(_package STREQUAL "mingw-w64-clang-x86_64-libc++")
      set(_version "99.1.0-1")
    elseif(_package STREQUAL "mingw-w64-clang-x86_64-libunwind")
      set(_version "99.1.0-2")
    elseif(_package STREQUAL "mingw-w64-clang-x86_64-compiler-rt")
      set(_version "99.1.0-3")
    elseif(_package STREQUAL "mingw-w64-clang-x86_64-crt")
      set(_version "r1000.gfuture-1")
    else()
      message(FATAL_ERROR "fake pacman received an unexpected package")
    endif()
    execute_process(COMMAND "${CMAKE_COMMAND}" -E echo
      "${_package} ${_version}")
    return()
  elseif(NOT _owner_index EQUAL -1)
    math(EXPR _value_index "${_owner_index} + 1")
    list(GET _args ${_value_index} _path)
    if(_path MATCHES "[/\\\\]libz\\.a$" OR
        _path MATCHES "[/\\\\]licenses[/\\\\]zlib[/\\\\]LICENSE$")
      set(_package "mingw-w64-clang-x86_64-zlib")
    elseif(_path MATCHES "[/\\\\]libncurses\\.a$" OR
        _path MATCHES "[/\\\\]licenses[/\\\\]ncurses[/\\\\]LICENSE$")
      set(_package "mingw-w64-clang-x86_64-ncurses")
    elseif(_path MATCHES "[/\\\\]libpthread\\.a$" OR
        _path MATCHES "[/\\\\]licenses[/\\\\]winpthreads[/\\\\]COPYING$")
      set(_package "mingw-w64-clang-x86_64-winpthreads")
    elseif(_path MATCHES "[/\\\\]libc\\+\\+\\.a$" OR
        _path MATCHES "[/\\\\]licenses[/\\\\]libc\\+\\+[/\\\\]LICENSE$")
      set(_package "mingw-w64-clang-x86_64-libc++")
    elseif(_path MATCHES "[/\\\\]libunwind\\.a$" OR
        _path MATCHES "[/\\\\]licenses[/\\\\]libunwind[/\\\\]LICENSE$")
      set(_package "mingw-w64-clang-x86_64-libunwind")
    elseif(_path MATCHES "[/\\\\]libclang_rt\\.builtins-x86_64\\.a$" OR
        _path MATCHES "[/\\\\]licenses[/\\\\]compiler-rt[/\\\\]LICENSE$")
      set(_package "mingw-w64-clang-x86_64-compiler-rt")
    elseif(_path MATCHES "[/\\\\]dllcrt2\\.o$" OR
        _path MATCHES "[/\\\\]licenses[/\\\\]crt[/\\\\]")
      set(_package "mingw-w64-clang-x86_64-crt")
    else()
      message(FATAL_ERROR "fake pacman received an unexpected owner path")
    endif()
    if(PURE_REDUCE_TOOLCHAIN_OWNER_MISMATCH AND
        _path MATCHES "[/\\\\]libpthread\\.a$")
      set(_package "mingw-w64-clang-x86_64-zlib")
    endif()
    execute_process(COMMAND "${CMAKE_COMMAND}" -E echo "${_package}")
    return()
  endif()
  message(FATAL_ERROR "fake pacman received an unsupported query")
endif()

if(NOT DEFINED PURE_REDUCE_SOURCE_DIR OR
    "${PURE_REDUCE_SOURCE_DIR}" STREQUAL "")
  message(FATAL_ERROR "PURE_REDUCE_SOURCE_DIR is required")
endif()

include("${PURE_REDUCE_SOURCE_DIR}/cmake/ToolchainProvenance.cmake")

if(DEFINED PURE_REDUCE_TOOLCHAIN_PROBE_MODE)
  if(PURE_REDUCE_TOOLCHAIN_PROBE_MODE STREQUAL "validate")
    pure_reduce_validate_toolchain_provenance(
      "${PURE_REDUCE_TOOLCHAIN_PROBE_FILE}"
      "${PURE_REDUCE_TOOLCHAIN_FIXTURE_ROOT}/vendored"
      _unused_records)
  elseif(PURE_REDUCE_TOOLCHAIN_PROBE_MODE STREQUAL "compare")
    pure_reduce_compare_toolchain_provenance(
      "${PURE_REDUCE_TOOLCHAIN_PROBE_FILE}"
      "${PURE_REDUCE_TOOLCHAIN_PROBE_SECOND_FILE}"
      "${PURE_REDUCE_TOOLCHAIN_FIXTURE_ROOT}/vendored")
  elseif(PURE_REDUCE_TOOLCHAIN_PROBE_MODE STREQUAL "json")
    file(READ "${PURE_REDUCE_TOOLCHAIN_PROBE_FILE}" _probe_json)
    pure_reduce_validate_toolchain_provenance_json(
      "${_probe_json}"
      "${PURE_REDUCE_TOOLCHAIN_FIXTURE_ROOT}/vendored"
      _unused_json_records)
  elseif(PURE_REDUCE_TOOLCHAIN_PROBE_MODE MATCHES "^capture-")
    if(PURE_REDUCE_TOOLCHAIN_PROBE_MODE STREQUAL "capture-owner")
      set(_owner_mismatch ON)
    else()
      set(_owner_mismatch OFF)
    endif()
    set(_pacman_command
      "${CMAKE_COMMAND};-DPURE_REDUCE_TOOLCHAIN_FAKE_COMMAND=pacman;-DPURE_REDUCE_TOOLCHAIN_FIXTURE_ROOT=${PURE_REDUCE_TOOLCHAIN_FIXTURE_ROOT};-DPURE_REDUCE_TOOLCHAIN_GENERATION=old;-DPURE_REDUCE_TOOLCHAIN_OWNER_MISMATCH=${_owner_mismatch};-P;${CMAKE_CURRENT_LIST_FILE};--")
    set(_clang_command
      "${CMAKE_COMMAND};-DPURE_REDUCE_TOOLCHAIN_FAKE_COMMAND=clang;-DPURE_REDUCE_TOOLCHAIN_FIXTURE_ROOT=${PURE_REDUCE_TOOLCHAIN_FIXTURE_ROOT};-P;${CMAKE_CURRENT_LIST_FILE};--")
    pure_reduce_capture_toolchain_provenance(
      "${_pacman_command}" "${_clang_command}"
      "${PURE_REDUCE_TOOLCHAIN_FIXTURE_ROOT}/vendored"
      "${PURE_REDUCE_TOOLCHAIN_PROBE_FILE}")
  elseif(PURE_REDUCE_TOOLCHAIN_PROBE_MODE STREQUAL "live")
    pure_reduce_capture_toolchain_provenance(
      "${PURE_REDUCE_TOOLCHAIN_LIVE_PACMAN}"
      "${PURE_REDUCE_TOOLCHAIN_LIVE_CLANG}"
      "${PURE_REDUCE_TOOLCHAIN_LIVE_LICENSES}"
      "${PURE_REDUCE_TOOLCHAIN_PROBE_FILE}")
    pure_reduce_validate_toolchain_provenance(
      "${PURE_REDUCE_TOOLCHAIN_PROBE_FILE}"
      "${PURE_REDUCE_TOOLCHAIN_LIVE_LICENSES}" _live_records)
    pure_reduce_toolchain_provenance_json("${_live_records}" _live_json)
    message(STATUS "live toolchain provenance: ${_live_json}")
  else()
    message(FATAL_ERROR "unknown provenance probe mode")
  endif()
  return()
endif()

string(SHA256 _fixture_key "${CMAKE_CURRENT_BINARY_DIR}")
file(TO_CMAKE_PATH
  "$ENV{TEMP}/pure reduce toolchain provenance-${_fixture_key}" _root)
file(REMOVE_RECURSE "${_root}")
file(MAKE_DIRECTORY
  "${_root}/prefix/lib/clang/99/lib/windows"
  "${_root}/prefix/share/licenses/zlib"
  "${_root}/prefix/share/licenses/ncurses"
  "${_root}/prefix/share/licenses/winpthreads"
  "${_root}/prefix/share/licenses/libc++"
  "${_root}/prefix/share/licenses/libunwind"
  "${_root}/prefix/share/licenses/compiler-rt"
  "${_root}/prefix/share/licenses/crt"
  "${_root}/vendored")

foreach(_input IN ITEMS
    libz.a libncurses.a libpthread.a libc++.a libunwind.a dllcrt2.o)
  file(WRITE "${_root}/prefix/lib/${_input}" "fixture ${_input}")
endforeach()
file(WRITE
  "${_root}/prefix/lib/clang/99/lib/windows/libclang_rt.builtins-x86_64.a"
  "fixture libclang_rt.builtins-x86_64.a")

set(_notice_records
  "share/licenses/zlib/LICENSE|ZLIB-LICENSE.txt"
  "share/licenses/ncurses/LICENSE|NCURSES-LICENSE.txt"
  "share/licenses/winpthreads/COPYING|WINPTHREADS-COPYING.txt"
  "share/licenses/libc++/LICENSE|LIBCXX-LICENSE.txt"
  "share/licenses/libunwind/LICENSE|LIBUNWIND-LICENSE.txt"
  "share/licenses/compiler-rt/LICENSE|COMPILER-RT-LICENSE.txt"
  "share/licenses/crt/COPYING|MINGW-W64-CRT-COPYING.txt"
  "share/licenses/crt/COPYING.MinGW-w64-runtime.txt|MINGW-W64-RUNTIME-COPYING.txt")
foreach(_record IN LISTS _notice_records)
  string(REPLACE "|" ";" _fields "${_record}")
  list(GET _fields 0 _system_notice)
  list(GET _fields 1 _vendored_notice)
  set(_payload "fixture license ${_vendored_notice}")
  file(WRITE "${_root}/prefix/${_system_notice}" "${_payload}")
  file(WRITE "${_root}/vendored/${_vendored_notice}" "${_payload}")
endforeach()

function(_fake_commands GENERATION OWNER_MISMATCH OUT_PACMAN OUT_CLANG)
  set(_pacman
    "${CMAKE_COMMAND};-DPURE_REDUCE_TOOLCHAIN_FAKE_COMMAND=pacman;-DPURE_REDUCE_TOOLCHAIN_FIXTURE_ROOT=${_root};-DPURE_REDUCE_TOOLCHAIN_GENERATION=${GENERATION};-DPURE_REDUCE_TOOLCHAIN_OWNER_MISMATCH=${OWNER_MISMATCH};-P;${CMAKE_CURRENT_LIST_FILE};--")
  set(_clang
    "${CMAKE_COMMAND};-DPURE_REDUCE_TOOLCHAIN_FAKE_COMMAND=clang;-DPURE_REDUCE_TOOLCHAIN_FIXTURE_ROOT=${_root};-P;${CMAKE_CURRENT_LIST_FILE};--")
  set(${OUT_PACMAN} "${_pacman}" PARENT_SCOPE)
  set(${OUT_CLANG} "${_clang}" PARENT_SCOPE)
endfunction()

function(_expect_rejection MODE FILE SECOND_FILE EXPECTED)
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_REDUCE_SOURCE_DIR=${PURE_REDUCE_SOURCE_DIR}"
      "-DPURE_REDUCE_TOOLCHAIN_PROBE_MODE=${MODE}"
      "-DPURE_REDUCE_TOOLCHAIN_PROBE_FILE=${FILE}"
      "-DPURE_REDUCE_TOOLCHAIN_PROBE_SECOND_FILE=${SECOND_FILE}"
      "-DPURE_REDUCE_TOOLCHAIN_FIXTURE_ROOT=${_root}"
      -P "${CMAKE_CURRENT_LIST_FILE}"
    RESULT_VARIABLE _result
    OUTPUT_VARIABLE _output
    ERROR_VARIABLE _error
    ENCODING UTF-8)
  if(_result EQUAL 0 OR NOT "${_output}\n${_error}" MATCHES "${EXPECTED}")
    message(FATAL_ERROR
      "expected provenance rejection '${EXPECTED}'\n"
      "stdout:\n${_output}\nstderr:\n${_error}")
  endif()
endfunction()

_fake_commands(old OFF _pacman _clang)
set(_snapshot "${_root}/toolchain-packages.tsv")
pure_reduce_capture_toolchain_provenance(
  "${_pacman}" "${_clang}" "${_root}/vendored" "${_snapshot}")

string(CONCAT _expected_snapshot
  "package\tversion\trole\tlink_input\tlink_input_sha256\towner\tsystem_notices\tsystem_notice_sha256s\tvendored_notices\tvendored_notice_sha256s\n"
  "mingw-w64-clang-x86_64-zlib\t9.0.0-1\tcompression\tlib/libz.a\t6b926f4aa0169e141bc505237b6a955250d47655a4edfed7b3ba737c24d730e0\tmingw-w64-clang-x86_64-zlib\tshare/licenses/zlib/LICENSE\tdf88c054e2fc640a243538894f3486381ae42e36d8bf07095ca298e293b29802\tZLIB-LICENSE.txt\tdf88c054e2fc640a243538894f3486381ae42e36d8bf07095ca298e293b29802\n"
  "mingw-w64-clang-x86_64-ncurses\t7.1-2\tterminal handling\tlib/libncurses.a\t3595badfa38150a9067944b11bf47c77452a6134e3a9a5797b5ec5b33cb904ac\tmingw-w64-clang-x86_64-ncurses\tshare/licenses/ncurses/LICENSE\t9f5798d75fb094679026085d938a529837b74e67310e4bbe7e9d2665edb0c1f5\tNCURSES-LICENSE.txt\t9f5798d75fb094679026085d938a529837b74e67310e4bbe7e9d2665edb0c1f5\n"
  "mingw-w64-clang-x86_64-winpthreads\tr999.gfuture-1\tPOSIX threads\tlib/libpthread.a\t859090f39bf638be13e38d672d2e294c1323dd04299444c925e35e58d0f0106f\tmingw-w64-clang-x86_64-winpthreads\tshare/licenses/winpthreads/COPYING\t03226a63836cc3750f71b184233e811eb5327665de34e658c796d248ce5f8e67\tWINPTHREADS-COPYING.txt\t03226a63836cc3750f71b184233e811eb5327665de34e658c796d248ce5f8e67\n"
  "mingw-w64-clang-x86_64-libc++\t99.1.0-1\tC++ standard library\tlib/libc++.a\t9e283aeb9392c019c2dd0147afbc43fd02672bac6443b91071c10da456e48d16\tmingw-w64-clang-x86_64-libc++\tshare/licenses/libc++/LICENSE\t29f7b7b8aa2517341e76f80e1c3bcafb97fd8f0bf92892a45b0a88fa47db61b9\tLIBCXX-LICENSE.txt\t29f7b7b8aa2517341e76f80e1c3bcafb97fd8f0bf92892a45b0a88fa47db61b9\n"
  "mingw-w64-clang-x86_64-libunwind\t99.1.0-2\tstack unwinding\tlib/libunwind.a\ta4f6b47e39797f767cf9720993a16b3bbeea5ab4253031099bcdf0f03cf9a174\tmingw-w64-clang-x86_64-libunwind\tshare/licenses/libunwind/LICENSE\t464c402bdcee79306458375d0034a0510feaaad6246ab18570f1c54f334716d0\tLIBUNWIND-LICENSE.txt\t464c402bdcee79306458375d0034a0510feaaad6246ab18570f1c54f334716d0\n"
  "mingw-w64-clang-x86_64-compiler-rt\t99.1.0-3\tcompiler runtime\tlib/clang/99/lib/windows/libclang_rt.builtins-x86_64.a\t9456fe2af93498e712802aac94b4ce136eefe8aba171f02455b6961f150e1bb1\tmingw-w64-clang-x86_64-compiler-rt\tshare/licenses/compiler-rt/LICENSE\tde0fa1f1bff072585dedb0ef7004dc1bb5fac2b71d403417d15bed397cc4e005\tCOMPILER-RT-LICENSE.txt\tde0fa1f1bff072585dedb0ef7004dc1bb5fac2b71d403417d15bed397cc4e005\n"
  "mingw-w64-clang-x86_64-crt\tr1000.gfuture-1\tC runtime startup\tlib/dllcrt2.o\teed985cc550ee321bf64fd7bd28299a13b1ab63d2aeb266802fea98394b5d8bf\tmingw-w64-clang-x86_64-crt\tshare/licenses/crt/COPYING,share/licenses/crt/COPYING.MinGW-w64-runtime.txt\t4355544c31250ad40ad5328aec99afb71c6ca9c9107cf5c6743b6a4fa55c29f9,dd0bd20e04ac5ef9045fdf2d8e879ec5bb188ed95a2dba4acce847955f51da71\tMINGW-W64-CRT-COPYING.txt,MINGW-W64-RUNTIME-COPYING.txt\t4355544c31250ad40ad5328aec99afb71c6ca9c9107cf5c6743b6a4fa55c29f9,dd0bd20e04ac5ef9045fdf2d8e879ec5bb188ed95a2dba4acce847955f51da71\n")
file(READ "${_snapshot}" _actual_snapshot)
if(NOT _actual_snapshot STREQUAL _expected_snapshot)
  message(FATAL_ERROR
    "captured rolling snapshot is not canonical\n"
    "expected:\n${_expected_snapshot}\nactual:\n${_actual_snapshot}")
endif()

pure_reduce_validate_toolchain_provenance(
  "${_snapshot}" "${_root}/vendored" _records)
list(LENGTH _records _record_count)
if(NOT _record_count EQUAL 7)
  message(FATAL_ERROR "canonical parse did not return exactly seven records")
endif()
list(GET _records 0 _first_record)
list(GET _records 6 _last_record)
if(NOT _first_record MATCHES "^mingw-w64-clang-x86_64-zlib\\|9\\.0\\.0-1\\|" OR
    NOT _last_record MATCHES "^mingw-w64-clang-x86_64-crt\\|r1000\\.gfuture-1\\|")
  message(FATAL_ERROR "parse did not preserve canonical record order")
endif()

pure_reduce_toolchain_provenance_tsv("${_records}" _tsv_content)
if(NOT _tsv_content STREQUAL _expected_snapshot)
  message(FATAL_ERROR "in-memory canonical TSV differs from file form")
endif()

string(CONCAT _expected_json
  "["
  "{\"package\":\"mingw-w64-clang-x86_64-zlib\",\"version\":\"9.0.0-1\",\"role\":\"compression\",\"link_input\":{\"path\":\"lib/libz.a\",\"sha256\":\"6b926f4aa0169e141bc505237b6a955250d47655a4edfed7b3ba737c24d730e0\",\"owner\":\"mingw-w64-clang-x86_64-zlib\"},\"notices\":[{\"system_path\":\"share/licenses/zlib/LICENSE\",\"vendored_path\":\"ZLIB-LICENSE.txt\",\"sha256\":\"df88c054e2fc640a243538894f3486381ae42e36d8bf07095ca298e293b29802\"}]},"
  "{\"package\":\"mingw-w64-clang-x86_64-ncurses\",\"version\":\"7.1-2\",\"role\":\"terminal handling\",\"link_input\":{\"path\":\"lib/libncurses.a\",\"sha256\":\"3595badfa38150a9067944b11bf47c77452a6134e3a9a5797b5ec5b33cb904ac\",\"owner\":\"mingw-w64-clang-x86_64-ncurses\"},\"notices\":[{\"system_path\":\"share/licenses/ncurses/LICENSE\",\"vendored_path\":\"NCURSES-LICENSE.txt\",\"sha256\":\"9f5798d75fb094679026085d938a529837b74e67310e4bbe7e9d2665edb0c1f5\"}]},"
  "{\"package\":\"mingw-w64-clang-x86_64-winpthreads\",\"version\":\"r999.gfuture-1\",\"role\":\"POSIX threads\",\"link_input\":{\"path\":\"lib/libpthread.a\",\"sha256\":\"859090f39bf638be13e38d672d2e294c1323dd04299444c925e35e58d0f0106f\",\"owner\":\"mingw-w64-clang-x86_64-winpthreads\"},\"notices\":[{\"system_path\":\"share/licenses/winpthreads/COPYING\",\"vendored_path\":\"WINPTHREADS-COPYING.txt\",\"sha256\":\"03226a63836cc3750f71b184233e811eb5327665de34e658c796d248ce5f8e67\"}]},"
  "{\"package\":\"mingw-w64-clang-x86_64-libc++\",\"version\":\"99.1.0-1\",\"role\":\"C++ standard library\",\"link_input\":{\"path\":\"lib/libc++.a\",\"sha256\":\"9e283aeb9392c019c2dd0147afbc43fd02672bac6443b91071c10da456e48d16\",\"owner\":\"mingw-w64-clang-x86_64-libc++\"},\"notices\":[{\"system_path\":\"share/licenses/libc++/LICENSE\",\"vendored_path\":\"LIBCXX-LICENSE.txt\",\"sha256\":\"29f7b7b8aa2517341e76f80e1c3bcafb97fd8f0bf92892a45b0a88fa47db61b9\"}]},"
  "{\"package\":\"mingw-w64-clang-x86_64-libunwind\",\"version\":\"99.1.0-2\",\"role\":\"stack unwinding\",\"link_input\":{\"path\":\"lib/libunwind.a\",\"sha256\":\"a4f6b47e39797f767cf9720993a16b3bbeea5ab4253031099bcdf0f03cf9a174\",\"owner\":\"mingw-w64-clang-x86_64-libunwind\"},\"notices\":[{\"system_path\":\"share/licenses/libunwind/LICENSE\",\"vendored_path\":\"LIBUNWIND-LICENSE.txt\",\"sha256\":\"464c402bdcee79306458375d0034a0510feaaad6246ab18570f1c54f334716d0\"}]},"
  "{\"package\":\"mingw-w64-clang-x86_64-compiler-rt\",\"version\":\"99.1.0-3\",\"role\":\"compiler runtime\",\"link_input\":{\"path\":\"lib/clang/99/lib/windows/libclang_rt.builtins-x86_64.a\",\"sha256\":\"9456fe2af93498e712802aac94b4ce136eefe8aba171f02455b6961f150e1bb1\",\"owner\":\"mingw-w64-clang-x86_64-compiler-rt\"},\"notices\":[{\"system_path\":\"share/licenses/compiler-rt/LICENSE\",\"vendored_path\":\"COMPILER-RT-LICENSE.txt\",\"sha256\":\"de0fa1f1bff072585dedb0ef7004dc1bb5fac2b71d403417d15bed397cc4e005\"}]},"
  "{\"package\":\"mingw-w64-clang-x86_64-crt\",\"version\":\"r1000.gfuture-1\",\"role\":\"C runtime startup\",\"link_input\":{\"path\":\"lib/dllcrt2.o\",\"sha256\":\"eed985cc550ee321bf64fd7bd28299a13b1ab63d2aeb266802fea98394b5d8bf\",\"owner\":\"mingw-w64-clang-x86_64-crt\"},\"notices\":[{\"system_path\":\"share/licenses/crt/COPYING\",\"vendored_path\":\"MINGW-W64-CRT-COPYING.txt\",\"sha256\":\"4355544c31250ad40ad5328aec99afb71c6ca9c9107cf5c6743b6a4fa55c29f9\"},{\"system_path\":\"share/licenses/crt/COPYING.MinGW-w64-runtime.txt\",\"vendored_path\":\"MINGW-W64-RUNTIME-COPYING.txt\",\"sha256\":\"dd0bd20e04ac5ef9045fdf2d8e879ec5bb188ed95a2dba4acce847955f51da71\"}]}"
  "]")
pure_reduce_toolchain_provenance_json("${_records}" _actual_json)
if(NOT _actual_json STREQUAL _expected_json)
  message(FATAL_ERROR
    "stable JSON projection changed\n"
    "expected: ${_expected_json}\nactual: ${_actual_json}")
endif()
pure_reduce_validate_toolchain_provenance_json(
  "${_actual_json}" "${_root}/vendored" _json_records)
if(NOT _json_records STREQUAL _records)
  message(FATAL_ERROR
    "canonical JSON validation did not reconstruct provenance records")
endif()
string(REPLACE "\"role\":\"compression\""
  "\"surprise\":\"x\",\"role\":\"compression\""
  _extra_member_json "${_actual_json}")
file(WRITE "${_root}/extra-member.json" "${_extra_member_json}")
_expect_rejection(json "${_root}/extra-member.json" "" "unexpected schema")

set(_roundtrip "${_root}/roundtrip.tsv")
pure_reduce_serialize_toolchain_provenance("${_records}" "${_roundtrip}")
file(READ "${_roundtrip}" _roundtrip_content)
if(NOT _roundtrip_content STREQUAL _expected_snapshot)
  message(FATAL_ERROR "parse/serialize round trip changed canonical bytes")
endif()
pure_reduce_compare_toolchain_provenance(
  "${_snapshot}" "${_roundtrip}" "${_root}/vendored")

function(_variant NAME OLD NEW OUT_FILE)
  string(REPLACE "${OLD}" "${NEW}" _content "${_expected_snapshot}")
  set(_path "${_root}/${NAME}.tsv")
  file(WRITE "${_path}" "${_content}")
  set(${OUT_FILE} "${_path}" PARENT_SCOPE)
endfunction()

string(REGEX REPLACE
  "mingw-w64-clang-x86_64-crt[^\n]*\n$" "" _missing_content
  "${_expected_snapshot}")
file(WRITE "${_root}/missing.tsv" "${_missing_content}")
_expect_rejection(validate "${_root}/missing.tsv" "" "missing package")

_variant(duplicate
  "mingw-w64-clang-x86_64-ncurses\t7.1-2"
  "mingw-w64-clang-x86_64-zlib\t7.1-2" _duplicate)
_expect_rejection(validate "${_duplicate}" "" "duplicate package")

_variant(unexpected
  "mingw-w64-clang-x86_64-zlib\t9.0.0-1"
  "mingw-w64-clang-x86_64-surprise\t9.0.0-1" _unexpected)
_expect_rejection(validate "${_unexpected}" "" "unexpected package")

_variant(malformed
  "6b926f4aa0169e141bc505237b6a955250d47655a4edfed7b3ba737c24d730e0"
  "NOT-A-SHA256" _malformed)
_expect_rejection(validate "${_malformed}" "" "malformed lowercase")

_variant(owner
  "mingw-w64-clang-x86_64-zlib\tshare/licenses/zlib"
  "mingw-w64-clang-x86_64-ncurses\tshare/licenses/zlib" _owner)
_expect_rejection(validate "${_owner}" "" "owner does not match package")

_fake_commands(new OFF _new_pacman _new_clang)
set(_new_snapshot "${_root}/new-toolchain-packages.tsv")
pure_reduce_capture_toolchain_provenance(
  "${_new_pacman}" "${_new_clang}" "${_root}/vendored" "${_new_snapshot}")
_expect_rejection(compare "${_snapshot}" "${_new_snapshot}"
  "cached/live toolchain provenance mismatch")

_expect_rejection(capture-owner "${_root}/owner-mismatch-capture.tsv" ""
  "owner query does not match package")

file(WRITE "${_root}/prefix/share/licenses/zlib/LICENSE"
  "tampered system notice with the same trusted filename\n")
_expect_rejection(capture-notice "${_root}/notice-mismatch-capture.tsv" ""
  "system/vendored notice mismatch")

file(REMOVE_RECURSE "${_root}")
message(STATUS "pure-reduce rolling toolchain provenance contract passed")
