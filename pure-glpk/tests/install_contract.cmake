foreach(required IN ITEMS
    SOURCE_DIR BINARY_DIR PORTABLE_PURE_PREFIX SOURCE_RUNTIME_DIR
    LLVM_READOBJ GLPK_MODULE_SOURCE GLPK_INTERFACE_SOURCE README_SOURCE
    COPYING_SOURCE WINDOWS_SOURCE EXAMPLE_SOURCE TEST_SOURCE GLPK_DLL_SOURCE
    COLAMD_DLL_SOURCE AMD_DLL_SOURCE SUITESPARSECONFIG_DLL_SOURCE
    OMP_DLL_SOURCE GLPK_LICENSE_SOURCE SUITESPARSE_LICENSE_SOURCE
    LLVM_LICENSE_SOURCE)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
  cmake_path(ABSOLUTE_PATH ${required} NORMALIZE OUTPUT_VARIABLE normalized)
  set(${required} "${normalized}")
  if(NOT EXISTS "${${required}}")
    message(FATAL_ERROR "${required} does not exist: ${${required}}")
  endif()
endforeach()

foreach(required IN ITEMS CONTRACT_ROOT TEST_ROOT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()
cmake_path(ABSOLUTE_PATH CONTRACT_ROOT NORMALIZE OUTPUT_VARIABLE CONTRACT_ROOT)
cmake_path(ABSOLUTE_PATH TEST_ROOT NORMALIZE OUTPUT_VARIABLE TEST_ROOT)

set(self_arguments
  "-DSOURCE_DIR=${SOURCE_DIR}"
  "-DBINARY_DIR=${BINARY_DIR}"
  "-DCONTRACT_ROOT=${CONTRACT_ROOT}"
  "-DSOURCE_RUNTIME_DIR=${SOURCE_RUNTIME_DIR}"
  "-DLLVM_READOBJ=${LLVM_READOBJ}"
  "-DGLPK_MODULE_SOURCE=${GLPK_MODULE_SOURCE}"
  "-DGLPK_INTERFACE_SOURCE=${GLPK_INTERFACE_SOURCE}"
  "-DREADME_SOURCE=${README_SOURCE}"
  "-DCOPYING_SOURCE=${COPYING_SOURCE}"
  "-DWINDOWS_SOURCE=${WINDOWS_SOURCE}"
  "-DEXAMPLE_SOURCE=${EXAMPLE_SOURCE}"
  "-DTEST_SOURCE=${TEST_SOURCE}"
  "-DGLPK_DLL_SOURCE=${GLPK_DLL_SOURCE}"
  "-DCOLAMD_DLL_SOURCE=${COLAMD_DLL_SOURCE}"
  "-DAMD_DLL_SOURCE=${AMD_DLL_SOURCE}"
  "-DSUITESPARSECONFIG_DLL_SOURCE=${SUITESPARSECONFIG_DLL_SOURCE}"
  "-DOMP_DLL_SOURCE=${OMP_DLL_SOURCE}"
  "-DGLPK_LICENSE_SOURCE=${GLPK_LICENSE_SOURCE}"
  "-DSUITESPARSE_LICENSE_SOURCE=${SUITESPARSE_LICENSE_SOURCE}"
  "-DLLVM_LICENSE_SOURCE=${LLVM_LICENSE_SOURCE}"
)
function(expect_probe_rejected label expected_diagnostic)
  execute_process(
    COMMAND "${CMAKE_COMMAND}" ${self_arguments} ${ARGN}
      -P "${CMAKE_CURRENT_LIST_FILE}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8
  )
  if(result EQUAL 0)
    message(FATAL_ERROR "Install contract accepted unsafe ${label}")
  endif()
  if(NOT "${output}\n${error}" MATCHES "${expected_diagnostic}")
    message(FATAL_ERROR
      "Unsafe ${label} produced the wrong diagnostic\n${output}\n${error}")
  endif()
endfunction()

function(require_safe_test_root)
  cmake_path(GET CONTRACT_ROOT PARENT_PATH contract_parent)
  if(NOT "${contract_parent}" STREQUAL "${BINARY_DIR}")
    message(FATAL_ERROR
      "Unsafe CONTRACT_ROOT; expected a direct child of BINARY_DIR\n"
      "CONTRACT_ROOT: ${CONTRACT_ROOT}\nBINARY_DIR: ${BINARY_DIR}")
  endif()
  cmake_path(GET TEST_ROOT PARENT_PATH test_parent)
  if(NOT "${test_parent}" STREQUAL "${CONTRACT_ROOT}")
    message(FATAL_ERROR
      "Unsafe TEST_ROOT; expected a direct child of CONTRACT_ROOT\n"
      "TEST_ROOT: ${TEST_ROOT}\nCONTRACT_ROOT: ${CONTRACT_ROOT}")
  endif()
  foreach(protected IN ITEMS SOURCE_DIR BINARY_DIR PORTABLE_PURE_PREFIX)
    cmake_path(IS_PREFIX TEST_ROOT "${${protected}}" NORMALIZE
      test_root_contains_protected)
    if(test_root_contains_protected)
      message(FATAL_ERROR
        "Unsafe TEST_ROOT contains protected ${protected}: ${${protected}}")
    endif()
  endforeach()
endfunction()

require_safe_test_root()
if(ROOT_SAFETY_PROBE)
  return()
endif()

function(require_clean_portable_prefix)
  file(GLOB prefix_module_owned LIST_DIRECTORIES FALSE
    "${PORTABLE_PURE_PREFIX}/lib/pure/glpk*")
  file(GLOB prefix_runtime_owned LIST_DIRECTORIES FALSE
    "${PORTABLE_PURE_PREFIX}/bin/libamd*.dll"
    "${PORTABLE_PURE_PREFIX}/bin/libcolamd*.dll"
    "${PORTABLE_PURE_PREFIX}/bin/libglpk*.dll"
    "${PORTABLE_PURE_PREFIX}/bin/libomp*.dll"
    "${PORTABLE_PURE_PREFIX}/bin/libsuitesparseconfig*.dll"
  )
  file(GLOB_RECURSE prefix_documentation_owned LIST_DIRECTORIES FALSE
    "${PORTABLE_PURE_PREFIX}/share/doc/pure-glpk/*")
  set(prefix_owned
    ${prefix_module_owned}
    ${prefix_runtime_owned}
    ${prefix_documentation_owned}
  )
  if(prefix_owned)
    set(relative_owned)
    foreach(owned IN LISTS prefix_owned)
      file(RELATIVE_PATH relative "${PORTABLE_PURE_PREFIX}" "${owned}")
      cmake_path(CONVERT "${relative}" TO_CMAKE_PATH_LIST relative NORMALIZE)
      list(APPEND relative_owned "${relative}")
    endforeach()
    list(SORT relative_owned)
    message(FATAL_ERROR
      "Portable Pure prefix already contains pure-glpk-owned files: "
      "${relative_owned}")
  endif()
endfunction()

require_clean_portable_prefix()
if(PREFIX_OWNERSHIP_PROBE)
  return()
endif()
expect_probe_rejected("source TEST_ROOT" "Unsafe TEST_ROOT"
  "-DPORTABLE_PURE_PREFIX=${PORTABLE_PURE_PREFIX}"
  "-DTEST_ROOT=${SOURCE_DIR}" -DROOT_SAFETY_PROBE=ON)
expect_probe_rejected("binary TEST_ROOT" "Unsafe TEST_ROOT"
  "-DPORTABLE_PURE_PREFIX=${PORTABLE_PURE_PREFIX}"
  "-DTEST_ROOT=${BINARY_DIR}" -DROOT_SAFETY_PROBE=ON)
expect_probe_rejected("portable-prefix TEST_ROOT" "Unsafe TEST_ROOT"
  "-DPORTABLE_PURE_PREFIX=${PORTABLE_PURE_PREFIX}"
  "-DTEST_ROOT=${PORTABLE_PURE_PREFIX}" -DROOT_SAFETY_PROBE=ON)

file(REMOVE_RECURSE "${TEST_ROOT}")
file(MAKE_DIRECTORY "${TEST_ROOT}")

set(contaminated_prefix "${TEST_ROOT}/contaminated prefix")
file(MAKE_DIRECTORY "${contaminated_prefix}/lib/pure")
file(WRITE "${contaminated_prefix}/lib/pure/glpk.pure" "stale package\n")
expect_probe_rejected("GLPK-contaminated portable prefix"
  "Portable Pure prefix already contains pure-glpk-owned files:[ \r\n]+lib/pure/glpk\\.pure"
  "-DPORTABLE_PURE_PREFIX=${contaminated_prefix}"
  "-DTEST_ROOT=${CONTRACT_ROOT}/prefix ownership probe"
  -DPREFIX_OWNERSHIP_PROBE=ON)

set(stage "${TEST_ROOT}/stage")
file(MAKE_DIRECTORY "${stage}")
file(COPY "${PORTABLE_PURE_PREFIX}/" DESTINATION "${stage}")

foreach(component IN ITEMS runtime documentation)
  execute_process(
    COMMAND "${CMAKE_COMMAND}" --install "${BINARY_DIR}"
      --prefix "${stage}" --component "${component}"
    RESULT_VARIABLE install_result
    OUTPUT_VARIABLE install_output
    ERROR_VARIABLE install_error
    ENCODING UTF-8
  )
  if(NOT install_result EQUAL 0)
    message(FATAL_ERROR
      "Unable to install ${component} component (${install_result})\n"
      "stdout:\n${install_output}\nstderr:\n${install_error}")
  endif()
endforeach()

set(portable_pure "${PORTABLE_PURE_PREFIX}/bin/pure.exe")
set(staged_pure "${stage}/bin/pure.exe")
file(SHA256 "${portable_pure}" portable_pure_hash)
file(SHA256 "${staged_pure}" staged_pure_hash)
if(NOT portable_pure_hash STREQUAL staged_pure_hash)
  message(FATAL_ERROR "Unrelated portable Pure executable was not preserved")
endif()

set(verifier "${SOURCE_DIR}/cmake/VerifyInstalledPackage.cmake")
set(verifier_arguments
  "-DSOURCE_RUNTIME_DIR=${SOURCE_RUNTIME_DIR}"
  "-DLLVM_READOBJ=${LLVM_READOBJ}"
  "-DGLPK_MODULE_SOURCE=${GLPK_MODULE_SOURCE}"
  "-DGLPK_INTERFACE_SOURCE=${GLPK_INTERFACE_SOURCE}"
  "-DREADME_SOURCE=${README_SOURCE}"
  "-DCOPYING_SOURCE=${COPYING_SOURCE}"
  "-DWINDOWS_SOURCE=${WINDOWS_SOURCE}"
  "-DEXAMPLE_SOURCE=${EXAMPLE_SOURCE}"
  "-DTEST_SOURCE=${TEST_SOURCE}"
  "-DGLPK_DLL_SOURCE=${GLPK_DLL_SOURCE}"
  "-DCOLAMD_DLL_SOURCE=${COLAMD_DLL_SOURCE}"
  "-DAMD_DLL_SOURCE=${AMD_DLL_SOURCE}"
  "-DSUITESPARSECONFIG_DLL_SOURCE=${SUITESPARSECONFIG_DLL_SOURCE}"
  "-DOMP_DLL_SOURCE=${OMP_DLL_SOURCE}"
  "-DGLPK_LICENSE_SOURCE=${GLPK_LICENSE_SOURCE}"
  "-DSUITESPARSE_LICENSE_SOURCE=${SUITESPARSE_LICENSE_SOURCE}"
  "-DLLVM_LICENSE_SOURCE=${LLVM_LICENSE_SOURCE}"
  "-DRUN_PURE_TEST_SCRIPT=${SOURCE_DIR}/cmake/RunPureTest.cmake"
  "-DWINDOWS_DEPENDENCY_VERIFIER=${SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
)

function(run_verifier stage_prefix result_var diagnostics_var)
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DSTAGE_PREFIX=${stage_prefix}"
      ${verifier_arguments}
      -P "${verifier}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8
  )
  set(${result_var} "${result}" PARENT_SCOPE)
  set(${diagnostics_var} "${output}\n${error}" PARENT_SCOPE)
endfunction()

run_verifier("${stage}" pristine_result pristine_diagnostics)
if(NOT pristine_result EQUAL 0)
  message(FATAL_ERROR
    "Untouched installed package was rejected (${pristine_result})\n"
    "${pristine_diagnostics}")
endif()

set(extra_file "${stage}/share/doc/pure-glpk/unexpected.txt")
file(WRITE "${extra_file}" "not package-owned\n")
run_verifier("${stage}" extra_result extra_diagnostics)
file(REMOVE "${extra_file}")
run_verifier("${stage}" post_extra_result post_extra_diagnostics)
if(NOT post_extra_result EQUAL 0)
  message(FATAL_ERROR
    "Installed stage was not pristine after extra-file restoration\n"
    "${post_extra_diagnostics}")
endif()

set(installed_readme "${stage}/share/doc/pure-glpk/README")
file(APPEND "${installed_readme}" "\nmutated installed artifact\n")
run_verifier("${stage}" altered_result altered_diagnostics)
file(COPY_FILE "${README_SOURCE}" "${installed_readme}")
run_verifier("${stage}" post_altered_result post_altered_diagnostics)
if(NOT post_altered_result EQUAL 0)
  message(FATAL_ERROR
    "Installed stage was not pristine after README restoration\n"
    "${post_altered_diagnostics}")
endif()

set(accepted_mutations)
if(extra_result EQUAL 0)
  list(APPEND accepted_mutations "extra package-owned file")
elseif(NOT extra_diagnostics MATCHES "unexpected\\.txt")
  message(FATAL_ERROR
    "Extra-file mutation was rejected without naming unexpected.txt\n"
    "${extra_diagnostics}")
endif()
if(altered_result EQUAL 0)
  list(APPEND accepted_mutations "altered README artifact")
elseif(NOT altered_diagnostics MATCHES
    "Installed pure-glpk hash mismatch for share/doc/pure-glpk/README([\r\n]|$)")
  message(FATAL_ERROR
    "Altered artifact lacked the exact README hash diagnostic\n"
    "${altered_diagnostics}")
endif()
if(accepted_mutations)
  message(FATAL_ERROR
    "Installed-package verifier accepted forbidden mutations: "
    "${accepted_mutations}")
endif()

message(STATUS
  "Installed-package contract rejected an extra file and altered README")
