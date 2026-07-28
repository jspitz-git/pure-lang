foreach(required IN ITEMS STAGE_PREFIX SOURCE_RUNTIME_DIR LLVM_READOBJ)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

if(POLICY CMP0207)
  cmake_policy(SET CMP0207 NEW)
endif()

cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE stage)
cmake_path(
  ABSOLUTE_PATH SOURCE_RUNTIME_DIR NORMALIZE OUTPUT_VARIABLE source_bin)
set(module_dir "${stage}/lib/pure")
set(doc_dir "${stage}/share/doc/pure-gtk")
set(loader_dir "${stage}/lib/gdk-pixbuf-2.0/2.10.0/loaders")
set(engine_dir "${stage}/lib/gtk-2.0/2.10.0/engines")
set(gtk_module_dir "${stage}/lib/gtk-2.0/modules")
set(work_dir "${stage}/Pure GTK Verification")

set(module_files
  gtk.dll glib.dll atk.dll cairo.dll pango.dll
  gtk.pure glib.pure atk.pure cairo.pure pango.pure)
set(runtime_files
  libLerc.dll
  libatk-1.0-0.dll
  libbrotlicommon.dll
  libbrotlidec.dll
  libbz2-1.dll
  libc++.dll
  libcairo-2.dll
  libdatrie-1.dll
  libdeflate.dll
  libexpat-1.dll
  libffi-8.dll
  libfontconfig-1.dll
  libfreetype-6.dll
  libfribidi-0.dll
  libgailutil-18.dll
  libgdk-win32-2.0-0.dll
  libgdk_pixbuf-2.0-0.dll
  libgio-2.0-0.dll
  libglib-2.0-0.dll
  libgmodule-2.0-0.dll
  libgobject-2.0-0.dll
  libgraphite2.dll
  libgtk-win32-2.0-0.dll
  libharfbuzz-0.dll
  libiconv-2.dll
  libintl-8.dll
  libjbig-0.dll
  libjpeg-8.dll
  liblzma-5.dll
  libpango-1.0-0.dll
  libpangocairo-1.0-0.dll
  libpangoft2-1.0-0.dll
  libpangowin32-1.0-0.dll
  libpcre2-8-0.dll
  libpixman-1-0.dll
  libpng16-16.dll
  libsharpyuv-0.dll
  libthai-0.dll
  libtiff-6.dll
  libwebp-7.dll
  libzstd.dll
  zlib1.dll)
set(documentation_files
  README COPYING COPYING.LESSER WINDOWS.md THIRD_PARTY.md)
set(example_files hello.pure uiexample.pure uiexample.glade life.pure)
set(test_files
  smoke.pure gui-smoke.pure pure-gtk-windows-pixbuf.exe)
set(license_packages
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
  zstd)

set(expected_files)
foreach(name IN LISTS module_files)
  list(APPEND expected_files "${module_dir}/${name}")
endforeach()
foreach(name IN LISTS runtime_files)
  list(APPEND expected_files "${stage}/bin/${name}")
endforeach()
foreach(name IN LISTS documentation_files)
  list(APPEND expected_files "${doc_dir}/${name}")
endforeach()
foreach(name IN LISTS example_files)
  list(APPEND expected_files "${doc_dir}/examples/${name}")
endforeach()
foreach(name IN LISTS test_files)
  list(APPEND expected_files "${doc_dir}/tests/${name}")
endforeach()
list(APPEND expected_files
  "${stage}/etc/fonts/fonts.conf"
  "${stage}/etc/gtk-2.0/im-multipress.conf"
  "${stage}/share/icons/Adwaita/index.theme"
  "${stage}/share/icons/AdwaitaLegacy/index.theme"
  "${stage}/share/icons/hicolor/index.theme"
  "${stage}/share/themes/MS-Windows/gtk-2.0/gtkrc"
  "${stage}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache")
foreach(expected IN LISTS expected_files)
  if(NOT EXISTS "${expected}")
    message(FATAL_ERROR "Missing installed pure-gtk file: ${expected}")
  endif()
endforeach()
foreach(package IN LISTS license_packages)
  if(NOT IS_DIRECTORY "${doc_dir}/licenses/${package}")
    message(FATAL_ERROR "Missing installed license directory: ${package}")
  endif()
endforeach()

file(GLOB loaders LIST_DIRECTORIES FALSE "${loader_dir}/*.dll")
file(GLOB engines LIST_DIRECTORIES FALSE "${engine_dir}/*.dll")
file(GLOB gtk_modules LIST_DIRECTORIES FALSE "${gtk_module_dir}/*.dll")
list(LENGTH loaders loader_count)
list(LENGTH engines engine_count)
list(LENGTH gtk_modules gtk_module_count)
if(NOT loader_count EQUAL 13)
  message(FATAL_ERROR "Expected 13 GdkPixbuf loaders, found ${loader_count}")
endif()
if(NOT engine_count EQUAL 2)
  message(FATAL_ERROR "Expected 2 GTK engines, found ${engine_count}")
endif()
if(NOT gtk_module_count EQUAL 1)
  message(FATAL_ERROR
    "Expected 1 GTK accessibility module, found ${gtk_module_count}")
endif()
if(EXISTS "${loader_dir}/pixbufloader_svg.dll")
  message(FATAL_ERROR "Unsupported SVG loader must not be installed")
endif()

set(loader_cache
  "${stage}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache")
file(READ "${loader_cache}" loader_cache_contents)
if(NOT loader_cache_contents MATCHES "@PURE_GTK_PREFIX@")
  message(FATAL_ERROR "GdkPixbuf loader cache is not relocatable")
endif()
if(loader_cache_contents MATCHES
    "(pixbufloader_svg|[Cc]:[/\\\\]|/clang64/|/pure-lang/)")
  message(FATAL_ERROR
    "GdkPixbuf loader cache contains an excluded or host-specific path")
endif()

foreach(runtime_file IN LISTS runtime_files)
  set(staged_file "${stage}/bin/${runtime_file}")
  set(source_file "${source_bin}/${runtime_file}")
  if(NOT EXISTS "${source_file}")
    message(FATAL_ERROR "Missing source runtime: ${source_file}")
  endif()
  file(SHA256 "${staged_file}" staged_hash)
  file(SHA256 "${source_file}" source_hash)
  if(NOT staged_hash STREQUAL source_hash)
    message(FATAL_ERROR "Runtime hash mismatch for ${runtime_file}")
  endif()
endforeach()

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    "-DRUNTIME_DIR=${stage}/bin"
    "-DGTK_LOADER_DIR=${loader_dir}"
    "-DGTK_ENGINE_DIR=${engine_dir}"
    "-DGTK_MODULE_DIR=${gtk_module_dir}"
    "-DGTK_MODULE=${module_dir}/gtk.dll"
    "-DGLIB_MODULE=${module_dir}/glib.dll"
    "-DATK_MODULE=${module_dir}/atk.dll"
    "-DCAIRO_MODULE=${module_dir}/cairo.dll"
    "-DPANGO_MODULE=${module_dir}/pango.dll"
    -P "${CMAKE_CURRENT_LIST_DIR}/VerifyWindowsDependencies.cmake"
  RESULT_VARIABLE audit_result
  OUTPUT_VARIABLE audit_output
  ERROR_VARIABLE audit_error
  ENCODING UTF-8)
if(NOT audit_result EQUAL 0)
  message(FATAL_ERROR
    "Installed pure-gtk PE audit failed (${audit_result})\n"
    "stdout:\n${audit_output}\nstderr:\n${audit_error}")
endif()

get_filename_component(llvm_bin "${LLVM_READOBJ}" DIRECTORY)
find_program(
  LLVM_OBJDUMP
  NAMES llvm-objdump
  HINTS "${llvm_bin}"
  NO_DEFAULT_PATH
  REQUIRED)
set(CMAKE_GET_RUNTIME_DEPENDENCIES_PLATFORM "windows+pe")
set(CMAKE_GET_RUNTIME_DEPENDENCIES_TOOL "objdump")
set(CMAKE_GET_RUNTIME_DEPENDENCIES_COMMAND "${LLVM_OBJDUMP}")
file(GLOB staged_modules LIST_DIRECTORIES FALSE "${module_dir}/*.dll")
file(GLOB staged_runtime LIST_DIRECTORIES FALSE "${stage}/bin/*.dll")
set(package_libraries
  ${staged_modules} ${staged_runtime} ${loaders} ${engines} ${gtk_modules})
file(GET_RUNTIME_DEPENDENCIES
  LIBRARIES ${package_libraries}
  DIRECTORIES "${stage}/bin"
  RESOLVED_DEPENDENCIES_VAR resolved_dependencies
  UNRESOLVED_DEPENDENCIES_VAR unresolved_dependencies
  CONFLICTING_DEPENDENCIES_PREFIX conflicts
  PRE_EXCLUDE_REGEXES "^api-ms-win-.*" "^ext-ms-.*"
  POST_EXCLUDE_REGEXES
    ".*[/\\\\][Ww][Ii][Nn][Dd][Oo][Ww][Ss][/\\\\]([Ss][Yy][Ss][Tt][Ee][Mm]32|[Ww][Ii][Nn][Ss][Xx][Ss])[/\\\\].*")
if(unresolved_dependencies)
  message(FATAL_ERROR
    "Unresolved staged PE dependencies: ${unresolved_dependencies}")
endif()
if(conflicts_FILENAMES)
  message(FATAL_ERROR
    "Conflicting staged PE dependencies: ${conflicts_FILENAMES}")
endif()
string(TOLOWER "${stage}/" stage_prefix_lower)
foreach(dependency IN LISTS resolved_dependencies)
  cmake_path(NORMAL_PATH dependency OUTPUT_VARIABLE normalized_dependency)
  string(TOLOWER "${normalized_dependency}" dependency_lower)
  string(FIND "${dependency_lower}" "${stage_prefix_lower}" prefix_index)
  if(NOT prefix_index EQUAL 0)
    message(FATAL_ERROR
      "Non-system PE dependency resolved outside stage: ${dependency}")
  endif()
endforeach()

file(REMOVE_RECURSE "${work_dir}")
file(MAKE_DIRECTORY "${work_dir}")
unset(ENV{PURELIB})
unset(ENV{GDK_PIXBUF_MODULE_FILE})
unset(ENV{GDK_PIXBUF_MODULEDIR})
unset(ENV{GTK_PATH})
unset(ENV{GTK_DATA_PREFIX})
unset(ENV{FONTCONFIG_FILE})
unset(ENV{FONTCONFIG_PATH})
set(ENV{TEMP} "${work_dir}")
set(ENV{TMP} "${work_dir}")
set(ENV{PATH} "${stage}/bin;C:/Windows/System32;C:/Windows")

function(run_checked name marker timeout)
  execute_process(
    COMMAND ${ARGN}
    WORKING_DIRECTORY "${work_dir}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    TIMEOUT "${timeout}"
    ENCODING UTF-8)
  if(NOT result EQUAL 0)
    message(FATAL_ERROR
      "${name} failed (${result})\nstdout:\n${output}\nstderr:\n${error}")
  endif()
  if(NOT error STREQUAL "")
    message(FATAL_ERROR
      "${name} emitted stderr\nstdout:\n${output}\nstderr:\n${error}")
  endif()
  if(NOT output MATCHES "(^|\r?\n)${marker}([^\r\n]*)(\r?\n|$)")
    message(FATAL_ERROR
      "${name} did not emit ${marker}\nstdout:\n${output}")
  endif()
endfunction()

run_checked(
  "Installed pure-gtk pixbuf test"
  "pure-gtk pixbuf smoke passed"
  30
  "${doc_dir}/tests/pure-gtk-windows-pixbuf.exe"
  "${module_dir}/gtk.dll"
  "${stage}/share/icons/Adwaita/16x16/devices/audio-headphones.png")
run_checked(
  "Installed pure-gtk GUI callback test"
  "pure-gtk GUI smoke passed"
  30
  "${stage}/bin/pure.exe" --norc -q
  -I "${module_dir}" -L "${module_dir}"
  -x "${doc_dir}/tests/gui-smoke.pure")
run_checked(
  "Installed pure-gtk wrapper smoke test"
  "pure-gtk smoke passed:"
  1200
  "${stage}/bin/pure.exe" --norc -q
  -I "${module_dir}" -L "${module_dir}"
  -x "${doc_dir}/tests/smoke.pure")

file(REMOVE_RECURSE "${work_dir}")
list(LENGTH expected_files expected_count)
list(LENGTH runtime_files runtime_count)
list(LENGTH license_packages license_count)
message(STATUS
  "Verified installed pure-gtk: ${expected_count} package files, "
  "${runtime_count} hash-matched runtime DLLs, ${loader_count} loaders, "
  "${engine_count} engines, ${gtk_module_count} accessibility module, "
  "${license_count} license directories, 3 sanitized runtime tests, and "
  "closed staged PE dependencies")
