#ifndef PURE_BONJOUR_WINDOWS_H
#define PURE_BONJOUR_WINDOWS_H

#include <pure/runtime.h>
#include <windows.h>
#include <windns.h>

typedef struct bonjour_service_t bonjour_service_t;

bonjour_service_t *bonjour_publish(const char *name, const char *type, int port);
pure_expr *bonjour_check(bonjour_service_t *service);
void bonjour_unpublish(bonjour_service_t *service);

#ifdef BONJOUR_WINDOWS_TESTING
#define BONJOUR_WINDOWS_PRIVATE
#else
#define BONJOUR_WINDOWS_PRIVATE static __attribute__((unused))
#endif

/* Each string result is heap allocated and must be released with free(). */
BONJOUR_WINDOWS_PRIVATE wchar_t *bonjour_utf8_to_wide(const char *utf8);
BONJOUR_WINDOWS_PRIVATE char *bonjour_wide_to_utf8(const wchar_t *wide);

/* Each FQDN result is heap allocated and must be released with free().
   Instance names are one raw UTF-8 DNS-SD label (at most 63 bytes); raw dots
   are rejected because this private helper has no escaping contract. */
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
} bonjour_dns_api_t;

BONJOUR_WINDOWS_PRIVATE bonjour_service_t *bonjour_publish_with_api(
    const char *name, const char *type, int port, const bonjour_dns_api_t *api,
    DWORD wait_ms);
#endif

#endif
