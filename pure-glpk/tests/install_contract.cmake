include("${CMAKE_CURRENT_LIST_DIR}/ContractTestRoot.cmake")
pure_glpk_validate_contract_test_root("install" unused_test_root)

foreach(required IN ITEMS
    PORTABLE_PURE_PREFIX SOURCE_RUNTIME_DIR
    LLVM_READOBJ GLPK_MODULE_SOURCE GLPK_INTERFACE_SOURCE README_SOURCE
    COPYING_SOURCE WINDOWS_SOURCE EXAMPLE_SOURCE TEST_SOURCE GLPK_DLL_SOURCE
    COLAMD_DLL_SOURCE AMD_DLL_SOURCE SUITESPARSECONFIG_DLL_SOURCE
    OMP_DLL_SOURCE GLPK_LICENSE_SOURCE SUITESPARSE_LICENSE_SOURCE
    OPENMP_LICENSE_SOURCE)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
  cmake_path(ABSOLUTE_PATH ${required} NORMALIZE OUTPUT_VARIABLE normalized)
  set(${required} "${normalized}")
  if(NOT EXISTS "${${required}}")
    message(FATAL_ERROR "${required} does not exist: ${${required}}")
  endif()
endforeach()

set(self_arguments
  "-DBINARY_DIR=${BINARY_DIR}"
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
  "-DOPENMP_LICENSE_SOURCE=${OPENMP_LICENSE_SOURCE}"
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

set(expected_package_delta
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
list(SORT expected_package_delta)

function(snapshot_prefix root paths_var hashes_var)
  if(NOT IS_DIRECTORY "${root}")
    message(FATAL_ERROR "Snapshot root is not a directory: ${root}")
  endif()
  file(GLOB_RECURSE entries LIST_DIRECTORIES FALSE RELATIVE "${root}"
    "${root}/*")
  list(SORT entries)
  set(paths)
  set(hashes)
  foreach(relative IN LISTS entries)
    cmake_path(CONVERT "${relative}" TO_CMAKE_PATH_LIST relative NORMALIZE)
    if(IS_SYMLINK "${root}/${relative}")
      message(FATAL_ERROR "Prefix snapshot rejects symlink: ${relative}")
    endif()
    file(SHA256 "${root}/${relative}" hash)
    list(APPEND paths "${relative}")
    list(APPEND hashes "${hash}")
  endforeach()
  set(${paths_var} "${paths}" PARENT_SCOPE)
  set(${hashes_var} "${hashes}" PARENT_SCOPE)
endfunction()

function(require_snapshot_preserved label expected_paths_var
    expected_hashes_var actual_root)
  set(expected_paths "${${expected_paths_var}}")
  set(expected_hashes "${${expected_hashes_var}}")
  snapshot_prefix("${actual_root}" actual_paths actual_hashes)
  foreach(relative IN LISTS expected_paths)
    list(FIND actual_paths "${relative}" actual_index)
    if(actual_index EQUAL -1)
      message(FATAL_ERROR "${label} removed pre-existing file: ${relative}")
    endif()
    list(FIND expected_paths "${relative}" expected_index)
    list(GET expected_hashes ${expected_index} expected_hash)
    list(GET actual_hashes ${actual_index} actual_hash)
    if(NOT actual_hash STREQUAL expected_hash)
      message(FATAL_ERROR "${label} changed pre-existing file: ${relative}")
    endif()
  endforeach()
endfunction()

function(require_exact_install_delta baseline_paths_var baseline_hashes_var
    installed_root)
  set(baseline_paths "${${baseline_paths_var}}")
  require_snapshot_preserved("pure-glpk install" "${baseline_paths_var}"
    "${baseline_hashes_var}" "${installed_root}")
  snapshot_prefix("${installed_root}" installed_paths installed_hashes)
  set(actual_delta "${installed_paths}")
  foreach(relative IN LISTS baseline_paths)
    list(REMOVE_ITEM actual_delta "${relative}")
  endforeach()
  list(SORT actual_delta)
  set(missing "${expected_package_delta}")
  foreach(relative IN LISTS actual_delta)
    list(REMOVE_ITEM missing "${relative}")
  endforeach()
  set(unexpected "${actual_delta}")
  foreach(relative IN LISTS expected_package_delta)
    list(REMOVE_ITEM unexpected "${relative}")
  endforeach()
  if(missing OR unexpected)
    message(FATAL_ERROR
      "Installed prefix delta mismatch\nmissing: ${missing}\nunexpected: ${unexpected}")
  endif()
endfunction()

require_clean_portable_prefix()
if(PREFIX_OWNERSHIP_PROBE)
  return()
endif()
if(DELTA_OWNERSHIP_PROBE)
  if(NOT DEFINED DELTA_STAGE OR "${DELTA_STAGE}" STREQUAL "")
    message(FATAL_ERROR "DELTA_STAGE is required")
  endif()
  cmake_path(ABSOLUTE_PATH DELTA_STAGE NORMALIZE OUTPUT_VARIABLE DELTA_STAGE)
  _pure_glpk_require_no_reparse("${DELTA_STAGE}" "DELTA_STAGE" TRUE)
  cmake_path(GET DELTA_STAGE PARENT_PATH delta_parent)
  _pure_glpk_fold_path("${delta_parent}" folded_delta_parent)
  _pure_glpk_fold_path("${TEST_ROOT}" folded_test_root)
  if(NOT folded_delta_parent STREQUAL folded_test_root)
    message(FATAL_ERROR
      "Unsafe DELTA_STAGE; expected a direct child of TEST_ROOT: ${DELTA_STAGE}")
  endif()
  snapshot_prefix("${PORTABLE_PURE_PREFIX}" baseline_paths baseline_hashes)
  require_exact_install_delta(baseline_paths baseline_hashes "${DELTA_STAGE}")
  return()
endif()
pure_glpk_run_root_safety_probes("install")
pure_glpk_reset_contract_test_root("install")

set(contaminated_prefix "${TEST_ROOT}/contaminated prefix")
file(MAKE_DIRECTORY "${contaminated_prefix}/lib/pure")
file(WRITE "${contaminated_prefix}/lib/pure/glpk.pure" "stale package\n")
expect_probe_rejected("GLPK-contaminated portable prefix"
  "Portable Pure prefix already contains pure-glpk-owned files:[ \r\n]+lib/pure/glpk\\.pure"
  "-DPORTABLE_PURE_PREFIX=${contaminated_prefix}"
  -DPREFIX_OWNERSHIP_PROBE=ON)

set(stage "${TEST_ROOT}/stage")
file(MAKE_DIRECTORY "${stage}")
snapshot_prefix("${PORTABLE_PURE_PREFIX}" baseline_paths baseline_hashes)
file(COPY "${PORTABLE_PURE_PREFIX}/" DESTINATION "${stage}")
require_snapshot_preserved("portable-prefix staging" baseline_paths
  baseline_hashes "${stage}")

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

require_exact_install_delta(baseline_paths baseline_hashes "${stage}")

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
  "-DOPENMP_LICENSE_SOURCE=${OPENMP_LICENSE_SOURCE}"
  "-DRUN_PURE_TEST_SCRIPT=${SOURCE_DIR}/cmake/RunPureTest.cmake"
  "-DWINDOWS_DEPENDENCY_VERIFIER=${SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
)

function(run_verifier stage_prefix result_var diagnostics_var)
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DSTAGE_PREFIX=${stage_prefix}"
      ${verifier_arguments}
      ${ARGN}
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

set(out_of_namespace_file
  "${stage}/share/unexpected-outside-owned-globs.txt")
file(WRITE "${out_of_namespace_file}" "not package-owned\n")
expect_probe_rejected("out-of-namespace installed file"
  "unexpected-outside-owned-globs\\.txt"
  "-DPORTABLE_PURE_PREFIX=${PORTABLE_PURE_PREFIX}"
  "-DDELTA_STAGE=${stage}"
  -DDELTA_OWNERSHIP_PROBE=ON)
file(REMOVE "${out_of_namespace_file}")
require_exact_install_delta(baseline_paths baseline_hashes "${stage}")

run_verifier("${stage}" wrong_openmp_license_result wrong_openmp_license_diagnostics
  "-DOPENMP_LICENSE_SOURCE=${GLPK_LICENSE_SOURCE}")
if(wrong_openmp_license_result EQUAL 0)
  message(FATAL_ERROR
    "Install verifier accepted a license from a package other than OpenMP")
endif()
if(NOT wrong_openmp_license_diagnostics MATCHES
    "Installed pure-glpk hash mismatch for share/doc/pure-glpk/openmp-LICENSE")
  message(FATAL_ERROR
    "Wrong OpenMP license source produced the wrong diagnostic:\n"
    "${wrong_openmp_license_diagnostics}")
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
