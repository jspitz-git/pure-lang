foreach(required IN ITEMS
    LLVM_READOBJ RUNTIME_DIR GTK_LOADER_DIR GTK_ENGINE_DIR GTK_MODULE_DIR
    GTK_MODULE GLIB_MODULE ATK_MODULE CAIRO_MODULE PANGO_MODULE)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

function(read_pe mode file output_var)
  if(NOT EXISTS "${file}")
    message(FATAL_ERROR "PE dependency does not exist: ${file}")
  endif()
  execute_process(
    COMMAND "${LLVM_READOBJ}" "${mode}" "${file}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8
  )
  if(NOT result EQUAL 0)
    message(FATAL_ERROR
      "Unable to inspect ${file} (${result})\n${output}\n${error}")
  endif()
  set(${output_var} "${output}" PARENT_SCOPE)
endfunction()

function(verify_pe file)
  read_pe("--file-headers" "${file}" headers)
  if(NOT headers MATCHES "Machine: IMAGE_FILE_MACHINE_AMD64")
    message(FATAL_ERROR "${file} is not an x86_64 PE image")
  endif()

  read_pe("--coff-imports" "${file}" imports)
  if(imports MATCHES
      "Name: (msys-2\\.0|libgcc[^.]*|libstdc\\+\\+[^.]*)\\.dll")
    message(FATAL_ERROR "${file} imports an incompatible MSYS/GNU runtime")
  endif()
endfunction()

function(require_import file import_name)
  read_pe("--coff-imports" "${file}" imports)
  if(NOT imports MATCHES "Name: ${import_name}")
    message(FATAL_ERROR "${file} does not import ${import_name}")
  endif()
endfunction()

function(require_export file export_name)
  read_pe("--coff-exports" "${file}" exports)
  if(NOT exports MATCHES "Name: ${export_name}(\r?\n|$)")
    message(FATAL_ERROR "${file} does not export ${export_name}")
  endif()
endfunction()

set(modules
  "${GTK_MODULE}"
  "${GLIB_MODULE}"
  "${ATK_MODULE}"
  "${CAIRO_MODULE}"
  "${PANGO_MODULE}"
)
foreach(module IN LISTS modules)
  verify_pe("${module}")
endforeach()

require_import("${GTK_MODULE}" "libgtk-win32-2\\.0-0\\.dll")
require_import("${GLIB_MODULE}" "libglib-2\\.0-0\\.dll")

set(gtk_utf8_aliases
  gtk_rc_add_default_file
  gtk_rc_set_default_files
  gtk_rc_parse
  gtk_window_set_icon_from_file
  gtk_window_set_default_icon_from_file
  gtk_accel_map_load
  gtk_accel_map_save
  gtk_image_new_from_file
  gtk_image_set_from_file
  gtk_file_chooser_get_filename
  gtk_file_chooser_set_filename
  gtk_file_chooser_select_filename
  gtk_file_chooser_unselect_filename
  gtk_file_chooser_get_filenames
  gtk_file_chooser_set_current_folder
  gtk_file_chooser_get_current_folder
  gtk_file_chooser_get_preview_filename
  gtk_file_chooser_add_shortcut_folder
  gtk_file_chooser_remove_shortcut_folder
  gtk_file_chooser_list_shortcut_folders
  gtk_icon_source_set_filename
  gtk_icon_source_get_filename
  gtk_icon_theme_set_search_path
  gtk_icon_theme_get_search_path
  gtk_icon_theme_append_search_path
  gtk_icon_theme_prepend_search_path
  gtk_icon_info_get_filename
  gtk_ui_manager_add_ui_from_file
  gtk_file_selection_set_filename
  gtk_file_selection_get_filename
  gtk_file_selection_get_selections
)
foreach(alias IN LISTS gtk_utf8_aliases)
  require_export("${GTK_MODULE}" "${alias}")
endforeach()

set(primary_runtime_names
  libgtk-win32-2.0-0.dll
  libgdk-win32-2.0-0.dll
  libglib-2.0-0.dll
  libgobject-2.0-0.dll
  libgio-2.0-0.dll
  libgmodule-2.0-0.dll
  libatk-1.0-0.dll
  libcairo-2.dll
  libpango-1.0-0.dll
  libpangocairo-1.0-0.dll
  libpangowin32-1.0-0.dll
  libgdk_pixbuf-2.0-0.dll
)
foreach(runtime_name IN LISTS primary_runtime_names)
  set(runtime "${RUNTIME_DIR}/${runtime_name}")
  verify_pe("${runtime}")
endforeach()

require_export("${RUNTIME_DIR}/libgtk-win32-2.0-0.dll" "gtk_init_check")
require_export("${RUNTIME_DIR}/libglib-2.0-0.dll" "g_random_int_range")
require_export("${RUNTIME_DIR}/libatk-1.0-0.dll" "atk_get_version")
require_export("${RUNTIME_DIR}/libcairo-2.dll" "cairo_version_string")
require_export("${RUNTIME_DIR}/libpango-1.0-0.dll" "pango_version_string")

file(GLOB gtk_plugins LIST_DIRECTORIES FALSE
  "${GTK_LOADER_DIR}/*.dll"
  "${GTK_ENGINE_DIR}/*.dll"
  "${GTK_MODULE_DIR}/*.dll"
)
list(LENGTH gtk_plugins gtk_plugin_count)
if(gtk_plugin_count LESS 16)
  message(FATAL_ERROR
    "Expected at least 16 GdkPixbuf/GTK plugins, found ${gtk_plugin_count}")
endif()
foreach(plugin IN LISTS gtk_plugins)
  verify_pe("${plugin}")
endforeach()

list(LENGTH gtk_utf8_aliases gtk_utf8_alias_count)
message(STATUS
  "Verified pure-gtk PE inventory: 5 x64 modules, "
  "${gtk_utf8_alias_count} UTF-8 aliases, 12 primary runtime DLLs, "
  "${gtk_plugin_count} loader/engine/accessibility plugins, no MSYS/GNU ABI")
