#include <gdk/gdk.h>
#include <gtk/gtk.h>
#include <errno.h>

#ifdef _WIN32
#include <windows.h>
#include <wchar.h>

static int pure_gtk_bundle_initialized;
static int pure_gtk_bundle_result;

static int pure_gtk_bundle_prefix(gchar **prefix)
{
  HMODULE module;
  wchar_t module_path[32768];
  DWORD length;
  int component;

  module = GetModuleHandleW(L"gtk.dll");
  if (module == NULL)
    return 0;
  length = GetModuleFileNameW(module, module_path,
                              (DWORD)G_N_ELEMENTS(module_path));
  if (length == 0 || length >= G_N_ELEMENTS(module_path))
    return 0;
  module_path[length] = L'\0';

  for (component = 0; component < 3; ++component) {
    wchar_t *separator = wcsrchr(module_path, L'\\');
    if (separator == NULL)
      return 0;
    *separator = L'\0';
  }

  *prefix = g_utf16_to_utf8((const gunichar2 *)module_path, -1,
                            NULL, NULL, NULL);
  return *prefix != NULL;
}

static void pure_gtk_set_bundle_path(const gchar *name, const gchar *value)
{
  if (g_getenv(name) == NULL)
    g_setenv(name, value, TRUE);
}

static int pure_gtk_write_loader_cache(const gchar *prefix)
{
  const gchar *placeholder = "@PURE_GTK_PREFIX@";
  gchar *template_path = NULL;
  gchar *template_contents = NULL;
  gchar *portable_prefix = NULL;
  gchar **parts = NULL;
  gchar *cache_contents = NULL;
  gchar *checksum = NULL;
  gchar *cache_dir = NULL;
  gchar *cache_path = NULL;
  GError *error = NULL;
  gsize length = 0;
  gchar *character;
  int result = 0;

  if (g_getenv("GDK_PIXBUF_MODULE_FILE") != NULL)
    return 1;

  template_path = g_build_filename(prefix, "lib", "gdk-pixbuf-2.0",
                                   "2.10.0", "loaders.cache", NULL);
  if (!g_file_get_contents(template_path, &template_contents, &length,
                           &error))
    goto done;

  portable_prefix = g_strdup(prefix);
  for (character = portable_prefix; *character != '\0'; ++character)
    if (*character == '\\')
      *character = '/';

  parts = g_strsplit(template_contents, placeholder, -1);
  if (parts[1] == NULL) {
    g_set_error(&error, G_FILE_ERROR, G_FILE_ERROR_INVAL,
                "Missing %s placeholder in %s", placeholder,
                template_path);
    goto done;
  }
  cache_contents = g_strjoinv(portable_prefix, parts);

  checksum = g_compute_checksum_for_string(G_CHECKSUM_SHA256, prefix, -1);
  cache_dir = g_build_filename(g_get_tmp_dir(), "pure-gtk",
                               checksum, NULL);
  cache_path = g_build_filename(cache_dir, "loaders.cache", NULL);
  if (g_mkdir_with_parents(cache_dir, 0700) != 0) {
    g_set_error(&error, G_FILE_ERROR, g_file_error_from_errno(errno),
                "Cannot create %s", cache_dir);
    goto done;
  }
  if (!g_file_set_contents(cache_path, cache_contents, -1, &error))
    goto done;

  g_setenv("GDK_PIXBUF_MODULE_FILE", cache_path, TRUE);
  result = 1;

done:
  if (error != NULL) {
    g_warning("pure-gtk loader cache initialization failed: %s",
              error->message);
    g_clear_error(&error);
  }
  g_free(cache_path);
  g_free(cache_dir);
  g_free(checksum);
  g_free(cache_contents);
  g_strfreev(parts);
  g_free(portable_prefix);
  g_free(template_contents);
  g_free(template_path);
  return result;
}

int pure_gtk_init_bundle(void)
{
  gchar *prefix = NULL;
  gchar *loader_dir = NULL;
  gchar *gtk_path = NULL;
  gchar *fontconfig_path = NULL;
  gchar *fontconfig_file = NULL;

  if (pure_gtk_bundle_initialized)
    return pure_gtk_bundle_result;
  pure_gtk_bundle_initialized = 1;

  if (!pure_gtk_bundle_prefix(&prefix))
    goto done;

  loader_dir = g_build_filename(prefix, "lib", "gdk-pixbuf-2.0",
                                "2.10.0", "loaders", NULL);
  gtk_path = g_build_filename(prefix, "lib", "gtk-2.0", NULL);
  fontconfig_path = g_build_filename(prefix, "etc", "fonts", NULL);
  fontconfig_file = g_build_filename(fontconfig_path, "fonts.conf", NULL);

  pure_gtk_set_bundle_path("GDK_PIXBUF_MODULEDIR", loader_dir);
  pure_gtk_set_bundle_path("GTK_DATA_PREFIX", prefix);
  pure_gtk_set_bundle_path("GTK_PATH", gtk_path);
  pure_gtk_set_bundle_path("FONTCONFIG_PATH", fontconfig_path);
  pure_gtk_set_bundle_path("FONTCONFIG_FILE", fontconfig_file);

  pure_gtk_bundle_result = pure_gtk_write_loader_cache(prefix);

done:
  g_free(fontconfig_file);
  g_free(fontconfig_path);
  g_free(gtk_path);
  g_free(loader_dir);
  g_free(prefix);
  return pure_gtk_bundle_result;
}
#endif
