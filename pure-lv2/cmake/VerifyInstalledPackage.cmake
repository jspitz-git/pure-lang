foreach(required IN ITEMS
    STAGE_PREFIX SOURCE_RUNTIME_DIR PURE2LV2_CC PURE2LV2_TOOL_DIR
    LLVM_READOBJ)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE stage)
cmake_path(
  ABSOLUTE_PATH SOURCE_RUNTIME_DIR NORMALIZE OUTPUT_VARIABLE source_bin)
set(module_dir "${stage}/lib/pure")
set(doc_dir "${stage}/share/doc/pure-lv2")
set(test_dir "${doc_dir}/tests")
set(expected_files
  "${stage}/bin/pure.exe"
  "${stage}/bin/libpure.dll"
  "${stage}/bin/liblilv-0.dll"
  "${stage}/bin/pure2lv2"
  "${stage}/bin/pure2lv2.cmd"
  "${stage}/bin/pure2lv2.ps1"
  "${module_dir}/lv2.dll"
  "${module_dir}/lv2.pure"
  "${module_dir}/lv2pure.c"
  "${module_dir}/lv2pure.h"
  "${module_dir}/lv2-manifest-template.ttl"
  "${module_dir}/lilv.dll"
  "${module_dir}/lilv.pure"
  "${stage}/include/pure/runtime.h"
  "${stage}/include/lv2/lv2plug.in/ns/lv2core/lv2.h"
  "${doc_dir}/README"
  "${doc_dir}/COPYING"
  "${doc_dir}/WINDOWS.md"
  "${doc_dir}/licenses/lv2/COPYING"
  "${doc_dir}/examples/pure_amp.pure"
  "${doc_dir}/examples/pure_metro.pure"
  "${doc_dir}/examples/pure_transp.pure"
  "${test_dir}/host.pure"
  "${test_dir}/VerifyGeneratedPlugins.cmake")
foreach(expected IN LISTS expected_files)
  if(NOT EXISTS "${expected}")
    message(FATAL_ERROR "Missing installed pure-lv2 file: ${expected}")
  endif()
endforeach()

foreach(reused IN ITEMS
    libpure.dll libgmp-10.dll libc++.dll libwinpthread-1.dll)
  set(staged_file "${stage}/bin/${reused}")
  set(source_file "${source_bin}/${reused}")
  if(NOT EXISTS "${staged_file}" OR NOT EXISTS "${source_file}")
    message(FATAL_ERROR "Missing reused runtime: ${reused}")
  endif()
  file(SHA256 "${staged_file}" staged_hash)
  file(SHA256 "${source_file}" source_hash)
  if(NOT staged_hash STREQUAL source_hash)
    message(FATAL_ERROR "Conflicting reused runtime: ${reused}")
  endif()
endforeach()

set(work_dir "${stage}/Pure LV2 Verification")
set(bundle_root "${work_dir}/Generated LV2 Bundles")
file(REMOVE_RECURSE "${work_dir}")
file(MAKE_DIRECTORY "${work_dir}")
set(ENV{PURE2LV2_CC} "${PURE2LV2_CC}")
set(ENV{PURE2LV2_TOOL_DIR} "${PURE2LV2_TOOL_DIR}")
unset(ENV{PURE2LV2_PREFIX})
unset(ENV{PURE2LV2_LV2_INCLUDE})
unset(ENV{PURELIB})
unset(ENV{LV2_PATH})
set(ENV{PATH} "${stage}/bin;C:/Windows/System32;C:/Windows")
set(powershell
  "$ENV{SystemRoot}/System32/WindowsPowerShell/v1.0/powershell.exe")

function(generate_bundle mode output uri)
  set(mode_args)
  if(mode STREQUAL "source")
    list(APPEND mode_args -s)
  endif()
  execute_process(
    COMMAND "${powershell}"
      -NoProfile -ExecutionPolicy Bypass
      -File "${stage}/bin/pure2lv2.ps1"
      ${mode_args}
      -o "${bundle_root}/${output}.lv2"
      -u "${uri}"
      "${doc_dir}/examples/pure_amp.pure"
    WORKING_DIRECTORY "${work_dir}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output_text
    ERROR_VARIABLE error_text
    TIMEOUT 60
    ENCODING UTF-8)
  if(NOT "${result}" STREQUAL "0")
    message(FATAL_ERROR
      "${mode} installed pure2lv2 generation failed (${result})\n"
      "stdout:\n${output_text}\nstderr:\n${error_text}")
  endif()
endfunction()

generate_bundle(batch batch-gain "urn:pure-lang:test")
generate_bundle(source source-gain "urn:pure-lang:source-test")
set(batch_dll "${bundle_root}/batch-gain.lv2/pure_amp.dll")
set(source_dll "${bundle_root}/source-gain.lv2/pure_amp.dll")

unset(ENV{PURE2LV2_CC})
unset(ENV{PURE2LV2_TOOL_DIR})
unset(ENV{PURELIB})
unset(ENV{LV2_PATH})
set(ENV{PATH} "${module_dir};${stage}/bin;C:/Windows/System32;C:/Windows")
execute_process(
  COMMAND "${stage}/bin/pure.exe" --norc -q
    -I "${module_dir}"
    -L "${module_dir}"
    -x "${test_dir}/host.pure"
    "${bundle_root}"
  WORKING_DIRECTORY "C:/Windows"
  RESULT_VARIABLE host_result
  OUTPUT_VARIABLE host_output
  ERROR_VARIABLE host_error
  TIMEOUT 45
  ENCODING UTF-8)
if(NOT "${host_result}" STREQUAL "0")
  message(FATAL_ERROR
    "Installed Pure LV2 host test failed (${host_result})\n"
    "stdout:\n${host_output}\nstderr:\n${host_error}")
endif()
if(NOT host_output MATCHES "(^|\r?\n)PURE_LV2_HOST_OK(\r?\n|$)")
  message(FATAL_ERROR
    "Installed Pure LV2 host test did not emit its success marker\n"
    "stdout:\n${host_output}\nstderr:\n${host_error}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    "-DPURE_LV2_MODULE=${module_dir}/lv2.dll"
    "-DBATCH_PLUGIN=${batch_dll}"
    "-DSOURCE_PLUGIN=${source_dll}"
    -P "${test_dir}/VerifyGeneratedPlugins.cmake"
  RESULT_VARIABLE audit_result
  OUTPUT_VARIABLE audit_output
  ERROR_VARIABLE audit_error
  ENCODING UTF-8)
if(NOT "${audit_result}" STREQUAL "0")
  message(FATAL_ERROR
    "Installed Pure LV2 PE audit failed (${audit_result})\n"
    "stdout:\n${audit_output}\nstderr:\n${audit_error}")
endif()

file(REMOVE_RECURSE "${work_dir}")
list(LENGTH expected_files expected_count)
message(STATUS
  "Verified installed pure-lv2: ${expected_count} package files, "
  "4 hash-matched reused DLLs, relocated native batch/source generation, "
  "Dynamic Manifest discovery, processing, lifecycle, and PE closure")
