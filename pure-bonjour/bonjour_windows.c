#include "bonjour_windows.h"

#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

static int bonjour_service_type_valid(const char *type)
{
  const char *suffix;
  size_t label_length;
  size_t i;

  if (type == NULL || type[0] != '_') return 0;
  suffix = strrchr(type, '.');
  if (suffix == NULL ||
      (strcmp(suffix, "._tcp") != 0 && strcmp(suffix, "._udp") != 0))
    return 0;
  label_length = (size_t)(suffix - type);
  if (label_length < 2 || label_length > 63) return 0;
  for (i = 1; i < label_length; ++i) {
    unsigned char c = (unsigned char)type[i];
    if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
          (c >= '0' && c <= '9') || c == '-'))
      return 0;
  }
  return 1;
}

static wchar_t *bonjour_wide_duplicate_range(const wchar_t *text, size_t length)
{
  wchar_t *copy;

  if (length > (SIZE_MAX / sizeof(*copy)) - 1) return NULL;
  copy = malloc((length + 1) * sizeof(*copy));
  if (copy == NULL) return NULL;
  memcpy(copy, text, length * sizeof(*copy));
  copy[length] = L'\0';
  return copy;
}

BONJOUR_WINDOWS_PRIVATE wchar_t *bonjour_utf8_to_wide(const char *utf8)
{
  int length;
  wchar_t *wide;

  if (utf8 == NULL) return NULL;
  length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8, -1, NULL, 0);
  if (length <= 0 || (size_t)length > SIZE_MAX / sizeof(*wide)) return NULL;
  wide = malloc((size_t)length * sizeof(*wide));
  if (wide == NULL) return NULL;
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8, -1, wide,
                          length) != length) {
    free(wide);
    return NULL;
  }
  return wide;
}

BONJOUR_WINDOWS_PRIVATE char *bonjour_wide_to_utf8(const wchar_t *wide)
{
  int length;
  char *utf8;

  if (wide == NULL) return NULL;
  length = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide, -1, NULL, 0,
                               NULL, NULL);
  if (length <= 0) return NULL;
  utf8 = malloc((size_t)length);
  if (utf8 == NULL) return NULL;
  if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide, -1, utf8, length,
                          NULL, NULL) != length) {
    free(utf8);
    return NULL;
  }
  return utf8;
}

BONJOUR_WINDOWS_PRIVATE wchar_t *bonjour_make_type_fqdn(const char *type)
{
  static const char local_suffix[] = ".local";
  size_t type_length;
  char *utf8_fqdn;
  wchar_t *wide_fqdn;

  if (!bonjour_service_type_valid(type)) return NULL;
  type_length = strlen(type);
  if (type_length > 255 - (sizeof(local_suffix) - 1)) return NULL;
  utf8_fqdn = malloc(type_length + sizeof(local_suffix));
  if (utf8_fqdn == NULL) return NULL;
  memcpy(utf8_fqdn, type, type_length);
  memcpy(utf8_fqdn + type_length, local_suffix, sizeof(local_suffix));
  wide_fqdn = bonjour_utf8_to_wide(utf8_fqdn);
  free(utf8_fqdn);
  return wide_fqdn;
}

BONJOUR_WINDOWS_PRIVATE wchar_t *bonjour_make_instance_fqdn(const char *name,
                                                             const char *type)
{
  static const char local_suffix[] = ".local";
  size_t name_length;
  size_t type_length;
  size_t fqdn_length;
  char *utf8_fqdn;
  wchar_t *wide_fqdn;

  if (name == NULL || name[0] == '\0' || !bonjour_service_type_valid(type))
    return NULL;
  name_length = strlen(name);
  type_length = strlen(type);
  if (name_length > 255 || type_length > 255 ||
      type_length > 255 - 1 - (sizeof(local_suffix) - 1) ||
      name_length > 255 - 1 - type_length - (sizeof(local_suffix) - 1))
    return NULL;
  fqdn_length = name_length + 1 + type_length + sizeof(local_suffix) - 1;
  utf8_fqdn = malloc(fqdn_length + 1);
  if (utf8_fqdn == NULL) return NULL;
  memcpy(utf8_fqdn, name, name_length);
  utf8_fqdn[name_length] = '.';
  memcpy(utf8_fqdn + name_length + 1, type, type_length);
  memcpy(utf8_fqdn + name_length + 1 + type_length, local_suffix,
         sizeof(local_suffix));
  wide_fqdn = bonjour_utf8_to_wide(utf8_fqdn);
  free(utf8_fqdn);
  return wide_fqdn;
}

BONJOUR_WINDOWS_PRIVATE int bonjour_split_instance_fqdn(const wchar_t *fqdn,
                                                         char **name,
                                                         char **type,
                                                         char **domain)
{
  const wchar_t *separator;
  const wchar_t *protocol;
  wchar_t *wide_type;
  wchar_t *wide_name;
  char *utf8_type;
  char *utf8_name;
  char *utf8_domain;

  if (name == NULL || type == NULL || domain == NULL) return -1;
  *name = NULL;
  *type = NULL;
  *domain = NULL;
  if (fqdn == NULL || fqdn[0] == L'\0') return -1;

  for (separator = wcschr(fqdn, L'.'); separator != NULL;
       separator = wcschr(separator + 1, L'.')) {
    protocol = wcsstr(separator + 1, L"._tcp.");
    if (protocol == NULL) protocol = wcsstr(separator + 1, L"._udp.");
    if (protocol == NULL) continue;

    wide_name = bonjour_wide_duplicate_range(fqdn,
                                             (size_t)(separator - fqdn));
    wide_type = bonjour_wide_duplicate_range(separator + 1,
                                             (size_t)(protocol - separator - 1) + 5);
    if (wide_name == NULL || wide_type == NULL) {
      free(wide_name);
      free(wide_type);
      return -1;
    }
    utf8_type = bonjour_wide_to_utf8(wide_type);
    if (utf8_type == NULL || !bonjour_service_type_valid(utf8_type)) {
      free(wide_name);
      free(wide_type);
      free(utf8_type);
      return -1;
    }
    utf8_name = bonjour_wide_to_utf8(wide_name);
    utf8_domain = bonjour_wide_to_utf8(protocol + 6);
    free(wide_name);
    free(wide_type);
    if (utf8_name == NULL || utf8_name[0] == '\0' || utf8_domain == NULL ||
        utf8_domain[0] == '\0') {
      free(utf8_name);
      free(utf8_type);
      free(utf8_domain);
      return -1;
    }
    *name = utf8_name;
    *type = utf8_type;
    *domain = utf8_domain;
    return 0;
  }
  return -1;
}

BONJOUR_WINDOWS_PRIVATE int bonjour_status_error(DWORD status)
{
  if (status == ERROR_SUCCESS) return 0;
  if (status > (DWORD)INT_MAX) return -INT_MAX;
  return -(int)status;
}
