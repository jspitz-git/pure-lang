set(required_directories STAGE_PREFIX SOURCE_RUNTIME_DIR)
set(required_files
  LLVM_READOBJ
  GLPK_MODULE_SOURCE
  GLPK_INTERFACE_SOURCE
  README_SOURCE
  COPYING_SOURCE
  WINDOWS_SOURCE
  EXAMPLE_SOURCE
  TEST_SOURCE
  GLPK_DLL_SOURCE
  COLAMD_DLL_SOURCE
  AMD_DLL_SOURCE
  SUITESPARSECONFIG_DLL_SOURCE
  OMP_DLL_SOURCE
  GLPK_LICENSE_SOURCE
  SUITESPARSE_LICENSE_SOURCE
  OPENMP_LICENSE_SOURCE
  RUN_PURE_TEST_SCRIPT
  WINDOWS_DEPENDENCY_VERIFIER
)
foreach(required IN LISTS required_directories required_files)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
  cmake_path(ABSOLUTE_PATH ${required} NORMALIZE OUTPUT_VARIABLE normalized)
  set(${required} "${normalized}")
endforeach()
foreach(required IN LISTS required_directories)
  if(NOT IS_DIRECTORY "${${required}}")
    message(FATAL_ERROR "${required} must be an existing directory: ${${required}}")
  endif()
endforeach()
foreach(required IN LISTS required_files)
  if(NOT EXISTS "${${required}}" OR IS_DIRECTORY "${${required}}")
    message(FATAL_ERROR "${required} must be an existing file: ${${required}}")
  endif()
endforeach()

set(expected_owned_files
  bin/libamd.dll
  bin/libcolamd.dll
  bin/libglpk-40.dll
  bin/libomp.dll
  bin/libsuitesparseconfig.dll
  lib/pure/glpk.dll
  lib/pure/glpk.pure
  share/doc/pure-glpk/COPYING
  share/doc/pure-glpk/README
  share/doc/pure-glpk/WINDOWS.md
  share/doc/pure-glpk/examples/lp.pure
  share/doc/pure-glpk/glpk-LICENSE
  share/doc/pure-glpk/openmp-LICENSE
  share/doc/pure-glpk/suitesparse-LICENSE
  share/doc/pure-glpk/tests/smoke.pure
)
set(owned_sources
  "${AMD_DLL_SOURCE}"
  "${COLAMD_DLL_SOURCE}"
  "${GLPK_DLL_SOURCE}"
  "${OMP_DLL_SOURCE}"
  "${SUITESPARSECONFIG_DLL_SOURCE}"
  "${GLPK_MODULE_SOURCE}"
  "${GLPK_INTERFACE_SOURCE}"
  "${COPYING_SOURCE}"
  "${README_SOURCE}"
  "${WINDOWS_SOURCE}"
  "${EXAMPLE_SOURCE}"
  "${GLPK_LICENSE_SOURCE}"
  "${OPENMP_LICENSE_SOURCE}"
  "${SUITESPARSE_LICENSE_SOURCE}"
  "${TEST_SOURCE}"
)

file(GLOB module_owned LIST_DIRECTORIES FALSE "${STAGE_PREFIX}/lib/pure/glpk*")
file(GLOB runtime_owned LIST_DIRECTORIES FALSE
  "${STAGE_PREFIX}/bin/libamd*.dll"
  "${STAGE_PREFIX}/bin/libcolamd*.dll"
  "${STAGE_PREFIX}/bin/libglpk*.dll"
  "${STAGE_PREFIX}/bin/libomp*.dll"
  "${STAGE_PREFIX}/bin/libsuitesparseconfig*.dll"
)
file(GLOB_RECURSE documentation_owned LIST_DIRECTORIES FALSE
  "${STAGE_PREFIX}/share/doc/pure-glpk/*")
set(actual_owned_files)
foreach(owned IN LISTS module_owned runtime_owned documentation_owned)
  file(RELATIVE_PATH relative "${STAGE_PREFIX}" "${owned}")
  cmake_path(CONVERT "${relative}" TO_CMAKE_PATH_LIST relative NORMALIZE)
  list(APPEND actual_owned_files "${relative}")
endforeach()
list(SORT actual_owned_files)

if(NOT actual_owned_files STREQUAL expected_owned_files)
  set(missing "${expected_owned_files}")
  foreach(path IN LISTS actual_owned_files)
    list(REMOVE_ITEM missing "${path}")
  endforeach()
  set(unexpected "${actual_owned_files}")
  foreach(path IN LISTS expected_owned_files)
    list(REMOVE_ITEM unexpected "${path}")
  endforeach()
  message(FATAL_ERROR
    "Installed pure-glpk manifest mismatch\n"
    "expected: ${expected_owned_files}\n"
    "actual: ${actual_owned_files}\n"
    "missing: ${missing}\n"
    "unexpected: ${unexpected}")
endif()

list(LENGTH expected_owned_files expected_count)
list(LENGTH owned_sources source_count)
if(NOT expected_count EQUAL source_count)
  message(FATAL_ERROR
    "Internal package contract error: ${expected_count} paths but "
    "${source_count} sources")
endif()
math(EXPR last_owned_index "${expected_count} - 1")
foreach(index RANGE ${last_owned_index})
  list(GET expected_owned_files ${index} relative)
  list(GET owned_sources ${index} source)
  set(installed "${STAGE_PREFIX}/${relative}")
  file(SHA256 "${installed}" installed_hash)
  file(SHA256 "${source}" source_hash)
  if(NOT installed_hash STREQUAL source_hash)
    message(FATAL_ERROR
      "Installed pure-glpk hash mismatch for ${relative}\n"
      "source: ${source_hash}\ninstalled: ${installed_hash}")
  endif()
endforeach()

foreach(reused IN ITEMS libgmp-10.dll zlib1.dll)
  set(staged_file "${STAGE_PREFIX}/bin/${reused}")
  set(source_file "${SOURCE_RUNTIME_DIR}/${reused}")
  if(NOT EXISTS "${staged_file}" OR IS_DIRECTORY "${staged_file}" OR
      NOT EXISTS "${source_file}" OR IS_DIRECTORY "${source_file}")
    message(FATAL_ERROR "Missing reused dependency ${reused}")
  endif()
  file(SHA256 "${staged_file}" staged_hash)
  file(SHA256 "${source_file}" source_hash)
  if(NOT staged_hash STREQUAL source_hash)
    message(FATAL_ERROR
      "Conflicting staged ${reused}: ${staged_hash} != ${source_hash}")
  endif()
endforeach()

set(module_dir "${STAGE_PREFIX}/lib/pure")
set(doc_dir "${STAGE_PREFIX}/share/doc/pure-glpk")
execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DPURE_EXECUTABLE=${STAGE_PREFIX}/bin/pure.exe"
    "-DPACKAGE_DIR=${module_dir}"
    "-DMODULE_DIR=${module_dir}"
    "-DRUNTIME_BIN_DIR=${STAGE_PREFIX}/bin"
    "-DTEST_SCRIPT=${doc_dir}/tests/smoke.pure"
    -P "${RUN_PURE_TEST_SCRIPT}"
  RESULT_VARIABLE smoke_result
  OUTPUT_VARIABLE smoke_output
  ERROR_VARIABLE smoke_error
  ENCODING UTF-8
)
if(NOT smoke_result EQUAL 0)
  message(FATAL_ERROR
    "Installed pure-glpk smoke test failed (${smoke_result})\n"
    "stdout:\n${smoke_output}\nstderr:\n${smoke_error}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    "-DGLPK_MODULE=${module_dir}/glpk.dll"
    "-DGLPK_DLL=${STAGE_PREFIX}/bin/libglpk-40.dll"
    "-DCOLAMD_DLL=${STAGE_PREFIX}/bin/libcolamd.dll"
    "-DAMD_DLL=${STAGE_PREFIX}/bin/libamd.dll"
    "-DSUITESPARSECONFIG_DLL=${STAGE_PREFIX}/bin/libsuitesparseconfig.dll"
    "-DOMP_DLL=${STAGE_PREFIX}/bin/libomp.dll"
    "-DGMP_DLL=${STAGE_PREFIX}/bin/libgmp-10.dll"
    "-DZLIB_DLL=${STAGE_PREFIX}/bin/zlib1.dll"
    -P "${WINDOWS_DEPENDENCY_VERIFIER}"
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

message(STATUS
  "Verified installed pure-glpk: ${expected_count} package files, "
  "exact hashes, deduplicated GMP/zlib, strict solver smoke test, "
  "and exact staged PE imports")
