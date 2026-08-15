foreach(required IN ITEMS SOURCE_DIR STAGE_PREFIX AUTHORITATIVE_MANIFEST)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

function(expect_rejection expected)
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${SOURCE_DIR}"
      "-DAUTHORITATIVE_MANIFEST=${AUTHORITATIVE_MANIFEST}"
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
set(installed_manifest
  "${STAGE_PREFIX}/share/doc/pure-faust/FaustDeveloper-ALLOWLIST.sha256")
file(READ "${installed_manifest}" original_manifest)
file(SHA256 "${unexpected}" unexpected_sha256)
string(TOLOWER "${unexpected_sha256}" unexpected_sha256)
file(APPEND "${installed_manifest}"
  "${unexpected_sha256}  share/pure-faust/unexpected.txt\n")
expect_rejection("differs from authoritative closure")
file(WRITE "${installed_manifest}" "${original_manifest}")
file(REMOVE "${unexpected}")

message(STATUS
  "Developer hash and jointly forged file/manifest mutations rejected")
