#include <winsock2.h>
#include <ws2tcpip.h>

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
  DNS_STATUS (WINAPI *browse)(PDNS_SERVICE_BROWSE_REQUEST,
                              PDNS_SERVICE_CANCEL);
  DNS_STATUS (WINAPI *cancel_browse)(PDNS_SERVICE_CANCEL);
  DNS_STATUS (WINAPI *resolve)(PDNS_SERVICE_RESOLVE_REQUEST,
                               PDNS_SERVICE_CANCEL);
  DNS_STATUS (WINAPI *cancel_resolve)(PDNS_SERVICE_CANCEL);
  VOID (WINAPI *free_records)(PDNS_RECORD, DNS_FREE_TYPE);
} bonjour_dns_api_t;
#endif

typedef struct bonjour_resolver_t bonjour_resolver_t;
typedef struct bonjour_name_state_t bonjour_name_state_t;

struct bonjour_name_state_t {
  bonjour_name_state_t *next;
  wchar_t *fqdn;
  uint64_t generation;
  int present;
};

struct bonjour_resolver_t {
  bonjour_resolver_t *next;
  bonjour_resolver_t *retired_next;
  bonjour_browser_t *browser;
  DNS_SERVICE_CANCEL cancel;
  wchar_t *fqdn;
  DWORD interface_index;
  uint64_t generation;
  int dispatching;
  int completed;
};

struct bonjour_browser_t {
  SRWLOCK lock;
  CONDITION_VARIABLE callbacks_done;
  DNS_SERVICE_CANCEL cancel;
  wchar_t *type_fqdn;
  bonjour_result_set_t results;
  bonjour_resolver_t *resolvers;
  bonjour_resolver_t *retired;
  bonjour_name_state_t *names;
  DWORD status;
  unsigned callbacks;
  unsigned dispatches;
  int avail;
  int closing;
  int browse_cancel_acknowledged;
  const bonjour_dns_api_t *api;
  DWORD wait_ms;
};

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

static void WINAPI bonjour_system_free_records(PDNS_RECORD records,
                                                DNS_FREE_TYPE free_type)
{
  (void)free_type;
  DnsRecordListFree(records, free_type);
}

static const bonjour_dns_api_t bonjour_system_dns_api = {
  DnsServiceConstructInstance,
  DnsServiceRegister,
  DnsServiceDeRegister,
  DnsServiceRegisterCancel,
  DnsServiceFreeInstance,
  DnsServiceBrowse,
  DnsServiceBrowseCancel,
  DnsServiceResolve,
  DnsServiceResolveCancel,
  bonjour_system_free_records,
#ifdef BONJOUR_WINDOWS_TESTING
  NULL,
#endif
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

static wchar_t *bonjour_local_hostname(void)
{
  static const wchar_t suffix[] = L".local";
  wchar_t label[DNS_MAX_NAME_BUFFER_LENGTH];
  DWORD capacity = DNS_MAX_NAME_BUFFER_LENGTH;
  size_t label_length;
  wchar_t *hostname;

  if (!GetComputerNameExW(ComputerNameDnsHostname, label, &capacity) ||
      capacity == 0)
    return NULL;
  label_length = wcslen(label);
  if (label_length > DNS_MAX_NAME_LENGTH - (sizeof(suffix) / sizeof(*suffix)))
    return NULL;
  hostname = malloc((label_length + sizeof(suffix) / sizeof(*suffix)) *
                    sizeof(*hostname));
  if (hostname == NULL) return NULL;
  memcpy(hostname, label, label_length * sizeof(*hostname));
  memcpy(hostname + label_length, suffix, sizeof(suffix));
  return hostname;
}

static int bonjour_fqdn_equal(const wchar_t *left, const wchar_t *right)
{
  if (left == NULL || right == NULL) return 0;
  return CompareStringOrdinal(left, -1, right, -1, TRUE) == CSTR_EQUAL;
}

static int bonjour_request_accepted(DWORD status)
{
  return status == ERROR_SUCCESS || status == DNS_REQUEST_PENDING;
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
  ReleaseSRWLockExclusive(&service->lock);

  free(effective_name);
  free(effective_type);
  free(effective_domain);
  if (instance != NULL) service->api->free_instance(instance);

  AcquireSRWLockExclusive(&service->lock);
  --service->callbacks;
  if (service->callbacks == 0)
    WakeAllConditionVariable(&service->callbacks_done);
  ReleaseSRWLockExclusive(&service->lock);
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
  wchar_t *hostname;
  DWORD status;

  if (api == NULL || api->construct_instance == NULL ||
      api->register_service == NULL || api->deregister_service == NULL ||
      api->cancel_registration == NULL || api->free_instance == NULL ||
      port < 0 || port > UINT16_MAX || wait_ms == INFINITE)
    return NULL;
  fqdn = bonjour_make_instance_fqdn(name, type);
  if (fqdn == NULL) return NULL;
  hostname = bonjour_local_hostname();
  if (hostname == NULL) {
    free(fqdn);
    return NULL;
  }

  service = calloc(1, sizeof(*service));
  if (service == NULL) {
    free(fqdn);
    free(hostname);
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
    free(hostname);
    return NULL;
  }

  service->instance = api->construct_instance(
      fqdn, hostname, NULL, NULL, (WORD)port, 0, 0, 0,
      NULL, NULL);
  free(fqdn);
  free(hostname);
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

static void bonjour_result_free(bonjour_result_t *result)
{
  free(result->fqdn);
  free(result->name);
  free(result->type);
  free(result->domain);
  free(result->address);
  free(result);
}

BONJOUR_WINDOWS_PRIVATE int bonjour_results_put(
    bonjour_result_set_t *set, const wchar_t *fqdn, DWORD interface_index,
    const char *name, const char *type, const char *domain,
    const char *address, uint16_t port)
{
  bonjour_result_t *result;
  char *new_name;
  char *new_type;
  char *new_domain;
  char *new_address;

  if (set == NULL || fqdn == NULL || name == NULL || type == NULL ||
      domain == NULL || address == NULL)
    return -1;
  for (result = set->head; result != NULL; result = result->next)
    if (result->interface_index == interface_index &&
        bonjour_fqdn_equal(result->fqdn, fqdn))
      break;
  if (result != NULL && strcmp(result->name, name) == 0 &&
      strcmp(result->type, type) == 0 && strcmp(result->domain, domain) == 0 &&
      strcmp(result->address, address) == 0 && result->port == port)
    return 0;

  new_name = bonjour_string_duplicate(name);
  new_type = bonjour_string_duplicate(type);
  new_domain = bonjour_string_duplicate(domain);
  new_address = bonjour_string_duplicate(address);
  if (new_name == NULL || new_type == NULL || new_domain == NULL ||
      new_address == NULL) {
    free(new_name);
    free(new_type);
    free(new_domain);
    free(new_address);
    return -1;
  }

  if (result == NULL) {
    size_t fqdn_length = wcslen(fqdn);
    wchar_t *new_fqdn = bonjour_wide_duplicate_range(fqdn, fqdn_length);

    result = calloc(1, sizeof(*result));
    if (new_fqdn == NULL || result == NULL) {
      free(new_fqdn);
      free(result);
      free(new_name);
      free(new_type);
      free(new_domain);
      free(new_address);
      return -1;
    }
    result->fqdn = new_fqdn;
    result->interface_index = interface_index;
    result->next = set->head;
    set->head = result;
    ++set->count;
  } else {
    free(result->name);
    free(result->type);
    free(result->domain);
    free(result->address);
  }
  result->name = new_name;
  result->type = new_type;
  result->domain = new_domain;
  result->address = new_address;
  result->port = port;
  return 1;
}

BONJOUR_WINDOWS_PRIVATE int bonjour_results_remove(
    bonjour_result_set_t *set, const wchar_t *fqdn, DWORD interface_index)
{
  bonjour_result_t **link;

  if (set == NULL || fqdn == NULL) return 0;
  for (link = &set->head; *link != NULL; link = &(*link)->next) {
    bonjour_result_t *result = *link;

    if (result->interface_index != interface_index ||
        !bonjour_fqdn_equal(result->fqdn, fqdn))
      continue;
    *link = result->next;
    bonjour_result_free(result);
    --set->count;
    return 1;
  }
  return 0;
}

BONJOUR_WINDOWS_PRIVATE void bonjour_results_clear(bonjour_result_set_t *set)
{
  bonjour_result_t *result;

  if (set == NULL) return;
  while ((result = set->head) != NULL) {
    set->head = result->next;
    bonjour_result_free(result);
  }
  set->count = 0;
}

static int bonjour_results_remove_fqdn(bonjour_result_set_t *set,
                                       const wchar_t *fqdn)
{
  bonjour_result_t **link = &set->head;
  int changed = 0;

  while (*link != NULL) {
    bonjour_result_t *result = *link;

    if (!bonjour_fqdn_equal(result->fqdn, fqdn)) {
      link = &result->next;
      continue;
    }
    *link = result->next;
    bonjour_result_free(result);
    --set->count;
    changed = 1;
  }
  return changed;
}

static int bonjour_results_contain_fqdn(const bonjour_result_set_t *set,
                                        const wchar_t *fqdn)
{
  const bonjour_result_t *result;

  for (result = set->head; result != NULL; result = result->next)
    if (bonjour_fqdn_equal(result->fqdn, fqdn)) return 1;
  return 0;
}

static bonjour_name_state_t *bonjour_name_find_locked(
    bonjour_browser_t *browser, const wchar_t *fqdn)
{
  bonjour_name_state_t *state;

  for (state = browser->names; state != NULL; state = state->next)
    if (bonjour_fqdn_equal(state->fqdn, fqdn)) return state;
  return NULL;
}

static bonjour_name_state_t *bonjour_name_get_locked(
    bonjour_browser_t *browser, const wchar_t *fqdn)
{
  bonjour_name_state_t *state = bonjour_name_find_locked(browser, fqdn);

  if (state != NULL) return state;
  state = calloc(1, sizeof(*state));
  if (state == NULL) return NULL;
  state->fqdn = bonjour_wide_duplicate_range(fqdn, wcslen(fqdn));
  if (state->fqdn == NULL) {
    free(state);
    return NULL;
  }
  state->next = browser->names;
  browser->names = state;
  return state;
}

static int bonjour_name_add_locked(bonjour_browser_t *browser,
                                   const wchar_t *fqdn,
                                   uint64_t *generation)
{
  bonjour_name_state_t *state = bonjour_name_get_locked(browser, fqdn);

  if (state == NULL || generation == NULL) return 0;
  if (!state->present) {
    if (state->generation == UINT64_MAX) return 0;
    ++state->generation;
    state->present = 1;
  }
  *generation = state->generation;
  return 1;
}

static int bonjour_name_delete_locked(bonjour_browser_t *browser,
                                      const wchar_t *fqdn)
{
  bonjour_name_state_t *state = bonjour_name_find_locked(browser, fqdn);

  if (state == NULL) return 0;
  if (state->generation == UINT64_MAX) return -1;
  ++state->generation;
  state->present = 0;
  return 1;
}

static int bonjour_name_is_current_locked(bonjour_browser_t *browser,
                                          const wchar_t *fqdn,
                                          uint64_t generation)
{
  bonjour_name_state_t *state = bonjour_name_find_locked(browser, fqdn);

  return state != NULL && state->present && state->generation == generation;
}

static int bonjour_resolvers_contain_fqdn_locked(
    const bonjour_browser_t *browser, const wchar_t *fqdn)
{
  const bonjour_resolver_t *resolver;

  for (resolver = browser->resolvers; resolver != NULL; resolver = resolver->next)
    if (bonjour_fqdn_equal(resolver->fqdn, fqdn)) return 1;
  for (resolver = browser->retired; resolver != NULL;
       resolver = resolver->retired_next)
    if (bonjour_fqdn_equal(resolver->fqdn, fqdn)) return 1;
  return 0;
}

static void bonjour_name_prune_locked(bonjour_browser_t *browser,
                                      const wchar_t *fqdn)
{
  bonjour_name_state_t **link;
  bonjour_name_state_t *state;

  for (link = &browser->names; *link != NULL; link = &(*link)->next)
    if (bonjour_fqdn_equal((*link)->fqdn, fqdn)) break;
  state = *link;
  if (state == NULL || state->present ||
      bonjour_results_contain_fqdn(&browser->results, state->fqdn) ||
      bonjour_resolvers_contain_fqdn_locked(browser, state->fqdn))
    return;
  *link = state->next;
  free(state->fqdn);
  free(state);
}

static void bonjour_names_clear(bonjour_browser_t *browser)
{
  bonjour_name_state_t *state;

  while ((state = browser->names) != NULL) {
    browser->names = state->next;
    free(state->fqdn);
    free(state);
  }
}

static void bonjour_resolver_free(bonjour_resolver_t *resolver)
{
  free(resolver->fqdn);
  free(resolver);
}

static int bonjour_resolver_detach_locked(bonjour_browser_t *browser,
                                          bonjour_resolver_t *resolver)
{
  bonjour_resolver_t **link;

  for (link = &browser->resolvers; *link != NULL; link = &(*link)->next) {
    if (*link != resolver) continue;
    *link = resolver->next;
    resolver->next = NULL;
    return 1;
  }
  return 0;
}

static void bonjour_browser_wake_locked(bonjour_browser_t *browser)
{
  WakeAllConditionVariable(&browser->callbacks_done);
}

static void WINAPI bonjour_resolve_complete(DWORD status, void *context,
                                             PDNS_SERVICE_INSTANCE instance)
{
  bonjour_resolver_t *resolver = context;
  bonjour_browser_t *browser = resolver->browser;
  char *name = NULL;
  char *type = NULL;
  char *domain = NULL;
  char address[INET6_ADDRSTRLEN];
  DWORD interface_index = resolver->interface_index;
  uint16_t port = 0;
  int valid = 0;
  int detached = 0;

  AcquireSRWLockExclusive(&browser->lock);
  ++browser->callbacks;
  ReleaseSRWLockExclusive(&browser->lock);

  address[0] = '\0';
  if (status == ERROR_SUCCESS && instance != NULL &&
      instance->pszInstanceName != NULL &&
      bonjour_split_instance_fqdn(instance->pszInstanceName, &name, &type,
                                  &domain) == 0) {
    if (instance->ip4Address != NULL)
      valid = InetNtopA(AF_INET, instance->ip4Address, address,
                        sizeof(address)) != NULL;
    else if (instance->ip6Address != NULL)
      valid = InetNtopA(AF_INET6, instance->ip6Address, address,
                        sizeof(address)) != NULL;
    if (valid) {
      interface_index = instance->dwInterfaceIndex;
      port = instance->wPort;
    }
  }
  AcquireSRWLockExclusive(&browser->lock);
  if (valid && !browser->closing &&
      bonjour_name_is_current_locked(browser, resolver->fqdn,
                                     resolver->generation)) {
    int changed = bonjour_results_put(
        &browser->results, instance->pszInstanceName, interface_index, name,
        type, domain, address, port);

    if (changed > 0) browser->avail = 1;
    if (changed < 0 && browser->status == ERROR_SUCCESS)
      browser->status = ERROR_NOT_ENOUGH_MEMORY;
  }
  resolver->completed = 1;
  if (!resolver->dispatching) {
    detached = bonjour_resolver_detach_locked(browser, resolver);
    if (detached && browser->closing) {
      resolver->retired_next = browser->retired;
      browser->retired = resolver;
      detached = 0;
    }
  }
  bonjour_name_prune_locked(browser, resolver->fqdn);
  ReleaseSRWLockExclusive(&browser->lock);

  if (instance != NULL) browser->api->free_instance(instance);
  free(name);
  free(type);
  free(domain);
  if (detached) bonjour_resolver_free(resolver);

  AcquireSRWLockExclusive(&browser->lock);
  --browser->callbacks;
  bonjour_browser_wake_locked(browser);
  ReleaseSRWLockExclusive(&browser->lock);
}

static void bonjour_start_resolver(bonjour_browser_t *browser,
                                   const wchar_t *fqdn,
                                   DWORD interface_index,
                                   uint64_t generation)
{
  bonjour_resolver_t *resolver;
  bonjour_resolver_t *scan;
  DNS_SERVICE_RESOLVE_REQUEST request;
  DNS_STATUS status;
  int free_resolver = 0;

  resolver = calloc(1, sizeof(*resolver));
  if (resolver == NULL) return;
  resolver->fqdn = bonjour_wide_duplicate_range(fqdn, wcslen(fqdn));
  if (resolver->fqdn == NULL) {
    free(resolver);
    return;
  }
  resolver->browser = browser;
  resolver->interface_index = interface_index;
  resolver->generation = generation;
  resolver->dispatching = 1;

#ifdef BONJOUR_WINDOWS_TESTING
  if (browser->api->before_resolver_link != NULL)
    browser->api->before_resolver_link();
#endif

  AcquireSRWLockExclusive(&browser->lock);
  if (browser->closing ||
      !bonjour_name_is_current_locked(browser, fqdn, generation)) {
    ReleaseSRWLockExclusive(&browser->lock);
    bonjour_resolver_free(resolver);
    return;
  }
  for (scan = browser->resolvers; scan != NULL; scan = scan->next) {
    if (scan->interface_index == interface_index &&
        scan->generation == generation &&
        bonjour_fqdn_equal(scan->fqdn, fqdn)) {
      ReleaseSRWLockExclusive(&browser->lock);
      bonjour_resolver_free(resolver);
      return;
    }
  }
  resolver->next = browser->resolvers;
  browser->resolvers = resolver;
  ++browser->dispatches;
  ReleaseSRWLockExclusive(&browser->lock);

  memset(&request, 0, sizeof(request));
  request.Version = DNS_QUERY_REQUEST_VERSION1;
  request.InterfaceIndex = interface_index;
  request.QueryName = resolver->fqdn;
  request.pResolveCompletionCallback = bonjour_resolve_complete;
  request.pQueryContext = resolver;
  status = browser->api->resolve(&request, &resolver->cancel);
  AcquireSRWLockExclusive(&browser->lock);
  resolver->dispatching = 0;
  --browser->dispatches;
  if (!bonjour_request_accepted((DWORD)status)) resolver->completed = 1;
  if (resolver->completed) {
    free_resolver = bonjour_resolver_detach_locked(browser, resolver);
    if (free_resolver && browser->closing) {
      resolver->retired_next = browser->retired;
      browser->retired = resolver;
      free_resolver = 0;
    }
  }
  bonjour_name_prune_locked(browser, resolver->fqdn);
  bonjour_browser_wake_locked(browser);
  ReleaseSRWLockExclusive(&browser->lock);
  if (free_resolver) bonjour_resolver_free(resolver);
}

static void WINAPI bonjour_browse_complete(DWORD status, void *context,
                                            PDNS_RECORD records)
{
  bonjour_browser_t *browser = context;
  PDNS_RECORD record;

  AcquireSRWLockExclusive(&browser->lock);
  ++browser->callbacks;
  if (browser->closing && status == ERROR_CANCELLED)
    browser->browse_cancel_acknowledged = 1;
  if (status != ERROR_SUCCESS && status != ERROR_CANCELLED &&
      browser->status == ERROR_SUCCESS && !browser->closing) {
    browser->status = status;
    browser->avail = 1;
  }
  ReleaseSRWLockExclusive(&browser->lock);

  if (status == ERROR_SUCCESS) {
    for (record = records; record != NULL; record = record->pNext) {
      const wchar_t *target;
      if (record->wType != DNS_TYPE_PTR || record->pName == NULL ||
          record->Data.PTR.pNameHost == NULL ||
          !bonjour_fqdn_equal(record->pName, browser->type_fqdn))
        continue;
      target = record->Data.PTR.pNameHost;
      if (record->Flags.S.Delete || record->dwTtl == 0) {
        int delete_status;

        AcquireSRWLockExclusive(&browser->lock);
        delete_status = bonjour_name_delete_locked(browser, target);
        if (delete_status < 0 &&
            browser->status == ERROR_SUCCESS)
          browser->status = ERROR_NOT_ENOUGH_MEMORY;
        if (bonjour_results_remove_fqdn(&browser->results, target))
          browser->avail = 1;
        bonjour_name_prune_locked(browser, target);
        ReleaseSRWLockExclusive(&browser->lock);
      } else {
        uint64_t generation = 0;
        int valid_generation;

        AcquireSRWLockExclusive(&browser->lock);
        valid_generation = bonjour_name_add_locked(browser, target,
                                                   &generation);
        if (!valid_generation && browser->status == ERROR_SUCCESS)
          browser->status = ERROR_NOT_ENOUGH_MEMORY;
        ReleaseSRWLockExclusive(&browser->lock);
        if (valid_generation)
          bonjour_start_resolver(browser, target, 0, generation);
      }
    }
  }
  if (records != NULL)
    browser->api->free_records(records, DnsFreeRecordList);

  AcquireSRWLockExclusive(&browser->lock);
  --browser->callbacks;
  bonjour_browser_wake_locked(browser);
  ReleaseSRWLockExclusive(&browser->lock);
}

static bonjour_browser_t *bonjour_browse_using_api(
    const char *type, const bonjour_dns_api_t *api, DWORD wait_ms)
{
  bonjour_browser_t *browser;
  DNS_SERVICE_BROWSE_REQUEST request;
  DNS_STATUS status;

  if (api == NULL || api->browse == NULL || api->cancel_browse == NULL ||
      api->resolve == NULL || api->cancel_resolve == NULL ||
      api->free_records == NULL || api->free_instance == NULL ||
      wait_ms == INFINITE)
    return NULL;
  browser = calloc(1, sizeof(*browser));
  if (browser == NULL) return NULL;
  browser->type_fqdn = bonjour_make_type_fqdn(type);
  if (browser->type_fqdn == NULL) {
    free(browser);
    return NULL;
  }
  InitializeSRWLock(&browser->lock);
  InitializeConditionVariable(&browser->callbacks_done);
  browser->api = api;
  browser->wait_ms = wait_ms;
  browser->status = ERROR_SUCCESS;

  memset(&request, 0, sizeof(request));
  request.Version = DNS_QUERY_REQUEST_VERSION1;
  request.InterfaceIndex = 0;
  request.QueryName = browser->type_fqdn;
  request.pBrowseCallback = bonjour_browse_complete;
  request.pQueryContext = browser;
  status = api->browse(&request, &browser->cancel);
  if (!bonjour_request_accepted((DWORD)status)) {
    free(browser->type_fqdn);
    free(browser);
    return NULL;
  }
  return browser;
}

bonjour_browser_t *bonjour_browse(const char *type)
{
  return bonjour_browse_using_api(type, &bonjour_system_dns_api, 10000);
}

#ifdef BONJOUR_WINDOWS_TESTING
BONJOUR_WINDOWS_PRIVATE bonjour_browser_t *bonjour_browse_with_api(
    const char *type, const bonjour_dns_api_t *api, DWORD wait_ms)
{
  return bonjour_browse_using_api(type, api, wait_ms);
}

BONJOUR_WINDOWS_PRIVATE size_t bonjour_browser_name_state_count(
    bonjour_browser_t *browser)
{
  bonjour_name_state_t *state;
  size_t count = 0;

  if (browser == NULL) return 0;
  AcquireSRWLockShared(&browser->lock);
  for (state = browser->names; state != NULL; state = state->next) ++count;
  ReleaseSRWLockShared(&browser->lock);
  return count;
}
#endif

int bonjour_avail(bonjour_browser_t *browser)
{
  int available;

  if (browser == NULL) return 0;
  AcquireSRWLockShared(&browser->lock);
  available = browser->status == ERROR_SUCCESS
                  ? browser->avail
                  : bonjour_status_error(browser->status);
  ReleaseSRWLockShared(&browser->lock);
  return available;
}

pure_expr *bonjour_get(bonjour_browser_t *browser)
{
  pure_expr *result;
  pure_expr **items = NULL;
  bonjour_result_t *record;
  size_t i = 0;

  if (browser == NULL) return NULL;
  AcquireSRWLockExclusive(&browser->lock);
  if (browser->status != ERROR_SUCCESS) {
    result = pure_int(bonjour_status_error(browser->status));
    ReleaseSRWLockExclusive(&browser->lock);
    return result;
  }
  if (browser->results.count != 0) {
    items = calloc(browser->results.count, sizeof(*items));
    if (items == NULL) {
      ReleaseSRWLockExclusive(&browser->lock);
      return NULL;
    }
  }
  for (record = browser->results.head; record != NULL; record = record->next) {
    items[i] = pure_tuplel(5, pure_cstring_dup(record->name),
                           pure_cstring_dup(record->type),
                           pure_cstring_dup(record->domain),
                           pure_cstring_dup(record->address),
                           pure_int(record->port));
    if (items[i] == NULL) break;
    ++i;
  }
  if (i == browser->results.count)
    result = pure_listv(i, items);
  else
    result = NULL;
  if (result != NULL) browser->avail = 0;
  ReleaseSRWLockExclusive(&browser->lock);
  if (result == NULL) {
    while (i != 0) pure_freenew(items[--i]);
  }
  free(items);
  return result;
}

static int bonjour_browser_wait(bonjour_browser_t *browser,
                                int require_empty_resolvers,
                                int require_browse_cancel_ack)
{
  ULONGLONG started = GetTickCount64();
  int quiescent = 1;

  AcquireSRWLockExclusive(&browser->lock);
  while (browser->callbacks != 0 || browser->dispatches != 0 ||
         (require_empty_resolvers && browser->resolvers != NULL) ||
         (require_browse_cancel_ack &&
          !browser->browse_cancel_acknowledged)) {
    ULONGLONG elapsed = GetTickCount64() - started;
    DWORD remaining;

    if (elapsed >= browser->wait_ms) {
      quiescent = 0;
      break;
    }
    remaining = browser->wait_ms - (DWORD)elapsed;
    if (!SleepConditionVariableSRW(&browser->callbacks_done, &browser->lock,
                                   remaining, 0) &&
        GetLastError() != ERROR_TIMEOUT) {
      quiescent = 0;
      break;
    }
  }
  ReleaseSRWLockExclusive(&browser->lock);
  return quiescent;
}

void bonjour_close(bonjour_browser_t *browser)
{
  PDNS_SERVICE_CANCEL *resolver_cancels = NULL;
  bonjour_resolver_t *resolver;
  bonjour_resolver_t *retired;
  size_t resolver_count = 0;
  size_t i = 0;
  DNS_STATUS browse_status;
  DNS_STATUS resolver_status = ERROR_SUCCESS;

  if (browser == NULL) return;
  AcquireSRWLockExclusive(&browser->lock);
  if (browser->closing) {
    ReleaseSRWLockExclusive(&browser->lock);
    return;
  }
  browser->closing = 1;
  browser->browse_cancel_acknowledged = 0;
  ReleaseSRWLockExclusive(&browser->lock);

  browse_status = browser->api->cancel_browse(&browser->cancel);
  if (!bonjour_browser_wait(browser, 0, 1)) goto retain;

  AcquireSRWLockShared(&browser->lock);
  for (resolver = browser->resolvers; resolver != NULL; resolver = resolver->next)
    ++resolver_count;
  ReleaseSRWLockShared(&browser->lock);
  if (resolver_count != 0) {
    resolver_cancels = calloc(resolver_count, sizeof(*resolver_cancels));
    if (resolver_cancels == NULL) {
      resolver_status = ERROR_NOT_ENOUGH_MEMORY;
      goto retain;
    }
    AcquireSRWLockShared(&browser->lock);
    for (resolver = browser->resolvers; resolver != NULL && i < resolver_count;
         resolver = resolver->next)
      resolver_cancels[i++] = &resolver->cancel;
    ReleaseSRWLockShared(&browser->lock);
    resolver_count = i;
    for (i = 0; i < resolver_count; ++i) {
      DNS_STATUS status = browser->api->cancel_resolve(resolver_cancels[i]);
      if (!bonjour_request_accepted((DWORD)status) &&
          bonjour_request_accepted((DWORD)resolver_status))
        resolver_status = status;
    }
  }
  free(resolver_cancels);
  resolver_cancels = NULL;
  if (!bonjour_request_accepted((DWORD)browse_status) ||
      !bonjour_request_accepted((DWORD)resolver_status) ||
      !bonjour_browser_wait(browser, 1, 1))
    goto retain;

  bonjour_results_clear(&browser->results);
  bonjour_names_clear(browser);
  while ((retired = browser->retired) != NULL) {
    browser->retired = retired->retired_next;
    bonjour_resolver_free(retired);
  }
  free(browser->type_fqdn);
  free(browser);
  return;

retain:
  free(resolver_cancels);
  fprintf(stderr,
          "pure-bonjour: discovery shutdown failed or did not become "
          "quiescent within %lu ms (browse status %lu, resolve status %lu); "
          "retaining browser state\n",
          (unsigned long)browser->wait_ms, (unsigned long)browse_status,
          (unsigned long)resolver_status);
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
