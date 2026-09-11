/* A child process for exercising the real runner's OS boundary. No MIDI. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv)
{
  const char *script=NULL, *token=getenv("PURE_MIDI_TEST_TOKEN");
  char mode[128]={0}; FILE *file; int i;
  if(argc==4 && !strcmp(argv[1],"--symlink"))
    return CreateSymbolicLinkA(argv[3],argv[2],2) ? 0:1;
  if(argc==3 && !strcmp(argv[1],"--short-path")) {
    char short_path[32768];
    if(!GetShortPathNameA(argv[2],short_path,sizeof(short_path))) return 1;
    puts(short_path); return 0;
  }
  if (argc==2 && !strcmp(argv[1],"--descendant")) { Sleep(30000); return 0; }
  if(argc==2 && !strcmp(argv[1],"--native-environment")) {
    const char *path=getenv("PATH");
    if(getenv("PURELIB") || getenv("PURE_INCLUDE") || getenv("PURE_LIBRARY") ||
       getenv("PURE_MIDI_OUT") || getenv("PURE_RUNNER_POISON") || !path || strstr(path,"poison")) {
      fputs("FAIL native test environment: inherited Pure/module/selector poison\n",stderr); return 93;
    }
    puts("PASS native test environment: no inherited Pure/module/selector poison"); return 0;
  }
  if(argc<4 || !*argv[0] || strcmp(argv[1],"--norc")) return 96;
  for (i=1;i+1<argc;++i) if (!strcmp(argv[i],"-x")) script=argv[i+1];
  if (!script || !(file=fopen(script,"rb"))) return 90;
  if (!fgets(mode,sizeof(mode),file)) return 91;
  fclose(file); mode[strcspn(mode,"\r\n")]=0;
  if (!token) token="no-token";
  if (!strcmp(mode,"parser")) fprintf(stderr,"fixture.pure:1: syntax error, unexpected ';'\n");
  else if (!strcmp(mode,"unhandled")) puts("unhandled_expression 42");
  else if (!strcmp(mode,"missing")) return 0;
  else if (!strcmp(mode,"wrong")) { puts("wrong-token"); return 0; }
  else if (!strcmp(mode,"duplicate")) puts(token);
  else if (!strcmp(mode,"embedded-token")) printf("INFO: premature %s\n",token);
  else if (!strcmp(mode,"nonzero")) { puts(token); return 37; }
  else if (!strcmp(mode,"timeout")) { puts(token); fflush(stdout); Sleep(30000); }
  else if (!strcmp(mode,"pipes") || !strcmp(mode,"stdout")) {
    for(i=0;i<4096;++i) {
      puts("INFO: a full pipe must never block concurrent draining of both streams 012345678901234567890123456789");
      if (!strcmp(mode,"pipes")) fputs("diagnostic 012345678901234567890123456789012345678901234567890123456789\n",stderr);
    }
  } else if (!strcmp(mode,"child")) {
    STARTUPINFOA si={0}; PROCESS_INFORMATION pi={0}; char exe[MAX_PATH],cmd[2*MAX_PATH];
    si.cb=sizeof(si); si.dwFlags=STARTF_USESTDHANDLES;
    si.hStdInput=GetStdHandle(STD_INPUT_HANDLE); si.hStdOutput=GetStdHandle(STD_OUTPUT_HANDLE);
    si.hStdError=GetStdHandle(STD_ERROR_HANDLE);
    GetModuleFileNameA(NULL,exe,MAX_PATH); snprintf(cmd,sizeof(cmd),"\"%s\" --descendant",exe);
    if (!CreateProcessA(exe,cmd,NULL,NULL,TRUE,0,NULL,NULL,&si,&pi)) return 92;
    printf("INFO: descendant=%lu\n",(unsigned long)pi.dwProcessId);
    CloseHandle(pi.hThread); CloseHandle(pi.hProcess);
  } else if (!strcmp(mode,"environment")) {
    const char *path=getenv("PATH"), *tmp=getenv("TEMP"); char cwd[MAX_PATH];
    GetCurrentDirectoryA(MAX_PATH,cwd);
    if (getenv("PURELIB") || getenv("PURE_INCLUDE") || getenv("PURE_LIBRARY") ||
        getenv("PURE_MIDI_OUT") || getenv("PURE_RUNNER_POISON") || !path || strstr(path,"poison") ||
        !tmp || strcmp(tmp,cwd)) return 93;
  } else if (!strcmp(mode,"selector")) {
    const char *selector=getenv("PURE_MIDI_TEST_OUTPUT");
    if (!selector || strcmp(selector,"interface:device with spaces")) return 94;
  } else if (strcmp(mode,"pristine") && strcmp(mode,"early")) return 95;
  puts(token);
  if (!strcmp(mode,"early")) puts("INFO: assertion ran after completion");
  return 0;
}
