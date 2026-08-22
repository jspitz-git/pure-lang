#include <gmp.h>
#include <mpfr.h>
#include <stdio.h>
#include <string.h>

static int fail(const char *message)
{
  fprintf(stderr, "FAIL: %s\n", message);
  return 1;
}

int main(void)
{
  char mpfr_header[32], gmp_header[32];
  mpfr_t value;
  snprintf(mpfr_header, sizeof mpfr_header, "%d.%d.%d",
    MPFR_VERSION_MAJOR, MPFR_VERSION_MINOR, MPFR_VERSION_PATCHLEVEL);
  snprintf(gmp_header, sizeof gmp_header, "%d.%d.%d",
    __GNU_MP_VERSION, __GNU_MP_VERSION_MINOR, __GNU_MP_VERSION_PATCHLEVEL);
  if (strcmp(mpfr_header, mpfr_get_version()) != 0)
    return fail("MPFR header/runtime version mismatch");
  if (strcmp(gmp_header, gmp_version) != 0)
    return fail("GMP header/runtime version mismatch");
  if (sizeof(mp_limb_t) != 8 || GMP_NUMB_BITS != 64 || GMP_NAIL_BITS != 0)
    return fail("unexpected GMP limb ABI");
  if (sizeof(mpfr_prec_t) != 4 || sizeof(mpfr_exp_t) != 4)
    return fail("unexpected MPFR scalar ABI");
  mpfr_init2(value, 128);
  if (mpfr_set_str(value, "1.25", 10, MPFR_RNDN) != 0 ||
      mpfr_get_prec(value) != 128 || mpfr_get_d(value, MPFR_RNDN) != 1.25) {
    mpfr_clear(value);
    return fail("128-bit MPFR operation failed");
  }
  mpfr_clear(value);
  puts("PURE_MPFR_ABI_OK");
  return 0;
}
