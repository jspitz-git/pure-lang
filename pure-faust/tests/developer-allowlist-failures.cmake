foreach(required IN ITEMS SOURCE_DIR STAGE_PREFIX)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

function(expect_rejection expected)
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${SOURCE_DIR}"
      "-DSTAGE_PREFIX=${STAGE_PREFIX}"
      -DEXPECT_DEVELOPER=ON
      -P "${SOURCE_DIR}/cmake/VerifyInstalledPackage.cmake"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8)
  if(result EQUAL 0 OR NOT error MATCHES "${expected}")
    message(FATAL_ERROR
      "Expected rejection '${expected}'\nstdout:\n${output}\nstderr:\n${error}")
  endif()
endfunction()

set(pure_c "${STAGE_PREFIX}/share/pure-faust/pure.c")
file(READ "${pure_c}" original_pure_c)
file(APPEND "${pure_c}" "mutation")
expect_rejection("allowlist hash mismatch")
file(WRITE "${pure_c}" "${original_pure_c}")

set(unexpected "${STAGE_PREFIX}/share/pure-faust/unexpected.txt")
file(WRITE "${unexpected}" "undeclared mutation\n")
expect_rejection("Unexpected pure-faust runtime inventory")
file(REMOVE "${unexpected}")

message(STATUS "Developer allowlist hash and undeclared-file mutations rejected")
