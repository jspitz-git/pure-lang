cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS SOURCE_DIR BINARY_DIR PURE_EXECUTABLE TEST_ROOT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

get_filename_component(binary_root "${BINARY_DIR}" ABSOLUTE)
get_filename_component(test_root "${TEST_ROOT}" ABSOLUTE)
cmake_path(IS_PREFIX binary_root "${test_root}" NORMALIZE safe_root)
if(NOT safe_root OR test_root STREQUAL binary_root)
  message(FATAL_ERROR "TEST_ROOT must be a child of BINARY_DIR")
endif()

get_filename_component(pure_bin_dir "${PURE_EXECUTABLE}" DIRECTORY)
get_filename_component(runtime_prefix "${pure_bin_dir}" DIRECTORY)
if(NOT EXISTS "${runtime_prefix}/lib/pure/math.pure" OR
    NOT EXISTS "${pure_bin_dir}/libc++.dll")
  message(FATAL_ERROR
    "PURE_EXECUTABLE must belong to a portable runtime containing libc++.dll")
endif()

set(package_stage "${TEST_ROOT}/package stage")
set(runtime_stage "${TEST_ROOT}/runtime stage")
set(poison_dir "${TEST_ROOT}/poison PURELIB")
file(REMOVE_RECURSE "${TEST_ROOT}")
file(MAKE_DIRECTORY "${package_stage}" "${poison_dir}")
execute_process(
  COMMAND "${CMAKE_COMMAND}" --install "${BINARY_DIR}" --prefix "${package_stage}"
  RESULT_VARIABLE result
)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Package-only install failed")
endif()

file(GLOB_RECURSE installed LIST_DIRECTORIES FALSE
  RELATIVE "${package_stage}" "${package_stage}/*")
list(TRANSFORM installed REPLACE "\\\\" "/")
list(SORT installed)
set(expected
  lib/pure/stlalgorithm.dll
  lib/pure/stlbase.dll
  lib/pure/stlbase.pure
  lib/pure/stlhmap.dll
  lib/pure/stlhmap.pure
  lib/pure/stlmap.dll
  lib/pure/stlmap.pure
  lib/pure/stlmmap.dll
  lib/pure/stlmmap.pure
  lib/pure/stlvec.dll
  lib/pure/stlvec.pure
  lib/pure/stlvec/algorithms.pure
  lib/pure/stlvec/heap.pure
  lib/pure/stlvec/merge.pure
  lib/pure/stlvec/minmax.pure
  lib/pure/stlvec/modifying.pure
  lib/pure/stlvec/nonmodifying.pure
  lib/pure/stlvec/numeric.pure
  lib/pure/stlvec/sort.pure
  share/doc/pure-stllib/COPYING
  share/doc/pure-stllib/README
  share/doc/pure-stllib/WINDOWS.md
  share/doc/pure-stllib/pure-stllib-cheatsheet.ods
  share/doc/pure-stllib/pure-stllib-cheatsheet.pdf
  share/doc/pure-stllib/pure-stlmap-README
  share/doc/pure-stllib/pure-stlvec-README
  share/doc/pure-stllib/examples/stlmap/anagram_groups_dict.txt
  share/doc/pure-stllib/examples/stlmap/anagrams.pure
  share/doc/pure-stllib/examples/stlmap/poly.pure
  share/doc/pure-stllib/examples/stlmap/readme-data.pure
  share/doc/pure-stllib/examples/stlvec/anagram_groups.pure
  share/doc/pure-stllib/examples/stlvec/anagram_groups_dict.txt
  share/doc/pure-stllib/examples/stlvec/collatz.pure
  share/doc/pure-stllib/examples/stlvec/grader.pure
  share/doc/pure-stllib/examples/stlvec/grader_config.txt
  share/doc/pure-stllib/examples/stlvec/grader_data.txt
  share/doc/pure-stllib/examples/stlvec/grader_util.pure
  share/doc/pure-stllib/examples/stlvec/sieve.pure
  share/doc/pure-stllib/examples/stlvec/stlstruct.pure
  share/doc/pure-stllib/examples/stlvec/stlutil.pure
  share/doc/pure-stllib/examples/stlvec/time_sort.pure
  share/doc/pure-stllib/examples/stlvec/time_struct.pure
)
list(SORT expected)
if(NOT installed STREQUAL expected)
  message(FATAL_ERROR
    "Unexpected manifest. Expected '${expected}', got '${installed}'")
endif()
if(EXISTS "${package_stage}/bin/libc++.dll")
  message(FATAL_ERROR "Package duplicated the shared portable libc++.dll")
endif()

file(TO_CMAKE_PATH "${SOURCE_DIR}" source_path)
file(TO_CMAKE_PATH "${BINARY_DIR}" binary_path)
foreach(relative IN LISTS installed)
  if(relative MATCHES "\\.(dll|pdf|ods)$")
    continue()
  endif()
  file(READ "${package_stage}/${relative}" content)
  string(REPLACE "\\" "/" content "${content}")
  foreach(forbidden IN ITEMS "${source_path}" "${binary_path}" "C:/msys64"
      "@version@" "|today|")
    string(FIND "${content}" "${forbidden}" offset)
    if(NOT offset EQUAL -1)
      message(FATAL_ERROR "Installed ${relative} contains ${forbidden}")
    endif()
  endforeach()
endforeach()

execute_process(
  COMMAND "${CMAKE_COMMAND}" -E copy_directory
    "${runtime_prefix}" "${runtime_stage}"
  RESULT_VARIABLE result
)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Could not copy the portable Pure runtime")
endif()
execute_process(
  COMMAND "${CMAKE_COMMAND}" --install "${BINARY_DIR}" --prefix "${runtime_stage}"
  RESULT_VARIABLE result
)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Could not install into the staged runtime")
endif()
file(WRITE "${poison_dir}/stlbase.pure"
  "unexpected token proving inherited PURELIB leakage;\n")

foreach(test_kind IN ITEMS stlvec stlmap)
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env
      "PURELIB=${poison_dir}"
      "PATH=C:/msys64/clang64/bin;$ENV{SystemRoot}/System32;$ENV{SystemRoot}"
      "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${runtime_stage}/bin/pure.exe"
      "-DPACKAGE_DIRS=${runtime_stage}/lib/pure"
      "-DTEST_SOURCE_DIR=${SOURCE_DIR}"
      "-DMODULE_DIR=${runtime_stage}/lib/pure"
      "-DTEST_KIND=${test_kind}"
      -P "${SOURCE_DIR}/cmake/RunPackageTests.cmake"
    WORKING_DIRECTORY "$ENV{SystemRoot}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
  )
  if(NOT result EQUAL 0)
    message(FATAL_ERROR
      "Installed ${test_kind} suite failed:\n${output}${error}")
  endif()
endforeach()
