set(PURE_FAUST_COMPILER_DLL_NAMES
  libLLVM-22.dll
  libclang-cpp.dll
  libc++.dll
  libffi-8.dll
  zlib1.dll
  libzstd.dll
  libxml2-16.dll
  libiconv-2.dll)

set(PURE_FAUST_COMPILER_BINARY_SHA256
  "clang.exe=0054204bc07618cbc06442813b648f396a001b5965c06a3a7d11cdbb29327ea3"
  "opt.exe=5f8b1c25e3c6fc9f629da2dd772968950e4b63b46b65850a14018ab3cbde5740"
  "libLLVM-22.dll=5cd6d966f72bae4cfbc11c9a18227d6e9b90a4e2edfb4e120bbb8e9dc3e55a1c"
  "libclang-cpp.dll=a9eda9b047b6d15499a254489ad3566e090012a86740073003b0d48374bc313f"
  "libc++.dll=7344daed05388589e9bd691ed1d30c568c374da4b8b6a12e1502185948c03cd4"
  "libffi-8.dll=17600337c32fc8dc60d8fafd07d7f84f86775777ad635e76e433e34fecbb5572"
  "zlib1.dll=94dd0a72d4da79e25294a91d1edf902d76eade7512d9218609a5fe43e3a7397a"
  "libzstd.dll=a4a29141c6dc489c59c260b5d4f781c195cea11ed231ee0cbfc6d3803b0708b7"
  "libxml2-16.dll=c6c34a810d86c19c034a1bc96c4c500bde8fb789ded69b434e67eee773605852"
  "libiconv-2.dll=c9f9b9addeac620eeccb6a23fc5a423fa1244e18431c00e1219db00d479ea332")

set(PURE_FAUST_COMPILER_BINARY_PROVENANCE
  "clang.exe|mingw-w64-clang-x86_64-clang|22.1.8-2|LLVM-Apache-2.0-WITH-LLVM-exception.txt"
  "libclang-cpp.dll|mingw-w64-clang-x86_64-clang-libs|22.1.8-2|LLVM-Apache-2.0-WITH-LLVM-exception.txt"
  "opt.exe|mingw-w64-clang-x86_64-llvm|22.1.8-2|LLVM-Apache-2.0-WITH-LLVM-exception.txt"
  "libLLVM-22.dll|mingw-w64-clang-x86_64-llvm-libs|22.1.8-2|LLVM-Apache-2.0-WITH-LLVM-exception.txt"
  "libc++.dll|mingw-w64-clang-x86_64-libc++|22.1.8-1|libcxx-LICENSE.txt"
  "libffi-8.dll|mingw-w64-clang-x86_64-libffi|3.7.1-1|libffi-LICENSE.txt"
  "zlib1.dll|mingw-w64-clang-x86_64-zlib|1.3.2-2|zlib-LICENSE.txt"
  "libzstd.dll|mingw-w64-clang-x86_64-zstd|1.5.7-2|zstd-LICENSE.txt"
  "libxml2-16.dll|mingw-w64-clang-x86_64-libxml2|2.15.3-1|libxml2-COPYING.txt"
  "libiconv-2.dll|mingw-w64-clang-x86_64-libiconv|1.19-1|libiconv-COPYING.txt")

set(PURE_FAUST_COMPILER_HEADER_ROOTS
  "lib/clang/22/include"
  "include")
set(PURE_FAUST_COMPILER_HEADER_FILES
  "include/_mingw.h"
  "include/_mingw_mac.h"
  "include/_mingw_secapi.h"
  "include/corecrt.h"
  "include/corecrt_wstdlib.h"
  "include/crtdefs.h"
  "include/limits.h"
  "include/malloc.h"
  "include/math.h"
  "include/sec_api/stdlib_s.h"
  "include/stddef.h"
  "include/stdint.h"
  "include/stdlib.h"
  "include/vadefs.h"
  "lib/clang/22/include/__stddef_wchar_t.h"
  "lib/clang/22/include/__stddef_wint_t.h"
  "lib/clang/22/include/limits.h"
  "lib/clang/22/include/mm_malloc.h"
  "lib/clang/22/include/stddef.h"
  "lib/clang/22/include/stdint.h"
  "lib/clang/22/include/vadefs.h")
set(PURE_FAUST_COMPILER_HEADER_INVENTORY_SHA256
  "dependency-closure=77d394f8dc5adac673526a7f863ddebb64e39785b18507836ba505678f8cc9ca")

function(pure_faust_configure_compiler_closure)
  cmake_path(GET PURE_FAUST_CLANG PARENT_PATH compiler_bin)
  cmake_path(GET compiler_bin PARENT_PATH compiler_prefix)
  cmake_path(GET PURE_FAUST_OPT PARENT_PATH opt_bin)
  if(NOT opt_bin STREQUAL compiler_bin)
    message(FATAL_ERROR "Clang and opt must come from the same LLVM prefix")
  endif()

  execute_process(
    COMMAND "${PURE_FAUST_CLANG}" -E -x c -v NUL
    RESULT_VARIABLE include_probe_result
    OUTPUT_VARIABLE include_probe_output
    ERROR_VARIABLE include_probe_error
    ENCODING UTF-8)
  if(NOT include_probe_result EQUAL 0)
    message(FATAL_ERROR
      "Clang include-search probe failed (${include_probe_result})\n"
      "${include_probe_output}\n${include_probe_error}")
  endif()
  string(REPLACE "\\" "/" include_probe "${include_probe_error}")
  foreach(root IN LISTS PURE_FAUST_COMPILER_HEADER_ROOTS)
    string(FIND "${include_probe}" "${compiler_prefix}/${root}" root_match)
    if(root_match EQUAL -1)
      message(FATAL_ERROR
        "Clang did not report required header root: ${compiler_prefix}/${root}")
    endif()
  endforeach()

  set(dependency_probe "${CMAKE_CURRENT_BINARY_DIR}/faust-header-probe.c")
  file(WRITE "${dependency_probe}"
    "#include <stdlib.h>\n#include <math.h>\n#include <stdint.h>\n")
  execute_process(
    COMMAND "${PURE_FAUST_CLANG}" -M -MT reference "${dependency_probe}"
    RESULT_VARIABLE dependency_result
    OUTPUT_VARIABLE dependency_output
    ERROR_VARIABLE dependency_error
    ENCODING UTF-8)
  if(NOT dependency_result EQUAL 0)
    message(FATAL_ERROR
      "Clang dependency probe failed (${dependency_result})\n"
      "${dependency_output}\n${dependency_error}")
  endif()
  string(REPLACE "\\" "/" dependency_output "${dependency_output}")
  string(REGEX REPLACE "[ \t\r\n]+" ";" dependency_tokens
    "${dependency_output}")
  set(reported_header_files)
  foreach(path IN LISTS dependency_tokens)
    string(FIND "${path}" "${compiler_prefix}/" prefix_match)
    if(prefix_match EQUAL 0)
      string(REPLACE "${compiler_prefix}/" "" relative "${path}")
      list(APPEND reported_header_files "${relative}")
    endif()
  endforeach()
  list(REMOVE_DUPLICATES reported_header_files)
  list(SORT reported_header_files)
  list(SORT PURE_FAUST_COMPILER_HEADER_FILES)
  if(NOT reported_header_files STREQUAL PURE_FAUST_COMPILER_HEADER_FILES)
    message(FATAL_ERROR
      "Dependency-derived header closure changed\n"
      "expected: ${PURE_FAUST_COMPILER_HEADER_FILES}\n"
      "reported: ${reported_header_files}")
  endif()

  set(source_files "${PURE_FAUST_CLANG}" "${PURE_FAUST_OPT}")
  set(relative_files "bin/clang.exe" "bin/opt.exe")
  foreach(dll IN LISTS PURE_FAUST_COMPILER_DLL_NAMES)
    if(dll STREQUAL "msys-2.0.dll")
      message(FATAL_ERROR "msys-2.0.dll is forbidden from FaustDeveloper")
    endif()
    list(APPEND source_files "${compiler_bin}/${dll}")
    list(APPEND relative_files "bin/${dll}")
  endforeach()

  foreach(entry IN LISTS PURE_FAUST_COMPILER_BINARY_SHA256)
    string(REPLACE "=" ";" fields "${entry}")
    list(GET fields 0 name)
    list(GET fields 1 expected_sha256)
    file(SHA256 "${compiler_bin}/${name}" actual_sha256)
    string(TOLOWER "${actual_sha256}" actual_sha256)
    if(NOT actual_sha256 STREQUAL expected_sha256)
      message(FATAL_ERROR
        "Unexpected compiler-closure SHA-256 for ${name}: ${actual_sha256}")
    endif()
  endforeach()

  set(expected_binary_names clang.exe opt.exe ${PURE_FAUST_COMPILER_DLL_NAMES})
  foreach(name IN LISTS expected_binary_names)
    set(mapping_count 0)
    foreach(mapping IN LISTS PURE_FAUST_COMPILER_BINARY_PROVENANCE)
      string(REPLACE "|" ";" fields "${mapping}")
      list(GET fields 0 mapped_name)
      if(mapped_name STREQUAL name)
        math(EXPR mapping_count "${mapping_count} + 1")
        list(GET fields 3 license_name)
        set(license_found OFF)
        foreach(license_entry IN LISTS PURE_FAUST_LICENSE_SHA256)
          if(license_entry MATCHES "/${license_name}=")
            set(license_found ON)
          endif()
        endforeach()
        if(NOT license_found)
          message(FATAL_ERROR
            "Compiler mapping lacks pinned license ${license_name}: ${name}")
        endif()
      endif()
    endforeach()
    if(NOT mapping_count EQUAL 1)
      message(FATAL_ERROR
        "Expected one package/license mapping for ${name}, got ${mapping_count}")
    endif()
  endforeach()

  list(SORT PURE_FAUST_COMPILER_HEADER_FILES)
  foreach(relative IN LISTS PURE_FAUST_COMPILER_HEADER_FILES)
    file(SHA256 "${compiler_prefix}/${relative}" header_sha256)
    string(TOLOWER "${header_sha256}" header_sha256)
    string(APPEND inventory "${header_sha256}  ${relative}\n")
    list(APPEND source_files "${compiler_prefix}/${relative}")
    list(APPEND relative_files "${relative}")
  endforeach()
  string(SHA256 inventory_sha256 "${inventory}")
  string(REPLACE "dependency-closure=" "" expected_inventory_sha256
    "${PURE_FAUST_COMPILER_HEADER_INVENTORY_SHA256}")
  if(NOT inventory_sha256 STREQUAL expected_inventory_sha256)
    message(FATAL_ERROR
      "Unexpected dependency-derived header inventory SHA-256: "
      "${inventory_sha256}")
  endif()

  foreach(source IN LISTS source_files)
    if(NOT EXISTS "${source}" OR IS_DIRECTORY "${source}")
      message(FATAL_ERROR "Missing compiler-closure file: ${source}")
    endif()
    cmake_path(GET source FILENAME basename)
    string(TOLOWER "${basename}" basename_lower)
    if(basename_lower STREQUAL "msys-2.0.dll" OR
       basename_lower MATCHES "^(bash|sh|dash|pacman)(\\.exe)?$")
      message(FATAL_ERROR "Forbidden compiler-closure file: ${source}")
    endif()
  endforeach()

  list(REMOVE_DUPLICATES relative_files)
  list(SORT relative_files)
  set(PURE_FAUST_COMPILER_PREFIX "${compiler_prefix}" PARENT_SCOPE)
  set(PURE_FAUST_COMPILER_BIN "${compiler_bin}" PARENT_SCOPE)
  set(PURE_FAUST_COMPILER_SOURCE_FILES "${source_files}" PARENT_SCOPE)
  set(PURE_FAUST_COMPILER_RELATIVE_FILES "${relative_files}" PARENT_SCOPE)
endfunction()
