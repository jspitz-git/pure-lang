set(PURE_LIBRARY_INSTALL_DIR "lib/pure" CACHE STRING
  "Relative install directory for Pure modules")
set(PURE_RUNTIME_INSTALL_DIR "bin" CACHE STRING
  "Relative install directory for bundled runtime DLLs")
set(PURE_DOCUMENTATION_INSTALL_DIR "share/doc/${PROJECT_NAME}" CACHE STRING
  "Relative install directory for package documentation")
set(PURE_EXAMPLES_INSTALL_DIR "${PURE_DOCUMENTATION_INSTALL_DIR}/examples"
  CACHE STRING "Relative install directory for package examples")

foreach(destination_var IN ITEMS
    PURE_LIBRARY_INSTALL_DIR
    PURE_RUNTIME_INSTALL_DIR
    PURE_DOCUMENTATION_INSTALL_DIR
    PURE_EXAMPLES_INSTALL_DIR)
  set(destination "${${destination_var}}")
  if(IS_ABSOLUTE "${destination}" OR
      destination MATCHES "(^|[/\\\\])\\.\\.([/\\\\]|$)")
    message(FATAL_ERROR
      "${destination_var} must remain within the installation prefix: ${destination}")
  endif()
endforeach()

set(version "${PROJECT_VERSION}")
string(TIMESTAMP today "%B %d, %Y")
configure_file(
  "${CMAKE_CURRENT_SOURCE_DIR}/README"
  "${CMAKE_CURRENT_BINARY_DIR}/README"
  @ONLY
  NEWLINE_STYLE UNIX
)
file(READ "${CMAKE_CURRENT_BINARY_DIR}/README" readme)
string(REPLACE "|today|" "${today}" readme "${readme}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/README" "${readme}")

install(
  TARGETS gtk glib atk cairo pango
  RUNTIME_DEPENDENCY_SET pure_gtk_runtime_dependencies
  RUNTIME DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  LIBRARY DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime
)
install(
  FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/gtk.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/glib.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/atk.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/cairo.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/pango.pure"
  DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime
)

if(WIN32)
  pkg_get_variable(PURE_PREFIX pure prefix)
  install(
    RUNTIME_DEPENDENCY_SET pure_gtk_runtime_dependencies
    DIRECTORIES
      "${GTK2_PREFIX}/bin"
      "${PURE_PREFIX}/bin"
    PRE_EXCLUDE_REGEXES
      "^api-ms-win-.*"
      "^ext-ms-.*"
    POST_EXCLUDE_REGEXES
      ".*[/\\\\][Ww][Ii][Nn][Dd][Oo][Ww][Ss][/\\\\]([Ss][Yy][Ss][Tt][Ee][Mm]32|[Ww][Ii][Nn][Ss][Xx][Ss])[/\\\\].*"
      ".*[/\\\\]libpure\\.dll"
    RUNTIME DESTINATION "${PURE_RUNTIME_INSTALL_DIR}"
    COMPONENT runtime
  )
  install(
    FILES "${GTK2_PREFIX}/bin/libgailutil-18.dll"
    DESTINATION "${PURE_RUNTIME_INSTALL_DIR}"
    COMPONENT runtime
  )

  install(
    DIRECTORY "${GTK2_PREFIX}/lib/gdk-pixbuf-2.0/2.10.0/loaders/"
    DESTINATION "lib/gdk-pixbuf-2.0/2.10.0/loaders"
    COMPONENT runtime
    FILES_MATCHING
      PATTERN "*.dll"
      PATTERN "pixbufloader_svg.dll" EXCLUDE
  )
  install(
    DIRECTORY "${GTK2_PREFIX}/lib/gtk-2.0/2.10.0/engines/"
    DESTINATION "lib/gtk-2.0/2.10.0/engines"
    COMPONENT runtime
    FILES_MATCHING PATTERN "*.dll"
  )
  install(
    DIRECTORY "${GTK2_PREFIX}/lib/gtk-2.0/modules/"
    DESTINATION "lib/gtk-2.0/modules"
    COMPONENT runtime
    FILES_MATCHING PATTERN "*.dll"
  )

  file(READ
    "${GTK2_PREFIX}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"
    gdk_pixbuf_loaders_cache
  )
  string(REGEX REPLACE
    "# LoaderDir = [^\r\n]*"
    "# LoaderDir = <bundle>/lib/gdk-pixbuf-2.0/2.10.0/loaders"
    gdk_pixbuf_loaders_cache
    "${gdk_pixbuf_loaders_cache}"
  )
  string(REGEX REPLACE
    "\r?\n\"[^\r\n]*pixbufloader_svg\\.dll\"\r?\n[^\r\n]*\r?\n[^\r\n]*\r?\n[^\r\n]*\r?\n[^\r\n]*\r?\n[^\r\n]*\r?\n\r?\n"
    "\n"
    gdk_pixbuf_loaders_cache
    "${gdk_pixbuf_loaders_cache}"
  )
  string(REGEX REPLACE
    "\"[^\r\n]*[/\\\\]([^/\\\\\r\n]+\\.dll)\""
    "\"@PURE_GTK_PREFIX@/lib/gdk-pixbuf-2.0/2.10.0/loaders/\\1\""
    gdk_pixbuf_loaders_cache
    "${gdk_pixbuf_loaders_cache}"
  )
  file(WRITE
    "${CMAKE_CURRENT_BINARY_DIR}/gdk-pixbuf-loaders.cache"
    "${gdk_pixbuf_loaders_cache}"
  )
  install(
    FILES "${CMAKE_CURRENT_BINARY_DIR}/gdk-pixbuf-loaders.cache"
    DESTINATION "lib/gdk-pixbuf-2.0/2.10.0"
    RENAME loaders.cache
    COMPONENT runtime
  )

  install(
    DIRECTORY "${GTK2_PREFIX}/etc/gtk-2.0/"
    DESTINATION "etc/gtk-2.0"
    COMPONENT runtime
  )
  install(
    DIRECTORY "${GTK2_PREFIX}/etc/fonts/"
    DESTINATION "etc/fonts"
    COMPONENT runtime
  )
  install(
    DIRECTORY "${GTK2_PREFIX}/share/fontconfig/"
    DESTINATION "share/fontconfig"
    COMPONENT runtime
  )
  install(
    DIRECTORY "${GTK2_PREFIX}/share/themes/"
    DESTINATION "share/themes"
    COMPONENT runtime
  )
  install(
    DIRECTORY
      "${GTK2_PREFIX}/share/icons/Adwaita"
      "${GTK2_PREFIX}/share/icons/AdwaitaLegacy"
    DESTINATION "share/icons"
    COMPONENT runtime
  )
  install(
    FILES
      "${GTK2_PREFIX}/share/icons/hicolor/index.theme"
      "${GTK2_PREFIX}/share/icons/hicolor/icon-theme.cache"
    DESTINATION "share/icons/hicolor"
    COMPONENT runtime
  )

  set(gtk_license_packages
    adwaita-icon-theme
    adwaita-icon-theme-legacy
    at-spi2-core
    brotli
    bzip2
    cairo
    expat
    fontconfig
    freetype
    fribidi
    gdk-pixbuf2
    gettext-runtime
    glib2
    graphite2
    gtk2
    harfbuzz
    hicolor-icon-theme
    jbigkit
    lerc
    libc++
    libdatrie
    libdeflate
    libffi
    libiconv
    libjpeg-turbo
    libpng
    libthai
    libtiff
    libwebp
    pango
    pcre2
    pixman
    xz
    zlib
    zstd
  )
  foreach(license_package IN LISTS gtk_license_packages)
    set(license_dir "${GTK2_PREFIX}/share/licenses/${license_package}")
    if(NOT IS_DIRECTORY "${license_dir}")
      message(FATAL_ERROR
        "Missing third-party license directory: ${license_dir}")
    endif()
    install(
      DIRECTORY "${license_dir}/"
      DESTINATION
        "${PURE_DOCUMENTATION_INSTALL_DIR}/licenses/${license_package}"
      COMPONENT documentation
    )
  endforeach()
endif()

install(
  FILES
    "${CMAKE_CURRENT_BINARY_DIR}/README"
    "${CMAKE_CURRENT_SOURCE_DIR}/COPYING"
    "${CMAKE_CURRENT_SOURCE_DIR}/COPYING.LESSER"
    "${CMAKE_CURRENT_SOURCE_DIR}/WINDOWS.md"
    "${CMAKE_CURRENT_SOURCE_DIR}/THIRD_PARTY.md"
  DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}"
  COMPONENT documentation
)
install(
  FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/examples/hello.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/examples/uiexample.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/examples/uiexample.glade"
    "${CMAKE_CURRENT_SOURCE_DIR}/examples/life.pure"
  DESTINATION "${PURE_EXAMPLES_INSTALL_DIR}"
  COMPONENT documentation
)
install(
  FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/gui-smoke.pure"
  DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}/tests"
  COMPONENT documentation
)
if(WIN32)
  install(
    TARGETS pure-gtk-windows-pixbuf
    RUNTIME DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}/tests"
    COMPONENT documentation
  )
endif()
