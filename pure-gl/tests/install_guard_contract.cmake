cmake_minimum_required(VERSION 3.25)
foreach(required SOURCE_DIR BINARY_DIR PURE_PREFIX CLANG64_PREFIX)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()
include("${SOURCE_DIR}/cmake/PeHelpers.cmake")
set(GL_PE_POWERSHELL "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe")
set(negative 0)
set(positive 0)

function(gl_contract_open leaf)
  if(NOT leaf MATCHES "^(install-contract|install-guard-contract)$")
    message(FATAL_ERROR "Unknown fixed audit leaf")
  endif()
  gl_pe_no_reparse("${BINARY_DIR}" "${SOURCE_DIR}" "${PURE_PREFIX}")
  # Validate the complete source tree before COPY could traverse a redirected
  # descendant. The legacy RED path uses the same no-follow snapshot checks.
  if(EXISTS "${BINARY_DIR}/pure-gl-install-guard.exe")
    execute_process(COMMAND "${BINARY_DIR}/pure-gl-install-guard.exe" --check-tree "${PURE_PREFIX}"
      RESULT_VARIABLE source_rc TIMEOUT 30)
    if(NOT source_rc EQUAL 0)
      message(FATAL_ERROR "Contract requires a regular canonical Pure source tree")
    endif()
  else()
    gl_contract_snapshot("${PURE_PREFIX}" source_rows)
  endif()
  set(root "${BINARY_DIR}/pure-gl-audits")
  set(root_owner "pure-gl audit root\nbuild=${BINARY_DIR}\nsource=${SOURCE_DIR}\n")
  set(owner "pure-gl audit leaf\nleaf=${leaf}\nbuild=${BINARY_DIR}\nsource=${SOURCE_DIR}\n")
  if(EXISTS "${root}")
    gl_pe_no_reparse("${root}" "${root}/.pure-gl-owner")
    file(READ "${root}/.pure-gl-owner" actual)
    if(NOT actual STREQUAL root_owner)
      message(FATAL_ERROR "Contract root ownership mismatch")
    endif()
  else()
    file(MAKE_DIRECTORY "${root}")
    file(WRITE "${root}/.pure-gl-owner" "${root_owner}")
  endif()
  if(EXISTS "${root}/${leaf}")
    gl_contract_clean("${leaf}")
  endif()
  file(MAKE_DIRECTORY "${root}/${leaf}")
  file(WRITE "${root}/${leaf}/.pure-gl-owner" "${owner}")
  set(work "${root}/${leaf}" PARENT_SCOPE)
endfunction()
function(gl_contract_clean leaf)
  execute_process(COMMAND "${BINARY_DIR}/pure-gl-install-guard.exe" --clean-audit "${leaf}"
    RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 40)
  if(NOT rc EQUAL 0)
    message(FATAL_ERROR "Owned audit cleanup refused (${rc}): ${out}${err}")
  endif()
endfunction()
function(gl_contract_snapshot root output)
  gl_pe_no_reparse("${root}")
  file(GLOB_RECURSE paths LIST_DIRECTORIES TRUE RELATIVE "${root}" "${root}/*")
  set(absolute)
  foreach(path IN LISTS paths)
    list(APPEND absolute "${root}/${path}")
  endforeach()
  if(absolute)
    gl_pe_no_reparse(${absolute})
  endif()
  set(rows)
  foreach(path IN LISTS paths)
    if(IS_DIRECTORY "${root}/${path}")
      list(APPEND rows "${path}|d|0|-")
    else()
      file(SIZE "${root}/${path}" size)
      file(SHA256 "${root}/${path}" hash)
      list(APPEND rows "${path}|f|${size}|${hash}")
    endif()
  endforeach()
  list(SORT rows)
  set(${output} "${rows}" PARENT_SCOPE)
endfunction()
function(gl_contract_same root expected)
  gl_contract_snapshot("${root}" actual)
  if(NOT actual STREQUAL expected)
    message(FATAL_ERROR "Failed operation changed protected fixture: ${root}")
  endif()
endfunction()
function(gl_contract_remove_file path)
  cmake_path(IS_PREFIX work "${path}" NORMALIZE below)
  if(NOT below OR path STREQUAL work OR IS_DIRECTORY "${path}")
    message(FATAL_ERROR "Refuse non-owned file removal: ${path}")
  endif()
  gl_pe_no_reparse("${work}/.pure-gl-owner" "${path}")
  get_filename_component(leaf "${work}" NAME)
  file(SHA256 "${work}/.pure-gl-owner" owner_hash)
  string(SHA256 wanted_hash "pure-gl audit leaf\r\nleaf=${leaf}\r\nbuild=${BINARY_DIR}\r\nsource=${SOURCE_DIR}\r\n")
  if(NOT owner_hash STREQUAL wanted_hash)
    message(FATAL_ERROR "Owned leaf sentinel mismatch before file removal")
  endif()
  file(REMOVE "${path}")
endfunction()
function(gl_contract_remove_empty path)
  cmake_path(IS_PREFIX work "${path}" NORMALIZE below)
  if(NOT below OR path STREQUAL work)
    message(FATAL_ERROR "Refuse non-owned directory removal: ${path}")
  endif()
  gl_pe_no_reparse("${work}/.pure-gl-owner" "${path}")
  get_filename_component(leaf "${work}" NAME)
  file(SHA256 "${work}/.pure-gl-owner" owner_hash)
  string(SHA256 wanted_hash "pure-gl audit leaf\r\nleaf=${leaf}\r\nbuild=${BINARY_DIR}\r\nsource=${SOURCE_DIR}\r\n")
  if(NOT owner_hash STREQUAL wanted_hash)
    message(FATAL_ERROR "Owned leaf sentinel mismatch before directory removal")
  endif()
  execute_process(COMMAND "${GL_PE_POWERSHELL}" -NoProfile -NonInteractive -Command
    "[IO.Directory]::Delete('${path}')" RESULT_VARIABLE rc)
  if(NOT rc EQUAL 0)
    message(FATAL_ERROR "Cannot remove empty owned directory")
  endif()
endfunction()
function(gl_contract_run name expected)
  execute_process(COMMAND ${ARGN} RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 260)
  file(WRITE "${work}/${name}.log" "exit=${rc}\n${out}${err}")
  string(REGEX REPLACE "[\r\n ]+" " " diagnostic "${out}${err}")
  if(expected STREQUAL PASS OR expected MATCHES "^PURE_GL_INSTALL_PACKAGE_OK")
    if(NOT rc EQUAL 0 OR (NOT expected STREQUAL PASS AND NOT diagnostic MATCHES "${expected}"))
      message(FATAL_ERROR "${name}: expected success: ${rc}\n${out}${err}")
    endif()
    math(EXPR count "${positive}+1")
    set(positive "${count}" PARENT_SCOPE)
    if(expected MATCHES "^PURE_GL_INSTALL_PACKAGE_OK")
      string(REGEX MATCH "PURE_GL_INSTALL_PACKAGE_OK[^\r\n]+" summary "${out}")
      message(STATUS "${summary}")
    endif()
  else()
    if(rc EQUAL 0 OR NOT diagnostic MATCHES "${expected}")
      message(FATAL_ERROR "${name}: expected rejection (${expected}): ${rc}\n${out}${err}")
    endif()
    math(EXPR count "${negative}+1")
    set(negative "${count}" PARENT_SCOPE)
  endif()
  message(STATUS "INSTALL_CASE_OK ${name} exit=${rc}")
endfunction()
if(GL_INSTALL_CONTRACT_HELPERS_ONLY)
  return()
endif()

# These probes catch unsafe recursive deletion, path redirection, forged guard
# authority, and absent stage exclusion. All targets are inside fixed owned leaves.
gl_contract_open(install-guard-contract)
string(RANDOM LENGTH 12 ALPHABET 0123456789abcdef instance)
set(stage "${work}/stage-${instance}")
file(MAKE_DIRECTORY "${stage}")
file(COPY "${PURE_PREFIX}/" DESTINATION "${stage}")
set(guard "${BINARY_DIR}/pure-gl-install-guard.exe")
set(install "${CMAKE_COMMAND}" --install "${BINARY_DIR}" --prefix "${stage}")
set(context "${BINARY_DIR}/pure-gl-install-context.cmake")
gl_contract_snapshot("${stage}" baseline)

if(NOT RED_ONLY)
file(READ "${work}/.pure-gl-owner" owner)
file(WRITE "${work}/.pure-gl-owner" "WRONG OWNER\n")
gl_contract_run(cleanup-wrong-owner "sentinel" "${guard}" --clean-audit install-guard-contract)
gl_contract_same("${stage}" "${baseline}")
file(WRITE "${work}/.pure-gl-owner" "${owner}")
file(MAKE_DIRECTORY "${work}/protected")
file(WRITE "${work}/protected/.pure-gl-protected" "KEEP\n")
gl_contract_run(cleanup-protected-descendant "protected descendant" "${guard}" --clean-audit install-guard-contract)
gl_contract_same("${stage}" "${baseline}")
file(READ "${work}/protected/.pure-gl-protected" kept)
if(NOT kept STREQUAL "KEEP\n")
  message(FATAL_ERROR "Protected descendant changed")
endif()
gl_contract_remove_file("${work}/protected/.pure-gl-protected")
gl_contract_remove_empty("${work}/protected")

set(link "${stage}/junction")
execute_process(COMMAND "${GL_PE_POWERSHELL}" -NoProfile -NonInteractive -Command
  "New-Item -ItemType Junction -Path '${link}' -Target '${work}' | Out-Null" RESULT_VARIABLE rc)
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "Cannot create owned junction fixture")
endif()
gl_contract_run(stage-junction "reparse|redirected" ${install} --component runtime)
gl_contract_run(cleanup-junction "reparse" "${guard}" --clean-audit install-guard-contract)
execute_process(COMMAND "${GL_PE_POWERSHELL}" -NoProfile -NonInteractive -Command
  "[IO.Directory]::Delete('${link}')" RESULT_VARIABLE rc)
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "Cannot unlink exact junction")
endif()
gl_contract_same("${stage}" "${baseline}")
set(link "${work}/hardlink")
execute_process(COMMAND "${GL_PE_POWERSHELL}" -NoProfile -NonInteractive -Command
  "New-Item -ItemType HardLink -Path '${link}' -Target '${stage}/lib/pure/prelude.pure' | Out-Null" RESULT_VARIABLE rc)
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "Cannot create owned hardlink fixture")
endif()
gl_contract_run(stage-hardlink "hardlink" ${install} --component runtime)
gl_contract_run(cleanup-hardlink "hardlink" "${guard}" --clean-audit install-guard-contract)
gl_contract_same("${stage}" "${baseline}")
gl_contract_remove_file("${link}")
set(ENV{PURE_GL_INSTALL_CHANNEL} "forged")
gl_contract_run(forged-owner "authenticated|owner channel" ${install} --component runtime)
unset(ENV{PURE_GL_INSTALL_CHANNEL})
gl_contract_same("${stage}" "${baseline}")
gl_contract_run(unknown-leaf "fixed audit leaf" "${guard}" --clean-audit ..)
endif()

# Independent native lock holder: the configured install must reject while the
# exact stage identity's named mutex belongs to a cooperating process.
set(lock_probe [==[
$ErrorActionPreference='Stop'
$code=@'
using System; using System.Runtime.InteropServices;
public static class GlStageLock {
 [StructLayout(LayoutKind.Sequential)] public struct Info { public uint Attr; public System.Runtime.InteropServices.ComTypes.FILETIME C,A,W; public uint Volume, HighSize, LowSize, Links, High, Low; }
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] public static extern IntPtr CreateFile(string p,uint a,uint s,IntPtr n,uint d,uint f,IntPtr t);
 [DllImport("kernel32.dll")] public static extern bool GetFileInformationByHandle(IntPtr h,out Info i);
 [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
}
'@
Add-Type $code
$h=[GlStageLock]::CreateFile('@STAGE@',0,7,[IntPtr]::Zero,3,0x02200000,[IntPtr]::Zero)
$info=New-Object GlStageLock+Info
if($h.ToInt64() -eq -1 -or -not [GlStageLock]::GetFileInformationByHandle($h,[ref]$info)) { throw 'Cannot inspect stage identity' }
[GlStageLock]::CloseHandle($h) | Out-Null
$name='Global\pure-gl-stage-{0:x8}-{1:x8}{2:x8}' -f $info.Volume,$info.High,$info.Low
$m=New-Object Threading.Mutex($false,$name)
if(-not $m.WaitOne(0)) { throw 'Fixture could not own mutex' }
try {
 $ErrorActionPreference='Continue'
 $o=& '@CMAKE@' --install '@BUILD@' --prefix '@STAGE@' --component runtime 2>&1
 $rc=$LASTEXITCODE
 if($rc -eq 0 -or "$o" -notmatch 'stage identity already owned') { throw "Installer ignored stage exclusion: $rc $o" }
 Write-Output 'GL_STAGE_EXCLUSION_OK'
} finally { $m.ReleaseMutex(); $m.Dispose() }
]==])
set(STAGE "${stage}")
set(CMAKE "${CMAKE_COMMAND}")
set(BUILD "${BINARY_DIR}")
string(CONFIGURE "${lock_probe}" lock_probe @ONLY)
file(WRITE "${work}/mutex.ps1" "${lock_probe}")
gl_contract_run(stage-exclusion PASS "${GL_PE_POWERSHELL}" -NoProfile -NonInteractive
  -ExecutionPolicy Bypass -File "${work}/mutex.ps1")
if(RED_ONLY)
  message(FATAL_ERROR "RED fixture unexpectedly found stage exclusion already implemented")
endif()
gl_contract_same("${stage}" "${baseline}")

# Compile the same guard with fault injection in an isolated, independently
# pinned fixture build. Production binaries have no injection environment hooks.
set(fixture_build "${work}/fixture-build")
set(fixture_stage "${work}/fixture-stage")
file(MAKE_DIRECTORY "${fixture_build}" "${fixture_stage}")
file(COPY "${PURE_PREFIX}/" DESTINATION "${fixture_stage}")
foreach(name pure-gl.dll pure-gl-test-runner.exe README pure-gl-install-baseline.tsv)
  file(COPY_FILE "${BINARY_DIR}/${name}" "${fixture_build}/${name}")
endforeach()
file(READ "${context}" fixture_context)
string(REPLACE "${BINARY_DIR}" "${fixture_build}" fixture_context "${fixture_context}")
file(CONFIGURE OUTPUT "${fixture_build}/pure-gl-install-context.cmake"
  CONTENT "${fixture_context}" @ONLY NEWLINE_STYLE UNIX)
file(SHA256 "${fixture_build}/pure-gl-install-context.cmake" fixture_context_hash)
file(READ "${BINARY_DIR}/pure_gl_install_authority.h" header)
string(REPLACE "${BINARY_DIR}" "${fixture_build}" header "${header}")
string(REGEX REPLACE "GL_NATIVE_CONTEXT_HASH L\"[a-f0-9]+\""
  "GL_NATIVE_CONTEXT_HASH L\"${fixture_context_hash}\"" header "${header}")
file(CONFIGURE OUTPUT "${fixture_build}/pure_gl_install_authority.h"
  CONTENT "${header}" @ONLY NEWLINE_STYLE UNIX)
file(STRINGS "${BINARY_DIR}/CMakeCache.txt" compiler REGEX "^CMAKE_C_COMPILER:[^=]+=")
string(REGEX REPLACE "^[^=]+=" "" compiler "${compiler}")
set(saved_path "$ENV{PATH}")
set(ENV{PATH} "${CLANG64_PREFIX}/bin;C:/Windows/System32;C:/Windows")
gl_contract_run(fixture-compile PASS "${compiler}" -std=c11 -Wall -Wextra -Werror
  -O2 -municode -DPURE_GL_INSTALL_GUARD_FIXTURE=1 "-I${fixture_build}"
  "${SOURCE_DIR}/cmake/pure_gl_install_guard.c" -lbcrypt
  -o "${fixture_build}/pure-gl-install-guard.exe")
# Authenticate each deliberately changed fixture context with a matching native
# fixture build. This reaches the real origin/hash checks rather than merely
# rejecting an untrusted alternate context filename at the bootstrap boundary.
file(COPY_FILE "${CLANG64_PREFIX}/bin/libfreeglut.dll" "${work}/wrong-origin.dll")
file(COPY_FILE "${CLANG64_PREFIX}/share/licenses/freeglut/COPYING" "${work}/wrong-notice.txt")
foreach(case runtime-origin license-origin source-hash pristine)
  set(mutated "${fixture_context}")
  if(case STREQUAL runtime-origin)
    string(REPLACE "${CLANG64_PREFIX}/bin/libfreeglut.dll" "${work}/wrong-origin.dll" mutated "${mutated}")
    set(expected "wrong origin")
  elseif(case STREQUAL license-origin)
    string(REPLACE "${CLANG64_PREFIX}/share/licenses/freeglut/COPYING" "${work}/wrong-notice.txt" mutated "${mutated}")
    set(expected "wrong origin")
  elseif(case STREQUAL source-hash)
    string(REPLACE "b6593d5ec4c113a274abb85b10e8615895cb0ddb89f7912af5fe5aa8df38a275"
      "0000000000000000000000000000000000000000000000000000000000000000" mutated "${mutated}")
    set(expected "configured source hash mismatch")
  endif()
  file(CONFIGURE OUTPUT "${fixture_build}/pure-gl-install-context.cmake"
    CONTENT "${mutated}" @ONLY NEWLINE_STYLE UNIX)
  file(SHA256 "${fixture_build}/pure-gl-install-context.cmake" mutated_hash)
  string(REGEX REPLACE "GL_NATIVE_CONTEXT_HASH L\"[a-f0-9]+\""
    "GL_NATIVE_CONTEXT_HASH L\"${mutated_hash}\"" mutated_header "${header}")
  file(CONFIGURE OUTPUT "${fixture_build}/pure_gl_install_authority.h"
    CONTENT "${mutated_header}" @ONLY NEWLINE_STYLE UNIX)
  gl_contract_run("fixture-compile-${case}" PASS "${compiler}" -std=c11 -Wall -Wextra -Werror
    -O2 -municode -DPURE_GL_INSTALL_GUARD_FIXTURE=1 "-I${fixture_build}"
    "${SOURCE_DIR}/cmake/pure_gl_install_guard.c" -lbcrypt
    -o "${fixture_build}/pure-gl-install-guard.exe")
  if(NOT case STREQUAL pristine)
    gl_contract_run("authenticated-${case}" "${expected}" "${CMAKE_COMMAND}"
      "-DGL_INSTALL_CONTEXT=${fixture_build}/pure-gl-install-context.cmake"
      -DGL_INSTALL_MODE=seal -P "${SOURCE_DIR}/cmake/VerifyInstalledPackage.cmake")
    gl_contract_same("${fixture_stage}" "${baseline}")
  endif()
endforeach()
set(ENV{PATH} "${saved_path}")
gl_contract_run(fixture-seal PASS "${CMAKE_COMMAND}"
  "-DGL_INSTALL_CONTEXT=${fixture_build}/pure-gl-install-context.cmake"
  -DGL_INSTALL_MODE=seal -P "${SOURCE_DIR}/cmake/VerifyInstalledPackage.cmake")
set(fixture_install "${CMAKE_COMMAND}"
  "-DGL_INSTALL_CONTEXT=${fixture_build}/pure-gl-install-context.cmake"
  "-DSTAGE_PREFIX=${fixture_stage}" -DGL_INSTALL_MODE=install
  -DGL_INSTALL_COMPONENT=runtime -P "${SOURCE_DIR}/cmake/VerifyInstalledPackage.cmake")
foreach(after 1 9 10 12)
  set(ENV{GL_GUARD_TEST_FAIL_AFTER_WRITE} "${after}")
  gl_contract_run("rollback-${after}" "injected pre-commit write failure" ${fixture_install})
  unset(ENV{GL_GUARD_TEST_FAIL_AFTER_WRITE})
  file(READ "${work}/rollback-${after}.log" rollback_log)
  if(NOT rollback_log MATCHES "INSTALL_BATCH_ROLLBACK_OK")
    message(FATAL_ERROR "Guard did not confirm controlled rollback")
  endif()
  gl_contract_same("${fixture_stage}" "${baseline}")
endforeach()
gl_contract_run(rollback-restored PASS ${fixture_install})
gl_contract_snapshot("${fixture_stage}" restored)
file(WRITE "${fixture_build}/install_manifest_runtime.txt" "KEEP PREVIOUS CONVENTIONAL MANIFEST\n")
file(SHA256 "${fixture_build}/install_manifest_runtime.txt" previous_manifest)
set(ENV{GL_GUARD_TEST_FAIL_AFTER_WRITE} 1)
gl_contract_run(rollback-previous-manifest "injected pre-commit write failure" ${fixture_install})
unset(ENV{GL_GUARD_TEST_FAIL_AFTER_WRITE})
gl_contract_same("${fixture_stage}" "${restored}")
file(SHA256 "${fixture_build}/install_manifest_runtime.txt" restored_manifest)
if(NOT restored_manifest STREQUAL previous_manifest)
  message(FATAL_ERROR "Controlled rollback changed pre-existing conventional manifest bytes")
endif()
gl_contract_run(manifest-restored PASS ${fixture_install})
gl_contract_run(documentation-first PASS ${install} --component documentation)
if(EXISTS "${stage}/lib/pure/pure-gl.dll")
  message(FATAL_ERROR "Documentation component overlaps runtime")
endif()
gl_contract_run(runtime-second PASS ${install} --component runtime)
gl_contract_run(final-pristine "PURE_GL_INSTALL_PACKAGE_OK.*installed_tests=2"
  "${CMAKE_COMMAND}" "-DGL_INSTALL_CONTEXT=${context}" "-DSTAGE_PREFIX=${stage}"
  -P "${SOURCE_DIR}/cmake/VerifyInstalledPackage.cmake")
message(STATUS "PURE_GL_INSTALL_GUARD_CONTRACT_OK negative=${negative} positive=${positive} protected_writes=0")
gl_contract_clean(install-guard-contract)
