cmake_minimum_required(VERSION 3.25)

if(DEFINED PURE_FASTCGI_GENERATE_ORACLES)
  foreach(required IN ITEMS
      PURE_FASTCGI_MODULE
      PURE_FASTCGI_MODULE_SOURCE
      PURE_FASTCGI_README
      PURE_FASTCGI_THIRD_PARTY
      PURE_FASTCGI_FCGI2_LICENSE
      PURE_FASTCGI_BINARY_DIR)
    if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
      message(FATAL_ERROR "${required} is required for package oracle generation")
    endif()
  endforeach()

  set(records)
  function(pure_fastcgi_record relative source purpose origin version)
    if(NOT EXISTS "${source}" OR IS_DIRECTORY "${source}")
      message(FATAL_ERROR "package input does not exist: ${source}")
    endif()
    list(APPEND records
      "${relative}|${source}|${purpose}|${origin}|${version}")
    set(records "${records}" PARENT_SCOPE)
  endfunction()

  pure_fastcgi_record(
    "lib/pure/fastcgi.dll" "${PURE_FASTCGI_MODULE}"
    "Pure FastCGI native module with statically linked fcgi2"
    "pure-fastcgi and FastCGI-Archives/fcgi2 sources"
    "pure-fastcgi-0.6+fcgi2-2.4.7@47f2c03b7771f0ef61d887734ef91e6fa747f837")
  pure_fastcgi_record(
    "lib/pure/fastcgi.pure" "${PURE_FASTCGI_MODULE_SOURCE}"
    "Pure language declarations for the FastCGI module"
    "pure-fastcgi source distribution" "0.6")
  pure_fastcgi_record(
    "share/doc/pure-fastcgi/LICENSE.fcgi2" "${PURE_FASTCGI_FCGI2_LICENSE}"
    "Verbatim licence for the embedded fcgi2 sources"
    "FastCGI-Archives/fcgi2 LICENSE"
    "47f2c03b7771f0ef61d887734ef91e6fa747f837")
  pure_fastcgi_record(
    "share/doc/pure-fastcgi/README" "${PURE_FASTCGI_README}"
    "PureFastCGI user documentation"
    "pure-fastcgi source distribution" "0.6")
  pure_fastcgi_record(
    "share/doc/pure-fastcgi/THIRD_PARTY.md" "${PURE_FASTCGI_THIRD_PARTY}"
    "Pinned third-party provenance and obligations"
    "pure-fastcgi package metadata" "0.6")

  list(SORT records COMPARE STRING CASE SENSITIVE ORDER ASCENDING)
  set(inventory "${PURE_FASTCGI_BINARY_DIR}/PureFastCGIInventory.tsv")
  file(WRITE "${inventory}"
    "relative_path\tpurpose\torigin\tversion_or_commit\tsha256\tsize\n")
  foreach(record IN LISTS records)
    string(REPLACE "|" ";" fields "${record}")
    list(GET fields 0 relative)
    list(GET fields 1 source)
    list(GET fields 2 purpose)
    list(GET fields 3 origin)
    list(GET fields 4 version)
    file(SHA256 "${source}" sha256)
    string(TOLOWER "${sha256}" sha256)
    file(SIZE "${source}" size)
    file(APPEND "${inventory}"
      "${relative}\t${purpose}\t${origin}\t${version}\t${sha256}\t${size}\n")
  endforeach()

  list(APPEND records
    "share/doc/pure-fastcgi/PureFastCGIInventory.tsv|${inventory}|")
  list(SORT records COMPARE STRING CASE SENSITIVE ORDER ASCENDING)
  set(manifest "${PURE_FASTCGI_BINARY_DIR}/PureFastCGIExpected.sha256")
  file(WRITE "${manifest}" "")
  foreach(record IN LISTS records)
    string(REPLACE "|" ";" fields "${record}")
    list(GET fields 0 relative)
    list(GET fields 1 source)
    file(SHA256 "${source}" sha256)
    string(TOLOWER "${sha256}" sha256)
    file(APPEND "${manifest}" "${sha256}  ${relative}\n")
  endforeach()
  return()
endif()

set(pure_fastcgi_inventory
  "${CMAKE_CURRENT_BINARY_DIR}/PureFastCGIInventory.tsv")
set(pure_fastcgi_manifest
  "${CMAKE_CURRENT_BINARY_DIR}/PureFastCGIExpected.sha256")
set(pure_fastcgi_fcgi2_license "${fcgi2_source}/LICENSE")

add_custom_command(
  OUTPUT "${pure_fastcgi_inventory}" "${pure_fastcgi_manifest}"
  COMMAND "${CMAKE_COMMAND}"
    -DPURE_FASTCGI_GENERATE_ORACLES=ON
    "-DPURE_FASTCGI_MODULE=$<TARGET_FILE:pure-fastcgi>"
    "-DPURE_FASTCGI_MODULE_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}/fastcgi.pure"
    "-DPURE_FASTCGI_README=${CMAKE_CURRENT_SOURCE_DIR}/README"
    "-DPURE_FASTCGI_THIRD_PARTY=${CMAKE_CURRENT_SOURCE_DIR}/THIRD_PARTY.md"
    "-DPURE_FASTCGI_FCGI2_LICENSE=${pure_fastcgi_fcgi2_license}"
    "-DPURE_FASTCGI_BINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
    -P "${CMAKE_CURRENT_LIST_FILE}"
  DEPENDS
    pure-fastcgi
    "${CMAKE_CURRENT_SOURCE_DIR}/fastcgi.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/README"
    "${CMAKE_CURRENT_SOURCE_DIR}/THIRD_PARTY.md"
    "${pure_fastcgi_fcgi2_license}"
    "${CMAKE_CURRENT_LIST_FILE}"
  COMMENT "Generating authoritative PureFastCGI package oracles"
  VERBATIM)
add_custom_target(pure-fastcgi-package-oracles ALL
  DEPENDS "${pure_fastcgi_inventory}" "${pure_fastcgi_manifest}")

install(TARGETS pure-fastcgi
  LIBRARY DESTINATION lib/pure
  COMPONENT PureFastCGI
  EXCLUDE_FROM_ALL)
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/fastcgi.pure"
  DESTINATION lib/pure
  COMPONENT PureFastCGI
  EXCLUDE_FROM_ALL)
install(FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/README"
    "${CMAKE_CURRENT_SOURCE_DIR}/THIRD_PARTY.md"
  DESTINATION share/doc/pure-fastcgi
  COMPONENT PureFastCGI
  EXCLUDE_FROM_ALL)
install(FILES "${pure_fastcgi_fcgi2_license}"
  DESTINATION share/doc/pure-fastcgi
  RENAME LICENSE.fcgi2
  COMPONENT PureFastCGI
  EXCLUDE_FROM_ALL)
install(FILES "${pure_fastcgi_inventory}"
  DESTINATION share/doc/pure-fastcgi
  COMPONENT PureFastCGI
  EXCLUDE_FROM_ALL)
