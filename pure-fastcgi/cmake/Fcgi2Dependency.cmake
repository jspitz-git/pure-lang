set(PURE_FASTCGI_FCGI2_VERSION "2.4.7")
set(PURE_FASTCGI_FCGI2_COMMIT
  "47f2c03b7771f0ef61d887734ef91e6fa747f837")
set(PURE_FASTCGI_FCGI2_URL
  "https://github.com/FastCGI-Archives/fcgi2/archive/refs/tags/2.4.7.tar.gz")
set(PURE_FASTCGI_FCGI2_ARCHIVE_SIZE "263969")
set(PURE_FASTCGI_FCGI2_ARCHIVE_SHA256
  "e41ddc3a473b555bdc0cbd80703dcb1f4610c1a7700d3b9d3d0c14a416e1074b")
set(PURE_FASTCGI_FCGI2_PATCH
  "${CMAKE_CURRENT_LIST_DIR}/../patches/fcgi2-2.4.7-clang64-types.patch")
set(PURE_FASTCGI_FCGI2_PATCH_SHA256
  "a95286e560aba3733a74929d0057168a605efcdc112beef2eccc31cf55854f7f")

function(pure_fastcgi_prepare_fcgi2)
  cmake_parse_arguments(PARSE_ARGV 0 arg "" "ARCHIVE;OUT_SOURCE_DIR" "")
  if(NOT IS_ABSOLUTE "${arg_ARCHIVE}" OR NOT EXISTS "${arg_ARCHIVE}")
    message(FATAL_ERROR "PURE_FASTCGI_FCGI2_ARCHIVE must name an existing absolute file")
  endif()

  file(SIZE "${arg_ARCHIVE}" actual_size)
  file(SHA256 "${arg_ARCHIVE}" actual_sha256)
  if(NOT actual_size EQUAL PURE_FASTCGI_FCGI2_ARCHIVE_SIZE)
    message(FATAL_ERROR "fcgi2 archive size mismatch")
  endif()
  if(NOT actual_sha256 STREQUAL PURE_FASTCGI_FCGI2_ARCHIVE_SHA256)
    message(FATAL_ERROR "fcgi2 archive SHA-256 mismatch")
  endif()

  set(root "${CMAKE_CURRENT_BINARY_DIR}/_deps/fcgi2-2.4.7")
  file(REMOVE_RECURSE "${root}")
  file(MAKE_DIRECTORY "${root}")
  file(ARCHIVE_EXTRACT INPUT "${arg_ARCHIVE}" DESTINATION "${root}")
  set(source "${root}/fcgi2-2.4.7")
  set(wsaa_accept_source
    "        hSock = WSAAccept((unsigned int) hListen,                    \n")
  set(wsaa_accept_normalized
    "        hSock = WSAAccept((unsigned int) hListen,\n")
  file(READ "${source}/libfcgi/os_win32.c" os_win32_source)
  string(FIND "${os_win32_source}" "${wsaa_accept_source}" wsaa_accept_index)
  if(wsaa_accept_index EQUAL -1)
    message(FATAL_ERROR "unexpected fcgi2 WSAAccept source line")
  endif()
  string(REPLACE "${wsaa_accept_source}" "${wsaa_accept_normalized}"
    os_win32_source "${os_win32_source}")
  file(WRITE "${source}/libfcgi/os_win32.c" "${os_win32_source}")
  if(NOT EXISTS "${PURE_FASTCGI_FCGI2_PATCH}")
    message(FATAL_ERROR "fcgi2 Windows patch is missing")
  endif()
  file(SHA256 "${PURE_FASTCGI_FCGI2_PATCH}" actual_patch_sha256)
  if(NOT actual_patch_sha256 STREQUAL PURE_FASTCGI_FCGI2_PATCH_SHA256)
    message(FATAL_ERROR "fcgi2 Windows patch SHA-256 mismatch")
  endif()
  if(NOT DEFINED PATCH_EXECUTABLE
      OR NOT IS_ABSOLUTE "${PATCH_EXECUTABLE}"
      OR NOT EXISTS "${PATCH_EXECUTABLE}"
      OR IS_DIRECTORY "${PATCH_EXECUTABLE}")
    message(FATAL_ERROR
      "PATCH_EXECUTABLE must name an existing absolute file")
  endif()
  execute_process(
    COMMAND "${PATCH_EXECUTABLE}" --batch --forward -p1
      -i "${PURE_FASTCGI_FCGI2_PATCH}"
    WORKING_DIRECTORY "${source}"
    RESULT_VARIABLE patch_result
    OUTPUT_VARIABLE patch_output
    ERROR_VARIABLE patch_error)
  if(NOT patch_result EQUAL 0)
    message(FATAL_ERROR "fcgi2 Windows patch failed: ${patch_output}${patch_error}")
  endif()
  file(COPY_FILE "${source}/include/fcgi_config_x86.h"
    "${source}/include/fcgi_config.h" ONLY_IF_DIFFERENT)
  set(${arg_OUT_SOURCE_DIR} "${source}" PARENT_SCOPE)
endfunction()

function(pure_fastcgi_add_fcgi2_target)
  cmake_parse_arguments(PARSE_ARGV 0 arg "" "SOURCE_DIR" "")
  if(NOT IS_DIRECTORY "${arg_SOURCE_DIR}")
    message(FATAL_ERROR "SOURCE_DIR must name an existing fcgi2 source directory")
  endif()

  add_library(fcgi2-static STATIC
    "${arg_SOURCE_DIR}/libfcgi/fcgi_stdio.c"
    "${arg_SOURCE_DIR}/libfcgi/fcgiapp.c"
    "${arg_SOURCE_DIR}/libfcgi/os_win32.c")
  target_include_directories(fcgi2-static PUBLIC "${arg_SOURCE_DIR}/include")
  target_compile_definitions(fcgi2-static PRIVATE DLLAPI=)
  target_compile_features(fcgi2-static PRIVATE c_std_11)
  target_link_libraries(fcgi2-static PUBLIC ws2_32)
endfunction()
