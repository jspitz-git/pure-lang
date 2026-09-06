cmake_minimum_required(VERSION 3.25)
foreach(required IN ITEMS SOURCE_DIR BINARY_DIR TEST_ROOT PURE_EXECUTABLE
    LLVM_READOBJ_EXECUTABLE GSL_RUNTIME_DLL GSLCBLAS_RUNTIME_DLL GSL_MODULE
    GSL_RUNTIME_LICENSE)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()
cmake_path(ABSOLUTE_PATH BINARY_DIR NORMALIZE OUTPUT_VARIABLE binary_root)
cmake_path(ABSOLUTE_PATH TEST_ROOT NORMALIZE OUTPUT_VARIABLE test_root)
cmake_path(IS_PREFIX binary_root "${test_root}" NORMALIZE safe)
if(NOT safe OR test_root STREQUAL binary_root)
  message(FATAL_ERROR "TEST_ROOT must be a proper child of BINARY_DIR")
endif()
set(package "${test_root}/package")
set(runtime "${test_root}/portable runtime")
file(REMOVE_RECURSE "${test_root}")
file(MAKE_DIRECTORY "${test_root}")
execute_process(COMMAND "${CMAKE_COMMAND}" --install "${BINARY_DIR}" --prefix "${package}"
  RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Package install failed:\n${output}${error}")
endif()
set(expected bin/libgsl-28.dll bin/libgslcblas-0.dll lib/pure/gsl.dll
  lib/pure/gsl.pure lib/pure/gsl/common.pure lib/pure/gsl/complex.pure
  lib/pure/gsl/fit.pure lib/pure/gsl/matrix.pure lib/pure/gsl/poly.pure
  lib/pure/gsl/randist.pure lib/pure/gsl/sf.pure lib/pure/gsl/sort.pure
  lib/pure/gsl/stats.pure lib/pure/gsl/utils.pure
  share/doc/pure-gsl/COPYING share/doc/pure-gsl/README
  share/doc/pure-gsl/WINDOWS.md share/doc/pure-gsl/gsl-COPYING
  share/doc/pure-gsl/examples/gslexample.pure
  share/doc/pure-gsl/examples/random_distributions.pure
  share/doc/pure-gsl/tests/smoke.pure)
file(GLOB_RECURSE installed RELATIVE "${package}" "${package}/*")
list(SORT expected)
list(SORT installed)
if(NOT installed STREQUAL expected)
  message(FATAL_ERROR "Installed manifest differs. Expected '${expected}', got '${installed}'")
endif()
set(content_pairs
  "bin/libgsl-28.dll|${GSL_RUNTIME_DLL}"
  "bin/libgslcblas-0.dll|${GSLCBLAS_RUNTIME_DLL}"
  "lib/pure/gsl.dll|${GSL_MODULE}"
  "lib/pure/gsl.pure|${SOURCE_DIR}/gsl.pure"
  "share/doc/pure-gsl/COPYING|${SOURCE_DIR}/COPYING"
  "share/doc/pure-gsl/README|${BINARY_DIR}/README"
  "share/doc/pure-gsl/WINDOWS.md|${SOURCE_DIR}/WINDOWS.md"
  "share/doc/pure-gsl/gsl-COPYING|${GSL_RUNTIME_LICENSE}"
  "share/doc/pure-gsl/examples/gslexample.pure|${SOURCE_DIR}/examples/gslexample.pure"
  "share/doc/pure-gsl/examples/random_distributions.pure|${SOURCE_DIR}/examples/random_distributions.pure"
  "share/doc/pure-gsl/tests/smoke.pure|${SOURCE_DIR}/tests/smoke.pure")
foreach(name IN ITEMS common complex fit matrix poly randist sf sort stats utils)
  list(APPEND content_pairs
    "lib/pure/gsl/${name}.pure|${SOURCE_DIR}/gsl/${name}.pure")
endforeach()
foreach(pair IN LISTS content_pairs)
  string(REPLACE "|" ";" fields "${pair}")
  list(GET fields 0 relative)
  list(GET fields 1 source)
  file(SHA256 "${package}/${relative}" actual)
  file(SHA256 "${source}" wanted)
  if(NOT actual STREQUAL wanted)
    message(FATAL_ERROR "Installed ${relative} differs from configured input")
  endif()
endforeach()
execute_process(COMMAND "${CMAKE_COMMAND}"
  "-DLLVM_READOBJ=${LLVM_READOBJ_EXECUTABLE}"
  "-DGSL_MODULE=${package}/lib/pure/gsl.dll"
  "-DGSL_DLL=${package}/bin/libgsl-28.dll"
  "-DGSLCBLAS_DLL=${package}/bin/libgslcblas-0.dll"
  -P "${SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
  RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Installed PE audit failed:\n${output}${error}")
endif()
file(WRITE "${package}/lib/pure/gsl/extra.dll" "unexpected")
execute_process(COMMAND "${CMAKE_COMMAND}"
  "-DSTAGE_PREFIX=${package}"
  "-DLLVM_READOBJ=${LLVM_READOBJ_EXECUTABLE}"
  -P "${SOURCE_DIR}/cmake/VerifyInstalledPackage.cmake"
  RESULT_VARIABLE extra_result OUTPUT_VARIABLE extra_output ERROR_VARIABLE extra_error)
if(extra_result EQUAL 0 OR
    NOT "${extra_output}\n${extra_error}" MATCHES "files differ")
  message(FATAL_ERROR
    "Installed verifier accepted a namespace extra or failed incorrectly:\n"
    "${extra_output}${extra_error}")
endif()
file(REMOVE "${package}/lib/pure/gsl/extra.dll")
get_filename_component(pure_bin "${PURE_EXECUTABLE}" DIRECTORY)
get_filename_component(pure_prefix "${pure_bin}" DIRECTORY)
if(NOT EXISTS "${pure_prefix}/lib/pure/math.pure")
  message(FATAL_ERROR "PURE_EXECUTABLE is not in an installed runtime")
endif()
file(COPY "${pure_prefix}/" DESTINATION "${runtime}")
execute_process(COMMAND "${CMAKE_COMMAND}" --install "${BINARY_DIR}" --prefix "${runtime}"
  RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Runtime overlay failed:\n${output}${error}")
endif()
execute_process(COMMAND "${CMAKE_COMMAND}"
  "-DPURE_EXECUTABLE=${runtime}/bin/pure.exe"
  "-DPACKAGE_DIR=${runtime}/lib/pure" "-DMODULE_DIR=${runtime}/lib/pure"
  "-DRUNTIME_BIN_DIR=${runtime}/bin"
  "-DTEST_SCRIPT=${runtime}/share/doc/pure-gsl/tests/smoke.pure"
  "-DRUN_WORKING_DIRECTORY=$ENV{SystemRoot}"
  -P "${SOURCE_DIR}/cmake/RunPureTest.cmake"
  RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Portable runtime smoke failed:\n${output}${error}")
endif()
message(STATUS "Verified exact 21-file install and standalone runtime smoke")
