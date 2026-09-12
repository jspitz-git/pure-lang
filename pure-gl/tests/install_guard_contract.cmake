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

# The independent process synchronizes on real native checkpoints. It attempts
# only exact file/directory operations beneath the sentinel-owned fixture leaf.
function(gl_contract_interleave name phase action relative mode component child_exit)
  set(probe_stage "${work}/interleave-${name}")
  file(MAKE_DIRECTORY "${probe_stage}")
  file(COPY "${PURE_PREFIX}/" DESTINATION "${probe_stage}")
  if(action STREQUAL "context")
    set(PROBE_TARGET "${fixture_build}/pure-gl-install-context.cmake")
  else()
    set(PROBE_TARGET "${probe_stage}/${relative}")
  endif()
  set(PROBE_STAGE "${probe_stage}")
  set(PROBE_BUILD "${fixture_build}")
  set(PROBE_WORK "${work}")
  set(PROBE_PHASE "${phase}")
  set(PROBE_ACTION "${action}")
  set(PROBE_MODE "${mode}")
  set(PROBE_COMPONENT "${component}")
  set(PROBE_EXIT "${child_exit}")
  set(PROBE_CMAKE "${CMAKE_COMMAND}")
  if(action STREQUAL "published")
    file(WRITE "${fixture_build}/install_manifest_runtime.txt" "KEEP BEFORE FINAL-CHECK FAILURE\n")
  endif()
  if(action MATCHES "^(published|prune|queued)$")
    gl_contract_snapshot("${fixture_build}" build_before)
  endif()
  if(fixture_script)
    set(PROBE_SCRIPT "${fixture_script}")
  else()
    set(PROBE_SCRIPT "${SOURCE_DIR}/cmake/VerifyInstalledPackage.cmake")
  endif()
  file(SHA256 "${work}/.pure-gl-owner" PROBE_OWNER)
  set(probe [==[
$ErrorActionPreference='Stop'
$taskWork=[IO.Path]::GetFullPath('@PROBE_WORK@')
$taskTarget=[IO.Path]::GetFullPath('@PROBE_TARGET@')
$taskSha=[Security.Cryptography.SHA256]::Create()
$taskOwnerHash=[BitConverter]::ToString($taskSha.ComputeHash([IO.File]::ReadAllBytes($taskWork+'\.pure-gl-owner'))).Replace('-','')
$taskSha.Dispose()
if(-not $taskTarget.StartsWith($taskWork+'\',[StringComparison]::OrdinalIgnoreCase) -or
   $taskOwnerHash -ne '@PROBE_OWNER@') { throw 'Unowned synchronized target' }
for($taskAncestor=$taskTarget; $taskAncestor.Length -gt 3; $taskAncestor=[IO.Path]::GetDirectoryName($taskAncestor)) {
 if(([IO.File]::Exists($taskAncestor) -or [IO.Directory]::Exists($taskAncestor)) -and
    (([IO.File]::GetAttributes($taskAncestor) -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw 'Redirected synchronized target' }
}
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class GlInterleave {
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] public static extern IntPtr CreateFile(string p,uint a,uint s,IntPtr n,uint d,uint f,IntPtr t);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] public static extern bool CreateDirectory(string p,IntPtr s);
 [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
 [StructLayout(LayoutKind.Sequential)] public struct Status { public IntPtr Code; public UIntPtr Information; }
 [DllImport("ntdll.dll")] public static extern int NtSetInformationFile(IntPtr h,out Status s,IntPtr p,uint n,int c);
 [DllImport("ntdll.dll")] public static extern uint RtlNtStatusToDosError(int s);
 public static int Rename(string a,string b) {
  IntPtr h=CreateFile(a,0x80010000,7,IntPtr.Zero,3,0x02200000,IntPtr.Zero);
  if(h.ToInt64()==-1) return Marshal.GetLastWin32Error();
  byte[] name=System.Text.Encoding.Unicode.GetBytes(System.IO.Path.GetFileName(b));
  IntPtr record=Marshal.AllocHGlobal(20+name.Length);
  for(int i=0;i<20;i++) Marshal.WriteByte(record,i,0);
  Marshal.WriteInt32(record,16,name.Length); Marshal.Copy(name,0,IntPtr.Add(record,20),name.Length);
  Status status; int code=NtSetInformationFile(h,out status,record,(uint)(20+name.Length),10);
  Marshal.FreeHGlobal(record); CloseHandle(h);
  return code>=0 ? 0 : (int)RtlNtStatusToDosError(code);
 }
 public static int Writable(string p,uint creation) {
  IntPtr h=CreateFile(p,0x40000000,7,IntPtr.Zero,creation,0x00200000,IntPtr.Zero);
  if(h.ToInt64()==-1) return Marshal.GetLastWin32Error();
  CloseHandle(h); return 0;
 }
}
'@
$taskId=[Guid]::NewGuid().ToString('N')
$taskReadyName='Local\pure-gl-review-ready-'+$taskId
$taskReleaseName='Local\pure-gl-review-release-'+$taskId
$taskReady=New-Object Threading.EventWaitHandle($false,[Threading.EventResetMode]::ManualReset,$taskReadyName)
$taskRelease=New-Object Threading.EventWaitHandle($false,[Threading.EventResetMode]::ManualReset,$taskReleaseName)
$taskStart=New-Object Diagnostics.ProcessStartInfo
$taskStart.FileName='@PROBE_CMAKE@'
$taskStart.Arguments='"-DGL_INSTALL_CONTEXT=@PROBE_BUILD@/pure-gl-install-context.cmake" "-DSTAGE_PREFIX=@PROBE_STAGE@" -DGL_INSTALL_MODE=@PROBE_MODE@ -DGL_INSTALL_COMPONENT=@PROBE_COMPONENT@ -P "@PROBE_SCRIPT@"'
$taskStart.UseShellExecute=$false
$taskStart.CreateNoWindow=$true
$taskStart.RedirectStandardOutput=$true
$taskStart.RedirectStandardError=$true
$taskStart.EnvironmentVariables['GL_GUARD_TEST_PHASE']='@PROBE_PHASE@'
$taskStart.EnvironmentVariables['GL_GUARD_TEST_READY']=$taskReadyName
$taskStart.EnvironmentVariables['GL_GUARD_TEST_RELEASE']=$taskReleaseName
$taskStart.EnvironmentVariables['GL_GUARD_TEST_TARGET']=$taskTarget
if('@PROBE_ACTION@' -eq 'prune') { $taskStart.EnvironmentVariables['GL_GUARD_TEST_FAIL_AFTER_WRITE']='1' }
$taskProcess=New-Object Diagnostics.Process
$taskProcess.StartInfo=$taskStart
if(-not $taskProcess.Start()) { throw 'Cannot start owned interleaving process' }
$taskOut=$taskProcess.StandardOutput.ReadToEndAsync()
$taskErr=$taskProcess.StandardError.ReadToEndAsync()
$taskFailure=$null
try {
 if(-not $taskReady.WaitOne(45000)) { throw 'Native synchronized checkpoint not reached' }
 if('@PROBE_ACTION@' -eq 'context') {
  $taskResult=[GlInterleave]::Rename($taskTarget,$taskTarget+'.moved')
  Write-Output ('context_rename='+$taskResult)
  if($taskResult -eq 0) {
   if([GlInterleave]::Rename($taskTarget+'.moved',$taskTarget) -ne 0) { throw 'Cannot restore exact owned context' }
   throw 'Validated context was replaceable before consumption'
  }
  if($taskResult -ne 32) { throw 'Context replacement failed for a reason other than retained identity' }
  $taskResult=[GlInterleave]::Writable($taskTarget,3)
  if($taskResult -eq 0) { throw 'Validated context was writable before consumption' }
  if($taskResult -ne 32) { throw 'Context write was not blocked by retained identity' }
 } elseif('@PROBE_ACTION@' -eq 'published' -or '@PROBE_ACTION@' -eq 'queued') {
  if([GlInterleave]::Writable($taskTarget,1) -ne 0) { throw 'Cannot create exact owned final-check mutation' }
 } elseif('@PROBE_ACTION@' -eq 'prune') {
  $taskResult=[GlInterleave]::Rename($taskTarget,$taskTarget+'.moved')
  Write-Output ('prune_rename='+$taskResult)
  if($taskResult -eq 0) {
   if(-not [GlInterleave]::CreateDirectory($taskTarget,[IntPtr]::Zero)) { throw 'Cannot create owned empty replacement fixture' }
   throw 'Rollback directory identity was released before deletion'
  }
  if($taskResult -ne 32) { throw 'Rollback replacement failed for a reason other than retained identity' }
 } elseif('@PROBE_ACTION@' -eq 'reservation') {
  $taskResult=[GlInterleave]::Writable($taskTarget,2)
  Write-Output ('reservation_write='+$taskResult)
  if($taskResult -eq 0) { throw 'Unselected runtime endpoint was writable during publication' }
  if($taskResult -ne 32) { throw 'Unselected runtime endpoint was not actively reserved' }
 }
} catch { $taskFailure=$_ }
finally {
 $taskRelease.Set() | Out-Null
 if(-not $taskProcess.WaitForExit(260000)) { $taskProcess.Kill(); $taskFailure='Owned interleaving process exceeded its deadline' }
 $taskReady.Dispose(); $taskRelease.Dispose()
}
$taskResult=$taskProcess.ExitCode
Write-Output ('child_exit='+$taskResult)
Write-Output $taskOut.Result
Write-Output $taskErr.Result
$taskProcess.Dispose()
if($taskFailure) { throw $taskFailure }
if($taskResult -ne @PROBE_EXIT@) { throw 'Unexpected synchronized child result' }
Write-Output 'GL_INTERLEAVE_OK @PROBE_ACTION@'
]==])
  string(CONFIGURE "${probe}" probe @ONLY)
  file(WRITE "${work}/${name}.ps1" "${probe}")
  set(expected PASS)
  if(ARGC GREATER 7)
    set(expected "${ARGV7}")
  endif()
  gl_contract_run("${name}" "${expected}" "${GL_PE_POWERSHELL}" -NoProfile -NonInteractive
    -ExecutionPolicy Bypass -File "${work}/${name}.ps1")
  file(READ "${work}/${name}.log" observed)
  string(REGEX MATCHALL "(context_rename|prune_rename|reservation_write)=[0-9]+" observations "${observed}")
  message(STATUS "GL_INTERLEAVE_OBSERVED ${name}: ${observations}")
  if(NOT expected STREQUAL "PASS")
    if(NOT observed MATCHES "reservation_write=0")
      message(FATAL_ERROR "Reservation mutation did not reach the independent writer")
    endif()
    set(negative "${negative}" PARENT_SCOPE)
    return()
  endif()
  if(action STREQUAL "queued" AND (NOT observed MATCHES "batch reservation collision" OR
      observed MATCHES "INSTALL_BATCH_READY_OK"))
    message(FATAL_ERROR "Queued cross-component collision did not fail before publication")
  endif()
  if(action STREQUAL "published" OR action STREQUAL "queued")
    gl_contract_remove_file("${PROBE_TARGET}")
  endif()
  if(action MATCHES "^(published|prune|queued)$")
    gl_contract_same("${fixture_build}" "${build_before}")
  endif()
  if(NOT action STREQUAL "reservation")
    gl_contract_same("${probe_stage}" "${baseline}")
  elseif(EXISTS "${PROBE_TARGET}")
    message(FATAL_ERROR "Unselected component reservation survived publication")
  endif()
  set(positive "${positive}" PARENT_SCOPE)
endfunction()

# Remove the production reservation call in a separately pinned policy build.
# The same synchronized actor must now write the unselected runtime endpoint;
# a text assertion or an unrelated bootstrap rejection cannot satisfy this.
function(gl_contract_reservation_mutation)
  set(original_build "${fixture_build}")
  set(fixture_build "${work}/reservation-mutation-build")
  file(MAKE_DIRECTORY "${fixture_build}/policy")
  foreach(name pure-gl.dll pure-gl-test-runner.exe README pure-gl-install-baseline.tsv)
    file(COPY_FILE "${original_build}/${name}" "${fixture_build}/${name}")
  endforeach()
  execute_process(COMMAND "${CMAKE_COMMAND}" "-DMODULE=${fixture_build}/pure-gl.dll"
    "-DRUNNER=${fixture_build}/pure-gl-test-runner.exe" "-DBUILD_DIR=${fixture_build}"
    -P "${SOURCE_DIR}/cmake/SealBuiltArtifacts.cmake" COMMAND_ERROR_IS_FATAL ANY)
  set(original_script "${SOURCE_DIR}/cmake/VerifyInstalledPackage.cmake")
  set(fixture_script "${fixture_build}/policy/VerifyInstalledPackage.cmake")
  file(READ "${original_script}" mutant)
  set(reserve "      install_guard_operation(--reserve \"\${stage}/\${destination}\")")
  string(FIND "${mutant}" "${reserve}" found)
  if(found LESS 0)
    message(FATAL_ERROR "Production reservation call is missing before mutation")
  endif()
  string(REPLACE "${reserve}" "      # Controlled contract mutation: no active reservation." mutant "${mutant}")
  file(CONFIGURE OUTPUT "${fixture_script}" CONTENT "${mutant}" @ONLY NEWLINE_STYLE UNIX)
  file(COPY_FILE "${SOURCE_DIR}/cmake/PeHelpers.cmake" "${fixture_build}/policy/PeHelpers.cmake")
  file(SHA256 "${original_script}" old_script_hash)
  file(SHA256 "${fixture_script}" new_script_hash)
  file(READ "${original_build}/pure-gl-install-context.cmake" mutation_context)
  string(REPLACE "${original_build}" "${fixture_build}" mutation_context "${mutation_context}")
  string(REPLACE "${original_script}" "${fixture_script}" mutation_context "${mutation_context}")
  string(REPLACE "${old_script_hash}" "${new_script_hash}" mutation_context "${mutation_context}")
  file(CONFIGURE OUTPUT "${fixture_build}/pure-gl-install-context.cmake"
    CONTENT "${mutation_context}" @ONLY NEWLINE_STYLE UNIX)
  file(SHA256 "${fixture_build}/pure-gl-install-context.cmake" mutation_context_hash)
  file(READ "${original_build}/pure_gl_install_authority.h" mutation_header)
  string(REPLACE "${original_build}" "${fixture_build}" mutation_header "${mutation_header}")
  string(REPLACE "${original_script}" "${fixture_script}" mutation_header "${mutation_header}")
  string(REGEX REPLACE "GL_NATIVE_CONTEXT_HASH L\"[a-f0-9]+\""
    "GL_NATIVE_CONTEXT_HASH L\"${mutation_context_hash}\"" mutation_header "${mutation_header}")
  string(REGEX REPLACE "GL_NATIVE_SCRIPT_HASH L\"[a-f0-9]+\""
    "GL_NATIVE_SCRIPT_HASH L\"${new_script_hash}\"" mutation_header "${mutation_header}")
  file(CONFIGURE OUTPUT "${fixture_build}/pure_gl_install_authority.h"
    CONTENT "${mutation_header}" @ONLY NEWLINE_STYLE UNIX)
  set(saved_path "$ENV{PATH}")
  set(ENV{PATH} "${CLANG64_PREFIX}/bin;C:/Windows/System32;C:/Windows")
  gl_contract_run(reservation-mutation-compile PASS "${compiler}" -std=c11 -Wall -Wextra -Werror
    -O2 -municode -DPURE_GL_INSTALL_GUARD_FIXTURE=1 "-I${fixture_build}"
    "${SOURCE_DIR}/cmake/pure_gl_install_guard.c" -lbcrypt
    -o "${fixture_build}/pure-gl-install-guard.exe")
  set(ENV{PATH} "${saved_path}")
  gl_contract_run(reservation-mutation-seal PASS "${CMAKE_COMMAND}"
    "-DGL_INSTALL_CONTEXT=${fixture_build}/pure-gl-install-context.cmake"
    -DGL_INSTALL_MODE=seal -P "${fixture_script}")
  gl_contract_interleave(reservation-mutation reserved reservation lib/pure/GL.pure install documentation 1
    "Unselected runtime endpoint was writable during publication")
  set(negative "${negative}" PARENT_SCOPE)
  set(positive "${positive}" PARENT_SCOPE)
endfunction()
if(GL_INSTALL_CONTRACT_HELPERS_ONLY)
  return()
endif()
if(FIX1_CASE AND NOT FIX1_CASE MATCHES "^(cmake-authority|context-window|post-publication|prune-identity|reservation)$")
  message(FATAL_ERROR "Unknown focused review contract")
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

if(NOT RED_ONLY AND (NOT FIX1_CASE OR FIX1_CASE STREQUAL "cmake-authority"))
  # An alternate executable must not run merely because it occupies argv[4].
  file(WRITE "${work}/alternate-cmake.c"
    "#include <stdio.h>\nint main(void) { puts(\"UNTRUSTED_CMAKE_LAUNCHED\"); return 0; }\n")
  file(STRINGS "${BINARY_DIR}/CMakeCache.txt" compiler REGEX "^CMAKE_C_COMPILER:[^=]+=")
  string(REGEX REPLACE "^[^=]+=" "" compiler "${compiler}")
  set(saved_path "$ENV{PATH}")
  set(ENV{PATH} "${CLANG64_PREFIX}/bin;C:/Windows/System32;C:/Windows")
  gl_contract_run(alternate-cmake-build PASS "${compiler}" -std=c11 -Wall -Wextra -Werror
    "${work}/alternate-cmake.c" -o "${work}/alternate-cmake.exe")
  set(ENV{PATH} "${saved_path}")
  gl_contract_run(cmake-executable-authority "configured CMake executable identity"
    "${guard}" --run "${stage}" "${BINARY_DIR}" "${work}/alternate-cmake.exe"
    "${context}" "${SOURCE_DIR}/cmake/VerifyInstalledPackage.cmake" install runtime)
  gl_contract_same("${stage}" "${baseline}")
  if(FIX1_CASE STREQUAL "cmake-authority")
    gl_contract_clean(install-guard-contract)
    return()
  endif()
endif()

if(NOT FIX1_CASE)
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
endif()
set(fixture_build "${work}/fixture-build")
set(fixture_stage "${work}/fixture-stage")
file(MAKE_DIRECTORY "${fixture_build}" "${fixture_stage}")
file(COPY "${PURE_PREFIX}/" DESTINATION "${fixture_stage}")
foreach(name pure-gl.dll pure-gl-test-runner.exe README pure-gl-install-baseline.tsv)
  file(COPY_FILE "${BINARY_DIR}/${name}" "${fixture_build}/${name}")
endforeach()
execute_process(COMMAND "${CMAKE_COMMAND}" "-DMODULE=${fixture_build}/pure-gl.dll"
  "-DRUNNER=${fixture_build}/pure-gl-test-runner.exe" "-DBUILD_DIR=${fixture_build}"
  -P "${SOURCE_DIR}/cmake/SealBuiltArtifacts.cmake" COMMAND_ERROR_IS_FATAL ANY)
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
  if(FIX1_CASE AND NOT case STREQUAL pristine)
    continue()
  endif()
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
if(NOT FIX1_CASE OR FIX1_CASE STREQUAL "context-window")
  gl_contract_interleave(context-consumption context-consume context unused seal all 0)
endif()
if(NOT FIX1_CASE OR FIX1_CASE STREQUAL "post-publication")
  gl_contract_interleave(post-publication published published unexpected-after-publication.txt install runtime 1)
endif()
if(NOT FIX1_CASE OR FIX1_CASE STREQUAL "prune-identity")
  gl_contract_interleave(prune-identity prune prune share/doc/pure-gl/tests install runtime 1)
endif()
if(NOT FIX1_CASE OR FIX1_CASE STREQUAL "reservation")
  gl_contract_interleave(cross-component-queued queued queued lib/pure/GL.pure install documentation 1)
  gl_contract_interleave(cross-component-reservation reserved reservation lib/pure/GL.pure install documentation 0)
  gl_contract_reservation_mutation()
endif()
if(FIX1_CASE)
  gl_contract_clean(install-guard-contract)
  return()
endif()
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
