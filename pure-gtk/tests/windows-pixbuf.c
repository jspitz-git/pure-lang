#include <gdk-pixbuf/gdk-pixbuf.h>
#include <stdio.h>
#include <windows.h>

typedef int (*pure_gtk_init_bundle_fn)(void);

int main(int argc, char **argv)
{
  GError *error = NULL;
  GdkPixbuf *pixbuf;
  HMODULE module;
  union {
    FARPROC address;
    pure_gtk_init_bundle_fn function;
  } initialize;

  if (argc != 3) {
    fputs("usage: pure-gtk-windows-pixbuf GTK.DLL IMAGE\n", stderr);
    return 2;
  }

  module = LoadLibraryA(argv[1]);
  if (module == NULL) {
    fprintf(stderr, "pure-gtk pixbuf test: cannot load %s (%lu)\n",
            argv[1], (unsigned long)GetLastError());
    return 1;
  }

  initialize.address = GetProcAddress(module, "pure_gtk_init_bundle");
  if (initialize.address == NULL) {
    fputs("pure-gtk pixbuf test: bundle initializer is not exported\n",
          stderr);
    FreeLibrary(module);
    return 1;
  }
  if (!initialize.function()) {
    fputs("pure-gtk pixbuf test: bundle initialization failed\n", stderr);
    FreeLibrary(module);
    return 1;
  }

  pixbuf = gdk_pixbuf_new_from_file(argv[2], &error);
  if (pixbuf == NULL) {
    fprintf(stderr, "pure-gtk pixbuf test: PNG load failed: %s\n",
            error != NULL ? error->message : "unknown error");
    g_clear_error(&error);
    FreeLibrary(module);
    return 1;
  }
  if (gdk_pixbuf_get_width(pixbuf) <= 0 ||
      gdk_pixbuf_get_height(pixbuf) <= 0) {
    fputs("pure-gtk pixbuf test: invalid decoded dimensions\n", stderr);
    g_object_unref(pixbuf);
    FreeLibrary(module);
    return 1;
  }

  g_object_unref(pixbuf);
  FreeLibrary(module);
  puts("pure-gtk pixbuf smoke passed");
  return 0;
}
