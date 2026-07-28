foreach(required IN ITEMS STAGE_PREFIX SOURCE_RUNTIME_DIR LLVM_READOBJ)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE stage)
cmake_path(ABSOLUTE_PATH SOURCE_RUNTIME_DIR NORMALIZE OUTPUT_VARIABLE source_bin)
set(module_dir "${stage}/lib/pure")
set(doc_dir "${stage}/share/doc/pure-glpk")

set(expected_files
  "${module_dir}/glpk.dll"
  "${module_dir}/glpk.pure"
  "${stage}/bin/libglpk-40.dll"
  "${stage}/bin/libcolamd.dll"
  "${stage}/bin/libamd.dll"
  "${stage}/bin/libsuitesparseconfig.dll"
  "${stage}/bin/libomp.dll"
  "${doc_dir}/README"
  "${doc_dir}/COPYING"
  "${doc_dir}/WINDOWS.md"
  "${doc_dir}/glpk-LICENSE"
  "${doc_dir}/suitesparse-LICENSE"
  "${doc_dir}/llvm-openmp-LICENSE"
  "${doc_dir}/examples/lp.pure"
  "${doc_dir}/tests/smoke.pure"
)
foreach(expected IN LISTS expected_files)
  if(NOT EXISTS "${expected}")
    message(FATAL_ERROR "Missing installed pure-glpk file: ${expected}")
  endif()
endforeach()

foreach(reused IN ITEMS libgmp-10.dll zlib1.dll)
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
  COMMAND "${stage}/bin/pure.exe" --norc
    -I "${module_dir}"
    -L "${module_dir}"
    -x "${doc_dir}/tests/smoke.pure"
  WORKING_DIRECTORY "C:/Windows"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
  ENCODING UTF-8
)
if(NOT result EQUAL 0)
  message(FATAL_ERROR
    "Installed pure-glpk smoke test failed (${result})\n"
    "stdout:\n${output}\nstderr:\n${error}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    "-DGLPK_MODULE=${module_dir}/glpk.dll"
    "-DGLPK_DLL=${stage}/bin/libglpk-40.dll"
    "-DCOLAMD_DLL=${stage}/bin/libcolamd.dll"
    "-DAMD_DLL=${stage}/bin/libamd.dll"
    "-DSUITESPARSECONFIG_DLL=${stage}/bin/libsuitesparseconfig.dll"
    "-DOMP_DLL=${stage}/bin/libomp.dll"
    "-DGMP_DLL=${stage}/bin/libgmp-10.dll"
    "-DZLIB_DLL=${stage}/bin/zlib1.dll"
    -P "${CMAKE_CURRENT_LIST_DIR}/VerifyWindowsDependencies.cmake"
  RESULT_VARIABLE audit_result
  OUTPUT_VARIABLE audit_output
  ERROR_VARIABLE audit_error
  ENCODING UTF-8
)
if(NOT audit_result EQUAL 0)
  message(FATAL_ERROR
    "Installed pure-glpk PE audit failed (${audit_result})\n"
    "stdout:\n${audit_output}\nstderr:\n${audit_error}")
endif()

list(LENGTH expected_files expected_count)
message(STATUS
  "Verified installed pure-glpk: ${expected_count} package files, "
  "deduplicated GMP/zlib, sanitized solver smoke test, and staged PE closure")
