#include <stdlib.h>

#ifndef FAUST_TEST_VERSION
#define FAUST_TEST_VERSION 11
#endif

const char pure_faust_sample_format[] = "double";

static int faust_test_state;
static int faust_test_anchor __attribute__((used)) = FAUST_TEST_VERSION;

__attribute__((constructor))
static void initialize_faust_test_state(void)
{
  faust_test_state = faust_test_anchor;
}

void *newreload(void)
{
  return malloc(1);
}

void deletereload(void *dsp)
{
  free(dsp);
}

void initreload(void *dsp, int rate)
{
  (void)dsp;
  (void)rate;
}

void buildUserInterfacereload(void *dsp, void *ui)
{
  (void)dsp;
  (void)ui;
}

int getNumInputsreload(void *dsp)
{
  (void)dsp;
  return faust_test_state;
}

int getNumOutputsreload(void *dsp)
{
  (void)dsp;
  return FAUST_TEST_VERSION;
}

void computereload(void *dsp, int count, double **inputs, double **outputs)
{
  (void)dsp;
  (void)count;
  (void)inputs;
  (void)outputs;
}
