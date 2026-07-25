include_guard(GLOBAL)

include(CheckCSourceCompiles)
include(CheckCXXSourceCompiles)

option(
  PURE_STRICT_TOOLCHAIN
  "Require the reference Clang 22 and LLVM 22 toolchain"
  ON
)
option(
  PURE_DEBUG_FRIENDLY
  "Preserve complete types and stack frames in Clang debug builds"
  ON
)
set(
  PURE_SANITIZERS
  ""
  CACHE STRING
  "Comma-separated Clang sanitizers to enable"
)

execute_process(
  COMMAND "${CMAKE_C_COMPILER}" -dumpmachine
  RESULT_VARIABLE PURE_C_COMPILER_TRIPLE_RESULT
  OUTPUT_VARIABLE PURE_HOST_TRIPLE
  OUTPUT_STRIP_TRAILING_WHITESPACE
  ERROR_QUIET
)
if(NOT PURE_C_COMPILER_TRIPLE_RESULT EQUAL 0 OR NOT PURE_HOST_TRIPLE)
  if(PURE_STRICT_TOOLCHAIN)
    message(FATAL_ERROR "Unable to determine the C compiler target triple")
  endif()
  set(PURE_HOST_TRIPLE "${CMAKE_SYSTEM_PROCESSOR}-${CMAKE_SYSTEM_NAME}")
endif()

function(pure_normalize_triple_architecture triple output_variable)
  string(REGEX MATCH "^[^-]+" architecture "${triple}")
  string(TOLOWER "${architecture}" architecture)
  if(architecture STREQUAL "aarch64")
    set(architecture "arm64")
  elseif(architecture STREQUAL "amd64")
    set(architecture "x86_64")
  endif()
  set("${output_variable}" "${architecture}" PARENT_SCOPE)
endfunction()

function(pure_require_clang64_path path description)
  file(TO_CMAKE_PATH "${path}" normalized_path)
  if(normalized_path MATCHES "^/clang64(/|$)")
    string(REGEX REPLACE
      "^/clang64" "${PURE_CLANG64_PREFIX}" normalized_path "${normalized_path}"
    )
  endif()
  file(REAL_PATH "${normalized_path}" normalized_path)
  file(TO_CMAKE_PATH "${normalized_path}" normalized_path)
  string(TOLOWER "${normalized_path}" normalized_path)
  cmake_path(
    IS_PREFIX PURE_CLANG64_PREFIX "${normalized_path}" NORMALIZE
    path_is_in_clang64
  )
  if(NOT path_is_in_clang64)
    message(FATAL_ERROR
      "The Windows release ${description} must come from ${PURE_CLANG64_PREFIX}; found ${path}"
    )
  endif()
endfunction()

if(PURE_STRICT_TOOLCHAIN)
  if(NOT CMAKE_C_COMPILER_ID STREQUAL "Clang")
    message(FATAL_ERROR "The reference build requires clang-22")
  endif()

  if(NOT CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    message(FATAL_ERROR "The reference build requires clang++-22")
  endif()

  if(CMAKE_C_COMPILER_VERSION VERSION_LESS 22
     OR CMAKE_C_COMPILER_VERSION VERSION_GREATER_EQUAL 23)
    message(FATAL_ERROR
      "The reference build requires Clang 22.x; found ${CMAKE_C_COMPILER_VERSION}"
    )
  endif()

  if(CMAKE_CXX_COMPILER_VERSION VERSION_LESS 22
     OR CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL 23)
    message(FATAL_ERROR
      "The reference build requires Clang 22.x; found ${CMAKE_CXX_COMPILER_VERSION}"
    )
  endif()

  if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "The reference build requires a 64-bit compiler")
  endif()
endif()

find_package(LLVM REQUIRED CONFIG)

if(LLVM_PACKAGE_VERSION VERSION_LESS 22
   OR LLVM_PACKAGE_VERSION VERSION_GREATER_EQUAL 23)
  message(FATAL_ERROR
    "Pure requires LLVM 22.x; found LLVM ${LLVM_PACKAGE_VERSION}"
  )
endif()

if(PURE_STRICT_TOOLCHAIN)
  if(NOT CMAKE_HOST_SYSTEM_NAME STREQUAL CMAKE_SYSTEM_NAME)
    message(FATAL_ERROR
      "The reference build requires matching host and target systems; found ${CMAKE_HOST_SYSTEM_NAME} and ${CMAKE_SYSTEM_NAME}"
    )
  endif()

  execute_process(
    COMMAND "${CMAKE_CXX_COMPILER}" -dumpmachine
    RESULT_VARIABLE PURE_CXX_COMPILER_TRIPLE_RESULT
    OUTPUT_VARIABLE PURE_CXX_COMPILER_TRIPLE
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
  )
  if(NOT PURE_CXX_COMPILER_TRIPLE_RESULT EQUAL 0 OR
     NOT PURE_CXX_COMPILER_TRIPLE)
    message(FATAL_ERROR "Unable to determine the C++ compiler target triple")
  endif()

  pure_normalize_triple_architecture(
    "${PURE_HOST_TRIPLE}" PURE_C_COMPILER_ARCHITECTURE
  )
  pure_normalize_triple_architecture(
    "${PURE_CXX_COMPILER_TRIPLE}" PURE_CXX_COMPILER_ARCHITECTURE
  )
  set(PURE_LLVM_HOST_TRIPLE "${LLVM_HOST_TRIPLE}")
  if(NOT PURE_LLVM_HOST_TRIPLE)
    set(PURE_LLVM_HOST_TRIPLE "${LLVM_TARGET_TRIPLE}")
  endif()
  pure_normalize_triple_architecture(
    "${PURE_LLVM_HOST_TRIPLE}" PURE_LLVM_HOST_ARCHITECTURE
  )
  if(NOT PURE_C_COMPILER_ARCHITECTURE STREQUAL
         PURE_CXX_COMPILER_ARCHITECTURE)
    message(FATAL_ERROR
      "C and C++ compiler targets do not match: ${PURE_HOST_TRIPLE} and ${PURE_CXX_COMPILER_TRIPLE}"
    )
  endif()
  if(NOT PURE_C_COMPILER_ARCHITECTURE STREQUAL
         PURE_LLVM_HOST_ARCHITECTURE)
    message(FATAL_ERROR
      "Compiler and LLVM host architectures do not match: ${PURE_HOST_TRIPLE} and ${PURE_LLVM_HOST_TRIPLE}"
    )
  endif()

  if(APPLE)
    if(NOT CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin" OR
       NOT CMAKE_SYSTEM_NAME STREQUAL "Darwin")
      message(FATAL_ERROR "The Apple release build requires a native macOS host")
    endif()
    string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" PURE_SYSTEM_PROCESSOR)
    if(NOT PURE_SYSTEM_PROCESSOR MATCHES "^(arm64|aarch64)$" OR
       NOT PURE_C_COMPILER_ARCHITECTURE STREQUAL "arm64")
      message(FATAL_ERROR
        "The macOS release build requires native arm64; found ${CMAKE_SYSTEM_PROCESSOR} and ${PURE_HOST_TRIPLE}"
      )
    endif()
    unset(PURE_EFFECTIVE_MACOS_C_TARGET CACHE)
    unset(PURE_EFFECTIVE_MACOS_CXX_TARGET CACHE)
    check_c_source_compiles(
      "#if !defined(__APPLE__) || !defined(__aarch64__) || defined(__x86_64__)\n#error unsupported target\n#endif\nint main(void) { return 0; }"
      PURE_EFFECTIVE_MACOS_C_TARGET
    )
    check_cxx_source_compiles(
      "#if !defined(__APPLE__) || !defined(__aarch64__) || defined(__x86_64__)\n#error unsupported target\n#endif\nint main() { return 0; }"
      PURE_EFFECTIVE_MACOS_CXX_TARGET
    )
    if(NOT PURE_EFFECTIVE_MACOS_C_TARGET OR
       NOT PURE_EFFECTIVE_MACOS_CXX_TARGET)
      message(FATAL_ERROR
        "The macOS release build requires an effective arm64-only compiler target"
      )
    endif()
  elseif(WIN32)
    if(NOT CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows" OR
       NOT CMAKE_SYSTEM_NAME STREQUAL "Windows")
      message(FATAL_ERROR "The Windows release build requires a native Windows host")
    endif()
    pure_normalize_triple_architecture(
      "${CMAKE_HOST_SYSTEM_PROCESSOR}" PURE_WINDOWS_HOST_ARCHITECTURE
    )
    pure_normalize_triple_architecture(
      "${CMAKE_SYSTEM_PROCESSOR}" PURE_WINDOWS_SYSTEM_ARCHITECTURE
    )
    if(NOT PURE_WINDOWS_HOST_ARCHITECTURE STREQUAL "x86_64" OR
       NOT PURE_WINDOWS_SYSTEM_ARCHITECTURE STREQUAL "x86_64")
      message(FATAL_ERROR
        "The Windows release build requires a native x86_64 host; found ${CMAKE_HOST_SYSTEM_PROCESSOR} and ${CMAKE_SYSTEM_PROCESSOR}"
      )
    endif()
    if(NOT CMAKE_C_COMPILER_FRONTEND_VARIANT STREQUAL "GNU" OR
       NOT CMAKE_CXX_COMPILER_FRONTEND_VARIANT STREQUAL "GNU")
      message(FATAL_ERROR
        "The Windows release build requires the GNU-like MSYS2 CLANG64 frontend"
      )
    endif()
    string(TOLOWER "${PURE_HOST_TRIPLE}" PURE_C_COMPILER_TRIPLE_LOWER)
    string(TOLOWER "${PURE_CXX_COMPILER_TRIPLE}" PURE_CXX_COMPILER_TRIPLE_LOWER)
    if(NOT PURE_C_COMPILER_TRIPLE_LOWER MATCHES
           "^x86_64-w64-windows-gnu$" OR
       NOT PURE_CXX_COMPILER_TRIPLE_LOWER MATCHES
           "^x86_64-w64-windows-gnu$")
      message(FATAL_ERROR
        "The Windows release build requires x86_64-w64-windows-gnu; found ${PURE_HOST_TRIPLE} and ${PURE_CXX_COMPILER_TRIPLE}"
      )
    endif()
    unset(PURE_EFFECTIVE_WINDOWS_C_TARGET CACHE)
    unset(PURE_EFFECTIVE_WINDOWS_CXX_TARGET CACHE)
    check_c_source_compiles(
      "#if !defined(_WIN32) || !defined(__MINGW32__) || !defined(__x86_64__)\n#error unsupported target\n#endif\nint main(void) { return 0; }"
      PURE_EFFECTIVE_WINDOWS_C_TARGET
    )
    check_cxx_source_compiles(
      "#if !defined(_WIN32) || !defined(__MINGW32__) || !defined(__x86_64__)\n#error unsupported target\n#endif\nint main() { return 0; }"
      PURE_EFFECTIVE_WINDOWS_CXX_TARGET
    )
    if(NOT PURE_EFFECTIVE_WINDOWS_C_TARGET OR
       NOT PURE_EFFECTIVE_WINDOWS_CXX_TARGET)
      message(FATAL_ERROR
        "The Windows release build requires an effective x86_64 MinGW target"
      )
    endif()

    file(REAL_PATH "${CMAKE_C_COMPILER}" PURE_C_COMPILER_REAL_PATH)
    get_filename_component(PURE_CLANG64_BIN_DIR "${PURE_C_COMPILER_REAL_PATH}" DIRECTORY)
    get_filename_component(PURE_CLANG64_PREFIX "${PURE_CLANG64_BIN_DIR}" DIRECTORY)
    file(TO_CMAKE_PATH "${PURE_CLANG64_PREFIX}" PURE_CLANG64_PREFIX)
    string(TOLOWER "${PURE_CLANG64_PREFIX}" PURE_CLANG64_PREFIX)
    get_filename_component(PURE_CLANG64_PREFIX_NAME "${PURE_CLANG64_PREFIX}" NAME)
    if(NOT PURE_CLANG64_PREFIX_NAME STREQUAL "clang64")
      message(FATAL_ERROR
        "The Windows release compiler must come from an MSYS2 CLANG64 prefix; found ${CMAKE_C_COMPILER}"
      )
    endif()
    pure_require_clang64_path("${CMAKE_C_COMPILER}" "C compiler")
    pure_require_clang64_path("${CMAKE_CXX_COMPILER}" "C++ compiler")
    pure_require_clang64_path("${LLVM_DIR}" "LLVM package")
  endif()
endif()

if(PURE_SANITIZERS)
  if(NOT CMAKE_C_COMPILER_ID STREQUAL "Clang" OR
     NOT CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    message(FATAL_ERROR "PURE_SANITIZERS requires Clang for C and C++")
  endif()

  add_compile_options(
    "-fsanitize=${PURE_SANITIZERS}"
    -fno-omit-frame-pointer
  )
  add_link_options("-fsanitize=${PURE_SANITIZERS}")
endif()

if(PURE_DEBUG_FRIENDLY)
  if(NOT PURE_SANITIZERS)
    add_compile_options(
      "$<$<AND:$<CONFIG:Debug>,$<COMPILE_LANG_AND_ID:C,Clang>>:-fno-omit-frame-pointer>"
      "$<$<AND:$<CONFIG:Debug>,$<COMPILE_LANG_AND_ID:CXX,Clang>>:-fno-omit-frame-pointer>"
    )
  endif()

  add_compile_options(
    "$<$<AND:$<CONFIG:Debug>,$<COMPILE_LANG_AND_ID:C,Clang>>:-fno-optimize-sibling-calls>"
    "$<$<AND:$<CONFIG:Debug>,$<COMPILE_LANG_AND_ID:C,Clang>>:-fstandalone-debug>"
    "$<$<AND:$<CONFIG:Debug>,$<COMPILE_LANG_AND_ID:C,Clang>>:-gdwarf-4>"
    "$<$<AND:$<CONFIG:Debug>,$<COMPILE_LANG_AND_ID:CXX,Clang>>:-fno-optimize-sibling-calls>"
    "$<$<AND:$<CONFIG:Debug>,$<COMPILE_LANG_AND_ID:CXX,Clang>>:-fstandalone-debug>"
    "$<$<AND:$<CONFIG:Debug>,$<COMPILE_LANG_AND_ID:CXX,Clang>>:-gdwarf-4>"
  )
endif()

message(STATUS "C compiler: ${CMAKE_C_COMPILER_ID} ${CMAKE_C_COMPILER_VERSION}")
message(STATUS "C compiler target: ${PURE_HOST_TRIPLE}")
message(STATUS "C++ compiler: ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}")
if(PURE_CXX_COMPILER_TRIPLE)
  message(STATUS "C++ compiler target: ${PURE_CXX_COMPILER_TRIPLE}")
endif()
message(STATUS "LLVM: ${LLVM_PACKAGE_VERSION} (${LLVM_DIR})")
message(STATUS "LLVM host target: ${LLVM_HOST_TRIPLE}")
