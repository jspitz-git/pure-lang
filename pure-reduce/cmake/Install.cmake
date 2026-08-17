include_guard(GLOBAL)

function(_pure_reduce_reject_serialization_delimiters VALUE LABEL)
  if("${VALUE}" MATCHES "[;|\t\r\n]")
    message(FATAL_ERROR
      "${LABEL} contains a forbidden serialization delimiter")
  endif()
endfunction()

function(_pure_reduce_validate_relative_path VALUE LABEL)
  _pure_reduce_reject_serialization_delimiters("${VALUE}" "${LABEL}")
  set(_path "${VALUE}")
  cmake_path(IS_ABSOLUTE _path _absolute)
  string(REPLACE "\\" "/" _path "${_path}")
  string(REPLACE "/" ";" _segments "${_path}")
  if(_absolute OR ".." IN_LIST _segments OR _path STREQUAL "" OR
      _path MATCHES "^[./\\\\]")
    message(FATAL_ERROR "unsafe ${LABEL}: ${VALUE}")
  endif()
endfunction()

function(_pure_reduce_validate_source_file VALUE LABEL)
  _pure_reduce_reject_serialization_delimiters("${VALUE}" "${LABEL}")
  string(REPLACE "\\" "/" _path "${VALUE}")
  string(REPLACE "/" ";" _segments "${_path}")
  if(NOT IS_ABSOLUTE "${VALUE}" OR ".." IN_LIST _segments OR
      NOT EXISTS "${VALUE}" OR IS_DIRECTORY "${VALUE}")
    message(FATAL_ERROR
      "${LABEL} must be an existing canonical absolute file: ${VALUE}")
  endif()
endfunction()

function(pure_reduce_verify_runtime_manifest DIRECTORY MANIFEST OUT_FILES)
  _pure_reduce_validate_source_file("${MANIFEST}" "runtime manifest")
  if(NOT IS_ABSOLUTE "${DIRECTORY}" OR NOT IS_DIRECTORY "${DIRECTORY}")
    message(FATAL_ERROR "runtime directory is missing: ${DIRECTORY}")
  endif()
  file(READ "${MANIFEST}" _manifest_text)
  if(_manifest_text MATCHES "[;|\t\r]")
    message(FATAL_ERROR "runtime manifest contains unsafe delimiters")
  endif()
  file(STRINGS "${MANIFEST}" _manifest_lines)
  set(_expected_relative)
  set(_verified_files)
  foreach(_line IN LISTS _manifest_lines)
    if(NOT _line MATCHES "^([0-9A-Fa-f]+) ([0-9]+) (.+)$")
      message(FATAL_ERROR "malformed runtime manifest line: ${_line}")
    endif()
    set(_expected_sha "${CMAKE_MATCH_1}")
    set(_expected_bytes "${CMAKE_MATCH_2}")
    set(_relative "${CMAKE_MATCH_3}")
    string(LENGTH "${_expected_sha}" _sha_length)
    if(NOT _sha_length EQUAL 64)
      message(FATAL_ERROR "malformed runtime manifest SHA-256: ${_line}")
    endif()
    _pure_reduce_validate_relative_path(
      "${_relative}" "runtime manifest relative path")
    if(_relative IN_LIST _expected_relative)
      message(FATAL_ERROR "duplicate runtime manifest path: ${_relative}")
    endif()
    set(_file "${DIRECTORY}/${_relative}")
    _pure_reduce_validate_source_file("${_file}" "runtime manifest file")
    file(SHA256 "${_file}" _actual_sha)
    file(SIZE "${_file}" _actual_bytes)
    string(TOLOWER "${_expected_sha}" _expected_sha)
    string(TOLOWER "${_actual_sha}" _actual_sha)
    if(NOT _actual_sha STREQUAL _expected_sha OR
        NOT _actual_bytes EQUAL _expected_bytes)
      message(FATAL_ERROR
        "runtime manifest hash/size mismatch for ${_relative}")
    endif()
    list(APPEND _expected_relative "${_relative}")
    list(APPEND _verified_files "${_file}")
  endforeach()
  file(GLOB_RECURSE _actual_files LIST_DIRECTORIES FALSE "${DIRECTORY}/*")
  set(_actual_relative)
  foreach(_file IN LISTS _actual_files)
    if(NOT IS_ABSOLUTE "${_file}" OR NOT EXISTS "${_file}")
      message(FATAL_ERROR
        "runtime directory contains a forbidden serialization delimiter or "
        "unrepresentable path")
    endif()
    file(RELATIVE_PATH _relative "${DIRECTORY}" "${_file}")
    string(REPLACE "\\" "/" _relative "${_relative}")
    _pure_reduce_validate_relative_path(
      "${_relative}" "runtime directory relative path")
    list(APPEND _actual_relative "${_relative}")
  endforeach()
  list(SORT _expected_relative COMPARE NATURAL CASE INSENSITIVE)
  list(SORT _actual_relative COMPARE NATURAL CASE INSENSITIVE)
  if(NOT _actual_relative STREQUAL _expected_relative)
    message(FATAL_ERROR
      "runtime manifest content mismatch\n"
      "manifest: ${_expected_relative}\nactual: ${_actual_relative}")
  endif()
  list(SORT _verified_files COMPARE NATURAL CASE INSENSITIVE)
  set(${OUT_FILES} "${_verified_files}" PARENT_SCOPE)
endfunction()

function(pure_reduce_register_runtime_dll)
  cmake_parse_arguments(_mapping ""
    "NAME;ORIGIN;VERSION;LICENSE_SOURCE;LICENSE_DESTINATION" "" ${ARGN})
  if(_mapping_UNPARSED_ARGUMENTS OR _mapping_KEYWORDS_MISSING_VALUES)
    message(FATAL_ERROR "malformed runtime DLL mapping")
  endif()
  foreach(_field IN ITEMS NAME ORIGIN VERSION LICENSE_SOURCE LICENSE_DESTINATION)
    if("${_mapping_${_field}}" STREQUAL "")
      message(FATAL_ERROR "runtime DLL mapping omits ${_field}")
    endif()
    _pure_reduce_reject_serialization_delimiters(
      "${_mapping_${_field}}" "runtime DLL mapping ${_field}")
  endforeach()
  string(TOLOWER "${_mapping_NAME}" _name)
  if(NOT _name MATCHES "^[^/\\\\]+\\.dll$")
    message(FATAL_ERROR "unsafe runtime DLL mapping name: ${_mapping_NAME}")
  endif()
  _pure_reduce_validate_source_file(
    "${_mapping_LICENSE_SOURCE}" "runtime DLL license source")
  _pure_reduce_validate_relative_path(
    "${_mapping_LICENSE_DESTINATION}" "runtime DLL license destination")
  string(SHA256 _key "${_name}")
  get_property(_already_set GLOBAL PROPERTY
    "PURE_REDUCE_RUNTIME_DLL_${_key}_NAME" SET)
  if(_already_set)
    message(FATAL_ERROR "duplicate runtime DLL mapping: ${_mapping_NAME}")
  endif()
  foreach(_field IN ITEMS NAME ORIGIN VERSION LICENSE_SOURCE LICENSE_DESTINATION)
    set_property(GLOBAL PROPERTY "PURE_REDUCE_RUNTIME_DLL_${_key}_${_field}"
      "${_mapping_${_field}}")
  endforeach()
endfunction()

function(_pure_reduce_lookup_runtime_dll DLL OUT_ORIGIN OUT_VERSION
    OUT_LICENSE_SOURCE OUT_LICENSE_DESTINATION)
  cmake_path(GET DLL FILENAME _name)
  string(TOLOWER "${_name}" _name)
  string(SHA256 _key "${_name}")
  get_property(_mapped GLOBAL PROPERTY
    "PURE_REDUCE_RUNTIME_DLL_${_key}_NAME" SET)
  if(NOT _mapped)
    message(FATAL_ERROR
      "non-system runtime DLL has no explicit origin/version/license mapping: "
      "${_name}")
  endif()
  get_property(_origin GLOBAL PROPERTY
    "PURE_REDUCE_RUNTIME_DLL_${_key}_ORIGIN")
  get_property(_version GLOBAL PROPERTY
    "PURE_REDUCE_RUNTIME_DLL_${_key}_VERSION")
  get_property(_license_source GLOBAL PROPERTY
    "PURE_REDUCE_RUNTIME_DLL_${_key}_LICENSE_SOURCE")
  get_property(_license_destination GLOBAL PROPERTY
    "PURE_REDUCE_RUNTIME_DLL_${_key}_LICENSE_DESTINATION")
  set(${OUT_ORIGIN} "${_origin}" PARENT_SCOPE)
  set(${OUT_VERSION} "${_version}" PARENT_SCOPE)
  set(${OUT_LICENSE_SOURCE} "${_license_source}" PARENT_SCOPE)
  set(${OUT_LICENSE_DESTINATION} "${_license_destination}" PARENT_SCOPE)
endfunction()

function(pure_reduce_verify_vendored_toolchain_licenses SOURCE_ROOT)
  set(_expected
    "ZLIB-LICENSE.txt=e32ff4e00d9d94930537635291da39e7e612703334bf6fde8c7f1686fe8a45a2"
    "NCURSES-LICENSE.txt=708999f95527e1ffa670c6fce288c6c600cb477dd04afcc1171422b3dd4ee226"
    "WINPTHREADS-COPYING.txt=63263614cdd29f2f93cba85e992f041b31f9fc7b4033692f31269489a8a1b177"
    "LIBCXX-LICENSE.txt=539dd7aed86e8a4f12cbdd0e6c50c189c7d74847e4fecc64ce2c6ee3a01da38b"
    "LIBUNWIND-LICENSE.txt=b5efebcaca80879234098e52d1725e6d9eb8fb96a19fce625d39184b705f7b6d"
    "COMPILER-RT-LICENSE.txt=1a8f1058753f1ba890de984e48f0242a3a5c29a6a8f2ed9fd813f36985387e8d"
    "MINGW-W64-CRT-COPYING.txt=99a69660981156c21336fdb5661f89341b013c94e4bf9e1c7467b4745718397f"
    "MINGW-W64-RUNTIME-COPYING.txt=1db8da07b436c68833c0673ffee3d9fcb2526047f3820b81661865dfedc79a1f")
  foreach(_entry IN LISTS _expected)
    string(REPLACE "=" ";" _fields "${_entry}")
    list(GET _fields 0 _name)
    list(GET _fields 1 _sha)
    set(_file "${SOURCE_ROOT}/licenses/${_name}")
    _pure_reduce_validate_source_file("${_file}" "vendored license")
    file(SHA256 "${_file}" _actual)
    string(TOLOWER "${_actual}" _actual)
    if(NOT _actual STREQUAL _sha)
      message(FATAL_ERROR "vendored toolchain license hash mismatch: ${_name}")
    endif()
  endforeach()
endfunction()

if(PURE_REDUCE_VERIFY_VENDORED_LICENSES)
  if(NOT DEFINED PURE_REDUCE_SOURCE_ROOT OR
      "${PURE_REDUCE_SOURCE_ROOT}" STREQUAL "")
    message(FATAL_ERROR "PURE_REDUCE_SOURCE_ROOT is required")
  endif()
  pure_reduce_verify_vendored_toolchain_licenses(
    "${PURE_REDUCE_SOURCE_ROOT}")
  message(STATUS "verified pinned CLANG64 license notice hashes")
  return()
endif()

if(PURE_REDUCE_INSTALL_CONTRACT_ONLY)
  return()
endif()

if(PURE_REDUCE_RUN_COMPONENT_INSTALL)
  foreach(_required IN ITEMS
      PURE_REDUCE_SOURCE_ROOT
      PURE_REDUCE_BINARY_ROOT
      PURE_REDUCE_UPSTREAM_BINARY_DIR
      PURE_REDUCE_DLL
      PURE_REDUCE_IMAGE
      PURE_REDUCE_LLVM_READOBJ
      PURE_REDUCE_CLANG64_ROOT
      PURE_REDUCE_RUNTIME_DLL_MAPPING_FILE
      PURE_REDUCE_INSTALL_PREFIX
      PURE_REDUCE_LIBRARY_INSTALL_DIR
      PURE_REDUCE_RUNTIME_INSTALL_DIR
      PURE_REDUCE_DOCUMENTATION_INSTALL_DIR)
    if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
      message(FATAL_ERROR "${_required} is required by PureReduce install")
    endif()
  endforeach()

  pure_reduce_verify_vendored_toolchain_licenses(
    "${PURE_REDUCE_SOURCE_ROOT}")
  _pure_reduce_validate_source_file(
    "${PURE_REDUCE_RUNTIME_DLL_MAPPING_FILE}" "runtime DLL mapping file")
  include("${PURE_REDUCE_RUNTIME_DLL_MAPPING_FILE}")

  foreach(_destination_var IN ITEMS
      PURE_REDUCE_LIBRARY_INSTALL_DIR
      PURE_REDUCE_RUNTIME_INSTALL_DIR
      PURE_REDUCE_DOCUMENTATION_INSTALL_DIR)
    _pure_reduce_validate_relative_path(
      "${${_destination_var}}" "${_destination_var}")
  endforeach()

  include("${CMAKE_CURRENT_LIST_DIR}/AuditWindowsDependencies.cmake")
  set(_search_dirs
    "${PURE_REDUCE_UPSTREAM_BINARY_DIR}"
    "${PURE_REDUCE_CLANG64_ROOT}/bin")
  pure_reduce_audit_pe("${PURE_REDUCE_DLL}" "${_search_dirs}" _pe_closure)

  file(REAL_PATH "${PURE_REDUCE_DLL}" _canonical_dll)
  set(_runtime_dlls "${_pe_closure}")
  list(REMOVE_ITEM _runtime_dlls "${_canonical_dll}")

  set(_records)
  macro(_pure_reduce_install_record SOURCE RELATIVE PURPOSE ORIGIN LICENSE)
    set(_source "${SOURCE}")
    set(_relative "${RELATIVE}")
    _pure_reduce_validate_source_file(
      "${_source}" "PureReduce inventory source")
    _pure_reduce_validate_relative_path(
      "${_relative}" "PureReduce inventory path")
    string(TOLOWER "${_relative}" _relative_lower)
    if(_relative_lower MATCHES "\\.(a|lib|o|obj|exe)$" OR
        _relative_lower MATCHES
          "(^|/)(bash|sh|dash|zsh|fish|cmd|powershell|pwsh|make|ninja|pacman)(\\.exe)?$" OR
        _relative_lower MATCHES "(^|/)reduce\\.exe$")
      message(FATAL_ERROR "forbidden PureReduce payload: ${_relative}")
    endif()
    foreach(_field IN ITEMS "${PURPOSE}" "${ORIGIN}" "${LICENSE}")
      _pure_reduce_reject_serialization_delimiters(
        "${_field}" "PureReduce inventory metadata")
    endforeach()
    list(APPEND _records
      "${_relative}|${_source}|${PURPOSE}|${ORIGIN}|${LICENSE}")
  endmacro()

  set(_library "${PURE_REDUCE_LIBRARY_INSTALL_DIR}")
  set(_docs "${PURE_REDUCE_DOCUMENTATION_INSTALL_DIR}")
  set(_upstream_install_inputs
    "${PURE_REDUCE_UPSTREAM_BINARY_DIR}/artifacts/install-inputs")
  set(_runtime_root
    "${PURE_REDUCE_UPSTREAM_BINARY_DIR}/artifacts/runtime")
  set(_metrics
    "${PURE_REDUCE_UPSTREAM_BINARY_DIR}/reduce-upstream-metrics.json")

  _pure_reduce_install_record(
    "${PURE_REDUCE_DLL}" "${_library}/reduce.dll"
    "Pure native module and embedded CSL runtime"
    "PureReduce bridge plus pinned REDUCE CSL closure"
    "${_docs}/COPYING and ${_docs}/licenses/REDUCE-LICENSE.txt and ${_docs}/licenses/CRLIBM-COPYING.LIB.txt and ${_docs}/licenses/LIBFFI-LICENSE.txt and ${_docs}/licenses/ZLIB-LICENSE.txt and ${_docs}/licenses/NCURSES-LICENSE.txt and ${_docs}/licenses/WINPTHREADS-COPYING.txt and ${_docs}/licenses/LIBCXX-LICENSE.txt and ${_docs}/licenses/LIBUNWIND-LICENSE.txt and ${_docs}/licenses/COMPILER-RT-LICENSE.txt and ${_docs}/licenses/MINGW-W64-CRT-COPYING.txt and ${_docs}/licenses/MINGW-W64-RUNTIME-COPYING.txt")
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

  set(_runtime_resource_count 0)
  set(_runtime_font_count 0)
  set(_excluded_font_sources
    src/cmex10.asm.gz
    src/cmmi10.asm.gz
    src/cmr10.asm.gz
    src/cmsy10.asm.gz)
  foreach(_runtime_name IN ITEMS reduce.resources reduce.fonts)
    set(_runtime_directory "${_runtime_root}/${_runtime_name}")
    set(_runtime_manifest "${_runtime_root}/${_runtime_name}.manifest")
    pure_reduce_verify_runtime_manifest(
      "${_runtime_directory}" "${_runtime_manifest}" _runtime_files)
    foreach(_runtime_file IN LISTS _runtime_files)
      file(RELATIVE_PATH _runtime_relative
        "${_runtime_directory}" "${_runtime_file}")
      string(REPLACE "\\" "/" _runtime_relative "${_runtime_relative}")
      if(_runtime_name STREQUAL "reduce.resources")
        if(NOT _runtime_relative STREQUAL "mma.awk" AND
            NOT _runtime_relative STREQUAL "qepcad.awk")
          message(FATAL_ERROR
            "unreviewed CSL runtime resource: ${_runtime_relative}")
        endif()
        math(EXPR _runtime_resource_count "${_runtime_resource_count} + 1")
        set(_runtime_purpose "CSL runtime resource")
        set(_runtime_license "${_docs}/licenses/REDUCE-LICENSE.txt")
      elseif(_runtime_relative IN_LIST _excluded_font_sources)
        continue()
      elseif(_runtime_relative MATCHES
          "(^|/)(README|README\\.BaKoMa|README\\.cmps-fonts|DejaVuLICENSE|fonts\\.dir|fonts\\.scale)$" OR
          _runtime_relative MATCHES "\\.(ttf|pfb|pfa|pfm)$")
        math(EXPR _runtime_font_count "${_runtime_font_count} + 1")
        if(_runtime_relative MATCHES "^DejaVu")
          set(_runtime_purpose "DejaVu font or license")
          set(_runtime_license "${_library}/reduce.fonts/DejaVuLICENSE")
        elseif(_runtime_relative MATCHES "^cmuntt\\.")
          set(_runtime_purpose "CM Unicode font")
          set(_runtime_license "${_docs}/licenses/CM-UNICODE-LICENSE.txt")
        else()
          set(_runtime_purpose "Computer Modern runtime font data or notice")
          set(_runtime_license
            "${_library}/reduce.fonts/README.BaKoMa and ${_library}/reduce.fonts/README.cmps-fonts")
        endif()
      else()
        message(FATAL_ERROR
          "unreviewed CSL runtime font payload: ${_runtime_relative}")
      endif()
      _pure_reduce_install_record(
        "${_runtime_file}"
        "${_library}/${_runtime_name}/${_runtime_relative}"
        "${_runtime_purpose}"
        "pinned REDUCE CSL runtime artifact ${_runtime_name}/${_runtime_relative}"
        "${_runtime_license}")
    endforeach()
    _pure_reduce_install_record(
      "${_runtime_manifest}"
      "${_docs}/runtime/${_runtime_name}.manifest"
      "Upstream runtime artifact hash and size manifest"
      "generated from pinned REDUCE CSL runtime artifacts"
      "${_docs}/licenses/REDUCE-LICENSE.txt")
  endforeach()
  if(NOT _runtime_resource_count EQUAL 2 OR NOT _runtime_font_count EQUAL 48)
    message(FATAL_ERROR
      "pinned runtime allowlist count changed: resources=${_runtime_resource_count}, "
      "fonts=${_runtime_font_count}")
  endif()

  foreach(_documentation IN ITEMS README COPYING THIRD_PARTY.md)
    _pure_reduce_install_record(
      "${PURE_REDUCE_SOURCE_ROOT}/${_documentation}"
      "${_docs}/${_documentation}"
      "PureReduce documentation"
      "pure-reduce source package"
      "${_docs}/COPYING")
  endforeach()
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
      0002-csl-windows-utf8-image-open.patch
      0003-configure-quote-source-paths.patch)
    _pure_reduce_install_record(
      "${PURE_REDUCE_SOURCE_ROOT}/patches/${_patch_name}"
      "${_docs}/patches/${_patch_name}"
      "Checksum-covered private-source correction"
      "PureReduce patch for pinned REDUCE source"
      "${_docs}/COPYING")
  endforeach()

  macro(_pure_reduce_add_license SOURCE NAME ORIGIN)
    _pure_reduce_install_record(
      "${SOURCE}" "${_docs}/licenses/${NAME}"
      "Third-party license notice" "${ORIGIN}" "self")
  endmacro()
  _pure_reduce_add_license(
    "${PURE_REDUCE_SOURCE_ROOT}/licenses/REDUCE-LICENSE.txt"
    "REDUCE-LICENSE.txt" "canonical REDUCE license")
  _pure_reduce_add_license(
    "${_upstream_install_inputs}/csl/cslbase/COPYING"
    "CSL-COPYING.txt" "detailed CSL notices")
  _pure_reduce_add_license(
    "${_upstream_install_inputs}/libraries/crlibm/COPYING"
    "CRLIBM-COPYING.txt" "crlibm GPL notice")
  _pure_reduce_add_license(
    "${_upstream_install_inputs}/libraries/crlibm/COPYING.LIB"
    "CRLIBM-COPYING.LIB.txt" "crlibm LGPL notice")
  _pure_reduce_add_license(
    "${_upstream_install_inputs}/libraries/libffi/LICENSE"
    "LIBFFI-LICENSE.txt" "libffi license")
  _pure_reduce_add_license(
    "${_upstream_install_inputs}/csl/cslbase/cm-unicode/LICENSE"
    "CM-UNICODE-LICENSE.txt" "CM Unicode font license")
  foreach(_license_name IN ITEMS
      ZLIB-LICENSE.txt
      NCURSES-LICENSE.txt
      WINPTHREADS-COPYING.txt
      LIBCXX-LICENSE.txt
      LIBUNWIND-LICENSE.txt
      COMPILER-RT-LICENSE.txt
      MINGW-W64-CRT-COPYING.txt
      MINGW-W64-RUNTIME-COPYING.txt)
    _pure_reduce_add_license(
      "${PURE_REDUCE_SOURCE_ROOT}/licenses/${_license_name}"
      "${_license_name}" "vendored pinned CLANG64 package license")
  endforeach()

  foreach(_runtime_dll IN LISTS _runtime_dlls)
    _pure_reduce_lookup_runtime_dll(
      "${_runtime_dll}" _dll_origin _dll_version
      _dll_license_source _dll_license_destination)
    set(_vendored_license_root "${PURE_REDUCE_SOURCE_ROOT}/licenses")
    cmake_path(IS_PREFIX _vendored_license_root
      "${_dll_license_source}" NORMALIZE _license_is_vendored)
    if(NOT _license_is_vendored)
      message(FATAL_ERROR
        "runtime DLL mapping license must be vendored under pure-reduce/licenses: "
        "${_dll_license_source}")
    endif()
    cmake_path(GET _runtime_dll FILENAME _runtime_dll_name)
    set(_runtime_parent "unknown")
    foreach(_parent_record IN LISTS PURE_REDUCE_AUDIT_PARENT_RECORDS)
      string(FIND "${_parent_record}" "|" _parent_separator)
      string(SUBSTRING "${_parent_record}" 0 ${_parent_separator}
        _parent_child)
      if(_parent_child STREQUAL _runtime_dll)
        math(EXPR _parent_start "${_parent_separator} + 1")
        string(SUBSTRING "${_parent_record}" ${_parent_start} -1
          _parent_path)
        cmake_path(GET _parent_path FILENAME _runtime_parent)
      endif()
    endforeach()
    _pure_reduce_install_record(
      "${_runtime_dll}" "${PURE_REDUCE_RUNTIME_INSTALL_DIR}/${_runtime_dll_name}"
      "Recursively audited non-system runtime DLL"
      "${_dll_origin} version ${_dll_version} imported by ${_runtime_parent}"
      "${_dll_license_destination}")
    cmake_path(GET _dll_license_destination FILENAME _dll_license_name)
    _pure_reduce_install_record(
      "${_dll_license_source}" "${_dll_license_destination}"
      "Mapped runtime DLL license notice"
      "${_dll_origin} version ${_dll_version}" "self")
  endforeach()

  file(READ "${_metrics}" _upstream_metrics_json)
  foreach(_metric IN ITEMS
      commit source_tree_sha256 elapsed_seconds source_bytes build_tree_bytes)
    string(JSON "_metric_${_metric}" ERROR_VARIABLE _metric_error
      GET "${_upstream_metrics_json}" "${_metric}")
    if(_metric_error)
      message(FATAL_ERROR "upstream metrics omit ${_metric}: ${_metric_error}")
    endif()
  endforeach()
  string(JSON _metric_link_object_count ERROR_VARIABLE _metric_error
    GET "${_upstream_metrics_json}" link_closure object_count)
  if(_metric_error)
    message(FATAL_ERROR
      "upstream metrics omit link object count: ${_metric_error}")
  endif()
  list(LENGTH _records _pre_metrics_count)
  math(EXPR _installed_file_count "${_pre_metrics_count} + 2")
  set(_package_metrics
    "${PURE_REDUCE_BINARY_ROOT}/PureReducePackageMetrics.json")
  file(WRITE "${_package_metrics}"
    "{\n"
    "  \"commit\": \"${_metric_commit}\",\n"
    "  \"source_tree_sha256\": \"${_metric_source_tree_sha256}\",\n"
    "  \"upstream_build_elapsed_seconds\": ${_metric_elapsed_seconds},\n"
    "  \"upstream_source_bytes\": ${_metric_source_bytes},\n"
    "  \"upstream_build_tree_bytes\": ${_metric_build_tree_bytes},\n"
    "  \"link_object_count\": ${_metric_link_object_count},\n"
    "  \"runtime_resource_count\": ${_runtime_resource_count},\n"
    "  \"runtime_font_count\": ${_runtime_font_count},\n"
    "  \"installed_file_count\": ${_installed_file_count}\n"
    "}\n")
  _pure_reduce_install_record(
    "${_package_metrics}" "${_docs}/pure-reduce-package-metrics.json"
    "Deterministic package metrics"
    "selected values from verified pinned upstream build"
    "${_docs}/COPYING")

  list(SORT _records COMPARE NATURAL CASE INSENSITIVE)
  set(_installed_inventory
    "${PURE_REDUCE_BINARY_ROOT}/PureReduceInstalledInventory.tsv")
  file(WRITE "${_installed_inventory}"
    "relative_path\tpurpose\torigin\tsha256\tbytes\tlicense\n")
  foreach(_record IN LISTS _records)
    string(REPLACE "|" ";" _fields "${_record}")
    list(GET _fields 0 _relative)
    list(GET _fields 1 _source)
    list(GET _fields 2 _purpose)
    list(GET _fields 3 _origin)
    list(GET _fields 4 _license)
    file(SHA256 "${_source}" _sha256)
    string(TOLOWER "${_sha256}" _sha256)
    file(SIZE "${_source}" _bytes)
    file(APPEND "${_installed_inventory}"
      "${_relative}\t${_purpose}\t${_origin}\t${_sha256}\t${_bytes}\t${_license}\n")
  endforeach()
  _pure_reduce_install_record(
    "${_installed_inventory}" "${_docs}/PureReduceInventory.tsv"
    "Machine-readable installed payload inventory"
    "generated deterministically from the verified package closure"
    "${_docs}/COPYING")

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
set(PURE_REDUCE_RUNTIME_DLL_MAPPING_FILE
  "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RuntimeDllMappings.cmake" CACHE FILEPATH
  "Reviewed origin/version/license mappings for non-system runtime DLLs")

foreach(_destination_var IN ITEMS
    PURE_REDUCE_LIBRARY_INSTALL_DIR
    PURE_REDUCE_RUNTIME_INSTALL_DIR
    PURE_REDUCE_DOCUMENTATION_INSTALL_DIR)
  _pure_reduce_validate_relative_path(
    "${${_destination_var}}" "${_destination_var}")
endforeach()

pure_reduce_verify_vendored_toolchain_licenses(
  "${CMAKE_CURRENT_SOURCE_DIR}")
_pure_reduce_validate_source_file(
  "${PURE_REDUCE_RUNTIME_DLL_MAPPING_FILE}" "runtime DLL mapping file")

if(TARGET reduce)
  if(NOT DEFINED PURE_REDUCE_LLVM_READOBJ OR
      NOT IS_ABSOLUTE "${PURE_REDUCE_LLVM_READOBJ}" OR
      NOT EXISTS "${PURE_REDUCE_LLVM_READOBJ}")
    message(FATAL_ERROR
      "PURE_REDUCE_LLVM_READOBJ must be an existing absolute executable")
  endif()
  cmake_path(GET PURE_REDUCE_LLVM_READOBJ PARENT_PATH _clang64_bin)
  cmake_path(GET _clang64_bin PARENT_PATH _clang64_root)
  add_custom_target(pure-reduce-vendored-license-verify
    COMMAND "${CMAKE_COMMAND}"
      -DPURE_REDUCE_VERIFY_VENDORED_LICENSES=ON
      "-DPURE_REDUCE_SOURCE_ROOT=${CMAKE_CURRENT_SOURCE_DIR}"
      -P "${CMAKE_CURRENT_LIST_FILE}"
    COMMENT "Verifying pinned CLANG64 license notice hashes"
    VERBATIM)
  add_dependencies(reduce pure-reduce-vendored-license-verify)
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
    "-DPURE_REDUCE_RUNTIME_DLL_MAPPING_FILE=@PURE_REDUCE_RUNTIME_DLL_MAPPING_FILE@"
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
