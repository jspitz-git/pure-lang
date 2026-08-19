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
typedef struct bonjour_callback_route_t bonjour_callback_route_t;

struct bonjour_callback_route_t {
  bonjour_callback_route_t *next;
  UINT_PTR token;
  void *object;
  unsigned active;
};

/* The routes lock and object locks are never held together.  A callback
   increments route->active before releasing the routes lock and exposing the
   object pointer, then releases the route only after its final object access.
   Cleanup detaches and waits without holding an object lock. */
static SRWLOCK bonjour_routes_lock = SRWLOCK_INIT;
static CONDITION_VARIABLE bonjour_routes_done = CONDITION_VARIABLE_INIT;
static bonjour_callback_route_t *bonjour_routes;
static UINT_PTR bonjour_next_token = 1;

#ifdef BONJOUR_WINDOWS_TESTING
static const bonjour_dns_api_t *bonjour_test_orphan_api;
#endif

static bonjour_callback_route_t *bonjour_route_add(void *object,
                                                    UINT_PTR *token)
{
  bonjour_callback_route_t *route = calloc(1, sizeof(*route));
  if (route == NULL) return NULL;
  AcquireSRWLockExclusive(&bonjour_routes_lock);
  if (bonjour_next_token == 0) {
    ReleaseSRWLockExclusive(&bonjour_routes_lock);
    free(route);
    return NULL;
  }
  route->token = bonjour_next_token++;
  route->object = object;
  route->next = bonjour_routes;
  bonjour_routes = route;
  *token = route->token;
  ReleaseSRWLockExclusive(&bonjour_routes_lock);
  return route;
}

static bonjour_callback_route_t *bonjour_route_acquire(void *context,
                                                       void **object)
{
  UINT_PTR token = (UINT_PTR)context;
  bonjour_callback_route_t *route;
  AcquireSRWLockExclusive(&bonjour_routes_lock);
  for (route = bonjour_routes; route != NULL; route = route->next)
    if (route->token == token) break;
  if (route != NULL && route->active != UINT_MAX) {
    ++route->active;
    *object = route->object;
  } else {
    route = NULL;
  }
  ReleaseSRWLockExclusive(&bonjour_routes_lock);
  return route;
}

static void bonjour_route_release(bonjour_callback_route_t *route)
{
  AcquireSRWLockExclusive(&bonjour_routes_lock);
  if (--route->active == 0) WakeAllConditionVariable(&bonjour_routes_done);
  ReleaseSRWLockExclusive(&bonjour_routes_lock);
}

static int bonjour_route_remove_and_wait(UINT_PTR token, DWORD wait_ms)
{
  bonjour_callback_route_t **link;
  bonjour_callback_route_t *route;
  ULONGLONG started = GetTickCount64();
  int removed = 1;
  AcquireSRWLockExclusive(&bonjour_routes_lock);
  for (link = &bonjour_routes; *link != NULL; link = &(*link)->next)
    if ((*link)->token == token) break;
  route = *link;
  if (route != NULL) {
    *link = route->next;
    while (route->active != 0) {
      ULONGLONG elapsed = GetTickCount64() - started;
      DWORD remaining;
      if (elapsed >= wait_ms) {
        route->next = bonjour_routes;
        bonjour_routes = route;
        route = NULL;
        removed = 0;
        break;
      }
      remaining = wait_ms - (DWORD)elapsed;
      if (!SleepConditionVariableSRW(&bonjour_routes_done,
                                     &bonjour_routes_lock, remaining, 0) &&
          GetLastError() != ERROR_TIMEOUT) {
        route->next = bonjour_routes;
        bonjour_routes = route;
        route = NULL;
        removed = 0;
        break;
      }
    }
  }
  ReleaseSRWLockExclusive(&bonjour_routes_lock);
  free(route);
  return removed;
}

static void bonjour_orphan_free_instance(PDNS_SERVICE_INSTANCE instance)
{
  if (instance == NULL) return;
#ifdef BONJOUR_WINDOWS_TESTING
  if (bonjour_test_orphan_api != NULL) {
    bonjour_test_orphan_api->free_instance(instance);
    return;
  }
#endif
  DnsServiceFreeInstance(instance);
}

static void bonjour_orphan_free_records(PDNS_RECORD records)
{
  if (records == NULL) return;
#ifdef BONJOUR_WINDOWS_TESTING
  if (bonjour_test_orphan_api != NULL) {
    bonjour_test_orphan_api->free_records(records, DnsFreeRecordList);
    return;
  }
#endif
  DnsRecordListFree(records, DnsFreeRecordList);
}

struct bonjour_name_state_t {
  bonjour_name_state_t *next;
  wchar_t *fqdn;
  uint64_t generation;
  int present;
};

typedef enum {
  BONJOUR_RESOLVER_ACTIVE,
  BONJOUR_RESOLVER_CANCELING,
  BONJOUR_RESOLVER_CANCELLED
} bonjour_resolver_cancel_state_t;

struct bonjour_resolver_t {
  bonjour_resolver_t *next;
  bonjour_browser_t *browser;
  DNS_SERVICE_CANCEL cancel;
  wchar_t *fqdn;
  DWORD interface_index;
  uint64_t generation;
  int dispatching;
  int completed;
  bonjour_resolver_cancel_state_t cancel_state;
  UINT_PTR token;
};

struct bonjour_browser_t {
  SRWLOCK lock;
  CONDITION_VARIABLE callbacks_done;
  DNS_SERVICE_CANCEL cancel;
  wchar_t *type_fqdn;
  bonjour_result_set_t results;
  bonjour_resolver_t *resolvers;
  bonjour_name_state_t *names;
  DWORD status;
  unsigned callbacks;
  unsigned dispatches;
  int avail;
  int closing;
  int browse_cancel_acknowledged;
  int cleanup_owner;
  int browse_cancel_established;
  int cleanup_pending;
  const bonjour_dns_api_t *api;
  DWORD wait_ms;
  UINT_PTR token;
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
  UINT_PTR token;
  int cancel_established;
  int shutdown_inflight;
  int cleanup_owner;
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
  NULL,
  NULL,
  NULL,
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

static int bonjour_register_cancel_completed(DWORD status)
{
  return status == ERROR_SUCCESS || status == ERROR_CANCELLED;
}

static int bonjour_query_cancel_completed(DWORD status)
{
  return status == ERROR_SUCCESS;
}

static void WINAPI bonjour_register_complete(DWORD status, void *context,
                                              PDNS_SERVICE_INSTANCE instance)
{
  bonjour_service_t *service = NULL;
  bonjour_callback_route_t *route =
      bonjour_route_acquire(context, (void **)&service);
  char *effective_name = NULL;
  char *effective_type = NULL;
  char *effective_domain = NULL;

  if (route == NULL) {
    bonjour_orphan_free_instance(instance);
    return;
  }
#ifdef BONJOUR_WINDOWS_TESTING
  if (service->api->after_registration_route_acquire != NULL)
    service->api->after_registration_route_acquire();
#endif
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
  bonjour_route_release(route);
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
#ifdef BONJOUR_WINDOWS_TESTING
  bonjour_test_orphan_api = api;
#endif
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
  if (bonjour_route_add(service, &service->token) == NULL) {
    api->free_instance(service->instance);
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
  request.pQueryContext = (void *)service->token;
  status = api->register_service(&request, &service->cancel);
  if (!bonjour_request_accepted(status)) {
    if (!bonjour_route_remove_and_wait(service->token, service->wait_ms))
      return NULL;
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
  int wait_for_shutdown = 0;

  if (service == NULL) return;
  AcquireSRWLockExclusive(&service->lock);
  if (service->cleanup_owner) {
    ReleaseSRWLockExclusive(&service->lock);
    return;
  }
  service->cleanup_owner = 1;
  previous_state = service->state;
  if (previous_state == BONJOUR_REG_STOPPED) {
    service->cleanup_owner = 0;
    ReleaseSRWLockExclusive(&service->lock);
    return;
  }
  if (previous_state == BONJOUR_REG_STOPPING &&
      service->cancel_established) {
    ReleaseSRWLockExclusive(&service->lock);
#ifdef BONJOUR_WINDOWS_TESTING
    if (service->api->before_service_route_drain != NULL)
      service->api->before_service_route_drain();
#endif
    if (bonjour_route_remove_and_wait(service->token, service->wait_ms))
      bonjour_release_service(service);
    else {
      AcquireSRWLockExclusive(&service->lock);
      service->cleanup_owner = 0;
      ReleaseSRWLockExclusive(&service->lock);
    }
    return;
  }
  if (previous_state == BONJOUR_REG_STOPPING && service->shutdown_inflight) {
    wait_for_shutdown = 1;
    ReleaseSRWLockExclusive(&service->lock);
  } else {
    if (previous_state == BONJOUR_REG_REGISTERED) {
      service->shutdown_status = ERROR_IO_PENDING;
      service->state = BONJOUR_REG_STOPPING;
      ResetEvent(service->completion);
    } else if (previous_state == BONJOUR_REG_FAILED) {
      service->state = BONJOUR_REG_STOPPING;
    }
    ReleaseSRWLockExclusive(&service->lock);
  }

  if (wait_for_shutdown) {
    completion_status = WaitForSingleObject(service->completion,
                                            service->wait_ms);
    if (completion_status == WAIT_OBJECT_0) {
      AcquireSRWLockShared(&service->lock);
      status = service->shutdown_status;
      ReleaseSRWLockShared(&service->lock);
    }
  } else if (previous_state == BONJOUR_REG_PENDING) {
    status = service->api->cancel_registration(&service->cancel);
  } else if (previous_state == BONJOUR_REG_REGISTERED) {
    memset(&request, 0, sizeof(request));
    request.Version = 1;
    request.pServiceInstance = service->instance;
    request.pRegisterCompletionCallback = bonjour_register_complete;
    request.pQueryContext = (void *)service->token;
    status = service->api->deregister_service(&request, NULL);
    if (bonjour_request_accepted(status)) {
      AcquireSRWLockExclusive(&service->lock);
      service->shutdown_inflight = 1;
      ReleaseSRWLockExclusive(&service->lock);
      completion_status = WaitForSingleObject(service->completion,
                                              service->wait_ms);
      if (completion_status == WAIT_OBJECT_0) {
        AcquireSRWLockShared(&service->lock);
        status = service->shutdown_status;
        ReleaseSRWLockShared(&service->lock);
      }
    }
  }

  if (previous_state == BONJOUR_REG_PENDING &&
      !bonjour_register_cancel_completed(status)) {
    AcquireSRWLockExclusive(&service->lock);
    service->cleanup_owner = 0;
    ReleaseSRWLockExclusive(&service->lock);
    fprintf(stderr,
            "pure-bonjour: registration cancellation failed (status %lu); "
            "retaining state for retry\n", (unsigned long)status);
    return;
  }
  if (previous_state == BONJOUR_REG_PENDING) {
    AcquireSRWLockExclusive(&service->lock);
    service->state = BONJOUR_REG_STOPPING;
    service->cancel_established = 1;
    ReleaseSRWLockExclusive(&service->lock);
  }
  if (previous_state == BONJOUR_REG_REGISTERED &&
      !bonjour_request_accepted(status)) {
    AcquireSRWLockExclusive(&service->lock);
    service->state = BONJOUR_REG_REGISTERED;
    service->shutdown_inflight = 0;
    service->cleanup_owner = 0;
    ReleaseSRWLockExclusive(&service->lock);
    fprintf(stderr,
            "pure-bonjour: deregistration dispatch failed (status %lu); "
            "retaining registered service for retry\n", (unsigned long)status);
    return;
  }
  if ((previous_state == BONJOUR_REG_REGISTERED || wait_for_shutdown) &&
      completion_status != WAIT_OBJECT_0) {
    AcquireSRWLockExclusive(&service->lock);
    service->cleanup_owner = 0;
    ReleaseSRWLockExclusive(&service->lock);
    fprintf(stderr,
            "pure-bonjour: deregistration did not complete within %lu ms; "
            "retaining registered service state for retry\n",
            (unsigned long)service->wait_ms);
    return;
  }
  if ((previous_state == BONJOUR_REG_REGISTERED || wait_for_shutdown) &&
      status != ERROR_SUCCESS) {
    AcquireSRWLockExclusive(&service->lock);
    service->state = BONJOUR_REG_REGISTERED;
    service->shutdown_inflight = 0;
    service->cleanup_owner = 0;
    ReleaseSRWLockExclusive(&service->lock);
    fprintf(stderr,
            "pure-bonjour: deregistration callback failed (status %lu); "
            "retaining registered service for retry\n", (unsigned long)status);
    return;
  }
  AcquireSRWLockExclusive(&service->lock);
  if (previous_state != BONJOUR_REG_REGISTERED &&
      previous_state != BONJOUR_REG_PENDING && !wait_for_shutdown)
    service->cancel_established = 1;
  ReleaseSRWLockExclusive(&service->lock);

  if (!bonjour_wait_for_callbacks(service)) {
    fprintf(stderr,
            "pure-bonjour: registration shutdown failed or did not become "
            "quiescent within %lu ms (status %lu); routing late callbacks "
            "away from released state\n",
            (unsigned long)service->wait_ms, (unsigned long)status);
  }

#ifdef BONJOUR_WINDOWS_TESTING
  if (service->api->before_service_route_drain != NULL)
    service->api->before_service_route_drain();
#endif
  if (!bonjour_route_remove_and_wait(service->token, service->wait_ms)) {
    AcquireSRWLockExclusive(&service->lock);
    service->cleanup_owner = 0;
    ReleaseSRWLockExclusive(&service->lock);
    fprintf(stderr,
            "pure-bonjour: registration callback drain timed out; retaining "
            "state for retry\n");
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
  const unsigned char *cursor;

  if (name == NULL || name[0] == '\0') return 0;
  length = strlen(name);
  if (length > 63 ||
      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, name, -1, NULL, 0) <= 0)
    return 0;
  for (cursor = (const unsigned char *)name; *cursor != '\0'; ++cursor)
    if (*cursor < 0x20 || *cursor == 0x7f) return 0;
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

static int bonjour_resolver_claim_cancel_locked(bonjour_resolver_t *resolver,
                                                 int *call_cancel)
{
  if (resolver->cancel_state == BONJOUR_RESOLVER_CANCELING) return 0;
  *call_cancel = resolver->cancel_state == BONJOUR_RESOLVER_ACTIVE;
  resolver->cancel_state = BONJOUR_RESOLVER_CANCELING;
  return 1;
}

static void bonjour_resolver_retry_cancel_locked(
    bonjour_resolver_t *resolver)
{
  resolver->cancel_state = BONJOUR_RESOLVER_ACTIVE;
}

static void bonjour_cancel_resolvers_for_fqdn(bonjour_browser_t *browser,
                                               const wchar_t *fqdn)
{
  for (;;) {
    bonjour_resolver_t *resolver;
    DNS_STATUS status = ERROR_SUCCESS;
    int call_cancel = 0;
    AcquireSRWLockExclusive(&browser->lock);
    for (resolver = browser->resolvers; resolver != NULL;
         resolver = resolver->next)
      if (bonjour_fqdn_equal(resolver->fqdn, fqdn)) break;
    if (resolver == NULL ||
        !bonjour_resolver_claim_cancel_locked(resolver, &call_cancel)) {
      ReleaseSRWLockExclusive(&browser->lock);
      return;
    }
    ReleaseSRWLockExclusive(&browser->lock);
    if (call_cancel)
      status = browser->api->cancel_resolve(&resolver->cancel);
    if (!bonjour_query_cancel_completed((DWORD)status)) {
      AcquireSRWLockExclusive(&browser->lock);
      bonjour_resolver_retry_cancel_locked(resolver);
      ReleaseSRWLockExclusive(&browser->lock);
      fprintf(stderr,
              "pure-bonjour: resolve cancellation failed (status %lu); "
              "retaining state for retry\n", (unsigned long)status);
      return;
    }
    if (!bonjour_route_remove_and_wait(resolver->token, browser->wait_ms)) {
      AcquireSRWLockExclusive(&browser->lock);
      resolver->cancel_state = BONJOUR_RESOLVER_CANCELLED;
      ReleaseSRWLockExclusive(&browser->lock);
      fprintf(stderr,
              "pure-bonjour: resolve callback drain timed out; retaining "
              "state for retry\n");
      return;
    }
    AcquireSRWLockExclusive(&browser->lock);
    bonjour_resolver_detach_locked(browser, resolver);
    bonjour_name_prune_locked(browser, fqdn);
    ReleaseSRWLockExclusive(&browser->lock);
    bonjour_resolver_free(resolver);
  }
}

static void bonjour_browser_wake_locked(bonjour_browser_t *browser)
{
  WakeAllConditionVariable(&browser->callbacks_done);
}

static void WINAPI bonjour_resolve_complete(DWORD status, void *context,
                                             PDNS_SERVICE_INSTANCE instance)
{
  bonjour_resolver_t *resolver = NULL;
  bonjour_callback_route_t *route =
      bonjour_route_acquire(context, (void **)&resolver);
  if (route == NULL) {
    bonjour_orphan_free_instance(instance);
    return;
  }
  bonjour_browser_t *browser = resolver->browser;
  char *name = NULL;
  char *type = NULL;
  char *domain = NULL;
  char address[INET6_ADDRSTRLEN];
  DWORD interface_index = resolver->interface_index;
  uint16_t port = 0;
  int valid = 0;

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
  bonjour_name_prune_locked(browser, resolver->fqdn);
  ReleaseSRWLockExclusive(&browser->lock);

  if (instance != NULL) browser->api->free_instance(instance);
  free(name);
  free(type);
  free(domain);
  AcquireSRWLockExclusive(&browser->lock);
  --browser->callbacks;
  valid = browser->callbacks == 0 && browser->dispatches == 0 &&
          browser->cleanup_pending;
  bonjour_browser_wake_locked(browser);
  ReleaseSRWLockExclusive(&browser->lock);
  bonjour_route_release(route);
  if (valid) bonjour_close(browser);
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
  int cleanup_browser = 0;

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
  bonjour_test_orphan_api = browser->api;
#endif
  if (bonjour_route_add(resolver, &resolver->token) == NULL) {
    bonjour_resolver_free(resolver);
    return;
  }

#ifdef BONJOUR_WINDOWS_TESTING
  if (browser->api->before_resolver_link != NULL)
    browser->api->before_resolver_link();
#endif

  AcquireSRWLockExclusive(&browser->lock);
  if (browser->closing ||
      !bonjour_name_is_current_locked(browser, fqdn, generation)) {
    ReleaseSRWLockExclusive(&browser->lock);
    bonjour_route_remove_and_wait(resolver->token, browser->wait_ms);
    bonjour_resolver_free(resolver);
    return;
  }
  for (scan = browser->resolvers; scan != NULL; scan = scan->next) {
    if (scan->interface_index == interface_index &&
        scan->generation == generation &&
        bonjour_fqdn_equal(scan->fqdn, fqdn)) {
      ReleaseSRWLockExclusive(&browser->lock);
      bonjour_route_remove_and_wait(resolver->token, browser->wait_ms);
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
  request.pQueryContext = (void *)resolver->token;
  status = browser->api->resolve(&request, &resolver->cancel);
  AcquireSRWLockExclusive(&browser->lock);
  resolver->dispatching = 0;
  --browser->dispatches;
  if (!bonjour_request_accepted((DWORD)status)) free_resolver = 1;
  bonjour_name_prune_locked(browser, resolver->fqdn);
  cleanup_browser = browser->callbacks == 0 && browser->dispatches == 0 &&
                    browser->cleanup_pending;
  bonjour_browser_wake_locked(browser);
  ReleaseSRWLockExclusive(&browser->lock);
  if (free_resolver) {
    if (bonjour_route_remove_and_wait(resolver->token, browser->wait_ms)) {
      AcquireSRWLockExclusive(&browser->lock);
      free_resolver = bonjour_resolver_detach_locked(browser, resolver);
      bonjour_name_prune_locked(browser, resolver->fqdn);
      ReleaseSRWLockExclusive(&browser->lock);
      if (free_resolver) bonjour_resolver_free(resolver);
    } else {
      AcquireSRWLockExclusive(&browser->lock);
      resolver->cancel_state = BONJOUR_RESOLVER_CANCELLED;
      ReleaseSRWLockExclusive(&browser->lock);
    }
  }
  if (cleanup_browser) bonjour_close(browser);
}

static void WINAPI bonjour_browse_complete(DWORD status, void *context,
                                            PDNS_RECORD records)
{
  bonjour_browser_t *browser = NULL;
  bonjour_callback_route_t *route =
      bonjour_route_acquire(context, (void **)&browser);
  PDNS_RECORD record;

  if (route == NULL) {
    bonjour_orphan_free_records(records);
    return;
  }
#ifdef BONJOUR_WINDOWS_TESTING
  if (browser->api->after_browse_route_acquire != NULL)
    browser->api->after_browse_route_acquire();
#endif

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
        bonjour_cancel_resolvers_for_fqdn(browser, target);
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
  status = browser->callbacks == 0 && browser->dispatches == 0 &&
           browser->cleanup_pending;
  bonjour_browser_wake_locked(browser);
  ReleaseSRWLockExclusive(&browser->lock);
  bonjour_route_release(route);
  if (status) bonjour_close(browser);
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
#ifdef BONJOUR_WINDOWS_TESTING
  bonjour_test_orphan_api = api;
#endif
  if (bonjour_route_add(browser, &browser->token) == NULL) {
    free(browser->type_fqdn);
    free(browser);
    return NULL;
  }

  memset(&request, 0, sizeof(request));
  request.Version = DNS_QUERY_REQUEST_VERSION1;
  request.InterfaceIndex = 0;
  request.QueryName = browser->type_fqdn;
  request.pBrowseCallback = bonjour_browse_complete;
  request.pQueryContext = (void *)browser->token;
  status = api->browse(&request, &browser->cancel);
  if (!bonjour_request_accepted((DWORD)status)) {
    bonjour_route_remove_and_wait(browser->token, browser->wait_ms);
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

BONJOUR_WINDOWS_PRIVATE size_t bonjour_callback_registry_count(void)
{
  bonjour_callback_route_t *route;
  size_t count = 0;
  AcquireSRWLockShared(&bonjour_routes_lock);
  for (route = bonjour_routes; route != NULL; route = route->next) ++count;
  ReleaseSRWLockShared(&bonjour_routes_lock);
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

void bonjour_close(bonjour_browser_t *browser)
{
  bonjour_resolver_t *resolver;
  bonjour_name_state_t *names;
  bonjour_result_set_t results;
  DNS_STATUS browse_status = ERROR_SUCCESS;
  int perform_browse_cancel = 0;

  if (browser == NULL) return;
  AcquireSRWLockExclusive(&browser->lock);
  if (browser->cleanup_owner) {
    ReleaseSRWLockExclusive(&browser->lock);
    return;
  }
  browser->cleanup_owner = 1;
  browser->closing = 1;
  browser->cleanup_pending = 0;
  browser->browse_cancel_acknowledged = 0;
  if (!browser->browse_cancel_established) {
    perform_browse_cancel = 1;
  }
  ReleaseSRWLockExclusive(&browser->lock);

  if (perform_browse_cancel)
    browse_status = browser->api->cancel_browse(&browser->cancel);

  if (!bonjour_query_cancel_completed((DWORD)browse_status)) {
    AcquireSRWLockExclusive(&browser->lock);
    browser->cleanup_owner = 0;
    browser->closing = 0;
    ReleaseSRWLockExclusive(&browser->lock);
    fprintf(stderr,
            "pure-bonjour: browse cancellation failed (status %lu); "
            "retaining state for retry\n", (unsigned long)browse_status);
    return;
  }
  AcquireSRWLockExclusive(&browser->lock);
  browser->browse_cancel_established = 1;
  ReleaseSRWLockExclusive(&browser->lock);

  AcquireSRWLockExclusive(&browser->lock);
  if (browser->callbacks != 0 || browser->dispatches != 0) {
    browser->cleanup_pending = 1;
    browser->cleanup_owner = 0;
    ReleaseSRWLockExclusive(&browser->lock);
    return;
  }
  ReleaseSRWLockExclusive(&browser->lock);

  if (!bonjour_route_remove_and_wait(browser->token, browser->wait_ms)) {
    AcquireSRWLockExclusive(&browser->lock);
    browser->cleanup_pending = 1;
    browser->cleanup_owner = 0;
    ReleaseSRWLockExclusive(&browser->lock);
    fprintf(stderr,
            "pure-bonjour: browse callback drain timed out; retaining state "
            "for retry\n");
    return;
  }

  for (;;) {
    DNS_STATUS status = ERROR_SUCCESS;
    int call_cancel = 0;
    AcquireSRWLockExclusive(&browser->lock);
    resolver = browser->resolvers;
    if (resolver != NULL &&
        !bonjour_resolver_claim_cancel_locked(resolver, &call_cancel)) {
      browser->cleanup_owner = 0;
      ReleaseSRWLockExclusive(&browser->lock);
      return;
    }
    ReleaseSRWLockExclusive(&browser->lock);
    if (resolver == NULL) break;
    if (call_cancel)
      status = browser->api->cancel_resolve(&resolver->cancel);
    if (!bonjour_query_cancel_completed((DWORD)status)) {
      AcquireSRWLockExclusive(&browser->lock);
      bonjour_resolver_retry_cancel_locked(resolver);
      browser->cleanup_owner = 0;
      ReleaseSRWLockExclusive(&browser->lock);
      fprintf(stderr,
              "pure-bonjour: resolve cancellation failed (status %lu); "
              "retaining state for retry\n", (unsigned long)status);
      return;
    }
    if (!bonjour_route_remove_and_wait(resolver->token, browser->wait_ms)) {
      AcquireSRWLockExclusive(&browser->lock);
      resolver->cancel_state = BONJOUR_RESOLVER_CANCELLED;
      browser->cleanup_pending = 1;
      browser->cleanup_owner = 0;
      ReleaseSRWLockExclusive(&browser->lock);
      fprintf(stderr,
              "pure-bonjour: resolve callback drain timed out; retaining "
              "state for retry\n");
      return;
    }
    AcquireSRWLockExclusive(&browser->lock);
    bonjour_resolver_detach_locked(browser, resolver);
    bonjour_name_prune_locked(browser, resolver->fqdn);
    ReleaseSRWLockExclusive(&browser->lock);
    bonjour_resolver_free(resolver);
  }

#ifdef BONJOUR_WINDOWS_TESTING
  if (browser->api->before_browser_cleanup != NULL)
    browser->api->before_browser_cleanup();
#endif

  AcquireSRWLockExclusive(&browser->lock);
  results = browser->results;
  browser->results.head = NULL;
  browser->results.count = 0;
  names = browser->names;
  browser->names = NULL;
  ReleaseSRWLockExclusive(&browser->lock);

  bonjour_results_clear(&results);
  while (names != NULL) {
    bonjour_name_state_t *next = names->next;
    free(names->fqdn);
    free(names);
    names = next;
  }
  free(browser->type_fqdn);
  free(browser);
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
  size_t escaped_length;
  size_t source_index;
  size_t target_index;
  char *utf8_fqdn;
  wchar_t *wide_fqdn;

  if (!bonjour_instance_label_valid(name) || !bonjour_service_type_valid(type))
    return NULL;
  name_length = strlen(name);
  type_length = strlen(type);
  escaped_length = name_length;
  for (source_index = 0; source_index < name_length; ++source_index)
    if (name[source_index] == '.' || name[source_index] == '\\')
      ++escaped_length;
  if (escaped_length > 255 || type_length > 255 ||
      type_length > 255 - 1 - (sizeof(local_suffix) - 1) ||
      escaped_length > 255 - 1 - type_length - (sizeof(local_suffix) - 1))
    return NULL;
  fqdn_length = escaped_length + 1 + type_length + sizeof(local_suffix) - 1;
  utf8_fqdn = malloc(fqdn_length + 1);
  if (utf8_fqdn == NULL) return NULL;
  target_index = 0;
  for (source_index = 0; source_index < name_length; ++source_index) {
    if (name[source_index] == '.' || name[source_index] == '\\')
      utf8_fqdn[target_index++] = '\\';
    utf8_fqdn[target_index++] = name[source_index];
  }
  utf8_fqdn[target_index++] = '.';
  memcpy(utf8_fqdn + target_index, type, type_length);
  memcpy(utf8_fqdn + target_index + type_length, local_suffix,
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
  const wchar_t *separator = NULL;
  const wchar_t *protocol;
  wchar_t *wide_type;
  wchar_t *wide_name;
  char *utf8_type;
  char *utf8_name;
  char *utf8_domain;
  size_t source_index;
  size_t target_index;
  size_t fqdn_length;

  if (name == NULL || type == NULL || domain == NULL) return -1;
  *name = NULL;
  *type = NULL;
  *domain = NULL;
  if (fqdn == NULL || fqdn[0] == L'\0') return -1;

  fqdn_length = wcslen(fqdn);
  for (source_index = 0; source_index < fqdn_length; ++source_index) {
    if (fqdn[source_index] == L'\\') {
      if (source_index + 1 >= fqdn_length ||
          (fqdn[source_index + 1] != L'.' &&
           fqdn[source_index + 1] != L'\\'))
        return -1;
      ++source_index;
      continue;
    }
    if (fqdn[source_index] == L'.') {
      separator = fqdn + source_index;
      break;
    }
  }
  if (separator != NULL) {
    if (wcschr(separator + 1, L'\\') != NULL) return -1;
    protocol = wcsstr(separator + 1, L"._tcp.");
    if (protocol == NULL) protocol = wcsstr(separator + 1, L"._udp.");
    if (protocol == NULL) return -1;

    wide_name = bonjour_wide_duplicate_range(fqdn,
                                             (size_t)(separator - fqdn));
    wide_type = bonjour_wide_duplicate_range(separator + 1,
                                             (size_t)(protocol - separator - 1) + 5);
    if (wide_name == NULL || wide_type == NULL) {
      free(wide_name);
      free(wide_type);
      return -1;
    }
    target_index = 0;
    for (source_index = 0; wide_name[source_index] != L'\0'; ++source_index) {
      if (wide_name[source_index] == L'\\') ++source_index;
      wide_name[target_index++] = wide_name[source_index];
    }
    wide_name[target_index] = L'\0';
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
    if (utf8_name == NULL || !bonjour_instance_label_valid(utf8_name) ||
        utf8_domain == NULL ||
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
