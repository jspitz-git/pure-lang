#include <stdint.h>
#include <stdio.h>
#include <winsock2.h>
#include <windows.h>

_Static_assert(sizeof(int64_t) >= sizeof(SOCKET),
	       "portable socket handle must hold SOCKET");

typedef int (*startup_fn)(void);
typedef int (*cleanup_fn)(void);
typedef int64_t (*socket_fn)(int, int, int);
typedef int (*close_fn)(int64_t);
typedef int (*shutdown_fn)(int64_t, int);
typedef int (*error_fn)(void);
typedef const char *(*strerror_fn)(int);

static FARPROC required_symbol(HMODULE module, const char *name)
{
  FARPROC symbol = GetProcAddress(module, name);
  if (!symbol)
    fprintf(stderr, "missing export: %s\n", name);
  return symbol;
}

int main(int argc, char **argv)
{
  HMODULE module;
  startup_fn startup;
  cleanup_fn cleanup;
  socket_fn open_socket;
  close_fn close_socket;
  shutdown_fn shutdown_socket;
  error_fn socket_error;
  strerror_fn socket_strerror;
  int64_t fd;
  int error;

  if (argc != 2) {
    fprintf(stderr, "usage: %s sockets.dll\n", argv[0]);
    return 2;
  }
  module = LoadLibraryA(argv[1]);
  if (!module) {
    fprintf(stderr, "LoadLibrary failed: %lu\n", GetLastError());
    return 1;
  }

  startup = (startup_fn)required_symbol(module, "pure_socket_startup");
  cleanup = (cleanup_fn)required_symbol(module, "pure_socket_cleanup");
  open_socket = (socket_fn)required_symbol(module, "pure_socket");
  close_socket = (close_fn)required_symbol(module, "pure_closesocket");
  shutdown_socket = (shutdown_fn)required_symbol(module, "pure_shutdown");
  socket_error = (error_fn)required_symbol(module, "pure_socket_errno");
  socket_strerror =
    (strerror_fn)required_symbol(module, "pure_socket_strerror");
  if (!startup || !cleanup || !open_socket || !close_socket ||
      !shutdown_socket || !socket_error || !socket_strerror) {
    FreeLibrary(module);
    return 1;
  }

  if (startup() || startup()) {
    fprintf(stderr, "idempotent Winsock startup failed\n");
    FreeLibrary(module);
    return 1;
  }
  fd = open_socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
  if (fd < 0 || close_socket(fd)) {
    fprintf(stderr, "socket open/close failed\n");
    FreeLibrary(module);
    return 1;
  }
  if (cleanup() || cleanup() || startup()) {
    fprintf(stderr, "Winsock cleanup/restart failed\n");
    FreeLibrary(module);
    return 1;
  }

  if (close_socket(-1) != SOCKET_ERROR) {
    fprintf(stderr, "invalid socket did not fail\n");
    FreeLibrary(module);
    return 1;
  }
  error = socket_error();
  if (error != WSAENOTSOCK || !socket_strerror(error) ||
      !*socket_strerror(error)) {
    fprintf(stderr, "Winsock error translation failed: %d\n", error);
    FreeLibrary(module);
    return 1;
  }

  fd = open_socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (fd < 0 || shutdown_socket(fd, SD_BOTH) != SOCKET_ERROR ||
      socket_error() != WSAENOTCONN || close_socket(fd) || cleanup()) {
    fprintf(stderr, "socket open/close after restart failed\n");
    FreeLibrary(module);
    return 1;
  }

  FreeLibrary(module);
  puts("PURE_SOCKETS_WINSOCK_AUDIT_OK");
  return 0;
}
