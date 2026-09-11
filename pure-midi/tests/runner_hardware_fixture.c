/* Reuse the deterministic backend surface, replacing only output behavior.
 * This module never links PortMidi. The real Pure script and stream wrapper
 * exercise cleanup, while literal counters make missing Note Off/close visible.
 */
#define Pm_CountDevices boundary_count_devices
#define Pm_GetDeviceInfo boundary_device_info
#define Pm_OpenOutput boundary_open_output
#define Pm_WriteShort boundary_write_short
#define Pm_Close boundary_close
#define Pm_Terminate boundary_terminate
#define Pt_Start boundary_timer_start
#define Pt_Stop boundary_timer_stop
#define Pt_Started boundary_timer_started
#define Pt_Sleep boundary_timer_sleep
#include "midi_boundary_harness.c"
#undef Pm_CountDevices
#undef Pm_GetDeviceInfo
#undef Pm_OpenOutput
#undef Pm_WriteShort
#undef Pm_Close
#undef Pm_Terminate
#undef Pt_Start
#undef Pt_Stop
#undef Pt_Started
#undef Pt_Sleep

static int ons,offs,closes,live,timer;
static int mode(const char *wanted) {
  const char *path=getenv("PURE_MIDI_TEST_FIXTURE"); char value[64]={0};
  FILE *f=path ? fopen(path,"rb"):NULL;
  if(f) { if(!fgets(value,sizeof(value),f)) value[0]=0; fclose(f); }
  value[strcspn(value,"\r\n")]=0; return !strcmp(value,wanted);
}
int Pm_CountDevices(void) { return 3; }
const void *Pm_GetDeviceInfo(int id) {
  static const struct { int version; const char *interf,*name; int input,output,opened,is_virtual; }
    ordinary={1,"fake","device with spaces",0,1,0,0}, duplicate={1,"fake","duplicate",0,1,0,0};
  return id==0 ? &ordinary:(id==1 || id==2) ? &duplicate:NULL;
}
int Pm_OpenOutput(void **stream,int id,void *driver,int size,void *proc,void *data,int latency) {
  (void)id; (void)driver; (void)size; (void)proc; (void)data; (void)latency;
  if(mode("open-fail")) return -9995;
  *stream=&output_stream; live=1; return 0;
}
int Pm_WriteShort(void *stream,int when,int message) {
  (void)when;
  if(stream!=&output_stream || !live) return -9995;
  if((message&255)==0x90) { ++ons; return mode("on-fail") ? -9995:0; }
  if((message&255)==0x80) { ++offs; return mode("off-fail") ? -9995:0; }
  return -9995;
}
int Pm_Close(void *stream) {
  (void)stream; ++closes; if(!mode("close-fail")) live=0;
  printf("INFO: fake close on=%d off=%d close=%d live=%d\n",ons,offs,closes,live);
  return mode("close-fail") ? -9995:0;
}
int Pm_Terminate(void) {
  printf("INFO: fake stopped on=%d off=%d close=%d live=%d\n",ons,offs,closes,live);
  return 0;
}
int Pt_Start(int resolution,void *callback,void *user) { (void)resolution; (void)callback; (void)user; timer=1; return 0; }
int Pt_Stop(void) { timer=0; return 0; }
int Pt_Started(void) { return timer; }
void Pt_Sleep(int duration) {
  (void)duration;
  if(mode("sleep-fail")) pure_throw(pure_string_dup("fake sleep failure"));
}
