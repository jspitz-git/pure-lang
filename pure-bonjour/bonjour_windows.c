#include "bonjour_windows.h"

#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#ifndef BONJOUR_WINDOWS_TESTING
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
#endif

typedef enum {
  BONJOUR_REG_PENDING,
  BONJOUR_REG_REGISTERED,
  BONJOUR_REG_FAILED,
  BONJOUR_REG_STOPPING,
  BONJOUR_REG_STOPPED
} bonjour_reg_state_t;

struct bonjour_service_t {
  SRWLOCK lock;
  CONDITION_VARIABLE callbacks_done;
  HANDLE completion;
  DNS_SERVICE_CANCEL cancel;
  PDNS_SERVICE_INSTANCE instance;
  bonjour_reg_state_t state;
  DWORD status;
  DWORD shutdown_status;
  unsigned callbacks;
  char *name;
  char *type;
  uint16_t port;
  const bonjour_dns_api_t *api;
  DWORD wait_ms;
};

static const bonjour_dns_api_t bonjour_system_dns_api = {
  DnsServiceConstructInstance,
  DnsServiceRegister,
  DnsServiceDeRegister,
  DnsServiceRegisterCancel,
  DnsServiceFreeInstance,
};

static char *bonjour_string_duplicate(const char *text)
{
  size_t length;
  char *copy;

  if (text == NULL) return NULL;
  length = strlen(text);
  if (length == SIZE_MAX) return NULL;
  copy = malloc(length + 1);
  if (copy != NULL) memcpy(copy, text, length + 1);
  return copy;
}

static int bonjour_request_accepted(DWORD status)
{
  return status == ERROR_SUCCESS || status == DNS_REQUEST_PENDING;
}

static WORD bonjour_network_port(uint16_t port)
{
  return (WORD)((port << 8) | (port >> 8));
}

static void WINAPI bonjour_register_complete(DWORD status, void *context,
                                              PDNS_SERVICE_INSTANCE instance)
{
  bonjour_service_t *service = context;
  char *effective_name = NULL;
  char *effective_type = NULL;
  char *effective_domain = NULL;

  AcquireSRWLockExclusive(&service->lock);
  ++service->callbacks;
  ReleaseSRWLockExclusive(&service->lock);

  if (status == ERROR_SUCCESS &&
      (instance == NULL || instance->pszInstanceName == NULL ||
       bonjour_split_instance_fqdn(instance->pszInstanceName, &effective_name,
                                   &effective_type, &effective_domain) != 0))
    status = ERROR_INVALID_DATA;

  AcquireSRWLockExclusive(&service->lock);
  if (service->state == BONJOUR_REG_PENDING) {
    if (status == ERROR_SUCCESS) {
      free(service->name);
      service->name = effective_name;
      effective_name = NULL;
      service->state = BONJOUR_REG_REGISTERED;
      service->status = ERROR_SUCCESS;
    } else {
      service->state = BONJOUR_REG_FAILED;
      service->status = status;
    }
  } else if (service->state == BONJOUR_REG_STOPPING &&
             service->shutdown_status == ERROR_IO_PENDING) {
    service->shutdown_status = status;
  }
  SetEvent(service->completion);
  --service->callbacks;
  if (service->callbacks == 0)
    WakeAllConditionVariable(&service->callbacks_done);
  ReleaseSRWLockExclusive(&service->lock);

  free(effective_name);
  free(effective_type);
  free(effective_domain);
}

static void bonjour_release_service(bonjour_service_t *service)
{
  service->api->free_instance(service->instance);
  CloseHandle(service->completion);
  free(service->name);
  free(service->type);
  free(service);
}

static bonjour_service_t *bonjour_publish_using_api(
    const char *name, const char *type, int port, const bonjour_dns_api_t *api,
    DWORD wait_ms)
{
  DNS_SERVICE_REGISTER_REQUEST request;
  bonjour_service_t *service;
  wchar_t *fqdn;
  DWORD status;

  if (api == NULL || api->construct_instance == NULL ||
      api->register_service == NULL || api->deregister_service == NULL ||
      api->cancel_registration == NULL || api->free_instance == NULL ||
      port < 0 || port > UINT16_MAX || wait_ms == INFINITE)
    return NULL;
  fqdn = bonjour_make_instance_fqdn(name, type);
  if (fqdn == NULL) return NULL;

  service = calloc(1, sizeof(*service));
  if (service == NULL) {
    free(fqdn);
    return NULL;
  }
  InitializeSRWLock(&service->lock);
  InitializeConditionVariable(&service->callbacks_done);
  service->completion = CreateEventW(NULL, TRUE, FALSE, NULL);
  service->name = bonjour_string_duplicate(name);
  service->type = bonjour_string_duplicate(type);
  service->port = (uint16_t)port;
  service->api = api;
  service->wait_ms = wait_ms;
  service->state = BONJOUR_REG_PENDING;
  service->status = ERROR_IO_PENDING;
  if (service->completion == NULL || service->name == NULL ||
      service->type == NULL) {
    if (service->completion != NULL) CloseHandle(service->completion);
    free(service->name);
    free(service->type);
    free(service);
    free(fqdn);
    return NULL;
  }

  service->instance = api->construct_instance(
      fqdn, NULL, NULL, NULL, bonjour_network_port((uint16_t)port), 0, 0, 0,
      NULL, NULL);
  free(fqdn);
  if (service->instance == NULL) {
    CloseHandle(service->completion);
    free(service->name);
    free(service->type);
    free(service);
    return NULL;
  }

  memset(&request, 0, sizeof(request));
  request.Version = 1;
  request.pServiceInstance = service->instance;
  request.pRegisterCompletionCallback = bonjour_register_complete;
  request.pQueryContext = service;
  status = api->register_service(&request, &service->cancel);
  if (!bonjour_request_accepted(status)) {
    api->free_instance(service->instance);
    CloseHandle(service->completion);
    free(service->name);
    free(service->type);
    free(service);
    return NULL;
  }
  return service;
}

bonjour_service_t *bonjour_publish(const char *name, const char *type, int port)
{
  return bonjour_publish_using_api(name, type, port, &bonjour_system_dns_api,
                                   10000);
}

#ifdef BONJOUR_WINDOWS_TESTING
BONJOUR_WINDOWS_PRIVATE bonjour_service_t *bonjour_publish_with_api(
    const char *name, const char *type, int port, const bonjour_dns_api_t *api,
    DWORD wait_ms)
{
  return bonjour_publish_using_api(name, type, port, api, wait_ms);
}
#endif

pure_expr *bonjour_check(bonjour_service_t *service)
{
  DWORD wait_status;
  DWORD status;
  bonjour_reg_state_t state;
  char *name;
  char *type;
  uint16_t port;
  pure_expr *result;

  if (service == NULL) return NULL;
  wait_status = WaitForSingleObject(service->completion, service->wait_ms);
  if (wait_status == WAIT_TIMEOUT)
    return pure_int(bonjour_status_error(ERROR_TIMEOUT));
  if (wait_status != WAIT_OBJECT_0)
    return pure_int(bonjour_status_error(GetLastError()));

  AcquireSRWLockShared(&service->lock);
  state = service->state;
  status = service->status;
  name = bonjour_string_duplicate(service->name);
  type = bonjour_string_duplicate(service->type);
  port = service->port;
  ReleaseSRWLockShared(&service->lock);
  if (state != BONJOUR_REG_REGISTERED) {
    free(name);
    free(type);
    return pure_int(bonjour_status_error(status));
  }
  if (name == NULL || type == NULL) {
    free(name);
    free(type);
    return pure_int(bonjour_status_error(ERROR_NOT_ENOUGH_MEMORY));
  }
  result = pure_tuplel(3, pure_cstring_dup(name), pure_cstring_dup(type),
                       pure_int(port));
  free(name);
  free(type);
  return result;
}

static int bonjour_wait_for_callbacks(bonjour_service_t *service)
{
  ULONGLONG started = GetTickCount64();
  int quiescent = 1;

  AcquireSRWLockExclusive(&service->lock);
  while (service->callbacks != 0) {
    ULONGLONG elapsed = GetTickCount64() - started;
    DWORD remaining;

    if (elapsed >= service->wait_ms) {
      quiescent = 0;
      break;
    }
    remaining = service->wait_ms - (DWORD)elapsed;
    if (!SleepConditionVariableSRW(&service->callbacks_done, &service->lock,
                                   remaining, 0)) {
      quiescent = 0;
      break;
    }
  }
  ReleaseSRWLockExclusive(&service->lock);
  return quiescent;
}

void bonjour_unpublish(bonjour_service_t *service)
{
  DNS_SERVICE_REGISTER_REQUEST request;
  bonjour_reg_state_t previous_state;
  DWORD status = ERROR_SUCCESS;
  DWORD completion_status = WAIT_OBJECT_0;

  if (service == NULL) return;
  AcquireSRWLockExclusive(&service->lock);
  previous_state = service->state;
  if (previous_state == BONJOUR_REG_STOPPING ||
      previous_state == BONJOUR_REG_STOPPED) {
    ReleaseSRWLockExclusive(&service->lock);
    return;
  }
  if (previous_state == BONJOUR_REG_REGISTERED)
    service->shutdown_status = ERROR_IO_PENDING;
  service->state = BONJOUR_REG_STOPPING;
  if (previous_state == BONJOUR_REG_REGISTERED)
    ResetEvent(service->completion);
  ReleaseSRWLockExclusive(&service->lock);

  if (previous_state == BONJOUR_REG_PENDING) {
    status = service->api->cancel_registration(&service->cancel);
  } else if (previous_state == BONJOUR_REG_REGISTERED) {
    memset(&request, 0, sizeof(request));
    request.Version = 1;
    request.pServiceInstance = service->instance;
    request.pRegisterCompletionCallback = bonjour_register_complete;
    request.pQueryContext = service;
    status = service->api->deregister_service(&request, NULL);
    if (bonjour_request_accepted(status)) {
      completion_status = WaitForSingleObject(service->completion,
                                              service->wait_ms);
      if (completion_status == WAIT_OBJECT_0) {
        AcquireSRWLockShared(&service->lock);
        status = service->shutdown_status;
        ReleaseSRWLockShared(&service->lock);
      }
    }
  }

  if (!bonjour_request_accepted(status) || completion_status != WAIT_OBJECT_0 ||
      !bonjour_wait_for_callbacks(service)) {
    fprintf(stderr,
            "pure-bonjour: registration shutdown failed or did not become "
            "quiescent within %lu ms (status %lu); retaining service state\n",
            (unsigned long)service->wait_ms, (unsigned long)status);
    return;
  }

  AcquireSRWLockExclusive(&service->lock);
  service->state = BONJOUR_REG_STOPPED;
  ReleaseSRWLockExclusive(&service->lock);
  bonjour_release_service(service);
}

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

static int bonjour_instance_label_valid(const char *name)
{
  size_t length;

  if (name == NULL || name[0] == '\0' || strchr(name, '.') != NULL) return 0;
  length = strlen(name);
  return length <= 63;
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

  if (!bonjour_instance_label_valid(name) || !bonjour_service_type_valid(type))
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
