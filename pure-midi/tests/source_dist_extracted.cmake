cmake_minimum_required(VERSION 3.25)
foreach(required SOURCE_DIR CLANG64_PREFIX PURE_PREFIX DIST_ROOT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "extracted source contract requires ${required}")
  endif()
endforeach()
execute_process(COMMAND "${CLANG64_PREFIX}/bin/mingw32-make.exe"
  -C "${SOURCE_DIR}" distcheck "CMAKE=${CMAKE_COMMAND}"
  "CLANG64_PREFIX=${CLANG64_PREFIX}" "PURE_PREFIX=${PURE_PREFIX}"
  "DIST_ROOT=${DIST_ROOT}" "DIST_DIR=${CMAKE_CURRENT_BINARY_DIR}" "DLL=.dll"
  "SHELL=${CLANG64_PREFIX}/../usr/bin/sh.exe" RESULT_VARIABLE rc)
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "public extracted source workflow failed (${rc})")
endif()
