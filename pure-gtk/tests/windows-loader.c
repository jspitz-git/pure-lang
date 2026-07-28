#include <stdio.h>
#include <windows.h>

static int check_export(HMODULE module, const char *name)
{
  if (GetProcAddress(module, name))
    return 1;

  fprintf(stderr, "pure-gtk loader test: missing export %s (error %lu)\n",
          name, GetLastError());
  return 0;
}

int main(void)
{
  HMODULE gtk = LoadLibraryA("gtk.dll");
  if (!gtk) {
    fprintf(stderr, "pure-gtk loader test: gtk.dll failed to load (error %lu)\n",
            GetLastError());
    return 1;
  }

  if (!check_export(gtk, "gtk_rc_parse") ||
      !check_export(gtk, "gtk_file_chooser_get_filename") ||
      !check_export(gtk, "gtk_ui_manager_add_ui_from_file")) {
    FreeLibrary(gtk);
    return 1;
  }

  FreeLibrary(gtk);
  puts("pure-gtk Windows loader test passed");
  return 0;
}
