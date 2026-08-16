set(PURE_FAUST_LIBRARY_INSTALL_DIR "lib/pure" CACHE STRING
  "Relative install directory for Pure modules")
set(PURE_FAUST_DOCUMENTATION_INSTALL_DIR "share/doc/pure-faust" CACHE STRING
  "Relative install directory for pure-faust documentation")

include("${CMAKE_CURRENT_LIST_DIR}/FaustToolchain.cmake")

set(PURE_FAUST_DEVELOPER_AVAILABLE OFF)
if(NOT "${PURE_FAUST_FAUST_ROOT}" STREQUAL "" OR
    NOT "${PURE_FAUST_CLANG}" STREQUAL "" OR
    NOT "${PURE_FAUST_OPT}" STREQUAL "")
  pure_faust_validate_toolchain()
  set(PURE_FAUST_DEVELOPER_AVAILABLE ON)
endif()

foreach(destination_var IN ITEMS
    PURE_FAUST_LIBRARY_INSTALL_DIR PURE_FAUST_DOCUMENTATION_INSTALL_DIR)
  set(destination "${${destination_var}}")
  if(IS_ABSOLUTE "${destination}" OR
      destination MATCHES "(^|[/\\\\])\\.\\.([/\\\\]|$)")
    message(FATAL_ERROR
      "${destination_var} must remain within the installation prefix: ${destination}")
  endif()
endforeach()

if(NOT EXISTS "${PURE_FAUST_CORE_FIXTURE}")
  message(FATAL_ERROR
    "PURE_FAUST_CORE_FIXTURE must name an existing compatible Faust bitcode fixture: "
    "${PURE_FAUST_CORE_FIXTURE}")
endif()

install(FILES faust2.pure
  DESTINATION "${PURE_FAUST_LIBRARY_INSTALL_DIR}"
  COMPONENT Runtime)
install(FILES
  COPYING
  COPYING.LESSER
  WINDOWS.md
  DESTINATION "${PURE_FAUST_DOCUMENTATION_INSTALL_DIR}"
  COMPONENT Runtime)
install(FILES "${PURE_FAUST_CORE_FIXTURE}"
  DESTINATION "${PURE_FAUST_DOCUMENTATION_INSTALL_DIR}/tests"
  RENAME reference.bc
  COMPONENT Runtime)

if(PURE_FAUST_DEVELOPER_AVAILABLE)
  set(PURE_FAUST_AUTHORITATIVE_MANIFEST
    "${CMAKE_CURRENT_BINARY_DIR}/FaustDeveloperExpected.sha256")
  file(WRITE "${PURE_FAUST_AUTHORITATIVE_MANIFEST}"
    "# SHA-256  relative-path\n# SELF  ${PURE_FAUST_DEVELOPER_ALLOWLIST_RELATIVE}\n")
  foreach(relative IN LISTS PURE_FAUST_DEVELOPER_RELATIVE_FILES)
    if(relative STREQUAL "bin/faust.exe")
      set(source "${PURE_FAUST_VALIDATED_FAUST}")
    elseif(relative MATCHES "^bin/")
      string(REGEX REPLACE "^bin/" "" filename "${relative}")
      set(source "${PURE_FAUST_COMPILER_BIN}/${filename}")
    elseif(relative MATCHES "^(include/|lib/clang/)")
      set(source "${PURE_FAUST_COMPILER_PREFIX}/${relative}")
    elseif(relative STREQUAL "share/pure-faust/pure.c")
      set(source "${PURE_FAUST_VALIDATED_PURE_C}")
    elseif(relative MATCHES "^share/doc/pure-faust/licenses/")
      string(REGEX REPLACE "^share/doc/pure-faust/licenses/" "" filename
        "${relative}")
      set(source "${CMAKE_CURRENT_SOURCE_DIR}/licenses/${filename}")
    elseif(relative STREQUAL "share/doc/pure-faust/THIRD_PARTY.md")
      set(source "${CMAKE_CURRENT_SOURCE_DIR}/THIRD_PARTY.md")
    elseif(relative STREQUAL "tools/faust2pure.ps1")
      set(source "${CMAKE_CURRENT_SOURCE_DIR}/tools/faust2pure.ps1")
    elseif(relative MATCHES "^cmake/")
      string(REGEX REPLACE "^cmake/" "" filename "${relative}")
      set(source "${CMAKE_CURRENT_SOURCE_DIR}/cmake/${filename}")
    else()
      message(FATAL_ERROR "No authoritative source mapping for ${relative}")
    endif()
    file(SHA256 "${source}" sha256)
    string(TOLOWER "${sha256}" sha256)
    file(APPEND "${PURE_FAUST_AUTHORITATIVE_MANIFEST}"
      "${sha256}  ${relative}\n")
  endforeach()
  install(PROGRAMS
    "${PURE_FAUST_VALIDATED_FAUST}"
    DESTINATION bin
    COMPONENT FaustDeveloper
    EXCLUDE_FROM_ALL)
  install(PROGRAMS "${PURE_FAUST_CLANG}" "${PURE_FAUST_OPT}"
    DESTINATION bin COMPONENT FaustDeveloper EXCLUDE_FROM_ALL)
  foreach(dll IN LISTS PURE_FAUST_COMPILER_DLL_NAMES)
    install(FILES "${PURE_FAUST_COMPILER_BIN}/${dll}"
      DESTINATION bin COMPONENT FaustDeveloper EXCLUDE_FROM_ALL)
  endforeach()
  foreach(relative IN LISTS PURE_FAUST_COMPILER_RELATIVE_FILES)
    if(NOT relative MATCHES "^bin/")
      cmake_path(GET relative PARENT_PATH destination)
      install(FILES "${PURE_FAUST_COMPILER_PREFIX}/${relative}"
        DESTINATION "${destination}"
        COMPONENT FaustDeveloper EXCLUDE_FROM_ALL)
    endif()
  endforeach()
  install(FILES "${PURE_FAUST_VALIDATED_PURE_C}"
    DESTINATION share/pure-faust
    COMPONENT FaustDeveloper
    EXCLUDE_FROM_ALL)
  install(PROGRAMS "${CMAKE_CURRENT_SOURCE_DIR}/tools/faust2pure.ps1"
    DESTINATION tools
    COMPONENT FaustDeveloper
    EXCLUDE_FROM_ALL)
  install(FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/cmake/CompilerClosure.cmake"
    DESTINATION cmake
    COMPONENT FaustDeveloper
    EXCLUDE_FROM_ALL)
  install(FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/THIRD_PARTY.md"
    DESTINATION "${PURE_FAUST_DOCUMENTATION_INSTALL_DIR}"
    COMPONENT FaustDeveloper
    EXCLUDE_FROM_ALL)
  install(FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/licenses/Faust-COPYING.txt"
    "${CMAKE_CURRENT_SOURCE_DIR}/licenses/LLVM-Apache-2.0-WITH-LLVM-exception.txt"
    "${CMAKE_CURRENT_SOURCE_DIR}/licenses/MinGW-w64-COPYING.txt"
    "${CMAKE_CURRENT_SOURCE_DIR}/licenses/libcxx-LICENSE.txt"
    "${CMAKE_CURRENT_SOURCE_DIR}/licenses/libffi-LICENSE.txt"
    "${CMAKE_CURRENT_SOURCE_DIR}/licenses/libiconv-COPYING.txt"
    "${CMAKE_CURRENT_SOURCE_DIR}/licenses/libxml2-COPYING.txt"
    "${CMAKE_CURRENT_SOURCE_DIR}/licenses/zlib-LICENSE.txt"
    "${CMAKE_CURRENT_SOURCE_DIR}/licenses/zstd-LICENSE.txt"
    DESTINATION "${PURE_FAUST_DOCUMENTATION_INSTALL_DIR}/licenses"
    COMPONENT FaustDeveloper
    EXCLUDE_FROM_ALL)
  cmake_path(GET PURE_FAUST_DEVELOPER_ALLOWLIST_RELATIVE PARENT_PATH
    allowlist_destination)
  install(FILES "${PURE_FAUST_AUTHORITATIVE_MANIFEST}"
    DESTINATION "${allowlist_destination}"
    RENAME "FaustDeveloper-ALLOWLIST.sha256"
    COMPONENT FaustDeveloper EXCLUDE_FROM_ALL)
else()
  install(CODE "" COMPONENT FaustDeveloper EXCLUDE_FROM_ALL)
endif()
