cmake_minimum_required(VERSION 3.25)
foreach(required IN ITEMS SOURCE_DIR FCGI2_ARCHIVE TEST_ROOT)
  if(NOT DEFINED ${required})
    message(FATAL_ERROR "FETCH_ENTRY_TEST_INPUT: ${required} is required")
  endif()
endforeach()
file(REMOVE_RECURSE "${TEST_ROOT}")
file(MAKE_DIRECTORY "${TEST_ROOT}")
set(output "${TEST_ROOT}/created/fcgi2-2.4.7.tar.gz")
file(MAKE_DIRECTORY "${TEST_ROOT}/created")
# A verified completed .part exercises the same atomic entry point without
# making ordinary contract tests depend on the network.
file(COPY_FILE "${FCGI2_ARCHIVE}" "${output}.part")
execute_process(COMMAND "${CMAKE_COMMAND}" "-DOUTPUT=${output}"
    -P "${SOURCE_DIR}/cmake/FetchFcgi2Entry.cmake"
  RESULT_VARIABLE result OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT result EQUAL 0 OR NOT EXISTS "${output}" OR EXISTS "${output}.part")
  message(FATAL_ERROR "FETCH_ENTRY_CREATE: entry did not create output\n${out}\n${err}")
endif()
file(SIZE "${output}" size)
file(SHA256 "${output}" sha)
if(NOT size EQUAL 263969 OR NOT sha STREQUAL
    "e41ddc3a473b555bdc0cbd80703dcb1f4610c1a7700d3b9d3d0c14a416e1074b")
  message(FATAL_ERROR "FETCH_ENTRY_IDENTITY: created archive was not verified")
endif()
file(APPEND "${output}" "x")
execute_process(COMMAND "${CMAKE_COMMAND}" "-DOUTPUT=${output}"
    -P "${SOURCE_DIR}/cmake/FetchFcgi2Entry.cmake"
  RESULT_VARIABLE bad_result ERROR_VARIABLE bad_error)
if(bad_result EQUAL 0 OR NOT bad_error MATCHES "refusing to overwrite")
  message(FATAL_ERROR "FETCH_ENTRY_MUTATION: mismatching output was accepted")
endif()
