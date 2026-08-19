cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS MODE PURE_PREFIX TOOLCHAIN_BIN)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "SDK_RUNTIME_INPUT: ${required} is required")
  endif()
endforeach()
if(NOT MODE STREQUAL "STAGE" AND NOT MODE STREQUAL "VERIFY")
  message(FATAL_ERROR "SDK_RUNTIME_INPUT: MODE must be STAGE or VERIFY")
endif()

# This is the single authoritative allowlist for the recursive non-system DLL
# closure of the CLANG64 Pure runtime. The later PureBonjour PE audit verifies
# that this remains the complete closure whenever Pure's link inputs change.
set(pure_windows_runtime_dlls
  libc++.dll
  libgmp-10.dll
  libiconv-2.dll
  libmpfr-6.dll
  libpcre-1.dll
  libpcreposix-0.dll
  libreadline8.dll
  libtermcap-0.dll
  libwinpthread-1.dll
  libzstd.dll
  zlib1.dll)

file(REAL_PATH "${TOOLCHAIN_BIN}" toolchain_bin)
if(NOT IS_DIRECTORY "${toolchain_bin}")
  message(FATAL_ERROR
    "SDK_RUNTIME_SOURCE: TOOLCHAIN_BIN is not a directory: ${toolchain_bin}")
endif()
file(REAL_PATH "${PURE_PREFIX}" pure_prefix)
set(destination_bin "${pure_prefix}/bin")
if(NOT IS_DIRECTORY "${destination_bin}")
  message(FATAL_ERROR
    "SDK_RUNTIME_DESTINATION: Pure bin directory is missing: ${destination_bin}")
endif()

set(casefolded_names)
foreach(dll IN LISTS pure_windows_runtime_dlls)
  string(TOLOWER "${dll}" casefolded)
  if(casefolded IN_LIST casefolded_names)
    message(FATAL_ERROR "SDK_RUNTIME_DUPLICATE: duplicate allowlist name ${dll}")
  endif()
  list(APPEND casefolded_names "${casefolded}")

  set(source "${toolchain_bin}/${dll}")
  if(NOT EXISTS "${source}" OR IS_DIRECTORY "${source}")
    message(FATAL_ERROR "SDK_RUNTIME_SOURCE: required DLL is missing: ${dll}")
  endif()
  file(REAL_PATH "${source}" resolved_source)
  cmake_path(GET resolved_source PARENT_PATH resolved_parent)
  if(NOT resolved_parent STREQUAL toolchain_bin)
    message(FATAL_ERROR
      "SDK_RUNTIME_ESCAPE: ${dll} resolves outside TOOLCHAIN_BIN")
  endif()
  file(READ "${resolved_source}" pe_magic OFFSET 0 LIMIT 2 HEX)
  string(TOLOWER "${pe_magic}" pe_magic)
  if(NOT pe_magic STREQUAL "4d5a")
    message(FATAL_ERROR "SDK_RUNTIME_FORMAT: ${dll} lacks the PE MZ signature")
  endif()

  set(destination "${destination_bin}/${dll}")
  if(MODE STREQUAL "STAGE")
    execute_process(
      COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${resolved_source}" "${destination}"
      RESULT_VARIABLE copy_result ERROR_VARIABLE copy_error)
    if(NOT copy_result EQUAL 0)
      message(FATAL_ERROR
        "SDK_RUNTIME_COPY: failed to stage ${dll}: ${copy_error}")
    endif()
  endif()
  if(NOT EXISTS "${destination}" OR IS_DIRECTORY "${destination}")
    message(FATAL_ERROR "SDK_RUNTIME_MISSING: staged DLL is missing: ${dll}")
  endif()
  file(SHA256 "${resolved_source}" source_hash)
  file(SHA256 "${destination}" destination_hash)
  if(NOT destination_hash STREQUAL source_hash)
    message(FATAL_ERROR "SDK_RUNTIME_HASH: staged DLL differs: ${dll}")
  endif()
endforeach()

list(LENGTH pure_windows_runtime_dlls runtime_dll_count)
message(STATUS
  "Pure Windows SDK runtime closure ${MODE}: ${runtime_dll_count} exact DLLs")
