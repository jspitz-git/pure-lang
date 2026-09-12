cmake_minimum_required(VERSION 3.25)
# Mutations exercise the production verifier at its external reader boundary.
# The fake emits complete captured records selected by the input DLL basename.
foreach(required SOURCE_DIR BINARY_DIR C_COMPILER LLVM_READOBJ LLVM_STRINGS
    PURE_GL_MODULE FREEGLUT_DLL PURE_GL_PURE_PREFIX PURE_GL_CLANG64_PREFIX
    PURE_GL_WINDOWS_SYSTEM_DIRECTORY)
  if(NOT DEFINED ${required})
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()
set(root "${BINARY_DIR}/pe contract")
file(MAKE_DIRECTORY "${root}")
file(WRITE "${root}/reader.c" [=[
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) {
  char path[32768]; char buf[4096]; size_t n;
  if(argc < 2) return 2;
  const char *name=argv[argc-1];
  for(const char *p=name; *p; ++p) if(*p=='/' || *p=='\\') name=p+1;
  if(snprintf(path,sizeof(path),"%s.data/%s.txt",argv[0],name)<0) return 3;
  FILE *f=fopen(path,"rb"); if(!f) return 4;
  while((n=fread(buf,1,sizeof(buf),f))) if(fwrite(buf,1,n,stdout)!=n) return 5;
  return fclose(f);
}
]=])
set(reader "${root}/reader.exe")
execute_process(COMMAND "${C_COMPILER}" -std=c11 -Wall -Wextra -Werror
  "${root}/reader.c" -o "${reader}" COMMAND_ERROR_IS_FATAL ANY)
file(MAKE_DIRECTORY "${reader}.data")
set(binaries "${PURE_GL_MODULE}" "${FREEGLUT_DLL}")
foreach(name libc++ libgmp-10 libiconv-2 libmpfr-6 libpcre-1 libpcreposix-0
    libpure libwinpthread-1 libzstd zlib1)
  list(APPEND binaries "${PURE_GL_PURE_PREFIX}/bin/${name}.dll")
endforeach()
foreach(binary IN LISTS binaries)
  get_filename_component(name "${binary}" NAME)
  execute_process(COMMAND "${LLVM_READOBJ}" --file-headers --coff-imports "${binary}"
    OUTPUT_VARIABLE records COMMAND_ERROR_IS_FATAL ANY)
  file(WRITE "${reader}.data/${name}.txt" "${records}")
  if(name STREQUAL "pure-gl.dll")
    set(module_records "${records}")
  elseif(name STREQUAL "libpure.dll")
    set(pure_records "${records}")
  endif()
endforeach()
file(SHA256 "${reader}" reader_hash)
file(SHA256 "${LLVM_STRINGS}" strings_hash)
set(args "-DLLVM_READOBJ=${reader}" "-DLLVM_READOBJ_SHA256=${reader_hash}"
  "-DLLVM_STRINGS=${LLVM_STRINGS}" "-DLLVM_STRINGS_SHA256=${strings_hash}"
  "-DPURE_GL_MODULE=${PURE_GL_MODULE}" "-DFREEGLUT_DLL=${FREEGLUT_DLL}"
  "-DPURE_GL_PURE_PREFIX=${PURE_GL_PURE_PREFIX}"
  "-DPURE_GL_CLANG64_PREFIX=${PURE_GL_CLANG64_PREFIX}"
  "-DPURE_GL_WINDOWS_SYSTEM_DIRECTORY=${PURE_GL_WINDOWS_SYSTEM_DIRECTORY}"
  "-DPURE_GL_RUNTIME_DIRECTORY=${BINARY_DIR}/pure-gl-runtime"
  -DPURE_GL_AUDIT_MODE=BUILD)
function(check name expected)
  execute_process(COMMAND "${CMAKE_COMMAND}" ${args} ${ARGN}
    -P "${SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
    RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 60)
  set(log "${out}\n${err}")
  file(WRITE "${root}/${name}.log" "${log}")
  # CMake wraps diagnostics according to path length; labels may span lines.
  string(REGEX REPLACE "[ \t\r\n]+" " " diagnostics "${log}")
  if(expected STREQUAL "PASS")
    if(NOT rc EQUAL 0)
      message(FATAL_ERROR "${name} pristine failed: ${log}")
    endif()
  else()
    if(rc EQUAL 0)
      message(FATAL_ERROR "${name}: verifier accepted mutation")
    endif()
    foreach(label IN LISTS expected)
      if(NOT diagnostics MATCHES "${label}")
        message(FATAL_ERROR "${name}: missing diagnostic ${label}: ${log}")
      endif()
    endforeach()
  endif()
  message(STATUS "PE contract ${name}: ${expected}")
endfunction()
set(extra "Import {\n  Name: libunexpected.dll\n  ImportLookupTableRVA: 0x100\n  ImportAddressTableRVA: 0x200\n  Symbol: test (0)\n}\n")
# The only non-ASCII output LLVM may emit is the exact physical input in File:.
# Keep that ownership field byte-exact while rejecting invalid UTF-8 and any
# Unicode in the remaining structural/import grammar.
set(unicode_module "${root}/café/pure-gl.dll")
file(MAKE_DIRECTORY "${root}/café")
file(COPY_FILE "${PURE_GL_MODULE}" "${unicode_module}")
file(SHA256 "${LLVM_READOBJ}" actual_reader_hash)
check(unicode-physical-file PASS "-DPURE_GL_MODULE=${unicode_module}"
  "-DLLVM_READOBJ=${LLVM_READOBJ}" "-DLLVM_READOBJ_SHA256=${actual_reader_hash}")
string(ASCII 255 undecodable)
string(REPLACE "File: ${PURE_GL_MODULE}" "File: ${root}/caf${undecodable}/pure-gl.dll"
  changed "${module_records}")
file(WRITE "${reader}.data/pure-gl.dll.txt" "${changed}")
check(invalid-utf8-file "pure-gl.dll;decoding failed" "-DPURE_GL_MODULE=${unicode_module}")
file(WRITE "${reader}.data/pure-gl.dll.txt" "${module_records}UnknownRecord: café\n")
check(unicode-nonfile-record "pure-gl.dll;decoding failed")
string(REPLACE "[" "@GL_PE_LBRACKET@" changed "${module_records}")
file(WRITE "${reader}.data/pure-gl.dll.txt" "${changed}")
check(reserved-encoding "pure-gl.dll;malformed")
file(WRITE "${reader}.data/pure-gl.dll.txt" "${module_records}${extra}")
check(injected "pure-gl.dll;expected;actual;missing;unexpected;libunexpected.dll")
string(REGEX REPLACE "Import \\{\n  Name: libpure.dll\n[^}]+}\n" "" changed "${module_records}")
file(WRITE "${reader}.data/pure-gl.dll.txt" "${changed}")
check(omitted "pure-gl.dll;expected;actual;missing;unexpected;libpure.dll")
file(WRITE "${reader}.data/pure-gl.dll.txt" "${module_records}UnknownRecord: 1\n")
check(unknown "pure-gl.dll;top-level")
string(REPLACE "  Name: libpure.dll" "  Name libpure.dll" changed "${module_records}")
file(WRITE "${reader}.data/pure-gl.dll.txt" "${changed}")
check(malformed "pure-gl.dll;malformed import")
string(REPLACE "  Name: libpure.dll" "  Name: libpure.dll\n  Name: libpure.dll" changed "${module_records}")
file(WRITE "${reader}.data/pure-gl.dll.txt" "${changed}")
check(duplicate "pure-gl.dll;multiple Name")
file(WRITE "${reader}.data/pure-gl.dll.txt" "${module_records}")
check(readobj-hash "SHA256 mismatch"
  -DLLVM_READOBJ_SHA256=0000000000000000000000000000000000000000000000000000000000000000)
check(strings-hash "SHA256 mismatch"
  -DLLVM_STRINGS_SHA256=0000000000000000000000000000000000000000000000000000000000000000)
string(ASCII 255 undecodable)
file(APPEND "${reader}.data/pure-gl.dll.txt" "${undecodable}")
check(reader-decoding "pure-gl.dll;decoding failed")
file(REMOVE "${reader}.data/pure-gl.dll.txt")
check(reader-error "pure-gl.dll;reader failed")
file(WRITE "${reader}.data/pure-gl.dll.txt" "${module_records}")
foreach(forbidden msys-2.0.dll libgcc_s_seh-1.dll libstdc++-6.dll)
  string(REPLACE "libpure.dll" "${forbidden}" changed "${module_records}")
  file(WRITE "${reader}.data/pure-gl.dll.txt" "${changed}")
  check("forbidden-${forbidden}" "forbidden runtime")
endforeach()
file(WRITE "${reader}.data/pure-gl.dll.txt" "${module_records}")
string(REPLACE "Format: COFF-x86-64" "Format: COFF-i386" changed "${pure_records}")
file(WRITE "${reader}.data/libpure.dll.txt" "${changed}")
check(architecture "libpure.dll;AMD64")
file(WRITE "${reader}.data/libpure.dll.txt" "${pure_records}${extra}")
check(recursive-injected "libpure.dll;expected;actual;missing;unexpected")
file(WRITE "${reader}.data/libpure.dll.txt" "${pure_records}")
file(MAKE_DIRECTORY "${root}/empty-pure/bin")
check(missing-runtime "missing dependency;libc[+][+][.]dll"
  "-DPURE_GL_PURE_PREFIX=${root}/empty-pure")
check(wrong-origin "wrong origin;libfreeglut.dll"
  "-DFREEGLUT_DLL=${PURE_GL_CLANG64_PREFIX}/bin/libfreeglut.dll")
check(path-escape "malformed absolute path|noncanonical"
  "-DPURE_GL_PURE_PREFIX=${PURE_GL_PURE_PREFIX}/bin/..")
set(powershell "${PURE_GL_WINDOWS_SYSTEM_DIRECTORY}/WindowsPowerShell/v1.0/powershell.exe")
set(junction "${root}/runtime-junction")
if(EXISTS "${junction}")
  message(FATAL_ERROR "contract requires absent ${junction}")
endif()
execute_process(COMMAND "${powershell}" -NoProfile -NonInteractive -Command
  "$ErrorActionPreference='Stop'; $null=New-Item -ItemType Junction -Path '${junction}' -Target '${BINARY_DIR}/pure-gl-runtime'"
  COMMAND_ERROR_IS_FATAL ANY)
check(reparse-runtime "reparse|wrong origin"
  "-DPURE_GL_RUNTIME_DIRECTORY=${junction}"
  "-DFREEGLUT_DLL=${junction}/libfreeglut.dll")
# Directory.Delete removes the junction itself without traversing its target.
execute_process(COMMAND "${powershell}" -NoProfile -NonInteractive -Command
  "$ErrorActionPreference='Stop'; [IO.Directory]::Delete('${junction}')"
  COMMAND_ERROR_IS_FATAL ANY)
# A module-local FreeGLUT beside the selected staged copy is ambiguous.
get_filename_component(module_dir "${PURE_GL_MODULE}" DIRECTORY)
if(EXISTS "${module_dir}/libfreeglut.dll")
  message(FATAL_ERROR "contract requires absent ${module_dir}/libfreeglut.dll")
endif()
file(COPY_FILE "${FREEGLUT_DLL}" "${module_dir}/libfreeglut.dll")
check(ambiguous "libfreeglut.dll;ambiguous")
file(REMOVE "${module_dir}/libfreeglut.dll")
# Case and record order must not change the exact normalized import set.
string(REGEX MATCHALL "Import \\{\n[^}]+}\n" blocks "${module_records}")
string(REGEX REPLACE "Import \\{\n[^}]+}\n" "" changed "${module_records}")
list(REVERSE blocks)
foreach(block IN LISTS blocks)
  string(REGEX MATCH "Name: ([^\n]+)" unused "${block}")
  string(TOUPPER "${CMAKE_MATCH_1}" upper)
  string(REPLACE "Name: ${CMAKE_MATCH_1}" "Name: ${upper}" block "${block}")
  string(APPEND changed "${block}")
endforeach()
file(WRITE "${reader}.data/pure-gl.dll.txt" "${changed}")
check(normalized PASS)
file(WRITE "${reader}.data/pure-gl.dll.txt" "${module_records}")
check(pristine PASS)
# A separate filename-selected fake preserves normal strings output and lets
# each loader mutation exercise the actual verifier without changing DLL bytes.
set(strings_reader "${root}/strings.exe")
file(COPY_FILE "${reader}" "${strings_reader}")
file(MAKE_DIRECTORY "${strings_reader}.data")
file(SHA256 "${strings_reader}" fake_strings_hash)
set(strings_args "-DLLVM_STRINGS=${strings_reader}"
  "-DLLVM_STRINGS_SHA256=${fake_strings_hash}")
file(WRITE "${strings_reader}.data/pure-gl.dll.txt"
  "libfreeglut.dll\nlibfreeglut.dll;libfreeglut.dll\n")
check(strings-semicolon-multiple "pure-gl.dll;ambiguous loader" ${strings_args})
file(WRITE "${strings_reader}.data/pure-gl.dll.txt"
  "libfreeglut.dll\n;libfreeglut.dll;\n")
check(strings-semicolon-decorated "pure-gl.dll;ambiguous loader" ${strings_args})
file(WRITE "${strings_reader}.data/pure-gl.dll.txt"
  "unrelated;[string]\nlibfreeglut.dll\nlibfreeglut.dll\n")
check(strings-unrelated-delimiters PASS ${strings_args})

# Own a complete alternative Pure DLL directory. The external prefix is never
# modified; the fake reader's File records point at these copied runtime DLLs.
# Shadow cases differ only by the extra competing origin in this Pure/bin.
set(shadow_pure "${root}/shadow-pure")
set(shadow_reader "${root}/shadow-reader.exe")
file(MAKE_DIRECTORY "${shadow_pure}/bin" "${shadow_reader}.data")
# Reset only this contract's two injected files after an interrupted/RED run.
file(REMOVE "${shadow_pure}/bin/libfreeglut.dll" "${shadow_pure}/bin/opengl32.dll")
file(COPY_FILE "${reader}" "${shadow_reader}")
foreach(binary IN LISTS binaries)
  get_filename_component(name "${binary}" NAME)
  file(READ "${reader}.data/${name}.txt" records)
  if(NOT name STREQUAL "pure-gl.dll" AND NOT name STREQUAL "libfreeglut.dll")
    file(COPY_FILE "${binary}" "${shadow_pure}/bin/${name}")
    string(REPLACE "${PURE_GL_PURE_PREFIX}/bin/" "${shadow_pure}/bin/" records "${records}")
  endif()
  file(WRITE "${shadow_reader}.data/${name}.txt" "${records}")
endforeach()
set(shadow_args "-DPURE_GL_PURE_PREFIX=${shadow_pure}"
  "-DLLVM_READOBJ=${shadow_reader}")
check(pure-bin-pristine PASS ${shadow_args})
file(COPY_FILE "${FREEGLUT_DLL}" "${shadow_pure}/bin/libfreeglut.dll")
check(pure-bin-freeglut-shadow "libfreeglut.dll;ambiguous;shadow-pure" ${shadow_args})
file(REMOVE "${shadow_pure}/bin/libfreeglut.dll")
file(COPY_FILE "${PURE_GL_WINDOWS_SYSTEM_DIRECTORY}/opengl32.dll"
  "${shadow_pure}/bin/opengl32.dll")
check(pure-bin-system-shadow "opengl32.dll;ambiguous;shadow-pure" ${shadow_args})
file(REMOVE "${shadow_pure}/bin/opengl32.dll")
check(pure-bin-restored PASS ${shadow_args})
file(WRITE "${strings_reader}.data/pure-gl.dll.txt" "libfreeglut.dll\nLIBFREEGLUT.DLL\n")
check(strings-ambiguous "pure-gl.dll;ambiguous loader" ${strings_args})
file(WRITE "${strings_reader}.data/pure-gl.dll.txt" "libfreeglut.dll\nfreeglut.dll\n")
check(strings-obsolete "pure-gl.dll;obsolete" ${strings_args})
file(WRITE "${strings_reader}.data/pure-gl.dll.txt" "prefix-libfreeglut.dll\n")
check(strings-not-exact "pure-gl.dll;line-exact" ${strings_args})
file(WRITE "${strings_reader}.data/pure-gl.dll.txt" "libfreeglut.dll\n${undecodable}")
check(strings-decoding "pure-gl.dll;decoding failed" ${strings_args})
file(REMOVE "${strings_reader}.data/pure-gl.dll.txt")
check(strings-error "pure-gl.dll;strings tool" ${strings_args})
check(final-pristine PASS)
message(STATUS "PURE_GL_RUNTIME_VERIFIER_CONTRACT_OK mutations=31 pristine=7")
