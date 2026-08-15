foreach(required IN ITEMS
    POWERSHELL_EXECUTABLE HELPER_SOURCE DRIVER_SOURCE TEST_ROOT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

function(require_result actual expected label)
  if(NOT actual EQUAL expected)
    message(FATAL_ERROR "${label}: expected result ${expected}, got ${actual}")
  endif()
endfunction()

function(require_contains text expected label)
  string(FIND "${text}" "${expected}" match)
  if(match EQUAL -1)
    message(FATAL_ERROR "${label}: missing '${expected}'\n${text}")
  endif()
endfunction()

function(run_helper layout input output result_var transcript_var)
  execute_process(
    COMMAND "${POWERSHELL_EXECUTABLE}" -NoProfile -ExecutionPolicy Bypass
      -File "${layout}/tools/faust2pure.ps1"
      -InputPath "${input}" -OutputPath "${output}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output_text
    ERROR_VARIABLE error_text
    ENCODING UTF-8)
  set(${result_var} "${result}" PARENT_SCOPE)
  set(${transcript_var} "${output_text}\n${error_text}" PARENT_SCOPE)
endfunction()

function(create_layout layout)
  file(MAKE_DIRECTORY "${layout}/tools" "${layout}/cmake" "${layout}/bin"
    "${layout}/share/pure-faust")
  file(COPY_FILE "${HELPER_SOURCE}" "${layout}/tools/faust2pure.ps1")
  file(COPY_FILE "${DRIVER_SOURCE}" "${layout}/cmake/RunFaust2Pure.cmake")
endfunction()

file(REMOVE_RECURSE "${TEST_ROOT}")
file(MAKE_DIRECTORY "${TEST_ROOT}")

# A missing Faust executable must diagnose a missing developer component.
set(missing_faust_layout "${TEST_ROOT}/missing faust")
create_layout("${missing_faust_layout}")
file(WRITE "${missing_faust_layout}/share/pure-faust/pure.c" "architecture")
file(WRITE "${missing_faust_layout}/bin/clang.exe" "placeholder")
file(WRITE "${missing_faust_layout}/bin/opt.exe" "placeholder")
file(WRITE "${missing_faust_layout}/input.dsp" "process = _;")
run_helper("${missing_faust_layout}" "${missing_faust_layout}/input.dsp"
  "${missing_faust_layout}/output.bc" helper_result helper_transcript)
if(helper_result EQUAL 0)
  message(FATAL_ERROR "Missing Faust executable unexpectedly succeeded")
endif()
require_contains("${helper_transcript}"
  "Faust developer component is not installed" "missing Faust")

# Layout validation must name the missing architecture file.
set(missing_arch_layout "${TEST_ROOT}/missing pure c")
create_layout("${missing_arch_layout}")
file(WRITE "${missing_arch_layout}/bin/faust.exe" "placeholder")
file(WRITE "${missing_arch_layout}/bin/clang.exe" "placeholder")
file(WRITE "${missing_arch_layout}/bin/opt.exe" "placeholder")
file(WRITE "${missing_arch_layout}/input.dsp" "process = _;")
run_helper("${missing_arch_layout}" "${missing_arch_layout}/input.dsp"
  "${missing_arch_layout}/output.bc" helper_result helper_transcript)
if(helper_result EQUAL 0)
  message(FATAL_ERROR "Missing pure.c unexpectedly succeeded")
endif()
require_contains("${helper_transcript}" "pure.c" "missing pure.c")

# These fakes exercise the real CMake driver without Faust, Clang, or opt.
set(fake_root "${TEST_ROOT}/fake tools")
file(MAKE_DIRECTORY "${fake_root}")
set(fake_source "${fake_root}/fake-tool.cs")
set(fake_builder "${fake_root}/build-fake-tool.ps1")
set(fake_executable "${fake_root}/fake-tool.exe")
file(WRITE "${fake_source}" [=[using System;
using System.Diagnostics;
using System.IO;

class FakeTool {
  static void Require(bool condition, int code) {
    if (!condition) Environment.Exit(code);
  }

  static void RequireName(string path, string expected, int code) {
    Require(String.Equals(Path.GetFileName(path), expected,
      StringComparison.OrdinalIgnoreCase), code);
  }

  static void Log(string marker) {
    File.AppendAllText(Environment.GetEnvironmentVariable("FAKE_LOG"),
      marker + Environment.NewLine);
  }

  static void Main(string[] args) {
    string tool = Path.GetFileNameWithoutExtension(
      Process.GetCurrentProcess().MainModule.FileName).ToLowerInvariant();
    if (tool == "faust") {
      Require(args.Length == 7, 11);
      Require(args[0] == "-lang" && args[1] == "c" && args[2] == "-a", 12);
      Require(args[3] == Environment.GetEnvironmentVariable("FAKE_EXPECTED_PURE"), 13);
      Require(args[4] == Environment.GetEnvironmentVariable("FAKE_EXPECTED_INPUT"), 14);
      Require(args[5] == "-o", 15);
      RequireName(args[6], "reference.c", 16);
      File.WriteAllText(args[6], "fake C source\n");
      Log("faust-ok");
      return;
    }
    if (tool == "clang") {
      Require(args.Length == 6, 21);
      Require(args[0] == "-emit-llvm" && args[1] == "-O3" && args[2] == "-c", 22);
      RequireName(args[3], "reference.c", 23);
      Require(args[4] == "-o", 24);
      RequireName(args[5], "reference.bc", 25);
      File.WriteAllText(args[5], "fake bitcode\n");
      Log("clang-ok");
      return;
    }
    if (tool == "opt") {
      Require(args.Length == 3, 31);
      Require(args[0] == "-passes=verify" && args[1] == "-disable-output", 32);
      RequireName(args[2], "reference.bc", 33);
      Log("verify-ok");
      if (Environment.GetEnvironmentVariable("FAKE_VERIFY_FAIL") == "1") {
        Environment.Exit(34);
      }
      return;
    }
    Environment.Exit(90);
  }
}
]=])
file(WRITE "${fake_builder}" [=[param([string]$Source, [string]$Output)
Add-Type -TypeDefinition (Get-Content -LiteralPath $Source -Raw) -OutputType ConsoleApplication -OutputAssembly $Output -ErrorAction Stop
]=])
execute_process(
  COMMAND "${POWERSHELL_EXECUTABLE}" -NoProfile -ExecutionPolicy Bypass
    -File "${fake_builder}" -Source "${fake_source}" -Output "${fake_executable}"
  RESULT_VARIABLE fake_build_result
  OUTPUT_VARIABLE fake_build_output
  ERROR_VARIABLE fake_build_error
  ENCODING UTF-8)
require_result("${fake_build_result}" 0 "fake tool build")
foreach(tool IN ITEMS faust clang opt)
  file(COPY_FILE "${fake_executable}" "${fake_root}/${tool}.exe")
endforeach()
set(fake_faust "${fake_root}/faust.exe")
set(fake_clang "${fake_root}/clang.exe")
set(fake_opt "${fake_root}/opt.exe")

set(spaced_root "${TEST_ROOT}/paths with spaces")
file(MAKE_DIRECTORY "${spaced_root}")
set(spaced_input "${spaced_root}/input with spaces.dsp")
set(spaced_pure "${spaced_root}/pure architecture.c")
set(spaced_output "${spaced_root}/output with spaces.bc")
set(fake_log "${spaced_root}/fake log.txt")
file(WRITE "${spaced_input}" "process = _;")
file(WRITE "${spaced_pure}" "architecture")
set(ENV{FAKE_EXPECTED_INPUT} "${spaced_input}")
set(ENV{FAKE_EXPECTED_PURE} "${spaced_pure}")
set(ENV{FAKE_LOG} "${fake_log}")
set(ENV{FAKE_VERIFY_FAIL} "1")
file(WRITE "${spaced_output}" "sentinel output\n")
file(READ "${spaced_output}" sentinel_before HEX)
execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DINPUT_PATH=${spaced_input}"
    "-DOUTPUT_PATH=${spaced_output}"
    "-DFAUST_EXECUTABLE=${fake_faust}"
    "-DPURE_ARCHITECTURE=${spaced_pure}"
    "-DCLANG_EXECUTABLE=${fake_clang}"
    "-DOPT_EXECUTABLE=${fake_opt}"
    -P "${DRIVER_SOURCE}"
  RESULT_VARIABLE driver_result
  OUTPUT_VARIABLE driver_output
  ERROR_VARIABLE driver_error
  ENCODING UTF-8)
if(driver_result EQUAL 0)
  message(FATAL_ERROR "Fake verifier failure unexpectedly succeeded")
endif()
require_contains("${driver_output}\n${driver_error}" "verify" "verifier stage")
file(READ "${spaced_output}" sentinel_after HEX)
if(NOT sentinel_after STREQUAL sentinel_before)
  message(FATAL_ERROR "Verifier failure changed the destination")
endif()

set(ENV{FAKE_VERIFY_FAIL} "0")
execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DINPUT_PATH=${spaced_input}"
    "-DOUTPUT_PATH=${spaced_output}"
    "-DFAUST_EXECUTABLE=${fake_faust}"
    "-DPURE_ARCHITECTURE=${spaced_pure}"
    "-DCLANG_EXECUTABLE=${fake_clang}"
    "-DOPT_EXECUTABLE=${fake_opt}"
    -P "${DRIVER_SOURCE}"
  RESULT_VARIABLE driver_result
  OUTPUT_VARIABLE driver_output
  ERROR_VARIABLE driver_error
  ENCODING UTF-8)
if(NOT driver_result EQUAL 0)
  message(FATAL_ERROR
    "quoted fake tools failed (${driver_result})\n"
    "stdout:\n${driver_output}\nstderr:\n${driver_error}")
endif()
file(READ "${spaced_output}" output_contents)
if(NOT output_contents STREQUAL "fake bitcode\n")
  message(FATAL_ERROR "Unexpected published bitcode: '${output_contents}'")
endif()
file(READ "${fake_log}" fake_log_contents)
foreach(marker IN ITEMS faust-ok clang-ok verify-ok)
  require_contains("${fake_log_contents}" "${marker}" "quoted fake tools")
endforeach()

message(STATUS "Faust helper failure-safety tests passed")
