foreach(required IN ITEMS STAGE_PREFIX SOURCE_RUNTIME_DIR LLVM_READOBJ)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE stage)
cmake_path(ABSOLUTE_PATH SOURCE_RUNTIME_DIR NORMALIZE OUTPUT_VARIABLE source_bin)
set(module_dir "${stage}/lib/pure")
set(doc_dir "${stage}/share/doc/pure-liblo")

set(expected_files
  "${module_dir}/lo.dll"
  "${module_dir}/lo.pure"
  "${module_dir}/osc.pure"
  "${stage}/bin/liblo.dll"
  "${doc_dir}/README"
  "${doc_dir}/COPYING"
  "${doc_dir}/COPYING.LESSER"
  "${doc_dir}/WINDOWS.md"
  "${doc_dir}/liblo-COPYING"
  "${doc_dir}/examples/client.pure"
  "${doc_dir}/examples/osc_example.pure"
  "${doc_dir}/examples/sc3test.pure"
  "${doc_dir}/examples/server.pure"
  "${doc_dir}/tests/loopback.pure"
)
foreach(expected IN LISTS expected_files)
  if(NOT EXISTS "${expected}")
    message(FATAL_ERROR "Missing installed pure-liblo file: ${expected}")
  endif()
endforeach()

foreach(reused IN ITEMS libpure.dll libgmp-10.dll)
  set(staged_file "${stage}/bin/${reused}")
  set(source_file "${source_bin}/${reused}")
  if(NOT EXISTS "${staged_file}" OR NOT EXISTS "${source_file}")
    message(FATAL_ERROR "Missing reused dependency ${reused}")
  endif()
  file(SHA256 "${staged_file}" staged_hash)
  file(SHA256 "${source_file}" source_hash)
  if(NOT staged_hash STREQUAL source_hash)
    message(FATAL_ERROR
      "Conflicting staged ${reused}: ${staged_hash} != ${source_hash}")
  endif()
endforeach()

set(ENV{PATH} "${stage}/bin;C:/Windows/System32;C:/Windows")
set(ENV{PURELIB} "")
execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DPURE_EXECUTABLE=${stage}/bin/pure.exe"
    "-DPURE_SOURCE_DIR=${module_dir}"
    "-DMODULE_DIR=${module_dir}"
    "-DLIBLO_RUNTIME_DIR=${stage}/bin"
    "-DPURE_RUNTIME_DIR=${stage}/bin"
    "-DTEST_SCRIPT=${doc_dir}/tests/loopback.pure"
    -P "${CMAKE_CURRENT_LIST_DIR}/RunPureTest.cmake"
  WORKING_DIRECTORY "C:/Windows"
  RESULT_VARIABLE test_result
  OUTPUT_VARIABLE test_output
  ERROR_VARIABLE test_error
  ENCODING UTF-8
)
if(NOT test_result EQUAL 0)
  message(FATAL_ERROR
    "Installed pure-liblo loopback test failed (${test_result})\n"
    "stdout:\n${test_output}\nstderr:\n${test_error}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    "-DPURE_LIBLO_MODULE=${module_dir}/lo.dll"
    "-DLIBLO_DLL=${stage}/bin/liblo.dll"
    -P "${CMAKE_CURRENT_LIST_DIR}/VerifyWindowsDependencies.cmake"
  RESULT_VARIABLE audit_result
  OUTPUT_VARIABLE audit_output
  ERROR_VARIABLE audit_error
  ENCODING UTF-8
)
if(NOT audit_result EQUAL 0)
  message(FATAL_ERROR
    "Installed pure-liblo PE audit failed (${audit_result})\n"
    "stdout:\n${audit_output}\nstderr:\n${audit_error}")
endif()

list(LENGTH expected_files expected_count)
message(STATUS
  "Verified installed pure-liblo: ${expected_count} package files, reused "
  "Pure/GMP runtimes, sanitized loopback test, and staged PE closure")
