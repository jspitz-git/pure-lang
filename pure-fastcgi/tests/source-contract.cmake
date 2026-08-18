include("${SOURCE_DIR}/cmake/Fcgi2Dependency.cmake")

if(NOT PURE_FASTCGI_FCGI2_COMMIT STREQUAL
    "47f2c03b7771f0ef61d887734ef91e6fa747f837")
  message(FATAL_ERROR "unexpected fcgi2 commit")
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

file(MAKE_DIRECTORY "${TEST_ROOT}")
file(READ "${FCGI2_ARCHIVE}" bytes HEX)
string(SUBSTRING "${bytes}" 2 -1 tail)
file(WRITE "${TEST_ROOT}/mutated.tar.gz" "00${tail}")
execute_process(
  COMMAND "${CMAKE_COMMAND}"
    -DSOURCE_DIR=${SOURCE_DIR}
    -DARCHIVE=${TEST_ROOT}/mutated.tar.gz
    -P "${SOURCE_DIR}/tests/verify-one-archive.cmake"
  RESULT_VARIABLE result ERROR_VARIABLE error)
if(result EQUAL 0 OR NOT error MATCHES "fcgi2 archive (size|SHA-256) mismatch")
  message(FATAL_ERROR "mutated fcgi2 archive was not rejected: ${error}")
endif()
