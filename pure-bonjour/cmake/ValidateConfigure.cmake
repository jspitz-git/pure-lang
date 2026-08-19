cmake_minimum_required(VERSION 3.25)

function(pure_bonjour_validate_target)
  include(CheckCSourceCompiles)
  unset(PURE_BONJOUR_TARGET_IS_WINDOWS_X64 CACHE)
  check_c_source_compiles([[#if !defined(_WIN32)
#error PureBonjour requires Windows
#endif
#if (!defined(__x86_64__) && !defined(_M_X64))
#error PureBonjour requires x86-64
#endif
#if defined(__aarch64__) || defined(_M_ARM64)
#error PureBonjour requires Windows x86-64
#endif
int main(void) { return 0; }
]] PURE_BONJOUR_TARGET_IS_WINDOWS_X64)
  if(NOT PURE_BONJOUR_TARGET_IS_WINDOWS_X64)
    message(FATAL_ERROR "PureBonjour requires the configured target to be Windows x86-64")
  endif()
endfunction()

function(pure_bonjour_validate_configure prefix include_dirs libraries)
  if(NOT IS_ABSOLUTE "${prefix}" OR NOT IS_DIRECTORY "${prefix}")
    message(FATAL_ERROR "PURE_PREFIX must be an absolute existing directory")
  endif()
  file(REAL_PATH "${prefix}" canonical_prefix)
  foreach(path IN LISTS include_dirs libraries)
    if(NOT IS_ABSOLUTE "${path}" OR NOT EXISTS "${path}")
      message(FATAL_ERROR "Pure pkg-config path does not exist: '${path}'")
    endif()
    file(REAL_PATH "${path}" canonical_path)
    cmake_path(IS_PREFIX canonical_prefix "${canonical_path}" NORMALIZE beneath)
    if(NOT beneath)
      message(FATAL_ERROR
        "Pure pkg-config path escapes canonical PURE_PREFIX: '${path}'")
    endif()
  endforeach()
endfunction()

if(DEFINED TEST_PREFIX)
  pure_bonjour_validate_configure("${TEST_PREFIX}" "${TEST_INCLUDE}"
    "${TEST_LIBRARY}")
endif()
