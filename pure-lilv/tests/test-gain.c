#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <lv2/lv2plug.in/ns/ext/dynmanifest/dynmanifest.h>
#include <lv2/lv2plug.in/ns/lv2core/lv2.h>

#ifndef TEST_GAIN_URI
#define TEST_GAIN_URI "urn:pure-lang:test:static-gain"
#endif

typedef struct {
  const float *input;
  float *output;
  const float *gain;
} TestGain;

static LV2_Handle
instantiate(const LV2_Descriptor *descriptor, double rate,
            const char *bundle_path, const LV2_Feature *const *features)
{
  (void)descriptor;
  (void)rate;
  (void)bundle_path;
  (void)features;
  return calloc(1, sizeof(TestGain));
}

static void
connect_port(LV2_Handle instance, uint32_t port, void *data)
{
  TestGain *self = (TestGain *)instance;
  if (port == 0)
    self->input = (const float *)data;
  else if (port == 1)
    self->output = (float *)data;
  else if (port == 2)
    self->gain = (const float *)data;
}

static void
run(LV2_Handle instance, uint32_t count)
{
  TestGain *self = (TestGain *)instance;
  for (uint32_t i = 0; i < count; ++i)
    self->output[i] = self->input[i] * *self->gain;
}

static void
cleanup(LV2_Handle instance)
{
  free(instance);
}

static const LV2_Descriptor descriptor = {
  TEST_GAIN_URI,
  instantiate,
  connect_port,
  NULL,
  run,
  NULL,
  cleanup,
  NULL
};

LV2_SYMBOL_EXPORT
const LV2_Descriptor *
lv2_descriptor(uint32_t index)
{
  return index == 0 ? &descriptor : NULL;
}

#ifdef TEST_DYNAMIC_MANIFEST

LV2_SYMBOL_EXPORT
int
lv2_dyn_manifest_open(LV2_Dyn_Manifest_Handle *handle,
                      const LV2_Feature *const *features)
{
  (void)features;
  *handle = (LV2_Dyn_Manifest_Handle)&descriptor;
  return 0;
}

LV2_SYMBOL_EXPORT
int
lv2_dyn_manifest_get_subjects(LV2_Dyn_Manifest_Handle handle, FILE *file)
{
  (void)handle;
  return fprintf(file, "<%s> a <http://lv2plug.in/ns/lv2core#Plugin> .\n",
                 TEST_GAIN_URI) < 0;
}

LV2_SYMBOL_EXPORT
int
lv2_dyn_manifest_get_data(LV2_Dyn_Manifest_Handle handle,
                          FILE *file, const char *uri)
{
  (void)handle;
  if (!uri || strcmp(uri, TEST_GAIN_URI))
    return 1;
  return fprintf(
    file,
    "<%s> a <http://lv2plug.in/ns/lv2core#Plugin> ;\n"
    "  <http://usefulinc.com/ns/doap#name> \"Dynamic Test Gain\" ;\n"
    "  <http://lv2plug.in/ns/lv2core#binary> <dynamic-gain.dll> ;\n"
    "  <http://lv2plug.in/ns/lv2core#port>\n"
    "  [ a <http://lv2plug.in/ns/lv2core#InputPort>,"
    "      <http://lv2plug.in/ns/lv2core#AudioPort> ;\n"
    "    <http://lv2plug.in/ns/lv2core#index> 0 ;\n"
    "    <http://lv2plug.in/ns/lv2core#symbol> \"in\" ;\n"
    "    <http://lv2plug.in/ns/lv2core#name> \"Input\" ],\n"
    "  [ a <http://lv2plug.in/ns/lv2core#OutputPort>,"
    "      <http://lv2plug.in/ns/lv2core#AudioPort> ;\n"
    "    <http://lv2plug.in/ns/lv2core#index> 1 ;\n"
    "    <http://lv2plug.in/ns/lv2core#symbol> \"out\" ;\n"
    "    <http://lv2plug.in/ns/lv2core#name> \"Output\" ],\n"
    "  [ a <http://lv2plug.in/ns/lv2core#InputPort>,"
    "      <http://lv2plug.in/ns/lv2core#ControlPort> ;\n"
    "    <http://lv2plug.in/ns/lv2core#index> 2 ;\n"
    "    <http://lv2plug.in/ns/lv2core#symbol> \"gain\" ;\n"
    "    <http://lv2plug.in/ns/lv2core#name> \"Gain\" ;\n"
    "    <http://lv2plug.in/ns/lv2core#default> 1.0 ;\n"
    "    <http://lv2plug.in/ns/lv2core#minimum> 0.0 ;\n"
    "    <http://lv2plug.in/ns/lv2core#maximum> 4.0 ] .\n",
    TEST_GAIN_URI) < 0;
}

LV2_SYMBOL_EXPORT
void
lv2_dyn_manifest_close(LV2_Dyn_Manifest_Handle handle)
{
  (void)handle;
}

#endif
