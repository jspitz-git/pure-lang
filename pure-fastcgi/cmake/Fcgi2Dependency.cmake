set(PURE_FASTCGI_FCGI2_VERSION "2.4.7")
set(PURE_FASTCGI_FCGI2_COMMIT
  "47f2c03b7771f0ef61d887734ef91e6fa747f837")
set(PURE_FASTCGI_FCGI2_URL
  "https://github.com/FastCGI-Archives/fcgi2/archive/refs/tags/2.4.7.tar.gz")
set(PURE_FASTCGI_FCGI2_ARCHIVE_SIZE "263969")
set(PURE_FASTCGI_FCGI2_ARCHIVE_SHA256
  "e41ddc3a473b555bdc0cbd80703dcb1f4610c1a7700d3b9d3d0c14a416e1074b")

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
  set(${arg_OUT_SOURCE_DIR} "${source}" PARENT_SCOPE)
endfunction()
