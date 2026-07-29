foreach(required IN ITEMS
    BUILD_ROOT TEST_ROOT PURE_BASE_PREFIX PURE_LV2_MODULE PURE_LV2_SOURCE_DIR
    PURE_LILV_MODULE PURE_LILV_SOURCE LILV_DLL SERD_DLL SORD_DLL SRATOM_DLL
    ZIX_DLL PURE2LV2_CC PURE2LV2_TOOL_DIR PURE2LV2_LV2_INCLUDE
    POWERSHELL_EXECUTABLE LLVM_READOBJ)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH BUILD_ROOT NORMALIZE OUTPUT_VARIABLE build_root)
cmake_path(ABSOLUTE_PATH TEST_ROOT NORMALIZE OUTPUT_VARIABLE test_root)
cmake_path(IS_PREFIX build_root "${test_root}" NORMALIZE test_is_in_build)
if(NOT test_is_in_build OR test_root STREQUAL build_root)
  message(FATAL_ERROR "TEST_ROOT must be a child of BUILD_ROOT")
endif()

set(prefix "${test_root}/Pure LV2 Integration Prefix")
set(module_dir "${prefix}/lib/pure")
set(bundle_root "${test_root}/Generated LV2 Bundles")
file(REMOVE_RECURSE "${test_root}")
file(MAKE_DIRECTORY "${test_root}")
file(COPY "${PURE_BASE_PREFIX}/" DESTINATION "${prefix}")
file(MAKE_DIRECTORY "${module_dir}" "${prefix}/bin")

file(COPY
  "${PURE_LV2_MODULE}"
  "${PURE_LV2_SOURCE_DIR}/lv2.pure"
  "${PURE_LV2_SOURCE_DIR}/lv2pure.c"
  "${PURE_LV2_SOURCE_DIR}/lv2pure.h"
  "${PURE_LV2_SOURCE_DIR}/lv2-manifest-template.ttl"
  DESTINATION "${module_dir}")
file(COPY
  "${PURE_LV2_SOURCE_DIR}/pure2lv2.cmd"
  "${PURE_LV2_SOURCE_DIR}/pure2lv2.ps1"
  DESTINATION "${prefix}/bin")
file(COPY "${PURE_LILV_MODULE}" DESTINATION "${module_dir}")
file(COPY "${PURE_LILV_SOURCE}" DESTINATION "${module_dir}")
file(COPY
  "${LILV_DLL}" "${SERD_DLL}" "${SORD_DLL}" "${SRATOM_DLL}" "${ZIX_DLL}"
  DESTINATION "${prefix}/bin")

set(ENV{PURE2LV2_PREFIX} "${prefix}")
set(ENV{PURE2LV2_CC} "${PURE2LV2_CC}")
set(ENV{PURE2LV2_TOOL_DIR} "${PURE2LV2_TOOL_DIR}")
set(ENV{PURE2LV2_LV2_INCLUDE} "${PURE2LV2_LV2_INCLUDE}")
set(ENV{PATH} "${prefix}/bin;C:/Windows/System32;C:/Windows")
unset(ENV{PURELIB})
unset(ENV{LV2_PATH})

function(generate_bundle mode output uri)
  set(mode_args)
  if(mode STREQUAL "source")
    list(APPEND mode_args -s)
  endif()
  execute_process(
    COMMAND "${POWERSHELL_EXECUTABLE}"
      -NoProfile -ExecutionPolicy Bypass
      -File "${prefix}/bin/pure2lv2.ps1"
      ${mode_args}
      -o "${bundle_root}/${output}.lv2"
      -u "${uri}"
      "${PURE_LV2_SOURCE_DIR}/examples/pure_amp.pure"
    WORKING_DIRECTORY "${test_root}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output_text
    ERROR_VARIABLE error_text
    TIMEOUT 60
    ENCODING UTF-8)
  if(NOT "${result}" STREQUAL "0")
    message(FATAL_ERROR
      "${mode} pure2lv2 generation failed (${result})\n"
      "stdout:\n${output_text}\nstderr:\n${error_text}")
  endif()
endfunction()

generate_bundle(batch batch-gain "urn:pure-lang:test")
generate_bundle(source source-gain "urn:pure-lang:source-test")

set(batch_dll "${bundle_root}/batch-gain.lv2/pure_amp.dll")
set(source_dll "${bundle_root}/source-gain.lv2/pure_amp.dll")
foreach(expected IN ITEMS
    "${batch_dll}"
    "${bundle_root}/batch-gain.lv2/manifest.ttl"
    "${source_dll}"
    "${bundle_root}/source-gain.lv2/manifest.ttl"
    "${bundle_root}/source-gain.lv2/pure_amp.pure")
  if(NOT EXISTS "${expected}")
    message(FATAL_ERROR "Generated LV2 bundle file is missing: ${expected}")
  endif()
endforeach()
if(EXISTS "${bundle_root}/batch-gain.lv2/pure_amp.pure")
  message(FATAL_ERROR "Batch-generated bundle unexpectedly contains source")
endif()

unset(ENV{PURE2LV2_PREFIX})
unset(ENV{PURE2LV2_CC})
unset(ENV{PURE2LV2_TOOL_DIR})
unset(ENV{PURE2LV2_LV2_INCLUDE})
unset(ENV{PURELIB})
unset(ENV{LV2_PATH})
set(ENV{PATH} "${module_dir};${prefix}/bin;C:/Windows/System32;C:/Windows")
execute_process(
  COMMAND "${prefix}/bin/pure.exe" --norc -q
    -I "${module_dir}"
    -L "${module_dir}"
    -x "${PURE_LV2_SOURCE_DIR}/tests/host.pure"
    "${bundle_root}"
  WORKING_DIRECTORY "C:/Windows"
  RESULT_VARIABLE host_result
  OUTPUT_VARIABLE host_output
  ERROR_VARIABLE host_error
  TIMEOUT 45
  ENCODING UTF-8)
if(NOT "${host_result}" STREQUAL "0")
  message(FATAL_ERROR
    "Generated plugin host test failed (${host_result})\n"
    "stdout:\n${host_output}\nstderr:\n${host_error}")
endif()
if(NOT host_output MATCHES "(^|\r?\n)PURE_LV2_HOST_OK(\r?\n|$)")
  message(FATAL_ERROR
    "Generated plugin host test did not emit its success marker\n"
    "stdout:\n${host_output}\nstderr:\n${host_error}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    "-DPURE_LV2_MODULE=${module_dir}/lv2.dll"
    "-DBATCH_PLUGIN=${batch_dll}"
    "-DSOURCE_PLUGIN=${source_dll}"
    -P "${PURE_LV2_SOURCE_DIR}/cmake/VerifyGeneratedPlugins.cmake"
  RESULT_VARIABLE audit_result
  OUTPUT_VARIABLE audit_output
  ERROR_VARIABLE audit_error
  ENCODING UTF-8)
if(NOT "${audit_result}" STREQUAL "0")
  message(FATAL_ERROR
    "Generated plugin PE audit failed (${audit_result})\n"
    "stdout:\n${audit_output}\nstderr:\n${audit_error}")
endif()

message(STATUS
  "Verified native batch/source generation, Dynamic Manifest discovery, "
  "audio processing, source-relative loading, lifecycle, and PE imports")
