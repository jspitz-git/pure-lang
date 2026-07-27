#include <sys/types.h>
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifndef _WIN32
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <netinet/in.h>
#include <netdb.h>
#else
#include <winsock2.h>
#include <ws2tcpip.h>
#endif

#include <pure/runtime.h>

#if !defined(AF_LOCAL) && defined(PF_LOCAL)
#define AF_LOCAL PF_LOCAL
#endif
#if !defined(AF_INET) && defined(PF_INET)
#define AF_INET PF_INET
#endif
#if !defined(AF_INET6) && defined(PF_INET6)
#define AF_INET6 PF_INET6
#endif
#ifndef AF_UNSPEC
#define AF_UNSPEC 0
#endif
#ifndef IPPROTO_IP
#define IPPROTO_IP 0
#endif

#ifdef _WIN32
// Unix domain sockets aren't available on Windows.
#undef AF_UNIX
// POSIX-compatible replacements for Windows-specific stuff.
#define SHUT_RD SD_RECEIVE
#define SHUT_WR SD_SEND
#define SHUT_RDWR SD_BOTH
#endif

#ifdef _WIN32
int socketpair(int domain, int ty, int protocol, int *sv)
{
  (void)domain;
  (void)ty;
  (void)protocol;
  (void)sv;
  // Not available on Windows.
  return -1;
}
#endif

static char socket_error_buf[1025];

int pure_socket_errno(void)
{
#ifdef _WIN32
  return WSAGetLastError();
#else
  return errno;
#endif
}

const char *pure_socket_strerror(int error)
{
#ifdef _WIN32
  DWORD len = FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM |
			     FORMAT_MESSAGE_IGNORE_INSERTS,
			     0, error, 0, socket_error_buf,
			     sizeof(socket_error_buf), 0);
  if (len) {
    while (len && (socket_error_buf[len-1] == '\r' ||
		   socket_error_buf[len-1] == '\n'))
      socket_error_buf[--len] = 0;
  } else {
    snprintf(socket_error_buf, sizeof(socket_error_buf),
	     "Winsock error %d", error);
  }
  return socket_error_buf;
#else
  return strerror(error);
#endif
}

#ifdef _WIN32
static SRWLOCK winsock_lock = SRWLOCK_INIT;
static int winsock_initialized;
static int winsock_cleanup_registered;

static void cleanup_winsock_at_exit(void);

int pure_socket_startup(void)
{
  int rc = 0;
  AcquireSRWLockExclusive(&winsock_lock);
  if (!winsock_initialized) {
    WORD version = MAKEWORD(2, 2);
    WSADATA data;
    rc = WSAStartup(version, &data);
    if (!rc && data.wVersion != version) {
      WSACleanup();
      rc = WSAVERNOTSUPPORTED;
    }
    if (!rc) {
      winsock_initialized = 1;
      if (!winsock_cleanup_registered) {
	if (atexit(cleanup_winsock_at_exit) == 0)
	  winsock_cleanup_registered = 1;
	else {
	  WSACleanup();
	  winsock_initialized = 0;
	  rc = WSASYSNOTREADY;
	}
      }
    }
  }
  ReleaseSRWLockExclusive(&winsock_lock);
  return rc;
}

int pure_socket_cleanup(void)
{
  int rc = 0;
  AcquireSRWLockExclusive(&winsock_lock);
  if (winsock_initialized) {
    rc = WSACleanup();
    if (!rc) winsock_initialized = 0;
  }
  ReleaseSRWLockExclusive(&winsock_lock);
  return rc;
}

static void cleanup_winsock_at_exit(void)
{
  pure_socket_cleanup();
}
#else
int pure_socket_startup(void) { return 0; }
int pure_socket_cleanup(void) { return 0; }
#endif

#define sockaddr_error pure_sym("::sockaddr_error")

static void sockaddr_err(const char *msg)
{
  if (!msg) msg = "Unknown error";
  pure_expr *err = pure_app(pure_symbol(sockaddr_error),
			    pure_cstring_dup(msg));
  pure_throw(err);
}

struct sockaddr *new_sockaddr()
{
  struct sockaddr *addr = malloc(sizeof(struct sockaddr_storage));
  if (addr) memset(addr, 0, sizeof(struct sockaddr_storage));
  return addr;
}

struct sockaddr *local_sockaddr(const char *path)
{
#ifdef AF_UNIX
  struct sockaddr_un *addr = malloc(sizeof(struct sockaddr_un));
  if (addr) {
    memset(addr, 0, sizeof(struct sockaddr_un));
    addr->sun_family = AF_UNIX;
    strncpy(addr->sun_path, path, sizeof(addr->sun_path)-1);
  }
  return (struct sockaddr*)addr;
#else
  (void)path;
  return 0;
#endif
}

struct sockaddr *make_sockaddr(int family, const char *host, const char *port)
{
  struct addrinfo hints, *res;
  struct sockaddr *addr = 0;
  int rc;
#ifdef _WIN32
  rc = pure_socket_startup();
  if (rc) {
    sockaddr_err(pure_socket_strerror(rc));
    return 0;
  }
#endif
  memset(&hints, 0, sizeof(hints));
  hints.ai_family = family;
  // host "*" means INADDR_ANY
  if (strcmp(host, "*") == 0) {
    hints.ai_flags |= AI_PASSIVE;
    host = 0;
  }
  rc = getaddrinfo(host, port, &hints, &res);
  if (rc) {
    sockaddr_err(gai_strerror(rc));
    return 0;
  }
  if (!res || !res->ai_addr) goto err;
  addr = malloc(res->ai_addrlen);
  if (!addr) goto err;
  memcpy(addr, res->ai_addr, res->ai_addrlen);
  freeaddrinfo(res);
  return addr;
 err:
  if (res) freeaddrinfo(res);
  return 0;
}

// Like above, but returns *all* matching addresses.
struct sockaddr **make_sockaddrs(int family, const char *host, const char *port)
{
  struct addrinfo hints, *res, *res0;
  struct sockaddr *addr = 0, **addrs;
  size_t count;
  int rc;
#ifdef _WIN32
  rc = pure_socket_startup();
  if (rc) {
    sockaddr_err(pure_socket_strerror(rc));
    return 0;
  }
#endif
  memset(&hints, 0, sizeof(hints));
  hints.ai_family = family;
  // host "*" means INADDR_ANY
  if (strcmp(host, "*") == 0) {
    hints.ai_flags |= AI_PASSIVE;
    host = 0;
  }
  rc = getaddrinfo(host, port, &hints, &res);
  if (rc) {
    sockaddr_err(gai_strerror(rc));
    return 0;
  }
  for (count = 0, res0 = res; res && res->ai_addr; res = res->ai_next)
    count++;
  addrs = malloc((count+1)*sizeof(struct sockaddr*));
  if (!addrs) goto err;
  if (count == 0) {
    if (res0) freeaddrinfo(res0);
    addrs[0] = 0;
    return 0;
  }
  for (count = 0, res = res0; res && res->ai_addr; res = res->ai_next) {
    addr = malloc(res->ai_addrlen);
    if (!addr) {
      while (count > 0) free(addrs[--count]);
      free(addrs);
      goto err;
    }
    memcpy(addr, res->ai_addr, res->ai_addrlen);
    addrs[count++] = addr;
  }
  addrs[count++] = 0;
  freeaddrinfo(res);
  return addrs;
 err:
  if (res0) freeaddrinfo(res0);
  return 0;
}

int sockaddr_family(struct sockaddr *addr)
{
  if (!addr)
    return 0;
  else
    return addr->sa_family;
}

const char *sockaddr_path(struct sockaddr *addr)
{
  if (!addr)
    return 0;
#ifdef AF_UNIX
  else if (addr->sa_family == AF_UNIX)
    return ((struct sockaddr_un*)addr)->sun_path;
#endif
  else
    return 0;
}

int sockaddr_port(struct sockaddr *addr)
{
  if (!addr)
    return -1;
  else if (addr->sa_family == AF_INET)
    return ntohs(((struct sockaddr_in*)addr)->sin_port);
  else if (addr->sa_family == AF_INET6)
    return ntohs(((struct sockaddr_in6*)addr)->sin6_port);
  else
    return -1;
}

static char buf[1025]; // TLD

const char *sockaddr_hostname(struct sockaddr *addr)
{
  if (!addr)
    return 0;
  else if (addr->sa_family == AF_INET || addr->sa_family == AF_INET6) {
    size_t len = (addr->sa_family == AF_INET)?
      sizeof(struct sockaddr_in):sizeof(struct sockaddr_in6);
    int rc = getnameinfo(addr, len, buf, sizeof(buf), 0, 0, 0);
    if (rc) {
      sockaddr_err(gai_strerror(rc));
      return 0;
    }
    return buf;
  } else
    return 0;
}

const char *sockaddr_ip(struct sockaddr *addr)
{
  if (!addr)
    return 0;
  else if (addr->sa_family == AF_INET || addr->sa_family == AF_INET6) {
    size_t len = (addr->sa_family == AF_INET)?
      sizeof(struct sockaddr_in):sizeof(struct sockaddr_in6);
    int rc = getnameinfo(addr, len, buf, sizeof(buf), 0, 0, NI_NUMERICHOST);
    if (rc) {
      sockaddr_err(gai_strerror(rc));
      return 0;
    }
    return buf;
  } else
    return 0;
}

const char *sockaddr_service(struct sockaddr *addr)
{
  if (!addr)
    return 0;
  else if (addr->sa_family == AF_INET || addr->sa_family == AF_INET6) {
    size_t len = (addr->sa_family == AF_INET)?
      sizeof(struct sockaddr_in):sizeof(struct sockaddr_in6);
    int rc = getnameinfo(addr, len, 0, 0, buf, sizeof(buf), 0);
    if (rc) {
      sockaddr_err(gai_strerror(rc));
      return 0;
    }
    return buf;
  } else
    return 0;
}

socklen_t sockaddr_len(struct sockaddr *addr)
{
  if (!addr)
    return 0;
  else if (addr->sa_family == 0)
    return sizeof(struct sockaddr_storage);
#ifdef AF_UNIX
  else if (addr->sa_family == AF_UNIX)
    return sizeof(struct sockaddr_un);
#endif
  else if (addr->sa_family == AF_INET)
    return sizeof(struct sockaddr_in);
  else if (addr->sa_family == AF_INET6)
    return sizeof(struct sockaddr_in6);
  else
    return 0;
}

/* We provide thin wrappers for the socket functions from the system
   library, as on Windows these use the stdcall calling convention and
   thus can't be called directly by Pure programs. */

#ifdef _WIN32
static SOCKET native_socket(int64_t fd)
{ return (SOCKET)(uintptr_t)fd; }

static int64_t portable_socket(SOCKET fd)
{ return fd == INVALID_SOCKET ? -1 : (int64_t)(uintptr_t)fd; }

static int winsock_length(size_t len)
{
  if (len > INT_MAX) {
    WSASetLastError(WSAEMSGSIZE);
    return -1;
  }
  return (int)len;
}
#else
static int native_socket(int64_t fd)
{ return (int)fd; }
#endif

int64_t pure_socket(int domain, int ty, int protocol)
{
#ifdef _WIN32
  int rc = pure_socket_startup();
  if (rc) {
    WSASetLastError(rc);
    return -1;
  }
  return portable_socket(socket(domain, ty, protocol));
#else
  return socket(domain, ty, protocol);
#endif
}

int pure_socketpair(int domain, int ty, int protocol, int *sv)
{ return socketpair(domain, ty, protocol, sv); }

int pure_shutdown(int64_t fd, int how)
{ return shutdown(native_socket(fd), how); }

/* Windows uses this to close a socket. On POSIX systems this is just the same
   as close(). */

int pure_closesocket(int64_t fd)
{
#ifdef _WIN32
  return closesocket(native_socket(fd));
#else
  return close(native_socket(fd));
#endif
}

int pure_listen(int64_t fd, int backlog)
{ return listen(native_socket(fd), backlog); }

int64_t pure_accept(int64_t fd, struct sockaddr *addr, int *addrlen)
{
#ifdef _WIN32
  return portable_socket(accept(native_socket(fd), addr, (socklen_t*)addrlen));
#else
  return accept(native_socket(fd), addr, (socklen_t*)addrlen);
#endif
}

int pure_bind(int64_t fd, struct sockaddr *addr, int addrlen)
{ return bind(native_socket(fd), addr, addrlen); }

int pure_connect(int64_t fd, struct sockaddr *addr, int addrlen)
{ return connect(native_socket(fd), addr, addrlen); }

int64_t pure_recv(int64_t fd, void *buf, size_t len, int flags)
{
#ifdef _WIN32
  int n = winsock_length(len);
  return n < 0 ? -1 : recv(native_socket(fd), (char*)buf, n, flags);
#else
  return recv(native_socket(fd), buf, len, flags);
#endif
}

int64_t pure_send(int64_t fd, const void *buf, size_t len, int flags)
{
#ifdef _WIN32
  int n = winsock_length(len);
  return n < 0 ? -1 : send(native_socket(fd), (const char*)buf, n, flags);
#else
  return send(native_socket(fd), buf, len, flags);
#endif
}

int64_t pure_recvfrom(int64_t fd, void *buf, size_t len, int flags,
		      struct sockaddr *addr, int *addrlen)
{
#ifdef _WIN32
  int n = winsock_length(len);
  return n < 0 ? -1 :
    recvfrom(native_socket(fd), (char*)buf, n, flags, addr,
	     (socklen_t*)addrlen);
#else
  return recvfrom(native_socket(fd), buf, len, flags, addr,
		  (socklen_t*)addrlen);
#endif
}

int64_t pure_sendto(int64_t fd, const void *buf, size_t len, int flags,
		    struct sockaddr *addr, int addrlen)
{
#ifdef _WIN32
  int n = winsock_length(len);
  return n < 0 ? -1 :
    sendto(native_socket(fd), (const char*)buf, n, flags, addr, addrlen);
#else
  return sendto(native_socket(fd), buf, len, flags, addr, addrlen);
#endif
}

int pure_getsockname(int64_t fd, struct sockaddr *addr, int *addrlen)
{ return getsockname(native_socket(fd), addr, (socklen_t*)addrlen); }

int pure_getpeername(int64_t fd, struct sockaddr *addr, int *addrlen)
{ return getpeername(native_socket(fd), addr, (socklen_t*)addrlen); }

int pure_getsockopt(int64_t fd, int level, int name, void *val, int *len)
{ return getsockopt(native_socket(fd), level, name, val, (socklen_t*)len); }

int pure_setsockopt(int64_t fd, int level, int name, const void *val, int len)
{ return setsockopt(native_socket(fd), level, name, val, len); }

#define define(sym) pure_def(pure_sym(#sym), pure_int(sym))

void __socket_defs(void)
{
#ifdef _WIN32
  int rc = pure_socket_startup();
  if (rc) {
    sockaddr_err(pure_socket_strerror(rc));
    return;
  }
#endif
  // Address families.
  define(AF_UNSPEC);
#ifdef AF_LOCAL
  define(AF_LOCAL);
#endif
#ifdef AF_UNIX
  define(AF_UNIX);
#endif
#ifdef AF_FILE
  define(AF_FILE);
#endif
  define(AF_INET);
  define(AF_INET6);
  // Socket types.
  define(SOCK_STREAM);
  define(SOCK_DGRAM);
#ifdef SOCK_SEQPACKET
  define(SOCK_SEQPACKET);
#endif
#ifdef SOCK_RAW
  define(SOCK_RAW);
#endif
#ifdef SOCK_RDM
  define(SOCK_RDM);
#endif
#ifdef SOCK_NONBLOCK
  // Useful on Linux to enable non-blocking operation.
  define(SOCK_NONBLOCK);
#endif
#ifdef SOCK_CLOEXEC
  // Useful on Linux to set the FD_CLOEXEC flag on the socket descriptor.
  define(SOCK_CLOEXEC);
#endif
  // shutdown flags.
#ifdef _WIN32
  define(SD_RECEIVE);
  define(SD_SEND);
  define(SD_BOTH);
#endif
  define(SHUT_RD);
  define(SHUT_WR);
  define(SHUT_RDWR);
  // send/recv flags.
#ifdef MSG_EOR
  define(MSG_EOR);
#endif
  define(MSG_OOB);
  define(MSG_PEEK);
#ifdef MSG_WAITALL
  define(MSG_WAITALL);
#endif
#ifdef MSG_DONTWAIT
  // Useful on Linux to enable non-blocking operation.
  define(MSG_DONTWAIT);
#endif
  // getsockopt/setsockopt flags.
  define(SOL_SOCKET);
  define(SO_ACCEPTCONN);
  define(SO_BROADCAST);
  define(SO_DEBUG);
  define(SO_DONTROUTE);
  define(SO_ERROR);
  define(SO_KEEPALIVE);
  define(SO_LINGER);
  define(SO_OOBINLINE);
  define(SO_RCVBUF);
#ifdef SO_RCVLOWAT
  define(SO_RCVLOWAT);
#endif
#ifdef SO_RCVTIMEO
  define(SO_RCVTIMEO);
#endif
  define(SO_REUSEADDR);
  define(SO_SNDBUF);
#ifdef SO_SNDLOWAT
  define(SO_SNDLOWAT);
#endif
#ifdef SO_SNDTIMEO
  define(SO_SNDTIMEO);
#endif
  define(SO_TYPE);
  // Important IP protocol numbers.
  define(IPPROTO_IP);
  define(IPPROTO_ICMP);
  define(IPPROTO_TCP);
  define(IPPROTO_UDP);
}
