include_guard(GLOBAL)

if(PURE_REDUCE_RUN_COMPONENT_INSTALL)
  foreach(_required IN ITEMS
      PURE_REDUCE_SOURCE_ROOT
      PURE_REDUCE_BINARY_ROOT
      PURE_REDUCE_UPSTREAM_BINARY_DIR
      PURE_REDUCE_DLL
      PURE_REDUCE_IMAGE
      PURE_REDUCE_LLVM_READOBJ
      PURE_REDUCE_CLANG64_ROOT
      PURE_REDUCE_INSTALL_PREFIX
      PURE_REDUCE_LIBRARY_INSTALL_DIR
      PURE_REDUCE_RUNTIME_INSTALL_DIR
      PURE_REDUCE_DOCUMENTATION_INSTALL_DIR)
    if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
      message(FATAL_ERROR "${_required} is required by PureReduce install")
    endif()
  endforeach()

  foreach(_destination_var IN ITEMS
      PURE_REDUCE_LIBRARY_INSTALL_DIR
      PURE_REDUCE_RUNTIME_INSTALL_DIR
      PURE_REDUCE_DOCUMENTATION_INSTALL_DIR)
    set(_destination "${${_destination_var}}")
    cmake_path(IS_ABSOLUTE _destination _absolute)
    string(REPLACE "\\" "/" _normalized_destination "${_destination}")
    string(REPLACE "/" ";" _segments "${_normalized_destination}")
    if(_absolute OR ".." IN_LIST _segments OR
        _normalized_destination STREQUAL "")
      message(FATAL_ERROR
        "${_destination_var} must remain within the install prefix: "
        "${_destination}")
    endif()
  endforeach()

  include("${CMAKE_CURRENT_LIST_DIR}/AuditWindowsDependencies.cmake")
  set(_search_dirs
    "${PURE_REDUCE_UPSTREAM_BINARY_DIR}"
    "${PURE_REDUCE_CLANG64_ROOT}/bin")
  pure_reduce_audit_pe("${PURE_REDUCE_DLL}" "${_search_dirs}" _pe_closure)

  file(REAL_PATH "${PURE_REDUCE_DLL}" _canonical_dll)
  set(_runtime_dlls "${_pe_closure}")
  list(REMOVE_ITEM _runtime_dlls "${_canonical_dll}")
  if(_runtime_dlls)
    message(FATAL_ERROR
      "the PE audit selected an unapproved redistributable runtime DLL; "
      "add an exact origin and license mapping before packaging: ${_runtime_dlls}")
  endif()

  set(_records)
  macro(_pure_reduce_install_record SOURCE RELATIVE PURPOSE ORIGIN LICENSE)
    set(_source "${SOURCE}")
    set(_relative "${RELATIVE}")
    if(NOT IS_ABSOLUTE "${_source}" OR NOT EXISTS "${_source}" OR
        IS_DIRECTORY "${_source}")
      message(FATAL_ERROR
        "PureReduce inventory source must be an existing absolute file: "
        "${_source}")
    endif()
    cmake_path(IS_ABSOLUTE _relative _relative_absolute)
    string(REPLACE "\\" "/" _relative "${_relative}")
    string(REPLACE "/" ";" _relative_segments "${_relative}")
    if(_relative_absolute OR ".." IN_LIST _relative_segments OR
        _relative STREQUAL "" OR _relative MATCHES "^[./\\\\]")
      message(FATAL_ERROR "unsafe PureReduce inventory path: ${_relative}")
    endif()
    string(TOLOWER "${_relative}" _relative_lower)
    if(_relative_lower MATCHES "\\.(a|lib|o|obj|exe)$" OR
        _relative_lower MATCHES
          "(^|/)(bash|sh|dash|zsh|fish|cmd|powershell|pwsh|make|ninja|pacman)(\\.exe)?$" OR
        _relative_lower MATCHES "(^|/)reduce\\.exe$")
      message(FATAL_ERROR "forbidden PureReduce payload: ${_relative}")
    endif()
    foreach(_field IN ITEMS "${PURPOSE}" "${ORIGIN}" "${LICENSE}")
      if(_field MATCHES "[|\t\r\n]")
        message(FATAL_ERROR "unsafe PureReduce inventory metadata: ${_field}")
      endif()
    endforeach()
    list(APPEND _records
      "${_relative}|${_source}|${PURPOSE}|${ORIGIN}|${LICENSE}")
  endmacro()

  set(_library "${PURE_REDUCE_LIBRARY_INSTALL_DIR}")
  set(_docs "${PURE_REDUCE_DOCUMENTATION_INSTALL_DIR}")
  set(_upstream_source "${PURE_REDUCE_UPSTREAM_BINARY_DIR}/source")
  set(_runtime_root
    "${PURE_REDUCE_UPSTREAM_BINARY_DIR}/artifacts/runtime")
  set(_metrics
    "${PURE_REDUCE_UPSTREAM_BINARY_DIR}/reduce-upstream-metrics.json")

  _pure_reduce_install_record(
    "${PURE_REDUCE_DLL}" "${_library}/reduce.dll"
    "Pure native module and embedded CSL runtime"
    "PureReduce bridge plus pinned REDUCE CSL closure"
    "${_docs}/licenses/REDUCE-LICENSE.txt and ${_docs}/COPYING")
  _pure_reduce_install_record(
    "${PURE_REDUCE_IMAGE}" "${_library}/reduce.img"
    "CSL heap image"
    "REDUCE commit 7efba90661139ae9c73c99fddd55f3fb2fabf69a"
    "${_docs}/licenses/REDUCE-LICENSE.txt")
  _pure_reduce_install_record(
    "${PURE_REDUCE_SOURCE_ROOT}/reduce.pure" "${_library}/reduce.pure"
    "Public Pure module"
    "pure-reduce source package"
    "${_docs}/COPYING")

  foreach(_runtime_name IN ITEMS reduce.resources reduce.fonts)
    set(_runtime_directory "${_runtime_root}/${_runtime_name}")
    if(NOT IS_DIRECTORY "${_runtime_directory}")
      message(FATAL_ERROR "missing CSL runtime directory: ${_runtime_directory}")
    endif()
    file(GLOB_RECURSE _runtime_files LIST_DIRECTORIES FALSE
      "${_runtime_directory}/*")
    list(SORT _runtime_files COMPARE NATURAL CASE INSENSITIVE)
    foreach(_runtime_file IN LISTS _runtime_files)
      file(RELATIVE_PATH _runtime_relative
        "${_runtime_directory}" "${_runtime_file}")
      string(REPLACE "\\" "/" _runtime_relative "${_runtime_relative}")
      if(_runtime_name STREQUAL "reduce.resources")
        set(_runtime_purpose "CSL runtime resource")
        set(_runtime_license "${_docs}/licenses/REDUCE-LICENSE.txt")
      elseif(_runtime_relative MATCHES "^DejaVu")
        set(_runtime_purpose "DejaVu font or license")
        set(_runtime_license "${_library}/reduce.fonts/DejaVuLICENSE")
      elseif(_runtime_relative MATCHES "^cmuntt\\.")
        set(_runtime_purpose "CM Unicode font")
        set(_runtime_license "${_docs}/licenses/CM-UNICODE-LICENSE.txt")
      else()
        set(_runtime_purpose "Computer Modern font data or notice")
        set(_runtime_license
          "${_library}/reduce.fonts/README.BaKoMa and ${_library}/reduce.fonts/README.cmps-fonts")
      endif()
      _pure_reduce_install_record(
        "${_runtime_file}"
        "${_library}/${_runtime_name}/${_runtime_relative}"
        "${_runtime_purpose}"
        "pinned REDUCE CSL runtime artifact ${_runtime_name}/${_runtime_relative}"
        "${_runtime_license}")
    endforeach()
    _pure_reduce_install_record(
      "${_runtime_root}/${_runtime_name}.manifest"
      "${_docs}/runtime/${_runtime_name}.manifest"
      "Upstream runtime artifact hash and size manifest"
      "generated from pinned REDUCE CSL runtime artifacts"
      "${_docs}/licenses/REDUCE-LICENSE.txt")
  endforeach()

  foreach(_documentation IN ITEMS README COPYING THIRD_PARTY.md)
    _pure_reduce_install_record(
      "${PURE_REDUCE_SOURCE_ROOT}/${_documentation}"
      "${_docs}/${_documentation}"
      "PureReduce documentation"
      "pure-reduce source package"
      "${_docs}/COPYING")
  endforeach()
  _pure_reduce_install_record(
    "${_metrics}" "${_docs}/reduce-upstream-metrics.json"
    "Pinned source build metrics and patch provenance"
    "verified PureReduce upstream build"
    "${_docs}/licenses/REDUCE-LICENSE.txt")

  file(GLOB _test_files LIST_DIRECTORIES FALSE
    "${PURE_REDUCE_SOURCE_ROOT}/tests/*.pure")
  list(SORT _test_files COMPARE NATURAL CASE INSENSITIVE)
  foreach(_test_file IN LISTS _test_files)
    cmake_path(GET _test_file FILENAME _test_name)
    _pure_reduce_install_record(
      "${_test_file}" "${_docs}/tests/${_test_name}"
      "Installed functional test"
      "pure-reduce source package"
      "${_docs}/COPYING")
  endforeach()

  foreach(_patch_name IN ITEMS
      0001-csl-winsupport-define-nil.patch
      0002-csl-windows-utf8-image-open.patch)
    _pure_reduce_install_record(
      "${PURE_REDUCE_SOURCE_ROOT}/patches/${_patch_name}"
      "${_docs}/patches/${_patch_name}"
      "Checksum-covered private-source correction"
      "PureReduce patch for pinned REDUCE source"
      "${_docs}/COPYING")
  endforeach()

  set(_license_mappings
    "${PURE_REDUCE_SOURCE_ROOT}/licenses/REDUCE-LICENSE.txt|REDUCE-LICENSE.txt|canonical REDUCE license"
    "${_upstream_source}/csl/cslbase/COPYING|CSL-COPYING.txt|detailed CSL notices"
    "${_upstream_source}/libraries/crlibm/COPYING|CRLIBM-COPYING.txt|crlibm GPL notice"
    "${_upstream_source}/libraries/crlibm/COPYING.LIB|CRLIBM-COPYING.LIB.txt|crlibm LGPL notice"
    "${_upstream_source}/libraries/libffi/LICENSE|LIBFFI-LICENSE.txt|libffi license"
    "${_upstream_source}/csl/cslbase/cm-unicode/LICENSE|CM-UNICODE-LICENSE.txt|CM Unicode font license"
    "${PURE_REDUCE_CLANG64_ROOT}/share/licenses/zlib/LICENSE|ZLIB-LICENSE.txt|MSYS2 CLANG64 zlib license"
    "${PURE_REDUCE_CLANG64_ROOT}/share/licenses/ncurses/LICENSE|NCURSES-LICENSE.txt|MSYS2 CLANG64 ncurses license"
    "${PURE_REDUCE_CLANG64_ROOT}/share/licenses/libwinpthread/COPYING|WINPTHREADS-COPYING.txt|MSYS2 CLANG64 winpthreads license"
    "${PURE_REDUCE_CLANG64_ROOT}/share/licenses/libc++/LICENSE|LIBCXX-LICENSE.txt|MSYS2 CLANG64 libc++ license"
    "${PURE_REDUCE_CLANG64_ROOT}/share/licenses/libunwind/LICENSE|LIBUNWIND-LICENSE.txt|MSYS2 CLANG64 libunwind license"
    "${PURE_REDUCE_CLANG64_ROOT}/share/licenses/compiler-rt/LICENSE|COMPILER-RT-LICENSE.txt|MSYS2 CLANG64 compiler-rt license"
    "${PURE_REDUCE_CLANG64_ROOT}/share/licenses/crt/COPYING|MINGW-W64-CRT-COPYING.txt|MSYS2 CLANG64 CRT aggregate notice"
    "${PURE_REDUCE_CLANG64_ROOT}/share/licenses/crt/COPYING.MinGW-w64-runtime.txt|MINGW-W64-RUNTIME-COPYING.txt|MinGW-w64 runtime notice")
  foreach(_mapping IN LISTS _license_mappings)
    string(REPLACE "|" ";" _fields "${_mapping}")
    list(GET _fields 0 _license_source)
    list(GET _fields 1 _license_name)
    list(GET _fields 2 _license_origin)
    _pure_reduce_install_record(
      "${_license_source}" "${_docs}/licenses/${_license_name}"
      "Third-party license notice"
      "${_license_origin}"
      "self")
  endforeach()

  list(SORT _records COMPARE NATURAL CASE INSENSITIVE)
  set(_manifest "${PURE_REDUCE_BINARY_ROOT}/PureReduceExpected.sha256")
  set(_inventory "${PURE_REDUCE_BINARY_ROOT}/PureReduceInventory.tsv")
  file(WRITE "${_manifest}" "")
  file(WRITE "${_inventory}"
    "relative_path\tpurpose\torigin\tsha256\tbytes\tlicense\n")
  set(_seen_relative_lower)
  foreach(_record IN LISTS _records)
    string(REPLACE "|" ";" _fields "${_record}")
    list(GET _fields 0 _relative)
    list(GET _fields 1 _source)
    list(GET _fields 2 _purpose)
    list(GET _fields 3 _origin)
    list(GET _fields 4 _license)
    string(TOLOWER "${_relative}" _relative_lower)
    if(_relative_lower IN_LIST _seen_relative_lower)
      message(FATAL_ERROR "duplicate PureReduce install path: ${_relative}")
    endif()
    list(APPEND _seen_relative_lower "${_relative_lower}")
    file(SHA256 "${_source}" _sha256)
    string(TOLOWER "${_sha256}" _sha256)
    file(SIZE "${_source}" _bytes)
    file(APPEND "${_manifest}" "${_sha256}  ${_relative}\n")
    file(APPEND "${_inventory}"
      "${_relative}\t${_purpose}\t${_origin}\t${_sha256}\t${_bytes}\t${_license}\n")
  endforeach()

  set(_install_root "$ENV{DESTDIR}${PURE_REDUCE_INSTALL_PREFIX}")
  foreach(_record IN LISTS _records)
    string(REPLACE "|" ";" _fields "${_record}")
    list(GET _fields 0 _relative)
    list(GET _fields 1 _source)
    cmake_path(GET _relative PARENT_PATH _relative_parent)
    set(_destination_directory "${_install_root}/${_relative_parent}")
    file(MAKE_DIRECTORY "${_destination_directory}")
    file(COPY_FILE "${_source}" "${_install_root}/${_relative}")
    file(SHA256 "${_install_root}/${_relative}" _installed_sha256)
    file(SHA256 "${_source}" _source_sha256)
    if(NOT _installed_sha256 STREQUAL _source_sha256)
      message(FATAL_ERROR "installed file hash changed: ${_relative}")
    endif()
  endforeach()
  message(STATUS
    "Installed audited PureReduce component using ${_manifest}")
  return()
endif()

set(PURE_REDUCE_LIBRARY_INSTALL_DIR "lib/pure" CACHE STRING
  "Relative install directory for the PureReduce module")
set(PURE_REDUCE_RUNTIME_INSTALL_DIR "bin" CACHE STRING
  "Relative install directory for audited PureReduce runtime DLLs")
set(PURE_REDUCE_DOCUMENTATION_INSTALL_DIR "share/doc/pure-reduce" CACHE STRING
  "Relative install directory for PureReduce documentation")

foreach(_destination_var IN ITEMS
    PURE_REDUCE_LIBRARY_INSTALL_DIR
    PURE_REDUCE_RUNTIME_INSTALL_DIR
    PURE_REDUCE_DOCUMENTATION_INSTALL_DIR)
  set(_destination "${${_destination_var}}")
  cmake_path(IS_ABSOLUTE _destination _absolute)
  string(REPLACE "\\" "/" _normalized_destination "${_destination}")
  string(REPLACE "/" ";" _segments "${_normalized_destination}")
  if(_absolute OR ".." IN_LIST _segments OR
      _normalized_destination STREQUAL "")
    message(FATAL_ERROR
      "${_destination_var} must remain within the install prefix: "
      "${_destination}")
  endif()
endforeach()

if(TARGET reduce)
  if(NOT DEFINED PURE_REDUCE_LLVM_READOBJ OR
      NOT IS_ABSOLUTE "${PURE_REDUCE_LLVM_READOBJ}" OR
      NOT EXISTS "${PURE_REDUCE_LLVM_READOBJ}")
    message(FATAL_ERROR
      "PURE_REDUCE_LLVM_READOBJ must be an existing absolute executable")
  endif()
  cmake_path(GET PURE_REDUCE_LLVM_READOBJ PARENT_PATH _clang64_bin)
  cmake_path(GET _clang64_bin PARENT_PATH _clang64_root)
  set(_component_code [=[
execute_process(
  COMMAND "@CMAKE_COMMAND@"
    -DPURE_REDUCE_RUN_COMPONENT_INSTALL=ON
    "-DPURE_REDUCE_SOURCE_ROOT=@CMAKE_CURRENT_SOURCE_DIR@"
    "-DPURE_REDUCE_BINARY_ROOT=@CMAKE_CURRENT_BINARY_DIR@"
    "-DPURE_REDUCE_UPSTREAM_BINARY_DIR=@PURE_REDUCE_UPSTREAM_BINARY_DIR@"
    "-DPURE_REDUCE_DLL=$<TARGET_FILE:reduce>"
    "-DPURE_REDUCE_IMAGE=@PURE_REDUCE_CSL_IMAGE@"
    "-DPURE_REDUCE_LLVM_READOBJ=@PURE_REDUCE_LLVM_READOBJ@"
    "-DPURE_REDUCE_CLANG64_ROOT=@_clang64_root@"
    "-DPURE_REDUCE_INSTALL_PREFIX=${CMAKE_INSTALL_PREFIX}"
    "-DPURE_REDUCE_LIBRARY_INSTALL_DIR=@PURE_REDUCE_LIBRARY_INSTALL_DIR@"
    "-DPURE_REDUCE_RUNTIME_INSTALL_DIR=@PURE_REDUCE_RUNTIME_INSTALL_DIR@"
    "-DPURE_REDUCE_DOCUMENTATION_INSTALL_DIR=@PURE_REDUCE_DOCUMENTATION_INSTALL_DIR@"
    -P "@CMAKE_CURRENT_LIST_FILE@"
  RESULT_VARIABLE _pure_reduce_install_result
  OUTPUT_VARIABLE _pure_reduce_install_output
  ERROR_VARIABLE _pure_reduce_install_error
  ENCODING UTF-8)
if(NOT _pure_reduce_install_result EQUAL 0)
  message(FATAL_ERROR
    "PureReduce component install failed (${_pure_reduce_install_result})\n"
    "stdout:\n${_pure_reduce_install_output}\n"
    "stderr:\n${_pure_reduce_install_error}")
endif()
message("${_pure_reduce_install_output}")
]=])
  string(CONFIGURE "${_component_code}" _component_code @ONLY)
  install(CODE "${_component_code}"
    COMPONENT PureReduce EXCLUDE_FROM_ALL)
else()
  install(CODE "" COMPONENT PureReduce EXCLUDE_FROM_ALL)
endif()
