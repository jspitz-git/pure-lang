include("${SOURCE_DIR}/cmake/Fcgi2Dependency.cmake")

if(NOT PURE_FASTCGI_FCGI2_COMMIT STREQUAL
    "47f2c03b7771f0ef61d887734ef91e6fa747f837")
  message(FATAL_ERROR "unexpected fcgi2 commit")
endif()

set(fcgi2_patch
  "${SOURCE_DIR}/patches/fcgi2-2.4.7-clang64-types.patch")
if(NOT EXISTS "${fcgi2_patch}")
  message(FATAL_ERROR "missing fcgi2 Windows patch")
endif()
file(SHA256 "${fcgi2_patch}" fcgi2_patch_sha256)
if(NOT fcgi2_patch_sha256 STREQUAL PURE_FASTCGI_FCGI2_PATCH_SHA256)
  message(FATAL_ERROR "fcgi2 Windows patch SHA-256 mismatch")
endif()

# The dependency helper must never discover an arbitrary patch.exe from PATH.
# A caller that omits the explicit tool must fail before patch application.
execute_process(
  COMMAND "${CMAKE_COMMAND}"
    -DSOURCE_DIR=${SOURCE_DIR}
    -DARCHIVE=${FCGI2_ARCHIVE}
    -P "${SOURCE_DIR}/tests/verify-one-archive.cmake"
  RESULT_VARIABLE missing_patch_result
  ERROR_VARIABLE missing_patch_error)
if(missing_patch_result EQUAL 0 OR NOT missing_patch_error MATCHES
    "PATCH_EXECUTABLE must name an existing absolute file")
  message(FATAL_ERROR
    "implicit/arbitrary patch discovery was not rejected: ${missing_patch_error}")
endif()

pure_fastcgi_prepare_fcgi2(
  ARCHIVE "${FCGI2_ARCHIVE}"
  OUT_SOURCE_DIR extracted)

foreach(required IN ITEMS include/fcgi_stdio.h libfcgi/fcgi_stdio.c
    libfcgi/fcgiapp.c libfcgi/os_win32.c LICENSE)
  if(NOT EXISTS "${extracted}/${required}")
    message(FATAL_ERROR "missing extracted fcgi2 input: ${required}")
  endif()
endforeach()

file(READ "${extracted}/libfcgi/os_win32.c" patched_os_win32)
foreach(required_patch IN ITEMS
    "ULONG_PTR fd;"
    "DWORD_PTR data"
    "\\(DWORD_PTR\\) webServerAddrs")
  if(NOT patched_os_win32 MATCHES "${required_patch}")
    message(FATAL_ERROR "fcgi2 Windows patch was not applied: ${required_patch}")
  endif()
endforeach()

file(MAKE_DIRECTORY "${TEST_ROOT}")
file(SIZE "${FCGI2_ARCHIVE}" original_size)
set(mutated_archive "${TEST_ROOT}/mutated.tar.gz")
file(COPY_FILE "${FCGI2_ARCHIVE}" "${mutated_archive}")
find_program(POWERSHELL_EXECUTABLE NAMES powershell.exe powershell REQUIRED)
execute_process(
  COMMAND "${POWERSHELL_EXECUTABLE}" -NoProfile -NonInteractive -Command
    "$bytes = [System.IO.File]::ReadAllBytes('${mutated_archive}')\n$bytes[0] = $bytes[0] -bxor 1\n[System.IO.File]::WriteAllBytes('${mutated_archive}', $bytes)"
  RESULT_VARIABLE mutate_result ERROR_VARIABLE mutate_error)
if(NOT mutate_result EQUAL 0)
  message(FATAL_ERROR "could not mutate fcgi2 archive: ${mutate_error}")
endif()
file(SIZE "${TEST_ROOT}/mutated.tar.gz" mutated_size)
if(NOT original_size EQUAL mutated_size)
  message(FATAL_ERROR "mutated fcgi2 archive changed size")
endif()
execute_process(
  COMMAND "${CMAKE_COMMAND}"
    -DSOURCE_DIR=${SOURCE_DIR}
    -DARCHIVE=${mutated_archive}
    -P "${SOURCE_DIR}/tests/verify-one-archive.cmake"
  RESULT_VARIABLE result ERROR_VARIABLE error)
if(result EQUAL 0 OR NOT error MATCHES "fcgi2 archive SHA-256 mismatch")
  message(FATAL_ERROR "mutated fcgi2 archive was not rejected: ${error}")
endif()
