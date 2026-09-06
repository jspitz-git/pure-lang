foreach(required IN ITEMS STAGE_PREFIX LLVM_READOBJ)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE stage)
set(module_dir "${stage}/lib/pure")
set(doc_dir "${stage}/share/doc/pure-gsl")

set(expected_files
  "${module_dir}/gsl.dll"
  "${module_dir}/gsl.pure"
  "${module_dir}/gsl/common.pure"
  "${module_dir}/gsl/utils.pure"
  "${module_dir}/gsl/matrix.pure"
  "${module_dir}/gsl/sort.pure"
  "${module_dir}/gsl/randist.pure"
  "${module_dir}/gsl/stats.pure"
  "${module_dir}/gsl/poly.pure"
  "${module_dir}/gsl/fit.pure"
  "${module_dir}/gsl/sf.pure"
  "${module_dir}/gsl/complex.pure"
  "${stage}/bin/libgsl-28.dll"
  "${stage}/bin/libgslcblas-0.dll"
  "${doc_dir}/README"
  "${doc_dir}/COPYING"
  "${doc_dir}/WINDOWS.md"
  "${doc_dir}/gsl-COPYING"
  "${doc_dir}/examples/gslexample.pure"
  "${doc_dir}/examples/random_distributions.pure"
  "${doc_dir}/tests/smoke.pure"
)
foreach(expected IN LISTS expected_files)
  if(NOT EXISTS "${expected}")
    message(FATAL_ERROR "Missing installed pure-gsl file: ${expected}")
  endif()
endforeach()

file(GLOB installed_top_level LIST_DIRECTORIES FALSE RELATIVE "${stage}"
  "${module_dir}/gsl*")
file(GLOB_RECURSE installed_namespace LIST_DIRECTORIES FALSE RELATIVE "${stage}"
  "${module_dir}/gsl/*")
file(GLOB installed_runtime LIST_DIRECTORIES FALSE RELATIVE "${stage}"
  "${stage}/bin/libgsl-*.dll" "${stage}/bin/libgslcblas-*.dll")
file(GLOB_RECURSE installed_docs LIST_DIRECTORIES FALSE RELATIVE "${stage}"
  "${doc_dir}/*")
set(installed_package_files ${installed_top_level} ${installed_namespace}
  ${installed_runtime} ${installed_docs})
set(expected_relative)
foreach(expected IN LISTS expected_files)
  file(RELATIVE_PATH relative "${stage}" "${expected}")
  list(APPEND expected_relative "${relative}")
endforeach()
list(SORT installed_package_files)
list(SORT expected_relative)
if(NOT installed_package_files STREQUAL expected_relative)
  message(FATAL_ERROR
    "Installed pure-gsl files differ. Expected '${expected_relative}', "
    "got '${installed_package_files}'")
endif()

file(GLOB installed_modules LIST_DIRECTORIES FALSE "${module_dir}/gsl/*.pure")
list(LENGTH installed_modules installed_module_count)
if(NOT installed_module_count EQUAL 10)
  message(FATAL_ERROR
    "Expected all 10 gsl namespace modules, found ${installed_module_count}")
endif()

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
    "Installed pure-gsl smoke test failed (${result})\n"
    "stdout:\n${output}\nstderr:\n${error}")
endif()
if(NOT error STREQUAL "")
  message(FATAL_ERROR
    "Installed pure-gsl smoke emitted diagnostics\n"
    "stdout:\n${output}\nstderr:\n${error}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    "-DGSL_MODULE=${module_dir}/gsl.dll"
    "-DGSL_DLL=${stage}/bin/libgsl-28.dll"
    "-DGSLCBLAS_DLL=${stage}/bin/libgslcblas-0.dll"
    -P "${CMAKE_CURRENT_LIST_DIR}/VerifyWindowsDependencies.cmake"
  RESULT_VARIABLE audit_result
  OUTPUT_VARIABLE audit_output
  ERROR_VARIABLE audit_error
  ENCODING UTF-8
)
if(NOT audit_result EQUAL 0)
  message(FATAL_ERROR
    "Installed pure-gsl PE audit failed (${audit_result})\n"
    "stdout:\n${audit_output}\nstderr:\n${audit_error}")
endif()

list(LENGTH expected_files expected_count)
message(STATUS
  "Verified installed pure-gsl: ${expected_count} package files, 10 modules, "
  "sanitized native smoke test, and staged PE closure")
