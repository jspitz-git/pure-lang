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

set(PURE_FAUST_COMPILER_HEADER_ROOTS
  "lib/clang/22/include"
  "include")
set(PURE_FAUST_MINGW_HEADER_PACKAGES
  "mingw-w64-clang-x86_64-headers-14.0.0.r220.gd999af622-1"
  "mingw-w64-clang-x86_64-crt-14.0.0.r220.gd999af622-1")
set(PURE_FAUST_COMPILER_HEADER_INVENTORY_SHA256
  "lib/clang/22/include=3e14c739b60d15a7c0f255734b13859e142d990a8e2fc8cf12eb74196e87cff3"
  "include=6beada17367e62412d6244d98721a4fc015ae4c0db4d897dd17487e7489b44cd")

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

  foreach(root IN LISTS PURE_FAUST_COMPILER_HEADER_ROOTS)
    if(NOT IS_DIRECTORY "${compiler_prefix}/${root}")
      message(FATAL_ERROR "Missing compiler header root: ${compiler_prefix}/${root}")
    endif()
    if(root STREQUAL "include")
      set(root_files)
      cmake_path(GET compiler_prefix PARENT_PATH msys_root)
      foreach(package IN LISTS PURE_FAUST_MINGW_HEADER_PACKAGES)
        set(package_manifest "${msys_root}/var/lib/pacman/local/${package}/files")
        if(NOT EXISTS "${package_manifest}")
          message(FATAL_ERROR
            "Missing MinGW build-provenance manifest: ${package_manifest}")
        endif()
        file(STRINGS "${package_manifest}" package_files
          REGEX "^clang64/include/.+[^/]$")
        foreach(package_file IN LISTS package_files)
          string(REGEX REPLACE "^clang64/" "" relative "${package_file}")
          list(APPEND root_files "${relative}")
        endforeach()
      endforeach()
      list(REMOVE_DUPLICATES root_files)
      list(SORT root_files)
    else()
      file(GLOB_RECURSE root_files RELATIVE "${compiler_prefix}"
        LIST_DIRECTORIES false CONFIGURE_DEPENDS
        "${compiler_prefix}/${root}/*")
    endif()
    if(NOT root_files)
      message(FATAL_ERROR "Compiler header root is empty: ${compiler_prefix}/${root}")
    endif()
    foreach(relative IN LISTS root_files)
      file(SHA256 "${compiler_prefix}/${relative}" header_sha256)
      string(TOLOWER "${header_sha256}" header_sha256)
      string(APPEND inventory "${header_sha256}  ${relative}\n")
      list(APPEND source_files "${compiler_prefix}/${relative}")
      list(APPEND relative_files "${relative}")
    endforeach()
    string(SHA256 inventory_sha256 "${inventory}")
    set(expected_inventory_sha256 "")
    foreach(entry IN LISTS PURE_FAUST_COMPILER_HEADER_INVENTORY_SHA256)
      string(REPLACE "=" ";" fields "${entry}")
      list(GET fields 0 entry_root)
      if(entry_root STREQUAL root)
        list(GET fields 1 expected_inventory_sha256)
      endif()
    endforeach()
    if(NOT inventory_sha256 STREQUAL expected_inventory_sha256)
      message(FATAL_ERROR
        "Unexpected compiler header inventory SHA-256 for ${root}: "
        "${inventory_sha256}")
    endif()
    unset(inventory)
  endforeach()

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
