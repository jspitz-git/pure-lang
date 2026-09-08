cmake_minimum_required(VERSION 3.25)

# This producer has no dependency on the verifier's expected-import table.
# Capture real llvm-readobj records independently and alter one contract at a
# time; a tiny native transport returns the captured bytes for the real parser.
foreach(required SOURCE_DIR MODULE_DIR CLANG64_PREFIX PURE_PREFIX RUNNER)
  if(NOT DEFINED ${required})
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()
set(PURE_AUDIO_RUNNER "${RUNNER}")
set(PURE_AUDIO_RUNNER_HELPERS_ONLY ON)
include("${SOURCE_DIR}/cmake/RunPureTest.cmake")
pure_audio_create_leaf(work)
file(MAKE_DIRECTORY "${work}/stage/bin" "${work}/stage/lib/pure")
set(names audio.dll fftw.dll srcprocess.dll sfinfo.dll realtime.dll
  pure.exe libpure.dll libc++.dll libgmp-10.dll libiconv-2.dll libmpfr-6.dll
  libpcre-1.dll libpcreposix-0.dll libreadline8.dll libtermcap-0.dll
  libwinpthread-1.dll libzstd.dll zlib1.dll libportaudio.dll libfftw3-3.dll
  libsamplerate-0.dll libsndfile-1.dll libogg-0.dll libvorbisenc-2.dll
  libFLAC.dll libopus-0.dll libmpg123-0.dll libmp3lame-0.dll libvorbis-0.dll)
set(rows)
foreach(name IN LISTS names)
  if(name MATCHES "^(audio|fftw|srcprocess|sfinfo|realtime)\\.dll$")
    set(source "${MODULE_DIR}/${name}")
    set(dest "${work}/stage/lib/pure/${name}")
  elseif(EXISTS "${PURE_PREFIX}/bin/${name}")
    set(source "${PURE_PREFIX}/bin/${name}")
    set(dest "${work}/stage/bin/${name}")
  else()
    set(source "${CLANG64_PREFIX}/bin/${name}")
    set(dest "${work}/stage/bin/${name}")
  endif()
  file(COPY_FILE "${source}" "${dest}")
  execute_process(COMMAND "${CLANG64_PREFIX}/bin/llvm-readobj.exe"
    --file-headers --coff-imports "${dest}"
    RESULT_VARIABLE rc OUTPUT_VARIABLE records ERROR_VARIABLE err)
  if(NOT rc EQUAL 0 OR NOT err STREQUAL "")
    message(FATAL_ERROR "Cannot capture independent ${name}: ${err}")
  endif()
  string(REPLACE "\r\n" "\n" records "${records}")
  file(WRITE "${dest}.records" "${records}")
  if(name STREQUAL "audio.dll")
    set(audio_records "${records}")
  endif()
  if(NOT name MATCHES "^(audio|fftw|srcprocess|sfinfo|realtime)\\.dll$")
    file(SHA256 "${source}" hash)
    string(APPEND rows "${name}|${source}|${hash}\n")
  endif()
endforeach()
file(WRITE "${work}/runtime-sources.txt" "${rows}")
file(WRITE "${work}/reader.c" [=[
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) {
  char path[4096]; unsigned char buf[8192]; size_t n;
  if (argc != 4 || strcmp(argv[1], "--file-headers") ||
      strcmp(argv[2], "--coff-imports")) return 64;
  if (snprintf(path, sizeof(path), "%s.records", argv[3]) >= (int)sizeof(path)) return 65;
  FILE *f = fopen(path, "rb"); if (!f) return 66;
  while ((n = fread(buf, 1, sizeof(buf), f))) if (fwrite(buf, 1, n, stdout) != n) return 67;
  return fclose(f);
}
]=])
execute_process(COMMAND "${CLANG64_PREFIX}/bin/clang.exe" -std=c11 -Wall -Wextra -Werror
  "${work}/reader.c" -o "${work}/reader.exe" RESULT_VARIABLE rc)
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "Cannot compile independent readobj transport")
endif()
set(negative 0)
set(positive 0)
set(failures)
set(system_directory "C:/Windows/System32")
function(verify_case name accept)
  if(DEFINED CASE_FILTER AND NOT name MATCHES "${CASE_FILTER}")
    return()
  endif()
  execute_process(COMMAND "${CMAKE_COMMAND}"
    "-DLLVM_READOBJ=${work}/reader.exe" "-DRUNTIME_DIR=${CLANG64_PREFIX}/bin"
    "-DAUDIO_MODULE=${MODULE_DIR}/audio.dll" "-DFFTW_MODULE=${MODULE_DIR}/fftw.dll"
    "-DSRCPROCESS_MODULE=${MODULE_DIR}/srcprocess.dll" "-DSFINFO_MODULE=${MODULE_DIR}/sfinfo.dll"
    "-DREALTIME_MODULE=${MODULE_DIR}/realtime.dll"
    "-DAUDIO_MODULE_DIR=${MODULE_DIR}" "-DPURE_AUDIO_CLANG64_PREFIX=${CLANG64_PREFIX}"
    "-DPURE_AUDIO_PURE_PREFIX=${PURE_PREFIX}"
    "-DPURE_AUDIO_WINDOWS_SYSTEM_DIRECTORY=${system_directory}"
    "-DPURE_AUDIO_RUNTIME_MANIFEST=${work}/runtime-sources.txt"
    "-DSTAGE_PREFIX=${work}/stage"
    -P "${SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
    RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 45)
  file(WRITE "${work}/${name}.log" "${out}\n${err}")
  if(accept)
    if(NOT rc EQUAL 0 OR NOT out MATCHES "PE_CLOSURE_OK count=29")
      message(FATAL_ERROR "${name}: independent pristine failed (${rc}): ${out}\n${err}")
    endif()
    math(EXPR count "${positive}+1")
    set(positive "${count}" PARENT_SCOPE)
  else()
    if(rc EQUAL 0 OR NOT "${out}${err}" MATCHES "audio audit:")
      list(APPEND failures "${name}")
      set(failures "${failures}" PARENT_SCOPE)
    endif()
    math(EXPR count "${negative}+1")
    set(negative "${count}" PARENT_SCOPE)
  endif()
endfunction()

# Real legacy verifier reads configured module paths, so supply its original
# records too. Its weak Name search accepts this extra import.
if(RED_ONLY)
  # The old contract has no staged boundary: a missing stage DLL is rescued
  # from its host runtime argument. This is a behavioral RED against real PEs.
  file(REMOVE "${work}/stage/bin/libvorbis-0.dll")
  execute_process(COMMAND "${CMAKE_COMMAND}"
    "-DLLVM_READOBJ=${CLANG64_PREFIX}/bin/llvm-readobj.exe" "-DRUNTIME_DIR=${CLANG64_PREFIX}/bin"
    "-DAUDIO_MODULE=${MODULE_DIR}/audio.dll" "-DFFTW_MODULE=${MODULE_DIR}/fftw.dll"
    "-DSRCPROCESS_MODULE=${MODULE_DIR}/srcprocess.dll" "-DSFINFO_MODULE=${MODULE_DIR}/sfinfo.dll"
    "-DREALTIME_MODULE=${MODULE_DIR}/realtime.dll" "-DSTAGE_PREFIX=${work}/stage"
    -P "${SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake" RESULT_VARIABLE rc)
  if(rc EQUAL 0)
    message(FATAL_ERROR "RED: verifier accepted missing staged transitive libvorbis-0.dll")
  endif()
  return()
endif()

verify_case(pristine TRUE)
foreach(mutation unknown missing duplicate forbidden-msys forbidden-gcc forbidden-cxx
    delay malformed no-name multiple-name wrong-machine wrong-format wrong-magic
    extra-header stray-name unknown-record trailing-garbage truncated-header
    missing-header-field unknown-header-field invalid-header-value)
  set(records "${audio_records}")
  if(mutation STREQUAL "unknown")
    string(APPEND records "Import {\n  Name: unknown.dll\n  ImportLookupTableRVA: 0x1\n  ImportAddressTableRVA: 0x2\n}\n")
  elseif(mutation STREQUAL "missing")
    string(REGEX REPLACE "Import \\{\n  Name: libpure.dll[^}]*}\n" "" records "${records}")
  elseif(mutation STREQUAL "duplicate")
    string(APPEND records "Import {\n  Name: LIBPURE.DLL\n  ImportLookupTableRVA: 0x1\n  ImportAddressTableRVA: 0x2\n}\n")
  elseif(mutation MATCHES "^forbidden-")
    if(mutation STREQUAL "forbidden-msys")
      set(bad "MsYs-2.0.DlL")
    elseif(mutation STREQUAL "forbidden-gcc")
      set(bad "LiBgCc_s_seh-1.DLL")
    else()
      set(bad "LiBsTdC++-6.DlL")
    endif()
    string(REPLACE "Name: libpure.dll" "Name: ${bad}" records "${records}")
  elseif(mutation STREQUAL "delay")
    string(REPLACE "Import {" "DelayImport {" records "${records}")
  elseif(mutation STREQUAL "malformed")
    string(APPEND records "Import {\n  Name: broken.dll\n")
  elseif(mutation STREQUAL "no-name")
    string(REPLACE "  Name: libpure.dll\n" "" records "${records}")
  elseif(mutation STREQUAL "multiple-name")
    string(REPLACE "Name: libpure.dll" "Name: libpure.dll\n  Name: extra.dll" records "${records}")
  elseif(mutation STREQUAL "wrong-machine")
    string(REPLACE "IMAGE_FILE_MACHINE_AMD64 (0x8664)" "IMAGE_FILE_MACHINE_I386 (0x14C)" records "${records}")
  elseif(mutation STREQUAL "wrong-format")
    string(REPLACE "Format: COFF-x86-64" "Format: ELF64-x86-64" records "${records}")
  elseif(mutation STREQUAL "wrong-magic")
    string(REPLACE "Magic: 0x20B" "Magic: 0x10B" records "${records}")
  elseif(mutation STREQUAL "extra-header")
    string(APPEND records "ImageFileHeader {\n  Machine: IMAGE_FILE_MACHINE_AMD64 (0x8664)\n}\n")
  elseif(mutation STREQUAL "stray-name")
    string(APPEND records "  Name: orphan.dll\n")
  elseif(mutation STREQUAL "unknown-record")
    string(APPEND records "MysteryImport {\n  Name: hidden.dll\n}\n")
  elseif(mutation STREQUAL "trailing-garbage")
    string(APPEND records "not a readobj record\n")
  elseif(mutation STREQUAL "truncated-header")
    string(REPLACE "DOSHeader {" "DOSHeader" records "${records}")
  elseif(mutation STREQUAL "missing-header-field")
    string(REGEX REPLACE "  SectionCount: [0-9]+\n" "" records "${records}")
  elseif(mutation STREQUAL "unknown-header-field")
    string(REPLACE "ImageFileHeader {" "ImageFileHeader {\n  HiddenImport: malicious.dll" records "${records}")
  else()
    string(REGEX REPLACE "  SectionCount: [0-9]+" "  SectionCount: invalid" records "${records}")
  endif()
  if(records STREQUAL audio_records)
    message(FATAL_ERROR "Mutation ${mutation} did not alter the fixture")
  endif()
  file(WRITE "${work}/stage/lib/pure/audio.dll.records" "${records}")
  verify_case("parser-${mutation}" FALSE)
endforeach()
file(WRITE "${work}/stage/lib/pure/audio.dll.records" "${audio_records}")
file(RENAME "${work}/stage/bin/libvorbis-0.dll" "${work}/stage/bin/libvorbis-0.keep")
verify_case(missing-transitive-host-fallback FALSE)
file(RENAME "${work}/stage/bin/libvorbis-0.keep" "${work}/stage/bin/libvorbis-0.dll")
file(COPY_FILE "${work}/stage/bin/libogg-0.dll" "${work}/stage/bin/extra.dll")
verify_case(extra-staged-pe FALSE)
file(REMOVE "${work}/stage/bin/extra.dll")
file(COPY_FILE "${work}/stage/bin/libogg-0.dll" "${work}/stage/bin/extra.payload")
verify_case(extra-staged-renamed-pe FALSE)
file(REMOVE "${work}/stage/bin/extra.payload")
file(MAKE_DIRECTORY "${work}/stage/extra")
file(COPY_FILE "${work}/stage/bin/libogg-0.dll" "${work}/stage/extra/libogg-0.dll")
verify_case(ambiguous-origin FALSE)
file(REMOVE "${work}/stage/extra/libogg-0.dll")
file(APPEND "${work}/runtime-sources.txt" "libpure.dll|${PURE_PREFIX}/bin/libpure.dll|bad\n")
verify_case(duplicate-declaration FALSE)
file(WRITE "${work}/runtime-sources.txt" "${rows}")
foreach(mutation malformed-row blank-row missing-declaration changed-source-hash wrong-source-origin)
  if(mutation STREQUAL "malformed-row")
    set(changed "${rows}broken|row|too|many\n")
  elseif(mutation STREQUAL "blank-row")
    set(changed "${rows}\n")
  elseif(mutation STREQUAL "missing-declaration")
    string(REGEX REPLACE "libpure.dll[^\n]+\n" "" changed "${rows}")
  elseif(mutation STREQUAL "changed-source-hash")
    string(REGEX REPLACE "(libpure.dll[^\n]+\\|)[0-9a-f]+" "\\1deadbeef" changed "${rows}")
  else()
    file(MAKE_DIRECTORY "${work}/host")
    file(COPY_FILE "${CLANG64_PREFIX}/bin/libogg-0.dll" "${work}/host/libogg-0.dll")
    string(REPLACE "${CLANG64_PREFIX}/bin/libogg-0.dll" "${work}/host/libogg-0.dll" changed "${rows}")
  endif()
  if(changed STREQUAL rows)
    message(FATAL_ERROR "Runtime manifest mutation ${mutation} did not change input")
  endif()
  file(WRITE "${work}/runtime-sources.txt" "${changed}")
  verify_case("manifest-${mutation}" FALSE)
endforeach()
file(WRITE "${work}/runtime-sources.txt" "${rows}")
file(READ "${work}/stage/bin/libpure.dll.records" pure_records)
file(APPEND "${work}/stage/bin/libpure.dll.records"
  "Import {\n  Name: unknown-transitive.dll\n  ImportLookupTableRVA: 0x1\n  ImportAddressTableRVA: 0x2\n}\n")
verify_case(libpure-extra-transitive-import FALSE)
file(WRITE "${work}/stage/bin/libpure.dll.records" "${pure_records}")
file(MAKE_DIRECTORY "${work}/foreign-system")
set(system_directory "${work}/foreign-system")
verify_case(non-authoritative-system-directory FALSE)
set(system_directory "C:/Windows/System32")

file(RENAME "${work}/stage/bin/libogg-0.dll" "${work}/stage/bin/libogg-0.saved")
execute_process(COMMAND "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
  -NoProfile -NonInteractive -Command
  "Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class AudioLink { [DllImport(\"kernel32\", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool CreateSymbolicLink(string l, string t, int f); }'; if(-not [AudioLink]::CreateSymbolicLink('${work}/stage/bin/libogg-0.dll','${work}/stage/bin/libogg-0.saved',2)) { throw 'cannot create unprivileged symbolic link' }"
  RESULT_VARIABLE rc)
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "Cannot establish runtime symbolic-link mutation")
endif()
verify_case(staged-runtime-symlink FALSE)
file(REMOVE "${work}/stage/bin/libogg-0.dll")
file(RENAME "${work}/stage/bin/libogg-0.saved" "${work}/stage/bin/libogg-0.dll")
execute_process(COMMAND "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
  -NoProfile -NonInteractive -Command
  "New-Item -ItemType Junction -Path '${work}/stage/junction' -Target '${work}/host' | Out-Null"
  RESULT_VARIABLE rc)
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "Cannot establish stage junction mutation")
endif()
verify_case(staged-junction-ancestor FALSE)
execute_process(COMMAND "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
  -NoProfile -NonInteractive -Command "[IO.Directory]::Delete('${work}/stage/junction')"
  RESULT_VARIABLE rc)
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "Cannot unlink exact owned stage junction")
endif()
file(APPEND "${work}/stage/bin/libogg-0.dll" "altered")
verify_case(altered-staged-hash FALSE)
file(COPY_FILE "${CLANG64_PREFIX}/bin/libogg-0.dll" "${work}/stage/bin/libogg-0.dll")
verify_case(restored-pristine TRUE)
if(failures)
  message(FATAL_ERROR "Runtime verifier accepted mutations (${work}): ${failures}")
endif()
pure_audio_cleanup_leaf("${work}")
message(STATUS "RUNTIME_VERIFIER_CONTRACT_OK negative=${negative} positive=${positive} pe_count=29")
