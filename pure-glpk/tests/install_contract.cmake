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

if(NOT DEFINED TEST_ROOT OR "${TEST_ROOT}" STREQUAL "")
  message(FATAL_ERROR "TEST_ROOT is required")
endif()
cmake_path(ABSOLUTE_PATH TEST_ROOT NORMALIZE OUTPUT_VARIABLE TEST_ROOT)

file(REMOVE_RECURSE "${TEST_ROOT}")
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

set(installed_readme "${stage}/share/doc/pure-glpk/README")
file(APPEND "${installed_readme}" "\nmutated installed artifact\n")
run_verifier("${stage}" altered_result altered_diagnostics)
file(COPY_FILE "${README_SOURCE}" "${installed_readme}")

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
elseif(NOT altered_diagnostics MATCHES "README")
  message(FATAL_ERROR
    "Altered artifact was rejected without naming README\n"
    "${altered_diagnostics}")
endif()
if(accepted_mutations)
  message(FATAL_ERROR
    "Installed-package verifier accepted forbidden mutations: "
    "${accepted_mutations}")
endif()

message(STATUS
  "Installed-package contract rejected an extra file and altered README")
