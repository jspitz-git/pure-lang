foreach(required IN ITEMS STAGE_PREFIX SOURCE_RUNTIME_DIR LLVM_READOBJ)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE stage)
cmake_path(
  ABSOLUTE_PATH SOURCE_RUNTIME_DIR NORMALIZE OUTPUT_VARIABLE source_bin)
set(module_dir "${stage}/lib/pure")
set(doc_dir "${stage}/share/doc/pure-lilv")
set(test_root "${doc_dir}/tests/lv2")

set(runtime_files
  liblilv-0.dll
  libserd-0.dll
  libsord-0.dll
  libsratom-0.dll
  libzix-0.dll)
set(expected_files
  "${stage}/bin/pure.exe"
  "${stage}/bin/libpure.dll"
  "${module_dir}/lilv.dll"
  "${module_dir}/lilv.pure"
  "${doc_dir}/README"
  "${doc_dir}/COPYING"
  "${doc_dir}/WINDOWS.md"
  "${doc_dir}/examples/lilv_examp.pure"
  "${doc_dir}/examples/prelude3.mid"
  "${doc_dir}/examples/synth.pure"
  "${doc_dir}/tests/smoke.pure"
  "${test_root}/static-gain.lv2/manifest.ttl"
  "${test_root}/static-gain.lv2/gain.ttl"
  "${test_root}/static-gain.lv2/static-gain.dll"
  "${test_root}/dynamic-gain.lv2/manifest.ttl"
  "${test_root}/dynamic-gain.lv2/dynamic-gain.dll")
foreach(name IN LISTS runtime_files)
  list(APPEND expected_files "${stage}/bin/${name}")
endforeach()
foreach(package IN ITEMS lilv lv2 serd sord sratom zix)
  list(APPEND expected_files "${doc_dir}/licenses/${package}/COPYING")
endforeach()
foreach(expected IN LISTS expected_files)
  if(NOT EXISTS "${expected}")
    message(FATAL_ERROR "Missing installed pure-lilv file: ${expected}")
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

file(GLOB lv2_bundles LIST_DIRECTORIES TRUE "${stage}/lib/lv2/*.lv2")
file(GLOB_RECURSE lv2_files LIST_DIRECTORIES FALSE "${stage}/lib/lv2/*")
list(LENGTH lv2_bundles lv2_bundle_count)
list(LENGTH lv2_files lv2_file_count)
if(NOT lv2_bundle_count EQUAL 25 OR NOT lv2_file_count EQUAL 82)
  message(FATAL_ERROR
    "Unexpected LV2 specification inventory: "
    "${lv2_bundle_count} bundles, ${lv2_file_count} files")
endif()

file(GLOB license_directories LIST_DIRECTORIES TRUE "${doc_dir}/licenses/*")
list(LENGTH license_directories license_count)
if(NOT license_count EQUAL 6)
  message(FATAL_ERROR
    "Unexpected pure-lilv license inventory: ${license_count} directories")
endif()

set(work_dir "${stage}/Pure Lilv Verification")
set(empty_lv2_root "${work_dir}/empty-lv2")
set(preset_root "${work_dir}/presets")
file(REMOVE_RECURSE "${work_dir}")
file(MAKE_DIRECTORY "${empty_lv2_root}" "${preset_root}")
unset(ENV{PURELIB})
unset(ENV{LV2_PATH})
set(ENV{PATH} "${stage}/bin;C:/Windows/System32;C:/Windows")

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DPURE_EXECUTABLE=${stage}/bin/pure.exe"
    "-DPURE_SOURCE_DIR=${module_dir}"
    "-DMODULE_DIR=${module_dir}"
    "-DPURE_RUNTIME_DIR=${stage}/bin"
    "-DLILV_RUNTIME_DIR=${stage}/bin"
    "-DDEPENDENCY_RUNTIME_DIR=${stage}/bin"
    "-DEMPTY_LV2_ROOT=${empty_lv2_root}"
    "-DTEST_LV2_ROOT=${test_root}"
    "-DPRESET_ROOT=${preset_root}"
    "-DTEST_SCRIPT=${doc_dir}/tests/smoke.pure"
    -P "${CMAKE_CURRENT_LIST_DIR}/RunSmokeTest.cmake"
  WORKING_DIRECTORY "${preset_root}"
  RESULT_VARIABLE test_result
  OUTPUT_VARIABLE test_output
  ERROR_VARIABLE test_error
  TIMEOUT 60
  ENCODING UTF-8)
file(REMOVE_RECURSE "${work_dir}")
if(NOT test_result EQUAL 0)
  message(FATAL_ERROR
    "Installed pure-lilv smoke test failed (${test_result})\n"
    "stdout:\n${test_output}\nstderr:\n${test_error}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    "-DPURE_LILV_MODULE=${module_dir}/lilv.dll"
    "-DLILV_DLL=${stage}/bin/liblilv-0.dll"
    "-DSERD_DLL=${stage}/bin/libserd-0.dll"
    "-DSORD_DLL=${stage}/bin/libsord-0.dll"
    "-DSRATOM_DLL=${stage}/bin/libsratom-0.dll"
    "-DZIX_DLL=${stage}/bin/libzix-0.dll"
    -P "${CMAKE_CURRENT_LIST_DIR}/VerifyWindowsDependencies.cmake"
  RESULT_VARIABLE audit_result
  OUTPUT_VARIABLE audit_output
  ERROR_VARIABLE audit_error
  ENCODING UTF-8)
if(NOT audit_result EQUAL 0)
  message(FATAL_ERROR
    "Installed pure-lilv PE audit failed (${audit_result})\n"
    "stdout:\n${audit_output}\nstderr:\n${audit_error}")
endif()

list(LENGTH expected_files expected_count)
list(LENGTH runtime_files runtime_count)
message(STATUS
  "Verified installed pure-lilv: ${expected_count} package files, "
  "${runtime_count} new DLLs, ${lv2_bundle_count} LV2 specification bundles, "
  "${license_count} license directories, 4 hash-matched reused DLLs, "
  "sanitized static/Dynamic Manifest smoke test, and staged PE closure")
