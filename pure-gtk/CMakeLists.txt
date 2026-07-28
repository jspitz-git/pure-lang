cmake_minimum_required(VERSION 3.25)

project(pure-gtk VERSION 0.13 LANGUAGES C)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(GTK2 REQUIRED IMPORTED_TARGET gtk+-2.0)
pkg_check_modules(GLIB REQUIRED IMPORTED_TARGET
  glib-2.0 gobject-2.0 gio-2.0 gmodule-2.0)
pkg_check_modules(ATK REQUIRED IMPORTED_TARGET atk)
pkg_check_modules(CAIRO REQUIRED IMPORTED_TARGET cairo)
pkg_check_modules(PANGO REQUIRED IMPORTED_TARGET pango)

function(add_pure_gtk_module target dependency)
  add_library(${target} MODULE "${target}.c")
  target_compile_features(${target} PRIVATE c_std_11)
  target_compile_options(${target} PRIVATE -Wall -Wextra -Werror)

  target_link_libraries(
    ${target}
    PRIVATE
      PkgConfig::PURE
      "PkgConfig::${dependency}"
  )
  set_target_properties(
    ${target}
    PROPERTIES
      PREFIX ""
      WINDOWS_EXPORT_ALL_SYMBOLS ON
  )
endfunction()

add_pure_gtk_module(gtk GTK2)
add_pure_gtk_module(glib GLIB)
add_pure_gtk_module(atk ATK)
add_pure_gtk_module(cairo CAIRO)
add_pure_gtk_module(pango PANGO)

if(WIN32)
  pkg_get_variable(GTK2_PREFIX gtk+-2.0 prefix)
  target_sources(gtk PRIVATE gtk-windows.def)

  add_executable(pure-gtk-windows-loader tests/windows-loader.c)
  target_compile_features(pure-gtk-windows-loader PRIVATE c_std_11)
  target_compile_options(
    pure-gtk-windows-loader
    PRIVATE
      -Wall
      -Wextra
      -Werror
  )

  add_executable(pure-gtk-windows-gui tests/windows-gui.c)
  target_compile_features(pure-gtk-windows-gui PRIVATE c_std_11)
  target_compile_options(
    pure-gtk-windows-gui
    PRIVATE
      -Wall
      -Wextra
      -Werror
  )
  target_link_libraries(pure-gtk-windows-gui PRIVATE PkgConfig::GTK2)
  find_program(LLVM_READOBJ NAMES llvm-readobj REQUIRED)
  add_custom_target(
    verify-windows-dependencies
    COMMAND "${CMAKE_COMMAND}"
      "-DLLVM_READOBJ=${LLVM_READOBJ}"
      "-DRUNTIME_DIR=${GTK2_PREFIX}/bin"
      "-DGTK_LOADER_DIR=${GTK2_PREFIX}/lib/gdk-pixbuf-2.0/2.10.0/loaders"
      "-DGTK_ENGINE_DIR=${GTK2_PREFIX}/lib/gtk-2.0/2.10.0/engines"
      "-DGTK_MODULE_DIR=${GTK2_PREFIX}/lib/gtk-2.0/modules"
      "-DGTK_MODULE=$<TARGET_FILE:gtk>"
      "-DGLIB_MODULE=$<TARGET_FILE:glib>"
      "-DATK_MODULE=$<TARGET_FILE:atk>"
      "-DCAIRO_MODULE=$<TARGET_FILE:cairo>"
      "-DPANGO_MODULE=$<TARGET_FILE:pango>"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
    DEPENDS gtk glib atk cairo pango
    COMMENT "Verifying the pure-gtk Windows PE inventory"
    VERBATIM
  )
endif()

set(
  PURE_FFI_SOURCE_DIR ""
  CACHE PATH "Source directory of pure-ffi used by the GUI integration test"
)
set(
  PURE_FFI_MODULE_DIR ""
  CACHE PATH "Directory containing ffi.dll for the GUI integration test"
)

include(CTest)
if(BUILD_TESTING AND WIN32)
  add_test(NAME pure-gtk-windows-loader COMMAND pure-gtk-windows-loader)
  set_tests_properties(
    pure-gtk-windows-loader
    PROPERTIES
      ENVIRONMENT_MODIFICATION
        "PATH=path_list_prepend:$<TARGET_FILE_DIR:gtk>"
      LABELS "gtk;loader;utf8"
      TIMEOUT 15
  )

  add_test(NAME pure-gtk-windows-gui COMMAND pure-gtk-windows-gui)
  set_tests_properties(
    pure-gtk-windows-gui
    PROPERTIES
      ENVIRONMENT_MODIFICATION
        "PATH=path_list_prepend:${GTK2_PREFIX}/bin"
      LABELS "gtk;gui;widget;callback;shutdown"
      TIMEOUT 15
  )

  pkg_get_variable(PURE_PREFIX pure prefix)
  find_program(
    PURE_EXECUTABLE
    NAMES pure
    HINTS "${PURE_PREFIX}/bin"
    NO_DEFAULT_PATH
    REQUIRED
  )
  add_test(
    NAME pure-gtk-smoke
    COMMAND "${PURE_EXECUTABLE}"
      -I "${CMAKE_CURRENT_SOURCE_DIR}"
      -L "$<TARGET_FILE_DIR:gtk>"
      -x "${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
  )
  set_tests_properties(
    pure-gtk-smoke
    PROPERTIES
      ENVIRONMENT_MODIFICATION
        "PATH=path_list_prepend:$<TARGET_FILE_DIR:gtk>;PATH=path_list_prepend:${GTK2_PREFIX}/bin"
      LABELS "gtk;runtime;integration;slow;no-display"
      REQUIRED_FILES
        "$<TARGET_FILE:gtk>;$<TARGET_FILE:glib>;$<TARGET_FILE:atk>;$<TARGET_FILE:cairo>;$<TARGET_FILE:pango>"
      TIMEOUT 1200
  )

  if(PURE_FFI_SOURCE_DIR AND PURE_FFI_MODULE_DIR)
    if(NOT EXISTS "${PURE_FFI_SOURCE_DIR}/ffi.pure" OR
        NOT EXISTS "${PURE_FFI_MODULE_DIR}/ffi.dll")
      message(FATAL_ERROR
        "PURE_FFI_SOURCE_DIR and PURE_FFI_MODULE_DIR must contain ffi.pure and ffi.dll")
    endif()
    add_test(
      NAME pure-gtk-gui-smoke
      COMMAND "${PURE_EXECUTABLE}"
        -I "${PURE_FFI_SOURCE_DIR}"
        -I "${CMAKE_CURRENT_SOURCE_DIR}"
        -L "${PURE_FFI_MODULE_DIR}"
        -L "$<TARGET_FILE_DIR:gtk>"
        -x "${CMAKE_CURRENT_SOURCE_DIR}/tests/gui-smoke.pure"
    )
    set_tests_properties(
      pure-gtk-gui-smoke
      PROPERTIES
        ENVIRONMENT_MODIFICATION
          "PATH=path_list_prepend:$<TARGET_FILE_DIR:gtk>;PATH=path_list_prepend:${PURE_FFI_MODULE_DIR};PATH=path_list_prepend:${GTK2_PREFIX}/bin"
        LABELS "gtk;gui;pure;ffi;widget;callback;shutdown"
        REQUIRED_FILES
          "${PURE_FFI_SOURCE_DIR}/ffi.pure;${PURE_FFI_MODULE_DIR}/ffi.dll;$<TARGET_FILE:gtk>;$<TARGET_FILE:glib>"
        TIMEOUT 30
    )
  else()
    message(STATUS
      "pure-gtk-gui-smoke disabled; set PURE_FFI_SOURCE_DIR and PURE_FFI_MODULE_DIR")
  endif()
endif()
