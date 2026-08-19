#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include <winsock2.h>
#include <windows.h>

#include "bonjour_windows.h"

typedef struct {
  bonjour_dns_api_t api;
  DNS_SERVICE_INSTANCE instance;
  DNS_SERVICE_INSTANCE callback_instance;
  wchar_t instance_name[128];
  DNS_SERVICE_INSTANCE resolved_instance;
  IP4_ADDRESS resolved_ip4;
  IP6_ADDRESS resolved_ip6;
  DWORD register_result;
  DWORD cancel_result;
  DWORD deregister_result;
  DWORD deregister_callback_result;
  DWORD browse_result;
  DWORD browse_cancel_result;
  DWORD resolve_result;
  DWORD resolve_cancel_result;
  int register_calls;
  int cancel_calls;
  int deregister_calls;
  int deregister_callback_calls;
  int deregister_nonnull_reserved;
  int free_instance_calls;
  int free_callback_instance_calls;
  int free_resolved_instance_calls;
  int callback_after_free;
  int callback_on_cancel;
  int browse_calls;
  int browse_cancel_calls;
  int resolve_calls;
  int resolve_cancel_calls;
  int record_free_calls;
  int browse_callback_on_cancel;
  int resolve_callback_on_cancel;
  int close_on_resolved_free;
  int delete_before_resolver_link;
  int callback_during_browser_cleanup;
  HANDLE browse_route_entered;
  HANDLE browse_route_release;
  PDNS_SERVICE_REGISTER_COMPLETE callback;
  void *callback_context;
  PDNS_SERVICE_BROWSE_CALLBACK browse_callback;
  void *browse_context;
  PDNS_SERVICE_RESOLVE_COMPLETE resolve_callback;
  void *resolve_context;
  PDNS_SERVICE_RESOLVE_COMPLETE resolve_callbacks[8];
  void *resolve_contexts[8];
  PDNS_SERVICE_CANCEL resolve_cancel_handles[8];
  PDNS_RECORD last_freed_records;
  bonjour_browser_t *browser_to_close;
  const wchar_t *expected_service_name;
} fake_dns_t;

static fake_dns_t *active_fake;

static PDNS_SERVICE_INSTANCE WINAPI fake_construct_instance(
    PCWSTR service_name, PCWSTR host_name, PIP4_ADDRESS ip4, PIP6_ADDRESS ip6,
    WORD port, WORD priority, WORD weight, DWORD properties_count,
    PCWSTR *keys, PCWSTR *values)
{
  fake_dns_t *fake = active_fake;

  assert(fake != NULL);
  assert(wcscmp(service_name, fake->expected_service_name != NULL
                                  ? fake->expected_service_name
                                  : L"Probe._puretodo45._tcp.local") == 0);
  assert(host_name != NULL);
  assert(host_name[0] != L'\0');
  assert(wcslen(host_name) > 6);
  assert(_wcsicmp(host_name + wcslen(host_name) - 6, L".local") == 0);
  assert(ip4 == NULL);
  assert(ip6 == NULL);
  assert(port == 43210);
  assert(priority == 0);
  assert(weight == 0);
  assert(properties_count == 0);
  assert(keys == NULL);
  assert(values == NULL);
  memset(&fake->instance, 0, sizeof(fake->instance));
  assert(wcslen(service_name) <
         sizeof(fake->instance_name) / sizeof(fake->instance_name[0]));
  wcscpy(fake->instance_name, service_name);
  fake->instance.pszInstanceName = fake->instance_name;
  fake->instance.wPort = port;
  return &fake->instance;
}

static DWORD WINAPI fake_register(PDNS_SERVICE_REGISTER_REQUEST request,
                                  PDNS_SERVICE_CANCEL cancel)
{
  fake_dns_t *fake = active_fake;

  (void)cancel;
  assert(fake != NULL);
  ++fake->register_calls;
  fake->callback = request->pRegisterCompletionCallback;
  fake->callback_context = request->pQueryContext;
  return fake->register_result;
}

static void fake_fire_callback(fake_dns_t *fake, DWORD status,
                               const wchar_t *effective_name)
{
  assert(fake->callback != NULL);
  if (fake->free_instance_calls != 0) ++fake->callback_after_free;
  fake->callback_instance = fake->instance;
  fake->callback_instance.pszInstanceName = (PWSTR)effective_name;
  fake->callback(status, fake->callback_context, &fake->callback_instance);
}

static DWORD WINAPI fake_cancel(PDNS_SERVICE_CANCEL cancel)
{
  fake_dns_t *fake = active_fake;

  (void)cancel;
  assert(fake != NULL);
  ++fake->cancel_calls;
  if (fake->callback_on_cancel)
    fake_fire_callback(fake, ERROR_CANCELLED, NULL);
  return fake->cancel_result;
}

static DWORD WINAPI fake_deregister(PDNS_SERVICE_REGISTER_REQUEST request,
                                    PDNS_SERVICE_CANCEL cancel)
{
  fake_dns_t *fake = active_fake;

  assert(fake != NULL);
  ++fake->deregister_calls;
  if (cancel != NULL) {
    ++fake->deregister_nonnull_reserved;
    return ERROR_INVALID_PARAMETER;
  }
  if (fake->deregister_result != ERROR_SUCCESS &&
      fake->deregister_result != DNS_REQUEST_PENDING)
    return fake->deregister_result;
  ++fake->deregister_callback_calls;
  fake_fire_callback(fake, fake->deregister_callback_result,
                     request->pServiceInstance->pszInstanceName);
  return fake->deregister_result;
}

static VOID WINAPI fake_free_instance(PDNS_SERVICE_INSTANCE instance)
{
  fake_dns_t *fake = active_fake;

  assert(fake != NULL);
  if (instance == &fake->instance)
    ++fake->free_instance_calls;
  else if (instance == &fake->callback_instance)
    ++fake->free_callback_instance_calls;
  else {
    assert(instance == &fake->resolved_instance);
    ++fake->free_resolved_instance_calls;
    if (fake->close_on_resolved_free)
      bonjour_close(fake->browser_to_close);
  }
}

static DNS_STATUS WINAPI fake_browse(PDNS_SERVICE_BROWSE_REQUEST request,
                                     PDNS_SERVICE_CANCEL cancel)
{
  fake_dns_t *fake = active_fake;

  (void)cancel;
  assert(fake != NULL);
  assert(request->Version == DNS_QUERY_REQUEST_VERSION1);
  assert(request->InterfaceIndex == 0);
  assert(wcscmp(request->QueryName, L"_puretodo45._tcp.local") == 0);
  ++fake->browse_calls;
  fake->browse_callback = request->pBrowseCallback;
  fake->browse_context = request->pQueryContext;
  return fake->browse_result;
}

static DNS_STATUS WINAPI fake_browse_cancel(PDNS_SERVICE_CANCEL cancel)
{
  fake_dns_t *fake = active_fake;

  (void)cancel;
  assert(fake != NULL);
  ++fake->browse_cancel_calls;
  if (fake->browse_callback_on_cancel)
    fake->browse_callback(ERROR_CANCELLED, fake->browse_context, NULL);
  return fake->browse_cancel_result;
}

static DNS_STATUS WINAPI fake_resolve(PDNS_SERVICE_RESOLVE_REQUEST request,
                                      PDNS_SERVICE_CANCEL cancel)
{
  fake_dns_t *fake = active_fake;
  int index;

  (void)cancel;
  assert(fake != NULL);
  assert(request->Version == DNS_QUERY_REQUEST_VERSION1);
  assert(request->InterfaceIndex == 0);
  assert(CompareStringOrdinal(request->QueryName, -1,
                              fake->expected_service_name != NULL
                                  ? fake->expected_service_name
                                  : L"Probe._puretodo45._tcp.local", -1,
                              TRUE) == CSTR_EQUAL);
  index = fake->resolve_calls++;
  assert(index < 8);
  fake->resolve_callback = request->pResolveCompletionCallback;
  fake->resolve_context = request->pQueryContext;
  fake->resolve_callbacks[index] = request->pResolveCompletionCallback;
  fake->resolve_contexts[index] = request->pQueryContext;
  fake->resolve_cancel_handles[index] = cancel;
  return fake->resolve_result;
}

static DNS_STATUS WINAPI fake_resolve_cancel(PDNS_SERVICE_CANCEL cancel)
{
  fake_dns_t *fake = active_fake;
  int index;

  assert(fake != NULL);
  for (index = 0; index < fake->resolve_calls; ++index)
    if (cancel == fake->resolve_cancel_handles[index]) break;
  assert(index < fake->resolve_calls);
  ++fake->resolve_cancel_calls;
  if (fake->resolve_callback_on_cancel)
    fake->resolve_callbacks[index](ERROR_CANCELLED,
                                   fake->resolve_contexts[index], NULL);
  return fake->resolve_cancel_result;
}

static VOID WINAPI fake_before_resolver_link(void)
{
  fake_dns_t *fake = active_fake;
  DNS_RECORD record;

  assert(fake != NULL);
  if (!fake->delete_before_resolver_link) return;
  fake->delete_before_resolver_link = 0;
  memset(&record, 0, sizeof(record));
  record.pName = L"_puretodo45._tcp.local";
  record.wType = DNS_TYPE_PTR;
  record.Flags.S.Delete = 1;
  record.Data.PTR.pNameHost = L"pROBE._PURETODO45._TCP.LOCAL";
  fake->last_freed_records = NULL;
  fake->browse_callback(ERROR_SUCCESS, fake->browse_context, &record);
}

static VOID WINAPI fake_before_browser_cleanup(void)
{
  fake_dns_t *fake = active_fake;
  if (!fake->callback_during_browser_cleanup) return;
  fake->callback_during_browser_cleanup = 0;
  memset(&fake->resolved_instance, 0, sizeof(fake->resolved_instance));
  fake->resolved_ip4 = htonl(0x7f000001u);
  fake->resolved_instance.pszInstanceName =
      L"Probe._puretodo45._tcp.local";
  fake->resolved_instance.ip4Address = &fake->resolved_ip4;
  fake->resolved_instance.wPort = 41000;
  fake->resolved_instance.dwInterfaceIndex = 7;
  fake->resolve_callbacks[0](ERROR_SUCCESS, fake->resolve_contexts[0],
                             &fake->resolved_instance);
}

static VOID WINAPI fake_after_browse_route_acquire(void)
{
  fake_dns_t *fake = active_fake;

  assert(fake != NULL);
  if (fake->browse_route_entered == NULL) return;
  assert(SetEvent(fake->browse_route_entered));
  assert(WaitForSingleObject(fake->browse_route_release, 1000) ==
         WAIT_OBJECT_0);
}

static VOID WINAPI fake_record_list_free(PDNS_RECORD records,
                                         DNS_FREE_TYPE free_type)
{
  fake_dns_t *fake = active_fake;

  assert(fake != NULL);
  assert(records != NULL);
  assert(free_type == DnsFreeRecordList);
  assert(records != fake->last_freed_records);
  fake->last_freed_records = records;
  ++fake->record_free_calls;
}

static fake_dns_t fake_dns_pending_registration(void)
{
  fake_dns_t fake;

  memset(&fake, 0, sizeof(fake));
  fake.api.construct_instance = fake_construct_instance;
  fake.api.register_service = fake_register;
  fake.api.deregister_service = fake_deregister;
  fake.api.cancel_registration = fake_cancel;
  fake.api.free_instance = fake_free_instance;
  fake.api.browse = fake_browse;
  fake.api.cancel_browse = fake_browse_cancel;
  fake.api.resolve = fake_resolve;
  fake.api.cancel_resolve = fake_resolve_cancel;
  fake.api.free_records = fake_record_list_free;
  fake.api.before_resolver_link = fake_before_resolver_link;
  fake.api.before_browser_cleanup = fake_before_browser_cleanup;
  fake.api.after_browse_route_acquire = fake_after_browse_route_acquire;
  fake.register_result = DNS_REQUEST_PENDING;
  fake.deregister_result = DNS_REQUEST_PENDING;
  fake.deregister_callback_result = ERROR_SUCCESS;
  fake.browse_result = DNS_REQUEST_PENDING;
  fake.browse_cancel_result = ERROR_SUCCESS;
  fake.browse_callback_on_cancel = 1;
  fake.resolve_result = DNS_REQUEST_PENDING;
  fake.resolve_cancel_result = ERROR_SUCCESS;
  return fake;
}

static void use_fake(fake_dns_t *fake)
{
  active_fake = fake;
}

static void assert_error(pure_expr *result, DWORD status)
{
  int32_t value = 0;

  assert(result != NULL);
  assert(pure_is_int(result, &value));
  assert(value == bonjour_status_error(status));
  pure_freenew(result);
}

static void assert_registration(pure_expr *result, const char *name,
                                const char *type, int port)
{
  size_t count = 0;
  pure_expr **items = NULL;
  const char *actual_name = NULL;
  const char *actual_type = NULL;
  int32_t actual_port = -1;

  assert(result != NULL);
  assert(pure_is_tuplev(result, &count, &items));
  assert(count == 3);
  assert(pure_is_string(items[0], &actual_name));
  assert(pure_is_string(items[1], &actual_type));
  assert(pure_is_int(items[2], &actual_port));
  assert(strcmp(actual_name, name) == 0);
  assert(strcmp(actual_type, type) == 0);
  assert(actual_port == port);
  free(items);
  pure_freenew(result);
}

static void assert_single_result(pure_expr *result, const char *name,
                                 const char *address, int port)
{
  size_t list_count = 0;
  size_t tuple_count = 0;
  pure_expr **list_items = NULL;
  pure_expr **tuple_items = NULL;
  const char *actual_name = NULL;
  const char *actual_type = NULL;
  const char *actual_domain = NULL;
  const char *actual_address = NULL;
  int32_t actual_port = -1;

  assert(result != NULL);
  assert(pure_is_listv(result, &list_count, &list_items));
  assert(list_count == 1);
  assert(pure_is_tuplev(list_items[0], &tuple_count, &tuple_items));
  assert(tuple_count == 5);
  assert(pure_is_string(tuple_items[0], &actual_name));
  assert(pure_is_string(tuple_items[1], &actual_type));
  assert(pure_is_string(tuple_items[2], &actual_domain));
  assert(pure_is_string(tuple_items[3], &actual_address));
  assert(pure_is_int(tuple_items[4], &actual_port));
  assert(strcmp(actual_name, name) == 0);
  assert(strcmp(actual_type, "_puretodo45._tcp") == 0);
  assert(strcmp(actual_domain, "local") == 0);
  assert(strcmp(actual_address, address) == 0);
  assert(actual_port == port);
  free(tuple_items);
  free(list_items);
  pure_freenew(result);
}

static void assert_empty_result(pure_expr *result)
{
  size_t count = 0;
  pure_expr **items = NULL;

  assert(result != NULL);
  assert(pure_is_listv(result, &count, &items));
  assert(count == 0);
  free(items);
  pure_freenew(result);
}

static void fake_fire_browse_target(fake_dns_t *fake, DNS_RECORD *record,
                                    int deleted, const wchar_t *target)
{
  memset(record, 0, sizeof(*record));
  record->pName = L"_puretodo45._tcp.local";
  record->wType = DNS_TYPE_PTR;
  record->dwTtl = deleted ? 0 : 120;
  record->Flags.S.Delete = deleted != 0;
  record->Data.PTR.pNameHost = (PWSTR)target;
  fake->last_freed_records = NULL;
  fake->browse_callback(ERROR_SUCCESS, fake->browse_context, record);
}

static void fake_fire_browse(fake_dns_t *fake, DNS_RECORD *record, int deleted)
{
  fake_fire_browse_target(fake, record, deleted,
                          L"Probe._puretodo45._tcp.local");
}

static void fake_fire_resolve_ipv4_at(fake_dns_t *fake, int index,
                                      DWORD host_address)
{
  assert(index >= 0 && index < fake->resolve_calls);
  memset(&fake->resolved_instance, 0, sizeof(fake->resolved_instance));
  fake->resolved_ip4 = htonl(host_address);
  fake->resolved_instance.pszInstanceName =
      L"Probe._puretodo45._tcp.local";
  fake->resolved_instance.ip4Address = &fake->resolved_ip4;
  fake->resolved_instance.wPort = 41000;
  fake->resolved_instance.dwInterfaceIndex = 7;
  fake->resolve_callbacks[index](ERROR_SUCCESS, fake->resolve_contexts[index],
                                 &fake->resolved_instance);
}

static void fake_fire_resolve_ipv4_interface(fake_dns_t *fake, int index,
                                             DWORD host_address,
                                             DWORD interface_index)
{
  assert(index >= 0 && index < fake->resolve_calls);
  memset(&fake->resolved_instance, 0, sizeof(fake->resolved_instance));
  fake->resolved_ip4 = htonl(host_address);
  fake->resolved_instance.pszInstanceName =
      L"Probe._puretodo45._tcp.local";
  fake->resolved_instance.ip4Address = &fake->resolved_ip4;
  fake->resolved_instance.wPort = 41000;
  fake->resolved_instance.dwInterfaceIndex = interface_index;
  fake->resolve_callbacks[index](ERROR_SUCCESS, fake->resolve_contexts[index],
                                 &fake->resolved_instance);
}

static void fake_fire_resolve_ipv4(fake_dns_t *fake)
{
  fake_fire_resolve_ipv4_at(fake, fake->resolve_calls - 1, 0x7f000001u);
}

static void fake_fire_resolve_ipv6(fake_dns_t *fake)
{
  memset(&fake->resolved_instance, 0, sizeof(fake->resolved_instance));
  memset(&fake->resolved_ip6, 0, sizeof(fake->resolved_ip6));
  fake->resolved_ip6.IP6Byte[15] = 1;
  fake->resolved_instance.pszInstanceName =
      L"Probe._puretodo45._tcp.local";
  fake->resolved_instance.ip6Address = &fake->resolved_ip6;
  fake->resolved_instance.wPort = 41000;
  fake->resolved_instance.dwInterfaceIndex = 7;
  fake->resolve_callback(ERROR_SUCCESS, fake->resolve_context,
                         &fake->resolved_instance);
}

static void test_synchronous_rejection_releases_partial_state(void)
{
  fake_dns_t fake = fake_dns_pending_registration();

  fake.register_result = ERROR_ACCESS_DENIED;
  use_fake(&fake);
  assert(bonjour_publish_with_api("Probe", "_puretodo45._tcp", 43210,
                                  &fake.api, 25) == NULL);
  assert(fake.register_calls == 1);
  assert(fake.cancel_calls == 0);
  assert(fake.deregister_calls == 0);
  assert(fake.free_instance_calls == 1);
}

static void test_asynchronous_success_updates_effective_name(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  bonjour_service_t *service;

  use_fake(&fake);
  service = bonjour_publish_with_api("Probe", "_puretodo45._tcp", 43210,
                                     &fake.api, 25);
  assert(service != NULL);
  fake_fire_callback(&fake, ERROR_SUCCESS,
                     L"Probe #2._puretodo45._tcp.local");
  assert_registration(bonjour_check(service), "Probe #2", "_puretodo45._tcp",
                      43210);
  bonjour_unpublish(service);
  assert(fake.deregister_calls == 1);
  assert(fake.deregister_callback_calls == 1);
  assert(fake.deregister_nonnull_reserved == 0);
  assert(fake.cancel_calls == 0);
  assert(fake.free_instance_calls == 1);
  assert(fake.callback_after_free == 0);
}

static void test_registration_callback_instances_are_freed(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  bonjour_service_t *service;

  use_fake(&fake);
  service = bonjour_publish_with_api("Probe", "_puretodo45._tcp", 43210,
                                     &fake.api, 25);
  assert(service != NULL);
  fake_fire_callback(&fake, ERROR_SUCCESS,
                     L"Probe._puretodo45._tcp.local");
  assert(fake.free_callback_instance_calls == 1);
  assert_registration(bonjour_check(service), "Probe", "_puretodo45._tcp",
                      43210);
  bonjour_unpublish(service);
  assert(fake.free_callback_instance_calls == 2);
  assert(fake.free_instance_calls == 1);
}

static void test_unpublish_after_callback_failure_releases_state(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  bonjour_service_t *service;

  use_fake(&fake);
  service = bonjour_publish_with_api("Probe", "_puretodo45._tcp", 43210,
                                     &fake.api, 25);
  assert(service != NULL);
  fake_fire_callback(&fake, ERROR_SUCCESS,
                     L"Probe._puretodo45._tcp.local");
  fake.deregister_callback_result = ERROR_ACCESS_DENIED;
  bonjour_unpublish(service);
  assert(fake.free_instance_calls == 1);
  assert(fake.deregister_calls == 1);
  assert(fake.deregister_callback_calls == 1);
  assert(fake.deregister_nonnull_reserved == 0);
  assert(fake.free_instance_calls == 1);
  assert(fake.callback_after_free == 0);
}

static void test_unpublish_after_dispatch_failure_releases_state(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  bonjour_service_t *service;

  use_fake(&fake);
  service = bonjour_publish_with_api("Probe", "_puretodo45._tcp", 43210,
                                     &fake.api, 25);
  assert(service != NULL);
  fake_fire_callback(&fake, ERROR_SUCCESS,
                     L"Probe._puretodo45._tcp.local");
  fake.deregister_result = ERROR_ACCESS_DENIED;
  bonjour_unpublish(service);
  assert(fake.free_instance_calls == 1);
  assert(fake.deregister_calls == 1);
  assert(fake.deregister_callback_calls == 0);
  assert(fake.deregister_nonnull_reserved == 0);
  assert(fake.free_instance_calls == 1);
  assert(fake.callback_after_free == 0);
}

static void test_check_timeout_is_bounded(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  ULONGLONG started;
  ULONGLONG elapsed;
  bonjour_service_t *service;

  use_fake(&fake);
  service = bonjour_publish_with_api("Probe", "_puretodo45._tcp", 43210,
                                     &fake.api, 25);
  assert(service != NULL);
  started = GetTickCount64();
  assert_error(bonjour_check(service), ERROR_TIMEOUT);
  elapsed = GetTickCount64() - started;
  assert(elapsed < 500);
  bonjour_unpublish(service);
}

static void test_pending_registration_is_cancelled_before_free(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  bonjour_service_t *service;

  use_fake(&fake);
  service = bonjour_publish_with_api("Probe", "_puretodo45._tcp", 43210,
                                     &fake.api, 25);
  assert(service != NULL);
  bonjour_unpublish(service);
  assert(fake.register_calls == 1);
  assert(fake.cancel_calls == 1);
  assert(fake.deregister_calls == 0);
  assert(fake.free_instance_calls == 1);
  assert(fake.callback_after_free == 0);
}

static void test_callback_completion_during_cancellation_is_safe(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  bonjour_service_t *service;

  fake.callback_on_cancel = 1;
  use_fake(&fake);
  service = bonjour_publish_with_api("Probe", "_puretodo45._tcp", 43210,
                                     &fake.api, 25);
  assert(service != NULL);
  bonjour_unpublish(service);
  assert(fake.cancel_calls == 1);
  assert(fake.free_instance_calls == 1);
  assert(fake.callback_after_free == 0);
}

static void test_repeated_null_cleanup_is_a_noop(void)
{
  fake_dns_t fake = fake_dns_pending_registration();

  use_fake(&fake);
  bonjour_unpublish(NULL);
  bonjour_unpublish(NULL);
  assert(fake.cancel_calls == 0);
  assert(fake.deregister_calls == 0);
  assert(fake.free_instance_calls == 0);
}

static void test_browse_rejection_releases_partial_state(void)
{
  fake_dns_t fake = fake_dns_pending_registration();

  fake.browse_result = ERROR_ACCESS_DENIED;
  use_fake(&fake);
  assert(bonjour_browse_with_api("_puretodo45._tcp", &fake.api, 25) == NULL);
  assert(fake.browse_calls == 1);
  assert(fake.browse_cancel_calls == 0);
  assert(fake.resolve_calls == 0);
}

static void test_browse_resolve_snapshot_update_and_removal(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  bonjour_browser_t *browser;
  DNS_RECORD add_record;
  DNS_RECORD pending_duplicate_record;
  DNS_RECORD duplicate_record;
  DNS_RECORD ipv6_record;
  DNS_RECORD remove_record;

  use_fake(&fake);
  browser = bonjour_browse_with_api("_puretodo45._tcp", &fake.api, 25);
  assert(browser != NULL);
  fake_fire_browse(&fake, &add_record, 0);
  assert(fake.record_free_calls == 1);
  assert(fake.resolve_calls == 1);
  fake_fire_browse_target(&fake, &pending_duplicate_record, 0,
                          L"pROBE._PURETODO45._TCP.LOCAL");
  assert(fake.record_free_calls == 2);
  assert(fake.resolve_calls == 1);
  fake_fire_resolve_ipv4(&fake);
  assert(fake.free_resolved_instance_calls == 1);
  assert(bonjour_avail(browser) == 1);
  assert_single_result(bonjour_get(browser), "Probe", "127.0.0.1", 41000);
  assert(bonjour_avail(browser) == 0);

  fake_fire_browse(&fake, &duplicate_record, 0);
  assert(fake.record_free_calls == 3);
  assert(fake.resolve_calls == 1);
  fake_fire_resolve_ipv4(&fake);
  assert(fake.free_resolved_instance_calls == 2);
  assert(bonjour_avail(browser) == 0);

  fake_fire_browse(&fake, &ipv6_record, 0);
  assert(fake.record_free_calls == 4);
  assert(fake.resolve_calls == 1);
  fake_fire_resolve_ipv6(&fake);
  assert(fake.free_resolved_instance_calls == 3);
  assert(bonjour_avail(browser) == 1);
  assert_single_result(bonjour_get(browser), "Probe", "::1", 41000);

  fake_fire_browse(&fake, &remove_record, 1);
  assert(fake.record_free_calls == 5);
  assert(bonjour_avail(browser) == 1);
  assert_empty_result(bonjour_get(browser));
  bonjour_close(browser);
  assert(fake.browse_cancel_calls == 1);
  assert(fake.resolve_cancel_calls == 1);
}

static void test_browse_cancel_failure_retains_state(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  bonjour_browser_t *browser;

  fake.browse_cancel_result = ERROR_ACCESS_DENIED;
  use_fake(&fake);
  browser = bonjour_browse_with_api("_puretodo45._tcp", &fake.api, 25);
  assert(browser != NULL);
  bonjour_close(browser);
  assert(bonjour_callback_registry_count() == 1);
  fake.browse_callback(ERROR_ACCESS_DENIED, fake.browse_context, NULL);
  assert(bonjour_callback_registry_count() == 1);
  fake.browse_cancel_result = ERROR_SUCCESS;
  bonjour_close(browser);
  assert(fake.browse_cancel_calls == 2);
  assert(fake.resolve_cancel_calls == 0);
  assert(bonjour_callback_registry_count() == 0);
}

static void test_registration_cancel_failure_retains_state_for_callback_and_retry(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  bonjour_service_t *service;

  fake.cancel_result = ERROR_ACCESS_DENIED;
  use_fake(&fake);
  service = bonjour_publish_with_api("Probe", "_puretodo45._tcp", 43210,
                                     &fake.api, 25);
  assert(service != NULL);
  bonjour_unpublish(service);
  assert(fake.cancel_calls == 1);
  assert(fake.free_instance_calls == 0);
  assert(bonjour_callback_registry_count() == 1);
  fake_fire_callback(&fake, ERROR_CANCELLED, NULL);
  assert(fake.free_callback_instance_calls == 1);
  assert(bonjour_callback_registry_count() == 1);
  fake.cancel_result = ERROR_SUCCESS;
  bonjour_unpublish(service);
  assert(fake.free_instance_calls == 1);
  assert(bonjour_callback_registry_count() == 0);
}

static void test_resolve_cancel_failure_retains_state_for_callback_and_retry(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  bonjour_browser_t *browser;
  DNS_RECORD add_record;

  fake.resolve_cancel_result = ERROR_ACCESS_DENIED;
  use_fake(&fake);
  browser = bonjour_browse_with_api("_puretodo45._tcp", &fake.api, 25);
  assert(browser != NULL);
  fake_fire_browse(&fake, &add_record, 0);
  assert(bonjour_callback_registry_count() == 2);
  bonjour_close(browser);
  assert(fake.browse_cancel_calls == 1);
  assert(fake.resolve_cancel_calls == 1);
  assert(bonjour_callback_registry_count() == 1);
  fake_fire_resolve_ipv4(&fake);
  assert(fake.free_resolved_instance_calls == 1);
  assert(bonjour_callback_registry_count() == 1);
  fake.resolve_cancel_result = ERROR_SUCCESS;
  bonjour_close(browser);
  assert(fake.browse_cancel_calls == 1);
  assert(fake.resolve_cancel_calls == 2);
  assert(bonjour_callback_registry_count() == 0);
}

static DWORD WINAPI fake_fire_browse_error_thread(void *parameter)
{
  fake_dns_t *fake = parameter;
  fake->browse_callback(ERROR_ACCESS_DENIED, fake->browse_context, NULL);
  return 0;
}

static void test_route_drain_timeout_is_bounded_and_retains_live_browser(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  bonjour_browser_t *browser;
  HANDLE callback_thread;
  ULONGLONG started;

  fake.browse_callback_on_cancel = 0;
  fake.browse_route_entered = CreateEventW(NULL, TRUE, FALSE, NULL);
  fake.browse_route_release = CreateEventW(NULL, TRUE, FALSE, NULL);
  assert(fake.browse_route_entered != NULL);
  assert(fake.browse_route_release != NULL);
  use_fake(&fake);
  browser = bonjour_browse_with_api("_puretodo45._tcp", &fake.api, 25);
  assert(browser != NULL);
  callback_thread = CreateThread(NULL, 0, fake_fire_browse_error_thread,
                                 &fake, 0, NULL);
  assert(callback_thread != NULL);
  assert(WaitForSingleObject(fake.browse_route_entered, 1000) == WAIT_OBJECT_0);
  started = GetTickCount64();
  bonjour_close(browser);
  assert(GetTickCount64() - started < 500);
  assert(bonjour_callback_registry_count() == 1);
  assert(SetEvent(fake.browse_route_release));
  assert(WaitForSingleObject(callback_thread, 1000) == WAIT_OBJECT_0);
  assert(bonjour_callback_registry_count() == 0);
  CloseHandle(callback_thread);
  CloseHandle(fake.browse_route_release);
  CloseHandle(fake.browse_route_entered);
}

static void test_removal_while_resolve_pending_cannot_readd_service(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  bonjour_browser_t *browser;
  DNS_RECORD add_record;
  DNS_RECORD remove_record;

  use_fake(&fake);
  browser = bonjour_browse_with_api("_puretodo45._tcp", &fake.api, 25);
  assert(browser != NULL);
  fake_fire_browse(&fake, &add_record, 0);
  fake_fire_browse(&fake, &remove_record, 1);
  fake_fire_resolve_ipv4(&fake);
  assert(bonjour_avail(browser) == 0);
  assert_empty_result(bonjour_get(browser));
  bonjour_close(browser);
}

static void test_zero_ttl_ptr_removes_without_delete_flag(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  bonjour_browser_t *browser;
  DNS_RECORD add_record;
  DNS_RECORD remove_record;

  use_fake(&fake);
  browser = bonjour_browse_with_api("_puretodo45._tcp", &fake.api, 25);
  assert(browser != NULL);
  fake_fire_browse(&fake, &add_record, 0);
  fake_fire_resolve_ipv4(&fake);
  assert_single_result(bonjour_get(browser), "Probe", "127.0.0.1", 41000);
  memset(&remove_record, 0, sizeof(remove_record));
  remove_record.pName = L"_puretodo45._tcp.local";
  remove_record.wType = DNS_TYPE_PTR;
  remove_record.Data.PTR.pNameHost = L"Probe._puretodo45._tcp.local";
  remove_record.dwTtl = 0;
  fake.last_freed_records = NULL;
  fake.browse_callback(ERROR_SUCCESS, fake.browse_context, &remove_record);
  assert(fake.resolve_calls == 1);
  assert(bonjour_avail(browser) == 1);
  assert_empty_result(bonjour_get(browser));
  bonjour_close(browser);
}

static void test_unknown_deletes_do_not_grow_name_state(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  bonjour_browser_t *browser;
  DNS_RECORD records[64];
  wchar_t targets[64][96];
  size_t index;

  use_fake(&fake);
  browser = bonjour_browse_with_api("_puretodo45._tcp", &fake.api, 25);
  assert(browser != NULL);
  assert(bonjour_browser_name_state_count(browser) == 0);
  for (index = 0; index < 64; ++index) {
    assert(swprintf(targets[index], 96,
                    L"Unknown-%zu._puretodo45._tcp.local", index) > 0);
    fake_fire_browse_target(&fake, &records[index], 1, targets[index]);
  }
  assert(fake.resolve_calls == 0);
  assert(bonjour_browser_name_state_count(browser) == 0);
  bonjour_close(browser);
}

static void test_resolver_route_is_removed_with_ptr(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  bonjour_browser_t *browser;
  DNS_RECORD add_record;
  DNS_RECORD remove_record;

  use_fake(&fake);
  browser = bonjour_browse_with_api("_puretodo45._tcp", &fake.api, 25);
  assert(browser != NULL);
  fake_fire_browse(&fake, &add_record, 0);
  assert(bonjour_browser_name_state_count(browser) == 1);
  fake_fire_browse_target(&fake, &remove_record, 1,
                          L"pROBE._PURETODO45._TCP.LOCAL");
  assert(bonjour_browser_name_state_count(browser) == 0);
  fake_fire_resolve_ipv4(&fake);
  assert(bonjour_avail(browser) == 0);
  assert(bonjour_browser_name_state_count(browser) == 0);
  bonjour_close(browser);
}

static void test_completed_and_cancelled_churn_reclaims_name_state(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  bonjour_browser_t *browser;
  DNS_RECORD add_records[6];
  DNS_RECORD remove_records[6];
  int index;

  use_fake(&fake);
  browser = bonjour_browse_with_api("_puretodo45._tcp", &fake.api, 25);
  assert(browser != NULL);
  for (index = 0; index < 6; ++index) {
    fake_fire_browse(&fake, &add_records[index], 0);
    if (index < 3)
      fake_fire_resolve_ipv4_at(&fake, index, 0x7f000001u + (DWORD)index);
    fake_fire_browse(&fake, &remove_records[index], 1);
    if (index >= 3)
      fake.resolve_callbacks[index](ERROR_CANCELLED,
                                    fake.resolve_contexts[index], NULL);
    assert(bonjour_browser_name_state_count(browser) == 0);
  }
  assert(fake.resolve_calls == 6);
  bonjour_close(browser);
}

static void test_delete_before_resolver_link_invalidates_add_generation(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  bonjour_browser_t *browser;
  DNS_RECORD add_record;

  fake.delete_before_resolver_link = 1;
  use_fake(&fake);
  browser = bonjour_browse_with_api("_puretodo45._tcp", &fake.api, 25);
  assert(browser != NULL);
  fake_fire_browse(&fake, &add_record, 0);
  assert(fake.resolve_calls == 0);
  assert(fake.record_free_calls == 2);
  assert_empty_result(bonjour_get(browser));
  bonjour_close(browser);
}

static void test_remove_readd_ignores_late_old_generation_completion(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  bonjour_browser_t *browser;
  DNS_RECORD first_add;
  DNS_RECORD remove_record;
  DNS_RECORD second_add;

  use_fake(&fake);
  browser = bonjour_browse_with_api("_puretodo45._tcp", &fake.api, 25);
  assert(browser != NULL);
  fake_fire_browse_target(&fake, &first_add, 0,
                          L"Probe._puretodo45._tcp.local");
  fake_fire_browse_target(&fake, &remove_record, 1,
                          L"PROBE._PURETODO45._TCP.LOCAL");
  fake_fire_browse_target(&fake, &second_add, 0,
                          L"pRoBe._puretodo45._tcp.local");
  assert(fake.resolve_calls == 2);
  fake_fire_resolve_ipv4_at(&fake, 1, 0x7f000002u);
  fake_fire_resolve_ipv4_at(&fake, 0, 0x7f000001u);
  assert_single_result(bonjour_get(browser), "Probe", "127.0.0.2", 41000);
  assert(bonjour_browser_name_state_count(browser) == 1);
  fake_fire_browse_target(&fake, &remove_record, 1,
                          L"PROBE._PURETODO45._TCP.LOCAL");
  assert(bonjour_browser_name_state_count(browser) == 0);
  bonjour_close(browser);
}

static void test_pending_resolver_is_cancelled_during_close(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  bonjour_browser_t *browser;
  DNS_RECORD add_record;

  fake.resolve_callback_on_cancel = 1;
  use_fake(&fake);
  browser = bonjour_browse_with_api("_puretodo45._tcp", &fake.api, 25);
  assert(browser != NULL);
  fake_fire_browse(&fake, &add_record, 0);
  bonjour_close(browser);
  assert(fake.browse_cancel_calls == 1);
  assert(fake.resolve_cancel_calls == 1);
  assert(fake.free_resolved_instance_calls == 0);
}

static void test_resolver_accepts_multiple_results_for_query_lifetime(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  bonjour_browser_t *browser;
  DNS_RECORD add_record;
  pure_expr *snapshot;
  size_t count = 0;
  pure_expr **items = NULL;

  use_fake(&fake);
  browser = bonjour_browse_with_api("_puretodo45._tcp", &fake.api, 25);
  assert(browser != NULL);
  fake_fire_browse(&fake, &add_record, 0);
  fake_fire_resolve_ipv4_interface(&fake, 0, 0x7f000001u, 7);
  fake_fire_resolve_ipv4_interface(&fake, 0, 0xc0000209u, 9);
  assert(fake.free_resolved_instance_calls == 2);
  snapshot = bonjour_get(browser);
  assert(snapshot != NULL);
  assert(pure_is_listv(snapshot, &count, &items));
  assert(count == 2);
  free(items);
  pure_freenew(snapshot);
  bonjour_close(browser);
  assert(fake.resolve_cancel_calls == 1);
}

static void test_resolver_callback_after_close_uses_retained_context(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  bonjour_browser_t *browser;
  DNS_RECORD add_record;

  fake.resolve_callback_on_cancel = 0;
  use_fake(&fake);
  browser = bonjour_browse_with_api("_puretodo45._tcp", &fake.api, 25);
  assert(browser != NULL);
  fake_fire_browse(&fake, &add_record, 0);
  bonjour_close(browser);
  fake.resolve_callbacks[0](ERROR_CANCELLED, fake.resolve_contexts[0], NULL);
  fake_fire_resolve_ipv4_interface(&fake, 0, 0x7f000001u, 7);
  assert(fake.free_resolved_instance_calls == 1);
  assert(bonjour_callback_registry_count() == 0);
}

static void test_registration_callback_after_cancel_uses_retained_context(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  bonjour_service_t *service;

  fake.callback_on_cancel = 0;
  use_fake(&fake);
  service = bonjour_publish_with_api("Probe", "_puretodo45._tcp", 43210,
                                     &fake.api, 25);
  assert(service != NULL);
  bonjour_unpublish(service);
  fake_fire_callback(&fake, ERROR_CANCELLED, NULL);
  assert(fake.free_callback_instance_calls == 1);
  assert(fake.cancel_calls == 1);
  assert(bonjour_callback_registry_count() == 0);
}

static void test_late_resolve_during_close_cleanup_misses_detached_route(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  bonjour_browser_t *browser;
  DNS_RECORD add_record;

  use_fake(&fake);
  browser = bonjour_browse_with_api("_puretodo45._tcp", &fake.api, 25);
  assert(browser != NULL);
  fake_fire_browse(&fake, &add_record, 0);
  fake.callback_during_browser_cleanup = 1;
  bonjour_close(browser);
  assert(fake.free_resolved_instance_calls == 1);
  assert(bonjour_callback_registry_count() == 0);
}

static void test_callback_registry_and_handles_return_to_baseline_after_churn(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  DWORD handles_before = 0;
  DWORD handles_after = 0;
  int index;

  use_fake(&fake);
  assert(GetProcessHandleCount(GetCurrentProcess(), &handles_before));
  for (index = 0; index < 1000; ++index) {
    bonjour_service_t *service = bonjour_publish_with_api(
        "Probe", "_puretodo45._tcp", 43210, &fake.api, 25);
    assert(service != NULL);
    bonjour_unpublish(service);
  }
  for (index = 0; index < 1000; ++index) {
    bonjour_browser_t *browser = bonjour_browse_with_api(
        "_puretodo45._tcp", &fake.api, 25);
    assert(browser != NULL);
    bonjour_close(browser);
  }
  assert(bonjour_callback_registry_count() == 0);
  assert(GetProcessHandleCount(GetCurrentProcess(), &handles_after));
  assert(handles_after <= handles_before + 2);
}

static void test_escaped_instance_round_trips_registration_and_discovery(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  bonjour_service_t *service;
  bonjour_browser_t *browser;
  DNS_RECORD add_record;
  DNS_RECORD remove_record;

  fake.expected_service_name =
      L"Probe\\.raw\\\\path._puretodo45._tcp.local";
  use_fake(&fake);
  service = bonjour_publish_with_api("Probe.raw\\path", "_puretodo45._tcp",
                                     43210, &fake.api, 25);
  assert(service != NULL);
  fake_fire_callback(&fake, ERROR_SUCCESS, fake.expected_service_name);
  assert_registration(bonjour_check(service), "Probe.raw\\path",
                      "_puretodo45._tcp", 43210);

  browser = bonjour_browse_with_api("_puretodo45._tcp", &fake.api, 25);
  assert(browser != NULL);
  fake_fire_browse_target(&fake, &add_record, 0, fake.expected_service_name);
  memset(&fake.resolved_instance, 0, sizeof(fake.resolved_instance));
  fake.resolved_ip4 = htonl(0x7f000001u);
  fake.resolved_instance.pszInstanceName = (PWSTR)fake.expected_service_name;
  fake.resolved_instance.ip4Address = &fake.resolved_ip4;
  fake.resolved_instance.wPort = 41000;
  fake.resolved_instance.dwInterfaceIndex = 7;
  fake.resolve_callbacks[0](ERROR_SUCCESS, fake.resolve_contexts[0],
                            &fake.resolved_instance);
  assert_single_result(bonjour_get(browser), "Probe.raw\\path", "127.0.0.1",
                       41000);
  fake_fire_browse_target(&fake, &remove_record, 1,
                          fake.expected_service_name);
  assert_empty_result(bonjour_get(browser));
  bonjour_close(browser);
  bonjour_unpublish(service);
}

static void test_close_during_resolve_callback_retains_until_callback_tail(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  bonjour_browser_t *browser;
  DNS_RECORD add_record;

  use_fake(&fake);
  browser = bonjour_browse_with_api("_puretodo45._tcp", &fake.api, 25);
  assert(browser != NULL);
  fake.browser_to_close = browser;
  fake.close_on_resolved_free = 1;
  fake_fire_browse(&fake, &add_record, 0);
  fake_fire_resolve_ipv4(&fake);
  assert(fake.browse_cancel_calls == 1);
  assert(fake.free_resolved_instance_calls == 1);
  assert(bonjour_callback_registry_count() == 0);
}

static void test_close_allows_synchronous_cancel_callbacks(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  bonjour_browser_t *browser;
  DNS_RECORD add_record;

  fake.browse_callback_on_cancel = 1;
  fake.resolve_callback_on_cancel = 1;
  use_fake(&fake);
  browser = bonjour_browse_with_api("_puretodo45._tcp", &fake.api, 25);
  assert(browser != NULL);
  fake_fire_browse(&fake, &add_record, 0);
  bonjour_close(browser);
  assert(fake.browse_cancel_calls == 1);
  assert(fake.resolve_cancel_calls == 1);
}

static void test_no_result_close_is_bounded(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  bonjour_browser_t *browser;
  ULONGLONG started;

  use_fake(&fake);
  browser = bonjour_browse_with_api("_puretodo45._tcp", &fake.api, 25);
  assert(browser != NULL);
  started = GetTickCount64();
  bonjour_close(browser);
  assert(GetTickCount64() - started < 500);
  assert(fake.browse_cancel_calls == 1);
  assert(fake.resolve_cancel_calls == 0);
}

static void test_delayed_browse_cancel_ack_cannot_target_freed_state(void)
{
  fake_dns_t fake = fake_dns_pending_registration();
  bonjour_browser_t *browser;
  ULONGLONG started;
  ULONGLONG elapsed;

  fake.browse_callback_on_cancel = 0;
  use_fake(&fake);
  browser = bonjour_browse_with_api("_puretodo45._tcp", &fake.api, 25);
  assert(browser != NULL);
  started = GetTickCount64();
  bonjour_close(browser);
  elapsed = GetTickCount64() - started;
  assert(elapsed < 500);
  fake.browse_callback(ERROR_CANCELLED, fake.browse_context, NULL);
  assert(fake.browse_cancel_calls == 1);
}

int main(void)
{
  pure_interp *interp = pure_create_interp(0, NULL);

  assert(interp != NULL);
  test_synchronous_rejection_releases_partial_state();
  test_asynchronous_success_updates_effective_name();
  test_registration_callback_instances_are_freed();
  test_unpublish_after_callback_failure_releases_state();
  test_unpublish_after_dispatch_failure_releases_state();
  test_check_timeout_is_bounded();
  test_pending_registration_is_cancelled_before_free();
  test_callback_completion_during_cancellation_is_safe();
  test_repeated_null_cleanup_is_a_noop();
  test_browse_rejection_releases_partial_state();
  test_browse_resolve_snapshot_update_and_removal();
  test_removal_while_resolve_pending_cannot_readd_service();
  test_zero_ttl_ptr_removes_without_delete_flag();
  test_unknown_deletes_do_not_grow_name_state();
  test_resolver_route_is_removed_with_ptr();
  test_completed_and_cancelled_churn_reclaims_name_state();
  test_delete_before_resolver_link_invalidates_add_generation();
  test_remove_readd_ignores_late_old_generation_completion();
  test_pending_resolver_is_cancelled_during_close();
  test_resolver_accepts_multiple_results_for_query_lifetime();
  test_resolver_callback_after_close_uses_retained_context();
  test_registration_callback_after_cancel_uses_retained_context();
  test_late_resolve_during_close_cleanup_misses_detached_route();
  test_callback_registry_and_handles_return_to_baseline_after_churn();
  test_escaped_instance_round_trips_registration_and_discovery();
  test_close_during_resolve_callback_retains_until_callback_tail();
  test_close_allows_synchronous_cancel_callbacks();
  test_no_result_close_is_bounded();
  test_delayed_browse_cancel_ack_cannot_target_freed_state();
  test_browse_cancel_failure_retains_state();
  test_registration_cancel_failure_retains_state_for_callback_and_retry();
  test_resolve_cancel_failure_retains_state_for_callback_and_retry();
  test_route_drain_timeout_is_bounded_and_retains_live_browser();
  bonjour_close(NULL);
  assert(bonjour_callback_registry_count() == 0);
  pure_delete_interp(interp);
  puts("pure-bonjour lifecycle tests passed");
  return 0;
}
