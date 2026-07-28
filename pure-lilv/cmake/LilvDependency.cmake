include(ExternalProject)

set(LILV_VERSION "0.26.4")
set(LILV_ARCHIVE_URL
  "https://download.drobilla.net/lilv-${LILV_VERSION}.tar.xz")
set(LILV_ARCHIVE_SHA256
  "1c8b5fcb78718173e67d76e51ad423f5113a9ff68463f2566195ae46396089e3")
set(LILV_PREFIX "${CMAKE_CURRENT_BINARY_DIR}/lilv-prefix")
set(LILV_INCLUDE_DIR "${LILV_PREFIX}/include/lilv-0")
set(LILV_RUNTIME_DLL "${LILV_PREFIX}/bin/liblilv-0.dll")
set(LILV_IMPORT_LIBRARY "${LILV_PREFIX}/lib/liblilv-0.dll.a")
file(MAKE_DIRECTORY "${LILV_INCLUDE_DIR}")

find_program(MESON_EXECUTABLE NAMES meson REQUIRED)

ExternalProject_Add(lilv-external
  URL "${LILV_ARCHIVE_URL}"
  URL_HASH "SHA256=${LILV_ARCHIVE_SHA256}"
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  PATCH_COMMAND
    "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=<SOURCE_DIR>"
      -P "${CMAKE_CURRENT_LIST_DIR}/PatchLilv.cmake"
  CONFIGURE_COMMAND
    "${MESON_EXECUTABLE}" setup <BINARY_DIR> <SOURCE_DIR>
      "--prefix=${LILV_PREFIX}"
      --buildtype=release
      --wrap-mode=nodownload
      -Ddynmanifest=enabled
      -Dtools=disabled
      -Dbindings_py=disabled
      -Dbindings_cpp=disabled
      -Ddocs=disabled
      -Dtests=disabled
  BUILD_COMMAND "${MESON_EXECUTABLE}" compile -C <BINARY_DIR>
  INSTALL_COMMAND "${MESON_EXECUTABLE}" install -C <BINARY_DIR>
  BUILD_BYPRODUCTS
    "${LILV_RUNTIME_DLL}"
    "${LILV_IMPORT_LIBRARY}")

ExternalProject_Get_Property(lilv-external SOURCE_DIR)
set(LILV_LICENSE_FILE "${SOURCE_DIR}/COPYING")

add_library(Lilv::lilv SHARED IMPORTED GLOBAL)
set_target_properties(Lilv::lilv PROPERTIES
  IMPORTED_LOCATION "${LILV_RUNTIME_DLL}"
  IMPORTED_IMPLIB "${LILV_IMPORT_LIBRARY}"
  INTERFACE_INCLUDE_DIRECTORIES "${LILV_INCLUDE_DIR}")
add_dependencies(Lilv::lilv lilv-external)

function(find_runtime_dll output prefix filename)
  find_file(found_runtime_dll
    NAMES "${filename}"
    HINTS "${prefix}/bin"
    NO_DEFAULT_PATH
    REQUIRED)
  set(${output} "${found_runtime_dll}" PARENT_SCOPE)
  unset(found_runtime_dll CACHE)
endfunction()

find_runtime_dll(SERD_RUNTIME_DLL "${SERD_PREFIX}" "libserd-0.dll")
find_runtime_dll(SORD_RUNTIME_DLL "${SORD_PREFIX}" "libsord-0.dll")
find_runtime_dll(SRATOM_RUNTIME_DLL "${SRATOM_PREFIX}" "libsratom-0.dll")
find_runtime_dll(ZIX_RUNTIME_DLL "${ZIX_PREFIX}" "libzix-0.dll")
