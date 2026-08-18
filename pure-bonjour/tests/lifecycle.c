#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include <windows.h>

#include "bonjour_windows.h"

typedef struct {
  bonjour_dns_api_t api;
  DNS_SERVICE_INSTANCE instance;
  DWORD register_result;
  DWORD cancel_result;
  DWORD deregister_result;
  DWORD deregister_callback_result;
  int register_calls;
  int cancel_calls;
  int deregister_calls;
  int deregister_callback_calls;
  int deregister_nonnull_reserved;
  int free_instance_calls;
  int callback_after_free;
  int callback_on_cancel;
  PDNS_SERVICE_REGISTER_COMPLETE callback;
  void *callback_context;
} fake_dns_t;

static fake_dns_t *active_fake;

static PDNS_SERVICE_INSTANCE WINAPI fake_construct_instance(
    PCWSTR service_name, PCWSTR host_name, PIP4_ADDRESS ip4, PIP6_ADDRESS ip6,
    WORD port, WORD priority, WORD weight, DWORD properties_count,
    PCWSTR *keys, PCWSTR *values)
{
  fake_dns_t *fake = active_fake;

  assert(fake != NULL);
  assert(wcscmp(service_name, L"Probe._puretodo45._tcp.local") == 0);
  assert(host_name == NULL);
  assert(ip4 == NULL);
  assert(ip6 == NULL);
  assert(port == 51880);
  assert(priority == 0);
  assert(weight == 0);
  assert(properties_count == 0);
  assert(keys == NULL);
  assert(values == NULL);
  memset(&fake->instance, 0, sizeof(fake->instance));
  fake->instance.pszInstanceName = (PWSTR)service_name;
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
  fake->instance.pszInstanceName = (PWSTR)effective_name;
  fake->callback(status, fake->callback_context, &fake->instance);
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
  assert(instance == &fake->instance);
  ++fake->free_instance_calls;
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
  fake.register_result = DNS_REQUEST_PENDING;
  fake.deregister_result = DNS_REQUEST_PENDING;
  fake.deregister_callback_result = ERROR_SUCCESS;
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

static void test_deregistration_callback_failure_retains_state(void)
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
  assert(fake.deregister_calls == 1);
  assert(fake.deregister_callback_calls == 1);
  assert(fake.deregister_nonnull_reserved == 0);
  assert(fake.free_instance_calls == 0);
  assert(fake.callback_after_free == 0);
}

static void test_deregistration_dispatch_failure_retains_state(void)
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
  assert(fake.deregister_calls == 1);
  assert(fake.deregister_callback_calls == 0);
  assert(fake.deregister_nonnull_reserved == 0);
  assert(fake.free_instance_calls == 0);
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
  assert(elapsed >= 10);
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

int main(void)
{
  pure_interp *interp = pure_create_interp(0, NULL);

  assert(interp != NULL);
  test_synchronous_rejection_releases_partial_state();
  test_asynchronous_success_updates_effective_name();
  test_deregistration_callback_failure_retains_state();
  test_deregistration_dispatch_failure_retains_state();
  test_check_timeout_is_bounded();
  test_pending_registration_is_cancelled_before_free();
  test_callback_completion_during_cancellation_is_safe();
  test_repeated_null_cleanup_is_a_noop();
  pure_delete_interp(interp);
  puts("pure-bonjour lifecycle tests passed");
  return 0;
}
