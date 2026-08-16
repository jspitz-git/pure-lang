set(PURE_FAUST_FAUST_VERSION "2.85.9")
set(PURE_FAUST_FAUST_RELEASE_TAG "2.85.9")
set(PURE_FAUST_FAUST_ASSET_URL
  "https://github.com/grame-cncm/faust/releases/download/2.85.9/Faust-2.85.9-win64.exe")
set(PURE_FAUST_FAUST_ASSET_SIZE 109591809)
set(PURE_FAUST_FAUST_ASSET_SHA256
  "d0994eb444ab4b1e75e3ed7c31897da24013db0672e2c6be8f2ab09b73d16977")
set(PURE_FAUST_FAUST_SOURCE_URL
  "https://github.com/grame-cncm/faust/releases/download/2.85.9/faust-2.85.9.tar.gz")
set(PURE_FAUST_FAUST_SOURCE_SIZE 79259467)
set(PURE_FAUST_FAUST_SOURCE_SHA256
  "0cd00968f81357b78df64c25aad12ec94bd4b75bd489ca0449fe7f7b1ad0efe1")

set(PURE_FAUST_INSTALLED_FAUST_SHA256
  "66327ceb3ed7170859a010767488028f333247ed80f9d4b38a08113073644a2a")
set(PURE_FAUST_INSTALLED_PURE_C_SHA256
  "c41948c5fad4c5e6f458559f862b228215b29577f7bb168848aac0e835688b63")

include("${CMAKE_CURRENT_LIST_DIR}/CompilerClosure.cmake")

set(PURE_FAUST_UPSTREAM_RELATIVE_FILES
  "bin/faust.exe"
  "share/faust/pure.c")
set(PURE_FAUST_LICENSE_SHA256
  "share/doc/pure-faust/licenses/Faust-COPYING.txt=92a42adab3110694eb7731691f57f229fcaba31570d1727eb7be3f197307378c"
  "share/doc/pure-faust/licenses/LLVM-Apache-2.0-WITH-LLVM-exception.txt=8d85c1057d742e597985c7d4e6320b015a9139385cff4cbae06ffc0ebe89afee"
  "share/doc/pure-faust/licenses/MinGW-w64-COPYING.txt=841dcac31b495c708d68622d0ace296acf9f9783375220ad02f6d61a59ca9ae5"
  "share/doc/pure-faust/licenses/libcxx-LICENSE.txt=bc043a21d9fcaff86c2b6e2c17f9f3ec3b253537ad49b4b71cda4a67e1e27025"
  "share/doc/pure-faust/licenses/libffi-LICENSE.txt=17b64dc60f3b6897a60f971e288b973f655c2edcdf08b25f3c3dd5549857881c"
  "share/doc/pure-faust/licenses/libiconv-COPYING.txt=9955bb96027f1abc8a070b4a1f088cb780bd965f782fab0c9e665abedf9812b8"
  "share/doc/pure-faust/licenses/libxml2-COPYING.txt=d5d3024e2c892c8517828d9fc438b21b54374c0f4b40a2a7a659569d72d3f162"
  "share/doc/pure-faust/licenses/zlib-LICENSE.txt=fade4e988b53fa7f9f30c9981fa0fbae4dcb12175cd2904fa3049581ec6494b2"
  "share/doc/pure-faust/licenses/zstd-LICENSE.txt=c06b31c78056b25eb546bed7babe58b59f880437a87730aae7f2b4e280863c1a")
set(PURE_FAUST_DEVELOPER_ALLOWLIST_RELATIVE
  "share/doc/pure-faust/FaustDeveloper-ALLOWLIST.sha256")
set(PURE_FAUST_DEVELOPER_RELATIVE_FILES
  "bin/faust.exe"
  "cmake/CompilerClosure.cmake"
  "share/doc/pure-faust/THIRD_PARTY.md"
  "share/doc/pure-faust/licenses/Faust-COPYING.txt"
  "share/doc/pure-faust/licenses/LLVM-Apache-2.0-WITH-LLVM-exception.txt"
  "share/doc/pure-faust/licenses/MinGW-w64-COPYING.txt"
  "share/doc/pure-faust/licenses/libcxx-LICENSE.txt"
  "share/doc/pure-faust/licenses/libffi-LICENSE.txt"
  "share/doc/pure-faust/licenses/libiconv-COPYING.txt"
  "share/doc/pure-faust/licenses/libxml2-COPYING.txt"
  "share/doc/pure-faust/licenses/zlib-LICENSE.txt"
  "share/doc/pure-faust/licenses/zstd-LICENSE.txt"
  "share/pure-faust/pure.c"
  "tools/faust2pure.ps1")

function(pure_faust_require_version executable expected label)
  execute_process(
    COMMAND "${executable}" --version
    RESULT_VARIABLE version_result
    OUTPUT_VARIABLE version_output
    ERROR_VARIABLE version_error
    ENCODING UTF-8)
  if(NOT version_result EQUAL 0)
    message(FATAL_ERROR
      "${label} version check failed (${version_result})\n"
      "stdout:\n${version_output}\nstderr:\n${version_error}")
  endif()
  set(version_transcript "${version_output}\n${version_error}")
  string(FIND "${version_transcript}" "${expected}" version_match)
  if(version_match EQUAL -1)
    message(FATAL_ERROR
      "${label} has the wrong version; expected '${expected}'\n"
      "${version_transcript}")
  endif()
endfunction()

function(pure_faust_validate_toolchain)
  foreach(required IN ITEMS
      PURE_FAUST_FAUST_ROOT PURE_FAUST_CLANG PURE_FAUST_OPT)
    if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
      message(FATAL_ERROR
        "${required} is required when configuring FaustDeveloper")
    endif()
  endforeach()

  cmake_path(ABSOLUTE_PATH PURE_FAUST_FAUST_ROOT NORMALIZE
    OUTPUT_VARIABLE faust_root)
  set(faust_executable "${faust_root}/bin/faust.exe")
  set(pure_architecture "${faust_root}/share/faust/pure.c")
  foreach(required_file IN ITEMS
      "${faust_executable}" "${pure_architecture}"
      "${PURE_FAUST_CLANG}" "${PURE_FAUST_OPT}")
    if(NOT EXISTS "${required_file}" OR IS_DIRECTORY "${required_file}")
      message(FATAL_ERROR "Missing FaustDeveloper input: ${required_file}")
    endif()
  endforeach()

  file(SHA256 "${faust_executable}" faust_sha256)
  string(TOLOWER "${faust_sha256}" faust_sha256)
  if(NOT faust_sha256 STREQUAL PURE_FAUST_INSTALLED_FAUST_SHA256)
    message(FATAL_ERROR
      "Unexpected Faust 2.85.9 compiler SHA-256: ${faust_sha256}")
  endif()
  file(SHA256 "${pure_architecture}" pure_c_sha256)
  string(TOLOWER "${pure_c_sha256}" pure_c_sha256)
  if(NOT pure_c_sha256 STREQUAL PURE_FAUST_INSTALLED_PURE_C_SHA256)
    message(FATAL_ERROR
      "Unexpected Faust 2.85.9 pure.c SHA-256: ${pure_c_sha256}")
  endif()

  pure_faust_require_version(
    "${faust_executable}" "FAUST Version ${PURE_FAUST_FAUST_VERSION}" "Faust")
  pure_faust_require_version("${PURE_FAUST_CLANG}" "clang version 22" "Clang")
  pure_faust_require_version("${PURE_FAUST_OPT}" "LLVM version 22" "opt")
  pure_faust_configure_compiler_closure()

  list(APPEND PURE_FAUST_DEVELOPER_RELATIVE_FILES
    ${PURE_FAUST_COMPILER_RELATIVE_FILES})
  list(REMOVE_DUPLICATES PURE_FAUST_DEVELOPER_RELATIVE_FILES)
  list(SORT PURE_FAUST_DEVELOPER_RELATIVE_FILES)

  set(PURE_FAUST_VALIDATED_ROOT "${faust_root}" PARENT_SCOPE)
  set(PURE_FAUST_VALIDATED_FAUST "${faust_executable}" PARENT_SCOPE)
  set(PURE_FAUST_VALIDATED_PURE_C "${pure_architecture}" PARENT_SCOPE)
  set(PURE_FAUST_COMPILER_PREFIX "${PURE_FAUST_COMPILER_PREFIX}" PARENT_SCOPE)
  set(PURE_FAUST_COMPILER_BIN "${PURE_FAUST_COMPILER_BIN}" PARENT_SCOPE)
  set(PURE_FAUST_COMPILER_SOURCE_FILES
    "${PURE_FAUST_COMPILER_SOURCE_FILES}" PARENT_SCOPE)
  set(PURE_FAUST_COMPILER_RELATIVE_FILES
    "${PURE_FAUST_COMPILER_RELATIVE_FILES}" PARENT_SCOPE)
  set(PURE_FAUST_DEVELOPER_RELATIVE_FILES
    "${PURE_FAUST_DEVELOPER_RELATIVE_FILES}" PARENT_SCOPE)
endfunction()
