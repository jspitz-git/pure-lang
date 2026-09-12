cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS SOURCE_DIR BINARY_DIR C_COMPILER PURE_EXECUTABLE
    CONFIGURED_FREEGLUT_RUNTIME_DLL PURE_GL_PURE_PREFIX PURE_GL_CLANG64_PREFIX
    PURE_GL_WINDOWS_SYSTEM_DIRECTORY)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

file(REAL_PATH "${CONFIGURED_FREEGLUT_RUNTIME_DLL}" configured_runtime)
file(REAL_PATH "${PURE_GL_CLANG64_PREFIX}" actual_clang_prefix)
cmake_path(IS_PREFIX actual_clang_prefix "${configured_runtime}" NORMALIZE
  runtime_from_clang_prefix)
if(runtime_from_clang_prefix)
  message(FATAL_ERROR
    "Configured test runtime must be staged outside the CLANG64 prefix: ${configured_runtime}")
endif()

include("${SOURCE_DIR}/tests/AuditHelpers.cmake")
gl_audit_open(runner-contract test_root)
execute_process(COMMAND "${PURE_GL_WINDOWS_SYSTEM_DIRECTORY}/WindowsPowerShell/v1.0/powershell.exe"
  -NoProfile -NonInteractive -File "${SOURCE_DIR}/tests/RunnerRetention.ps1"
  -Runner "${RUNNER}" -Compiler "${C_COMPILER}" -Root "${test_root}" -Source "${SOURCE_DIR}"
  RESULT_VARIABLE retention_rc OUTPUT_VARIABLE retention_out ERROR_VARIABLE retention_err TIMEOUT 60)
if(NOT retention_rc EQUAL 0)
  message(FATAL_ERROR "Retained runner inputs failed: ${retention_out}${retention_err}")
endif()
message(STATUS "${retention_out}")

set(fixture_source "${test_root}/legacy_probe.c")
set(fixture_exe "${test_root}/legacy probe.exe")
file(WRITE "${fixture_source}" [=[
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
int main(void) {
  char cwd[32768];
  if (!GetCurrentDirectoryA(sizeof(cwd), cwd)) return 2;
  printf("EFFECTIVE_CWD=%s\n", cwd);
  printf("EFFECTIVE_PATH=%s\n", getenv("PATH") ? getenv("PATH") : "<absent>");
  printf("EFFECTIVE_PURELIB=%s\n", getenv("PURELIB") ? getenv("PURELIB") : "UNSET");
  return 0;
}
]=])
execute_process(COMMAND "${C_COMPILER}" -std=c11 -Wall -Wextra -Werror
  "${fixture_source}" -o "${fixture_exe}"
  RESULT_VARIABLE compile_result OUTPUT_VARIABLE compile_output
  ERROR_VARIABLE compile_error)
if(NOT compile_result EQUAL 0)
  message(FATAL_ERROR "Cannot compile legacy runner probe: ${compile_output}${compile_error}")
endif()

set(hanging_runner_source "${test_root}/hanging_runner.c")
set(hanging_runner "${test_root}/hanging runner.exe")
file(WRITE "${hanging_runner_source}" [=[
#include <windows.h>
int main(void) {
  Sleep(30000);
  return 0;
}
]=])
execute_process(COMMAND "${C_COMPILER}" -std=c11 -Wall -Wextra -Werror
  "${hanging_runner_source}" -o "${hanging_runner}"
  RESULT_VARIABLE compile_result OUTPUT_VARIABLE compile_output
  ERROR_VARIABLE compile_error)
if(NOT compile_result EQUAL 0)
  message(FATAL_ERROR "Cannot compile hanging adapter probe: ${compile_output}${compile_error}")
endif()

if(LEGACY)
  set(module_dir "${test_root}/module")
  file(MAKE_DIRECTORY "${module_dir}")
  set(ENV{PATH}
    "${PURE_GL_PURE_PREFIX}/bin;${PURE_GL_CLANG64_PREFIX}/bin;${PURE_GL_WINDOWS_SYSTEM_DIRECTORY};${test_root}/ambient-msys2/bin")
  set(ENV{PURELIB} "${test_root}/ambient-purelib")
  execute_process(COMMAND "${CMAKE_COMMAND}"
    "-DPURE_EXECUTABLE=${fixture_exe}"
    "-DPURE_LIBRARY_DIR=${module_dir}"
    "-DPURE_GL_SOURCE_DIR=${SOURCE_DIR}"
    "-DTEST_SCRIPT=${SOURCE_DIR}/tests/runner_probe.pure"
    -P "${SOURCE_DIR}/cmake/RunPureTest.cmake"
    RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
  if(NOT result EQUAL 0)
    message(FATAL_ERROR "Legacy runner probe did not execute: ${output}${error}")
  endif()
  string(REGEX MATCH "EFFECTIVE_PATH=([^\r\n]+)" unused "${output}")
  file(TO_CMAKE_PATH "${CMAKE_MATCH_1}" actual_path)
  set(expected_path
    "${PURE_GL_PURE_PREFIX}/bin;${module_dir};${PURE_GL_CLANG64_PREFIX}/bin;${PURE_GL_WINDOWS_SYSTEM_DIRECTORY}")
  file(TO_CMAKE_PATH "${expected_path}" expected_path)
  if(NOT actual_path STREQUAL expected_path)
    message(FATAL_ERROR
      "Runner leaked inherited PATH. Expected '${expected_path}', got '${actual_path}'")
  endif()
  message(FATAL_ERROR "Legacy runner unexpectedly satisfied the native contract")
endif()

foreach(required IN ITEMS RUNNER FIXTURE)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

set(source_dir "${test_root}/source inputs")
set(module_dir "${test_root}/module output")
set(pure_prefix "${test_root}/pure prefix")
set(clang_prefix "${test_root}/clang prefix")
set(runtime_dir "${test_root}/package runtime")
file(MAKE_DIRECTORY "${source_dir}/tests" "${module_dir}"
  "${pure_prefix}/bin" "${clang_prefix}" "${runtime_dir}")
foreach(interface IN ITEMS GL GL_ARB GL_EXT GL_NV GL_ATI GLU GLUT)
  file(WRITE "${source_dir}/${interface}.pure" "// ${interface} interface fixture\n")
endforeach()
file(COPY_FILE "${FIXTURE}" "${pure_prefix}/bin/pure fixture.exe")
file(COPY_FILE "${FIXTURE}" "${module_dir}/pure-gl.dll")
file(COPY_FILE "${FIXTURE}" "${runtime_dir}/libfreeglut.dll")
file(COPY_FILE "${SOURCE_DIR}/tests/runner_probe.pure"
  "${source_dir}/tests/runner probe.pure")

set(base_args
  "-DPURE_GL_RUNNER=${RUNNER}"
  "-DPURE_EXECUTABLE=${pure_prefix}/bin/pure fixture.exe"
  "-DPURE_GL_SOURCE_DIR=${source_dir}"
  "-DPURE_GL_MODULE=${module_dir}/pure-gl.dll"
  "-DFREEGLUT_RUNTIME_DLL=${runtime_dir}/libfreeglut.dll"
  "-DPURE_GL_PURE_PREFIX=${pure_prefix}"
  "-DPURE_GL_CLANG64_PREFIX=${clang_prefix}"
  "-DPURE_GL_WINDOWS_SYSTEM_DIRECTORY=${PURE_GL_WINDOWS_SYSTEM_DIRECTORY}"
  "-DTEST_SCRIPT=${source_dir}/tests/runner probe.pure"
  -DTEST_WORKING_DIRECTORY=C:/Windows
  -DTIMEOUT_MS=3000)

function(run_adapter expected name)
  execute_process(COMMAND "${CMAKE_COMMAND}" ${ARGN}
    -P "${SOURCE_DIR}/cmake/RunPureTest.cmake"
    RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error TIMEOUT 30)
  set(diagnostics "${output}\n${error}")
  if(expected STREQUAL "PASS")
    if(NOT result EQUAL 0)
      message(FATAL_ERROR "${name} failed: ${diagnostics}")
    endif()
  else()
    if(result EQUAL 0 OR NOT diagnostics MATCHES "${expected}")
      message(FATAL_ERROR
        "${name} did not reject with '${expected}' (${result}): ${diagnostics}")
    endif()
  endif()
  set(last_output "${output}" PARENT_SCOPE)
  set(last_error "${error}" PARENT_SCOPE)
  set(last_result "${result}" PARENT_SCOPE)
endfunction()

foreach(missing IN ITEMS PURE_GL_RUNNER PURE_EXECUTABLE PURE_GL_SOURCE_DIR
    PURE_GL_MODULE FREEGLUT_RUNTIME_DLL PURE_GL_PURE_PREFIX
    PURE_GL_CLANG64_PREFIX PURE_GL_WINDOWS_SYSTEM_DIRECTORY TEST_SCRIPT
    TEST_WORKING_DIRECTORY TIMEOUT_MS)
  set(args ${base_args})
  list(FILTER args EXCLUDE REGEX "^-D${missing}=")
  run_adapter("${missing}.*required" "missing-${missing}" ${args})
endforeach()

set(outer_timeout_args ${base_args})
list(FILTER outer_timeout_args EXCLUDE REGEX "^-DPURE_GL_RUNNER=")
list(FILTER outer_timeout_args EXCLUDE REGEX "^-DTIMEOUT_MS=")
list(APPEND outer_timeout_args "-DPURE_GL_RUNNER=${hanging_runner}"
  -DTIMEOUT_MS=1)
run_adapter("terminated due to timeout" adapter-outer-timeout
  ${outer_timeout_args})

foreach(mode IN ITEMS stderr wrong hang pristine)
  file(WRITE "${source_dir}/tests/${mode}.pure" "${mode}\n")
  set(args ${base_args})
  list(FILTER args EXCLUDE REGEX "^-DTEST_SCRIPT=")
  list(APPEND args "-DTEST_SCRIPT=${source_dir}/tests/${mode}.pure")
  if(mode STREQUAL stderr)
    run_adapter("stderr.*not empty" stderr ${args})
  elseif(mode STREQUAL wrong)
    run_adapter("completion protocol" wrong-token ${args})
  elseif(mode STREQUAL hang)
    list(FILTER args EXCLUDE REGEX "^-DTIMEOUT_MS=")
    list(APPEND args -DTIMEOUT_MS=400)
    run_adapter("deadline exceeded" process-tree-timeout ${args})
    string(REGEX MATCH "DESCENDANT_PID=([0-9]+)" unused
      "${last_output}${last_error}")
    if(NOT CMAKE_MATCH_1)
      message(FATAL_ERROR "Timeout fixture did not report its descendant: ${last_output}${last_error}")
    endif()
    execute_process(
      COMMAND "${PURE_GL_WINDOWS_SYSTEM_DIRECTORY}/WindowsPowerShell/v1.0/powershell.exe"
        -NoProfile -NonInteractive -Command
        "if (Get-Process -Id ${CMAKE_MATCH_1} -ErrorAction SilentlyContinue) { exit 1 }"
      RESULT_VARIABLE alive)
    if(NOT alive EQUAL 0)
      message(FATAL_ERROR "Runner left descendant ${CMAKE_MATCH_1} alive")
    endif()
  else()
    run_adapter(PASS paths-with-spaces ${args})
    set(expected_path
      "${pure_prefix}/bin;${module_dir};${runtime_dir};${PURE_GL_WINDOWS_SYSTEM_DIRECTORY}")
    file(TO_CMAKE_PATH "${expected_path}" expected_path)
    string(REGEX MATCH "EFFECTIVE_PATH=([^\r\n]+)" unused "${last_output}")
    file(TO_CMAKE_PATH "${CMAKE_MATCH_1}" actual_path)
    if(NOT actual_path STREQUAL expected_path)
      message(FATAL_ERROR "Exact PATH mismatch: expected '${expected_path}', got '${actual_path}'")
    endif()
    string(FIND "${actual_path}" "${clang_prefix}" clang_prefix_position)
    if(NOT clang_prefix_position EQUAL -1)
      message(FATAL_ERROR "Exact PATH contains the CLANG64 source prefix: ${actual_path}")
    endif()
    if(NOT last_output MATCHES "EFFECTIVE_CWD=C:\\\\Windows" OR
        NOT last_output MATCHES "EFFECTIVE_PURELIB=UNSET")
      message(FATAL_ERROR "Working directory/PURELIB contract failed: ${last_output}")
    endif()
  endif()
endforeach()

# Exercise the real probe through the same adapter. Its observable output is
# independent of the native fixture and proves that the token reaches Pure.
set(real_args ${base_args})
list(FILTER real_args EXCLUDE REGEX "^-DPURE_EXECUTABLE=")
list(FILTER real_args EXCLUDE REGEX "^-DPURE_GL_PURE_PREFIX=")
list(FILTER real_args EXCLUDE REGEX "^-DTEST_SCRIPT=")
list(APPEND real_args
  "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
  "-DPURE_GL_PURE_PREFIX=${PURE_GL_PURE_PREFIX}"
  "-DTEST_SCRIPT=${SOURCE_DIR}/tests/runner_probe.pure"
  -DTIMEOUT_MS=15000)
run_adapter(PASS real-pure-probe ${real_args})
if(NOT last_output MATCHES "EFFECTIVE_CWD=C:\\\\Windows" OR
    NOT last_output MATCHES "EFFECTIVE_PURELIB=UNSET" OR
    NOT last_output MATCHES "EFFECTIVE_PATH=")
  message(FATAL_ERROR "Real Pure probe omitted environment evidence: ${last_output}")
endif()
string(FIND "${last_output}" "${PURE_GL_CLANG64_PREFIX}" actual_clang_position)
if(NOT actual_clang_position EQUAL -1)
  message(FATAL_ERROR
    "Real Pure probe PATH contains the actual CLANG64 prefix: ${last_output}")
endif()

execute_process(COMMAND "${RUNNER}" --pure "${pure_prefix}/bin/pure fixture.exe"
  --pure "${pure_prefix}/bin/pure fixture.exe"
  --script "${source_dir}/tests/pristine.pure" --timeout-ms 1000
  --cwd C:/Windows --path-entry "${pure_prefix}/bin"
  --include "${source_dir}" --library "${module_dir}"
  --input "${source_dir}/GL.pure"
  RESULT_VARIABLE duplicate_result OUTPUT_VARIABLE duplicate_output
  ERROR_VARIABLE duplicate_error)
if(duplicate_result EQUAL 0 OR
    NOT "${duplicate_output}${duplicate_error}" MATCHES "duplicate --pure")
  message(FATAL_ERROR "Runner accepted duplicate --pure: ${duplicate_output}${duplicate_error}")
endif()

# Pure 0.68 derives its prelude path as UTF-8, then uses narrow CRT stat/fopen.
# On a non-UTF-8 Windows ACP the physical Unicode executable prefix loses the
# prelude. Exercise only an identity-checked 8.3 spelling of that same executable;
# scripts, includes, runtime PATH and protected inputs remain physical paths.
set(unicode_prefix "${test_root}/pure café")
file(MAKE_DIRECTORY "${unicode_prefix}")
file(COPY "${PURE_GL_PURE_PREFIX}/" DESTINATION "${unicode_prefix}")
set(unicode_script "${unicode_prefix}/probe.pure")
file(COPY_FILE "${SOURCE_DIR}/tests/runner_probe.pure" "${unicode_script}")
set(unicode_pure "${unicode_prefix}/bin/pure.exe")
file(SHA256 "${PURE_EXECUTABLE}" original_pure_hash)
file(SHA256 "${unicode_pure}" copied_pure_hash)
if(NOT copied_pure_hash STREQUAL original_pure_hash)
  message(FATAL_ERROR "Unicode probe must use the identical Pure executable")
endif()
file(WRITE "${test_root}/short-path.ps1" [=[
param([string]$Path)
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class GlShortPath {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern uint GetShortPathName(string p, StringBuilder b, uint n);
}
'@
$buffer=[Text.StringBuilder]::new(32768)
$count=[GlShortPath]::GetShortPathName($Path,$buffer,32768)
if ($count -eq 0 -or $count -ge 32768) { throw 'No Windows short path' }
$buffer.ToString()
]=])
execute_process(COMMAND "${PURE_GL_WINDOWS_SYSTEM_DIRECTORY}/WindowsPowerShell/v1.0/powershell.exe"
  -NoProfile -NonInteractive -File "${test_root}/short-path.ps1" -Path "${unicode_pure}"
  RESULT_VARIABLE rc OUTPUT_VARIABLE windows_alias ERROR_VARIABLE err OUTPUT_STRIP_TRAILING_WHITESPACE)
if(NOT rc EQUAL 0 OR windows_alias STREQUAL "")
  message(FATAL_ERROR "Independent Windows short-path query failed: ${err}")
endif()
execute_process(COMMAND "${RUNNER}" --print-pure-executable-alias "${unicode_pure}"
  RESULT_VARIABLE rc OUTPUT_VARIABLE runner_alias ERROR_VARIABLE err OUTPUT_STRIP_TRAILING_WHITESPACE)
file(TO_CMAKE_PATH "${windows_alias}" windows_alias)
file(TO_CMAKE_PATH "${runner_alias}" runner_alias)
if(NOT rc EQUAL 0 OR NOT runner_alias STREQUAL windows_alias)
  message(FATAL_ERROR "Runner did not return the independently verified Windows alias (${rc}): ${runner_alias} ${err}")
endif()
set(unicode_args --pure "${unicode_pure}" --script "${unicode_script}"
  --cwd C:/Windows --timeout-ms 15000 --include "${unicode_prefix}/lib/pure"
  --library "${unicode_prefix}/lib/pure" --input "${unicode_prefix}/lib/pure/prelude.pure"
  --path-entry "${unicode_prefix}/bin" --path-entry "${PURE_GL_WINDOWS_SYSTEM_DIRECTORY}")
execute_process(COMMAND "${RUNNER}" ${unicode_args}
  RESULT_VARIABLE direct_rc OUTPUT_VARIABLE direct_out ERROR_VARIABLE direct_err TIMEOUT 20)
if(direct_rc EQUAL 0)
  message(STATUS "PURE_GL_UNICODE_DIRECT_PREFIX_OK host_crt_supports_unicode=1")
elseif("${direct_err}" MATCHES "stderr was not empty")
  message(STATUS "PURE_GL_UNICODE_PREFIX_LIMITATION Pure-0.68 UTF8-libdir/narrow-CRT mismatch authenticated_rejection=1")
else()
  message(FATAL_ERROR "Unicode prefix control failed outside the known Pure boundary: ${direct_out}${direct_err}")
endif()
foreach(case absent nonascii wrong-identity external)
  if(case STREQUAL absent)
    set(candidate "${windows_alias}.absent")
    set(expected "ASCII executable alias missing")
  elseif(case STREQUAL nonascii)
    set(candidate "${unicode_pure}")
    set(expected "executable alias must be ASCII")
  elseif(case STREQUAL wrong-identity)
    set(candidate "${pure_prefix}/bin/pure fixture.exe")
    set(expected "executable alias physical identity mismatch")
  else()
    set(candidate "${PURE_EXECUTABLE}")
    set(expected "executable alias physical identity mismatch")
  endif()
  execute_process(COMMAND "${RUNNER}" ${unicode_args} --pure-executable-alias "${candidate}"
    RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 20)
  if(rc EQUAL 0 OR NOT "${err}" MATCHES "${expected}" OR out MATCHES "PURE_GL_TEST_OK")
    message(FATAL_ERROR "Unsafe executable alias escaped: ${case} (${rc}) ${out}${err}")
  endif()
  message(STATUS "PURE_GL_EXECUTABLE_ALIAS_REJECT_OK ${case}")
endforeach()
execute_process(COMMAND "${RUNNER}" ${unicode_args} --pure-executable-alias "${windows_alias}"
  RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 20)
if(NOT rc EQUAL 0 OR NOT err STREQUAL "" OR
    NOT out MATCHES "PURE_GL_EXECUTABLE_ALIAS_OK physical_identity=1 ascii=1" OR
    NOT out MATCHES "EFFECTIVE_PURELIB=UNSET" OR NOT out MATCHES "PURE_GL_TEST_OK")
  message(FATAL_ERROR "Verified alias failed to run the same physical Unicode prefix: ${out}${err}")
endif()
file(SHA256 "${unicode_pure}" after_pure_hash)
if(NOT after_pure_hash STREQUAL copied_pure_hash)
  message(FATAL_ERROR "Executable alias changed physical Pure bytes")
endif()
message(STATUS "PURE_GL_EXECUTABLE_ALIAS_CONTRACT_OK negatives=4 physical_unicode_stage=1 identical_bytes=1")
message(STATUS "PURE_GL_RUNNER_CONTRACT_OK")
gl_audit_clean(runner-contract)
