foreach(required IN ITEMS
    PURE_EXECUTABLE PACKAGE_DIRS TEST_SOURCE_DIR MODULE_DIR TEST_KIND)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

unset(ENV{PURELIB})
get_filename_component(pure_bin_dir "${PURE_EXECUTABLE}" DIRECTORY)
get_filename_component(pure_runtime_prefix "${pure_bin_dir}" DIRECTORY)
if(NOT EXISTS "${pure_runtime_prefix}/lib/pure/math.pure")
  message(FATAL_ERROR
    "PURE_EXECUTABLE must belong to an installed Pure runtime prefix")
endif()
if(WIN32)
  set(ENV{PATH}
    "${MODULE_DIR};${pure_bin_dir};$ENV{SystemRoot}/System32;$ENV{SystemRoot}")
else()
  set(ENV{PATH} "${MODULE_DIR}:${pure_bin_dir}:$ENV{PATH}")
endif()
set(pure_arguments
  --norc
  -L "${MODULE_DIR}"
)
foreach(package_dir IN LISTS PACKAGE_DIRS)
  list(APPEND pure_arguments -I "${package_dir}")
endforeach()

if(TEST_KIND STREQUAL "stlvec")
  set(test_directory "${TEST_SOURCE_DIR}/pure-stlvec/ut")
  list(APPEND pure_arguments -I "${test_directory}")
  list(APPEND pure_arguments -x "${test_directory}/ut_all.pure")
  set(success_marker "PASSED STLVEC UNIT TESTS")
elseif(TEST_KIND STREQUAL "stlmap")
  set(test_directory "${TEST_SOURCE_DIR}/pure-stlmap/uts")
  set(map_tests
    "${test_directory}/uts_stlhmap.pure"
    "${test_directory}/uts_stlhset.pure"
    "${test_directory}/uts_stlmap_iter.pure"
    "${test_directory}/uts_stlmap.pure"
    "${test_directory}/uts_stlmmap_iter.pure"
    "${test_directory}/uts_stlmmap.pure"
    "${test_directory}/uts_stlmset_iter.pure"
    "${test_directory}/uts_stlmset.pure"
    "${test_directory}/uts_stlset_iter.pure"
    "${test_directory}/uts_stlset.pure"
  )
  list(APPEND pure_arguments -x "${test_directory}/check_uts.pure")
  list(APPEND pure_arguments ${map_tests})
  set(success_marker "PASSED STLMAP UTS TESTS")
else()
  message(FATAL_ERROR "Unknown TEST_KIND: ${TEST_KIND}")
endif()

execute_process(
  COMMAND "${PURE_EXECUTABLE}" ${pure_arguments}
  WORKING_DIRECTORY "${test_directory}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
  ENCODING UTF-8
)

if(NOT result EQUAL 0)
  message(FATAL_ERROR
    "pure-stllib ${TEST_KIND} tests failed (${result})\nstdout:\n${output}\nstderr:\n${error}")
endif()

string(ASCII 9 tab)
set(libunwind_warning_count 0)
set(libunwind_line
  "libunwind: ${tab}pc not in table, pc=0x[0-9A-Fa-f]+")
if(error STREQUAL "")
  # No diagnostics.
elseif(error MATCHES "^(${libunwind_line}\r?\n)+$")
  string(REGEX MATCHALL "${libunwind_line}" libunwind_warnings "${error}")
  list(LENGTH libunwind_warnings libunwind_warning_count)
else()
  message(FATAL_ERROR
    "pure-stllib ${TEST_KIND} emitted unexpected stderr\n"
    "stdout:\n${output}\nstderr:\n${error}")
endif()
if(libunwind_warning_count GREATER 0)
  message(STATUS
    "Allowed ${libunwind_warning_count} known libunwind JIT diagnostics")
endif()
if(NOT output MATCHES
    "(^|\r?\n)--- ${success_marker} ---([\r\n]|$)")
  message(FATAL_ERROR
    "pure-stllib ${TEST_KIND} success marker missing\nstdout:\n${output}\nstderr:\n${error}")
endif()
message(STATUS "${output}")
