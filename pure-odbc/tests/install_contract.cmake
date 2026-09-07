cmake_minimum_required(VERSION 3.25)

include("${CMAKE_CURRENT_LIST_DIR}/ContractTestRoot.cmake")

set(required_directories
  PORTABLE_PURE_PREFIX WINDOWS_DIRECTORY
    PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY)
set(required_files
  LLVM_READOBJ ODBC_MODULE_SOURCE
    ODBC_INTERFACE_SOURCE README_SOURCE COPYING_SOURCE COPYING_LESSER_SOURCE
    WINDOWS_SOURCE EXAMPLE_SOURCE SMOKE_SOURCE PEOPLE_SOURCE SCHEMA_SOURCE
    GMP_DLL_SOURCE PURE_RUNTIME_DLL_SOURCE RUN_PURE_TEST_EXECUTABLE
    WINDOWS_DEPENDENCY_VERIFIER SYSTEM_ODBC_DLL)
foreach(required IN LISTS required_directories required_files)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
  cmake_path(ABSOLUTE_PATH ${required} NORMALIZE OUTPUT_VARIABLE normalized)
  set(${required} "${normalized}")
endforeach()
foreach(required IN LISTS required_directories)
  if(NOT IS_DIRECTORY "${${required}}")
    message(FATAL_ERROR
      "${required} must be an existing directory: ${${required}}")
  endif()
endforeach()
foreach(required IN LISTS required_files)
  if(NOT EXISTS "${${required}}" OR IS_DIRECTORY "${${required}}")
    message(FATAL_ERROR "${required} must be an existing file: ${${required}}")
  endif()
endforeach()

pure_odbc_validate_contract_test_root("cleanup" unused_test_root)
pure_odbc_reset_contract_test_root("cleanup")
set(install_root "${TEST_ROOT}/task5-install")
set(stage "${install_root}/stage")
file(MAKE_DIRECTORY "${install_root}" "${stage}")

set(expected_runtime_delta
  lib/pure/odbc.dll
  lib/pure/odbc.pure)
set(expected_documentation_delta
  share/doc/pure-odbc/README
  share/doc/pure-odbc/COPYING
  share/doc/pure-odbc/COPYING.LESSER
  share/doc/pure-odbc/WINDOWS.md
  share/doc/pure-odbc/examples/menagerie.pure
  share/doc/pure-odbc/tests/smoke.pure
  share/doc/pure-odbc/tests/data/people.csv
  share/doc/pure-odbc/tests/data/Schema.ini)
set(expected_package_delta
  ${expected_runtime_delta} ${expected_documentation_delta})
list(SORT expected_runtime_delta)
list(SORT expected_documentation_delta)
list(SORT expected_package_delta)

function(snapshot_prefix root output_manifest)
  if(NOT IS_DIRECTORY "${root}")
    message(FATAL_ERROR "Snapshot root is not a directory: ${root}")
  endif()
  _pure_odbc_require_no_reparse("${root}" "prefix snapshot" TRUE)
  file(GLOB_RECURSE entries LIST_DIRECTORIES FALSE RELATIVE "${root}"
    "${root}/*")
  list(SORT entries)
  set(manifest)
  foreach(relative IN LISTS entries)
    cmake_path(CONVERT "${relative}" TO_CMAKE_PATH_LIST relative NORMALIZE)
    if(relative MATCHES "(^|/)\\.\\.(/|$)" OR IS_ABSOLUTE "${relative}")
      message(FATAL_ERROR "Unsafe snapshot path: ${relative}")
    endif()
    file(SHA256 "${root}/${relative}" hash)
    string(TOLOWER "${hash}" hash)
    string(APPEND manifest "${hash}|${relative}\n")
  endforeach()
  file(WRITE "${output_manifest}" "${manifest}")
endfunction()

function(require_no_owned_files root)
  foreach(relative IN LISTS expected_package_delta)
    if(EXISTS "${root}/${relative}" OR IS_SYMLINK "${root}/${relative}")
      message(FATAL_ERROR
        "Portable Pure prefix already contains pure-odbc file: ${relative}")
    endif()
  endforeach()
endfunction()

require_no_owned_files("${PORTABLE_PURE_PREFIX}")
set(baseline_manifest "${install_root}/baseline.sha256")
snapshot_prefix("${PORTABLE_PURE_PREFIX}" "${baseline_manifest}")
file(COPY "${PORTABLE_PURE_PREFIX}/" DESTINATION "${stage}")

function(install_component component output_manifest)
  execute_process(
    COMMAND "${CMAKE_COMMAND}" --install "${BINARY_DIR}"
      --prefix "${stage}" --component "${component}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8
  )
  if(NOT result EQUAL 0)
    message(FATAL_ERROR
      "Unable to install ${component} component (${result})\n"
      "stdout:\n${output}\nstderr:\n${error}")
  endif()
  set(generated "${BINARY_DIR}/install_manifest_${component}.txt")
  if(NOT EXISTS "${generated}" OR IS_DIRECTORY "${generated}")
    message(FATAL_ERROR
      "CMake did not generate the ${component} component manifest: "
      "${generated}")
  endif()
  file(COPY_FILE "${generated}" "${output_manifest}")
endfunction()

set(runtime_manifest "${install_root}/install_manifest_runtime.txt")
set(documentation_manifest
  "${install_root}/install_manifest_documentation.txt")
install_component(runtime "${runtime_manifest}")
install_component(documentation "${documentation_manifest}")

set(verifier "${SOURCE_DIR}/cmake/VerifyInstalledPackage.cmake")
set(verifier_arguments
  "-DSTAGE_PREFIX=${stage}"
  "-DBASELINE_MANIFEST=${baseline_manifest}"
  "-DRUNTIME_COMPONENT_MANIFEST=${runtime_manifest}"
  "-DDOCUMENTATION_COMPONENT_MANIFEST=${documentation_manifest}"
  "-DLLVM_READOBJ=${LLVM_READOBJ}"
  "-DODBC_MODULE_SOURCE=${ODBC_MODULE_SOURCE}"
  "-DODBC_INTERFACE_SOURCE=${ODBC_INTERFACE_SOURCE}"
  "-DREADME_SOURCE=${README_SOURCE}"
  "-DCOPYING_SOURCE=${COPYING_SOURCE}"
  "-DCOPYING_LESSER_SOURCE=${COPYING_LESSER_SOURCE}"
  "-DWINDOWS_SOURCE=${WINDOWS_SOURCE}"
  "-DEXAMPLE_SOURCE=${EXAMPLE_SOURCE}"
  "-DSMOKE_SOURCE=${SMOKE_SOURCE}"
  "-DPEOPLE_SOURCE=${PEOPLE_SOURCE}"
  "-DSCHEMA_SOURCE=${SCHEMA_SOURCE}"
  "-DGMP_DLL_SOURCE=${GMP_DLL_SOURCE}"
  "-DPURE_RUNTIME_DLL_SOURCE=${PURE_RUNTIME_DLL_SOURCE}"
  "-DRUN_PURE_TEST_EXECUTABLE=${RUN_PURE_TEST_EXECUTABLE}"
  "-DWINDOWS_DEPENDENCY_VERIFIER=${WINDOWS_DEPENDENCY_VERIFIER}"
  "-DWINDOWS_DIRECTORY=${WINDOWS_DIRECTORY}"
  "-DSYSTEM_ODBC_DLL=${SYSTEM_ODBC_DLL}"
  "-DPURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY=${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}"
  # Compatibility input for the pre-hardening RED verifier.
  "-DSOURCE_RUNTIME_DIR=${PORTABLE_PURE_PREFIX}/bin"
)

function(run_verifier result_var diagnostics_var)
  execute_process(
    COMMAND "${CMAKE_COMMAND}" ${verifier_arguments} ${ARGN}
      -P "${verifier}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8
  )
  set(${result_var} "${result}" PARENT_SCOPE)
  set(${diagnostics_var} "${output}\n${error}" PARENT_SCOPE)
endfunction()

function(expect_rejected label expected)
  run_verifier(result diagnostics ${ARGN})
  if(result EQUAL 0)
    message(FATAL_ERROR "Installed verifier accepted ${label}")
  endif()
  if(NOT diagnostics MATCHES "${expected}")
    message(FATAL_ERROR
      "Installed verifier rejected ${label} with the wrong diagnostic\n"
      "${diagnostics}")
  endif()
endfunction()

run_verifier(pristine_result pristine_diagnostics)
if(NOT pristine_result EQUAL 0)
  message(FATAL_ERROR
    "Pristine installed package was rejected (${pristine_result})\n"
    "${pristine_diagnostics}")
endif()

set(forged_windows_directory "${install_root}/forged-Windows")
file(MAKE_DIRECTORY "${forged_windows_directory}")
expect_rejected("a forged authoritative Windows directory"
  "WINDOWS_DIRECTORY.*authoritative|authoritative.*WINDOWS_DIRECTORY"
  "-DPURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY=${forged_windows_directory}")

set(outside_old_globs "${stage}/share/task5-outside-old-globs.txt")
file(WRITE "${outside_old_globs}" "unexpected package delta\n")
expect_rejected("an extra file outside old ownership globs"
  "unexpected:.*share/task5-outside-old-globs\\.txt")
file(REMOVE "${outside_old_globs}")

set(missing_owned "${stage}/share/doc/pure-odbc/tests/data/Schema.ini")
file(REMOVE "${missing_owned}")
expect_rejected("a missing owned file" "missing:.*Schema\\.ini")
file(COPY_FILE "${SCHEMA_SOURCE}" "${missing_owned}")

set(extra_owned "${stage}/share/doc/pure-odbc/unexpected.txt")
file(WRITE "${extra_owned}" "unexpected package file\n")
expect_rejected("an extra package file" "unexpected:.*unexpected\\.txt")
file(REMOVE "${extra_owned}")

set(altered_owned "${stage}/share/doc/pure-odbc/README")
file(APPEND "${altered_owned}" "mutated\n")
expect_rejected("an altered owned file" "hash mismatch.*README")
file(COPY_FILE "${README_SOURCE}" "${altered_owned}")

set(deleted_baseline_relative "bin/libiconv-2.dll")
set(deleted_baseline "${stage}/${deleted_baseline_relative}")
file(REMOVE "${deleted_baseline}")
expect_rejected("a deleted baseline file"
  "removed pre-existing file.*libiconv-2\\.dll")
file(COPY_FILE
  "${PORTABLE_PURE_PREFIX}/${deleted_baseline_relative}"
  "${deleted_baseline}")

set(overwritten_baseline_relative "bin/pure.exe")
set(overwritten_baseline "${stage}/${overwritten_baseline_relative}")
file(APPEND "${overwritten_baseline}" "mutated baseline\n")
expect_rejected("an overwritten baseline file"
  "changed pre-existing file.*bin/pure\\.exe")
file(COPY_FILE
  "${PORTABLE_PURE_PREFIX}/${overwritten_baseline_relative}"
  "${overwritten_baseline}")

file(READ "${runtime_manifest}" original_runtime_manifest)
file(APPEND "${runtime_manifest}" "${stage}/share/wrong-component.txt\n")
expect_rejected("a wrong runtime component manifest"
  "runtime component manifest mismatch")
file(WRITE "${runtime_manifest}" "${original_runtime_manifest}")

set(staged_gmp "${stage}/bin/libgmp-10.dll")
file(APPEND "${staged_gmp}" "mismatched GMP\n")
expect_rejected("mismatched reused GMP" "GMP.*hash mismatch")
file(COPY_FILE "${PORTABLE_PURE_PREFIX}/bin/libgmp-10.dll" "${staged_gmp}")

file(MAKE_DIRECTORY "${stage}/share/foreign-manager")
set(bundled_manager "${stage}/share/foreign-manager/odbc32.dll")
file(WRITE "${bundled_manager}" "bundled manager\n")
expect_rejected("a bundled ODBC manager anywhere"
  "bundled ODBC manager.*odbc32\\.dll")
file(REMOVE "${bundled_manager}")

set(bundled_driver "${stage}/share/foreign-manager/msodbcsql18.dll")
file(WRITE "${bundled_driver}" "bundled database driver\n")
expect_rejected("a bundled ODBC driver anywhere"
  "bundled ODBC driver.*msodbcsql18\\.dll")
file(REMOVE "${bundled_driver}")

run_verifier(final_result final_diagnostics)
if(NOT final_result EQUAL 0)
  message(FATAL_ERROR
    "Installed stage was not pristine after mutations (${final_result})\n"
    "${final_diagnostics}")
endif()

list(LENGTH expected_package_delta owned_count)
message(STATUS
  "pure-odbc install contract passed ${owned_count}-file delta, component, "
  "hash, baseline, GMP, manager, driver, runtime, and PE mutations")
