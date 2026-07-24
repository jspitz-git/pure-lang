include_guard(GLOBAL)

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
endif()

find_package(LLVM REQUIRED CONFIG)

if(LLVM_PACKAGE_VERSION VERSION_LESS 22
   OR LLVM_PACKAGE_VERSION VERSION_GREATER_EQUAL 23)
  message(FATAL_ERROR
    "Pure requires LLVM 22.x; found LLVM ${LLVM_PACKAGE_VERSION}"
  )
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
message(STATUS "C++ compiler: ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}")
message(STATUS "LLVM: ${LLVM_PACKAGE_VERSION} (${LLVM_DIR})")
