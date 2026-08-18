#include <assert.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>

#include "bonjour_windows.h"

static void test_utf8_round_trips(void)
{
  static const char *const samples[] = {
    "ASCII text",
    "Probe \xC4\x85",
    "\xE6\x9D\xB1\xE4\xBA\xAC",
  };
  size_t i;

  for (i = 0; i < sizeof(samples) / sizeof(samples[0]); ++i) {
    wchar_t *wide = bonjour_utf8_to_wide(samples[i]);
    char *utf8;

    assert(wide != NULL);
    utf8 = bonjour_wide_to_utf8(wide);
    assert(utf8 != NULL);
    assert(strcmp(utf8, samples[i]) == 0);
    free(utf8);
    free(wide);
  }

  assert(bonjour_utf8_to_wide("\xC3\x28") == NULL);
}

static void test_names(void)
{
  wchar_t *type = bonjour_make_type_fqdn("_puretodo45._tcp");
  wchar_t *fqdn = bonjour_make_instance_fqdn("Probe \xC4\x85",
                                             "_puretodo45._tcp");
  char *name = NULL;
  char *split_type = NULL;
  char *domain = NULL;
  char too_long_type[71];
  char too_long_instance[65];
  char too_long_name[240];

  assert(type != NULL);
  assert(wcscmp(type, L"_puretodo45._tcp.local") == 0);
  free(type);

  assert(fqdn != NULL);
  assert(bonjour_split_instance_fqdn(fqdn, &name, &split_type, &domain) == 0);
  assert(strcmp(name, "Probe \xC4\x85") == 0);
  assert(strcmp(split_type, "_puretodo45._tcp") == 0);
  assert(strcmp(domain, "local") == 0);
  free(fqdn);
  free(name);
  free(split_type);
  free(domain);

  assert(bonjour_make_type_fqdn("http.tcp") == NULL);
  assert(bonjour_make_type_fqdn("_http._sctp") == NULL);
  assert(bonjour_make_type_fqdn("_http._tcp.local") == NULL);

  too_long_type[0] = '_';
  memset(too_long_type + 1, 'a', 63);
  memcpy(too_long_type + 64, "._tcp", 6);
  assert(bonjour_make_type_fqdn(too_long_type) == NULL);

  memset(too_long_instance, 'a', sizeof(too_long_instance) - 1);
  too_long_instance[sizeof(too_long_instance) - 1] = '\0';
  assert(bonjour_make_instance_fqdn(too_long_instance,
                                    "_puretodo45._tcp") == NULL);
  assert(bonjour_make_instance_fqdn("Probe.raw", "_puretodo45._tcp") == NULL);

  memset(too_long_name, 'a', sizeof(too_long_name) - 1);
  too_long_name[sizeof(too_long_name) - 1] = '\0';
  assert(bonjour_make_instance_fqdn(too_long_name, "_puretodo45._tcp") == NULL);
  assert(bonjour_split_instance_fqdn(L"Probe._puretodo45._tcp",
                                     &name, &split_type, &domain) < 0);
}

static void test_status_errors(void)
{
  assert(bonjour_status_error(ERROR_SUCCESS) == 0);
  assert(bonjour_status_error(ERROR_ACCESS_DENIED) < 0);
  assert(bonjour_status_error(ERROR_INVALID_PARAMETER) < 0);
  assert(bonjour_status_error((DWORD)UINT_MAX) == -INT_MAX);
}

int main(void)
{
  test_utf8_round_trips();
  test_names();
  test_status_errors();
  puts("pure-bonjour unit tests passed");
  return 0;
}
