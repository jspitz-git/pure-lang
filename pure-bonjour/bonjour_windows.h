#ifndef PURE_BONJOUR_WINDOWS_H
#define PURE_BONJOUR_WINDOWS_H

#include <windows.h>

#ifdef BONJOUR_WINDOWS_TESTING
#define BONJOUR_WINDOWS_PRIVATE
#else
#define BONJOUR_WINDOWS_PRIVATE static __attribute__((unused))
#endif

/* Each string result is heap allocated and must be released with free(). */
BONJOUR_WINDOWS_PRIVATE wchar_t *bonjour_utf8_to_wide(const char *utf8);
BONJOUR_WINDOWS_PRIVATE char *bonjour_wide_to_utf8(const wchar_t *wide);

/* Each FQDN result is heap allocated and must be released with free(). */
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

#endif
