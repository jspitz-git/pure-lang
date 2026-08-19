#ifndef PURE_BONJOUR_WINDOWS_H
#define PURE_BONJOUR_WINDOWS_H

#include <pure/runtime.h>
#include <windows.h>
#include <windns.h>

typedef struct bonjour_service_t bonjour_service_t;
typedef struct bonjour_browser_t bonjour_browser_t;

bonjour_service_t *bonjour_publish(const char *name, const char *type, int port);
pure_expr *bonjour_check(bonjour_service_t *service);
void bonjour_unpublish(bonjour_service_t *service);
bonjour_browser_t *bonjour_browse(const char *type);
int bonjour_avail(bonjour_browser_t *browser);
pure_expr *bonjour_get(bonjour_browser_t *browser);
void bonjour_close(bonjour_browser_t *browser);

#ifdef BONJOUR_WINDOWS_TESTING
#define BONJOUR_WINDOWS_PRIVATE
#else
#define BONJOUR_WINDOWS_PRIVATE static __attribute__((unused))
#endif

/* Each string result is heap allocated and must be released with free(). */
BONJOUR_WINDOWS_PRIVATE wchar_t *bonjour_utf8_to_wide(const char *utf8);
BONJOUR_WINDOWS_PRIVATE char *bonjour_wide_to_utf8(const wchar_t *wide);

/* Each FQDN result is heap allocated and must be released with free().
   Instance names are one UTF-8 DNS-SD label (at most 63 bytes); literal dots
   and backslashes use DNS presentation escaping. */
BONJOUR_WINDOWS_PRIVATE wchar_t *bonjour_make_type_fqdn(const char *type);
BONJOUR_WINDOWS_PRIVATE wchar_t *bonjour_make_instance_fqdn(const char *name,
                                                            const char *type);

/* Returns 0 with three owned UTF-8 strings, or a negative status on failure. */
BONJOUR_WINDOWS_PRIVATE int bonjour_split_instance_fqdn(const wchar_t *fqdn,
                                                        char **name,
                                                        char **type,
                                                        char **domain);

/* Returns 0 for ERROR_SUCCESS and a negative, overflow-safe status otherwise. */
BONJOUR_WINDOWS_PRIVATE int bonjour_status_error(DWORD status);

typedef struct bonjour_result_t {
  struct bonjour_result_t *next;
  wchar_t *fqdn;
  DWORD interface_index;
  char *name;
  char *type;
  char *domain;
  char *address;
  uint16_t port;
} bonjour_result_t;

typedef struct {
  bonjour_result_t *head;
  size_t count;
} bonjour_result_set_t;

BONJOUR_WINDOWS_PRIVATE int bonjour_results_put(
    bonjour_result_set_t *set, const wchar_t *fqdn, DWORD interface_index,
    const char *name, const char *type, const char *domain,
    const char *address, uint16_t port);
BONJOUR_WINDOWS_PRIVATE int bonjour_results_remove(
    bonjour_result_set_t *set, const wchar_t *fqdn, DWORD interface_index);
BONJOUR_WINDOWS_PRIVATE void bonjour_results_clear(bonjour_result_set_t *set);

#ifdef BONJOUR_WINDOWS_TESTING
typedef struct {
  PDNS_SERVICE_INSTANCE (WINAPI *construct_instance)(
      PCWSTR, PCWSTR, PIP4_ADDRESS, PIP6_ADDRESS, WORD, WORD, WORD, DWORD,
      PCWSTR *, PCWSTR *);
  DWORD (WINAPI *register_service)(PDNS_SERVICE_REGISTER_REQUEST,
                                   PDNS_SERVICE_CANCEL);
  DWORD (WINAPI *deregister_service)(PDNS_SERVICE_REGISTER_REQUEST,
                                     PDNS_SERVICE_CANCEL);
  DWORD (WINAPI *cancel_registration)(PDNS_SERVICE_CANCEL);
  VOID (WINAPI *free_instance)(PDNS_SERVICE_INSTANCE);
  DNS_STATUS (WINAPI *browse)(PDNS_SERVICE_BROWSE_REQUEST,
                              PDNS_SERVICE_CANCEL);
  DNS_STATUS (WINAPI *cancel_browse)(PDNS_SERVICE_CANCEL);
  DNS_STATUS (WINAPI *resolve)(PDNS_SERVICE_RESOLVE_REQUEST,
                               PDNS_SERVICE_CANCEL);
  DNS_STATUS (WINAPI *cancel_resolve)(PDNS_SERVICE_CANCEL);
  VOID (WINAPI *free_records)(PDNS_RECORD, DNS_FREE_TYPE);
  VOID (WINAPI *before_resolver_link)(void);
  VOID (WINAPI *before_browser_cleanup)(void);
  VOID (WINAPI *after_browse_route_acquire)(void);
} bonjour_dns_api_t;

BONJOUR_WINDOWS_PRIVATE bonjour_service_t *bonjour_publish_with_api(
    const char *name, const char *type, int port, const bonjour_dns_api_t *api,
    DWORD wait_ms);
BONJOUR_WINDOWS_PRIVATE bonjour_browser_t *bonjour_browse_with_api(
    const char *type, const bonjour_dns_api_t *api, DWORD wait_ms);
BONJOUR_WINDOWS_PRIVATE size_t bonjour_browser_name_state_count(
    bonjour_browser_t *browser);
BONJOUR_WINDOWS_PRIVATE size_t bonjour_callback_registry_count(void);
#endif

#endif
