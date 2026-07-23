#include <stdlib.h>

const char pure_faust_sample_format[] = "double";

extern int faust_missing_test_dependency(void);

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
  return faust_missing_test_dependency();
}

int getNumOutputsreload(void *dsp)
{
  (void)dsp;
  return 44;
}

void computereload(void *dsp, int count, double **inputs, double **outputs)
{
  (void)dsp;
  (void)count;
  (void)inputs;
  (void)outputs;
}
