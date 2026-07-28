#include <gtk/gtk.h>
#include <stdio.h>

static gboolean callback_seen;

static void clicked(GtkButton *button, gpointer user_data)
{
  (void)button;
  (void)user_data;
  callback_seen = TRUE;
  gtk_main_quit();
}

static gboolean activate(gpointer user_data)
{
  gtk_button_clicked(GTK_BUTTON(user_data));
  return FALSE;
}

static gboolean timed_out(gpointer user_data)
{
  (void)user_data;
  gtk_main_quit();
  return FALSE;
}

int main(void)
{
  GtkWidget *window;
  GtkWidget *button;
  guint timeout_id;

  if (!gtk_init_check(NULL, NULL)) {
    fputs("pure-gtk native GUI test: GTK initialization failed\n", stderr);
    return 1;
  }

  window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  button = gtk_button_new_with_label("Pure GTK callback");
  gtk_window_set_title(GTK_WINDOW(window), "Pure GTK smoke");
  gtk_window_set_default_size(GTK_WINDOW(window), 240, 80);
  gtk_container_add(GTK_CONTAINER(window), button);
  g_signal_connect(button, "clicked", G_CALLBACK(clicked), NULL);

  timeout_id = g_timeout_add(5000, timed_out, NULL);
  g_idle_add(activate, button);
  gtk_widget_show_all(window);
  gtk_main();

  if (callback_seen)
    g_source_remove(timeout_id);
  gtk_widget_destroy(window);

  if (!callback_seen) {
    fputs("pure-gtk native GUI test: callback timed out\n", stderr);
    return 1;
  }

  puts("pure-gtk native GUI test passed");
  return 0;
}
