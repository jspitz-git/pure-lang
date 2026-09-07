cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS SOURCE_DIR BINARY_DIR CONTRACT_ROOT TEST_ROOT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

foreach(path_var IN ITEMS SOURCE_DIR BINARY_DIR CONTRACT_ROOT TEST_ROOT)
  cmake_path(ABSOLUTE_PATH ${path_var} NORMALIZE OUTPUT_VARIABLE normalized)
  set(${path_var} "${normalized}")
endforeach()

function(require_safe_test_root)
  foreach(directory IN ITEMS SOURCE_DIR BINARY_DIR)
    if(NOT IS_DIRECTORY "${${directory}}")
      message(FATAL_ERROR
        "${directory} must be an existing directory: ${${directory}}")
    endif()
  endforeach()
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
  foreach(protected IN ITEMS SOURCE_DIR BINARY_DIR)
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

function(expect_unsafe_root_rejected label unsafe_contract_root unsafe_test_root)
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${SOURCE_DIR}"
      "-DBINARY_DIR=${BINARY_DIR}"
      "-DCONTRACT_ROOT=${unsafe_contract_root}"
      "-DTEST_ROOT=${unsafe_test_root}"
      -DROOT_SAFETY_PROBE=ON
      -P "${CMAKE_CURRENT_LIST_FILE}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8
  )
  if(result EQUAL 0)
    message(FATAL_ERROR
      "Runner cleanup guard accepted unsafe ${label}: ${unsafe_test_root}")
  endif()
  if(NOT "${output}\n${error}" MATCHES "Unsafe (CONTRACT_ROOT|TEST_ROOT)")
    message(FATAL_ERROR
      "Unsafe runner ${label} produced the wrong diagnostic\n${output}\n${error}")
  endif()
endfunction()

expect_unsafe_root_rejected("source TEST_ROOT" "${CONTRACT_ROOT}" "${SOURCE_DIR}")
expect_unsafe_root_rejected("binary TEST_ROOT" "${CONTRACT_ROOT}" "${BINARY_DIR}")
expect_unsafe_root_rejected("CONTRACT_ROOT" "${SOURCE_DIR}" "${SOURCE_DIR}/runner")

file(REMOVE_RECURSE "${TEST_ROOT}")
file(MAKE_DIRECTORY
  "${TEST_ROOT}/pure/bin"
  "${TEST_ROOT}/module"
  "${TEST_ROOT}/runtime")
file(WRITE "${TEST_ROOT}/pure/bin/pure.cmd"
  "@echo off\r\n"
  "echo EFFECTIVE_CWD=%CD%\r\n"
  "echo EFFECTIVE_PATH=%PATH%\r\n"
  "if defined PURELIB echo EFFECTIVE_PURELIB=SET\r\n"
  "if not defined PURELIB echo EFFECTIVE_PURELIB=UNSET\r\n"
  "exit /b 0\r\n")
file(WRITE "${TEST_ROOT}/pure/bin/stderr-pure.cmd"
  "@echo off\r\n"
  "echo ZERO_EXIT_STDERR_SENTINEL 1>&2\r\n"
  "exit /b 0\r\n")
file(WRITE "${TEST_ROOT}/test.pure" "// runner probe\n")

set(all_args
  "-DPURE_EXECUTABLE=${TEST_ROOT}/pure/bin/pure.cmd"
  "-DPACKAGE_DIR=${SOURCE_DIR}"
  "-DMODULE_DIR=${TEST_ROOT}/module"
  "-DRUNTIME_BIN_DIR=${TEST_ROOT}/runtime"
  "-DTEST_SCRIPT=${TEST_ROOT}/test.pure")

foreach(missing IN ITEMS PURE_EXECUTABLE PACKAGE_DIR MODULE_DIR RUNTIME_BIN_DIR TEST_SCRIPT)
  set(args ${all_args})
  list(FILTER args EXCLUDE REGEX "^-D${missing}=")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env
      "PATH=C:/ambient-msys2/bin;C:/ambient-tools"
      "PURELIB=C:/ambient-purelib"
      "${CMAKE_COMMAND}" ${args}
      -P "${SOURCE_DIR}/cmake/RunPureTest.cmake"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error)
  if(result EQUAL 0)
    message(FATAL_ERROR "Runner accepted a missing ${missing}")
  endif()
  if(NOT "${output}\n${error}" MATCHES "${missing} is required")
    message(FATAL_ERROR
      "Missing ${missing} produced the wrong diagnostic:\n${output}${error}")
  endif()
endforeach()

execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    "PATH=C:/ambient-msys2/bin;C:/ambient-tools"
    "PURELIB=C:/ambient-purelib"
    "${CMAKE_COMMAND}" ${all_args}
    -P "${SOURCE_DIR}/cmake/RunPureTest.cmake"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Runner probe failed:\n${output}${error}")
endif()
string(REGEX MATCH "EFFECTIVE_PATH=([^\r\n]+)" unused "${output}")
set(actual_path "${CMAKE_MATCH_1}")
set(expected_path
  "${TEST_ROOT}/module;${TEST_ROOT}/runtime;${TEST_ROOT}/pure/bin;C:/Windows/System32;C:/Windows")
string(REPLACE "\\" "/" actual_path "${actual_path}")
string(REPLACE "\\" "/" expected_path "${expected_path}")
if(NOT actual_path STREQUAL expected_path)
  message(FATAL_ERROR
    "Runner leaked or omitted a PATH entry. Expected '${expected_path}', got '${actual_path}'")
endif()
if(NOT "${output}" MATCHES "EFFECTIVE_PURELIB=UNSET")
  message(FATAL_ERROR "Runner did not unset PURELIB:\n${output}${error}")
endif()
string(REGEX MATCH "EFFECTIVE_CWD=([^\r\n]+)" unused "${output}")
set(actual_working_directory "${CMAKE_MATCH_1}")
string(REPLACE "\\" "/" actual_working_directory
  "${actual_working_directory}")
if(NOT actual_working_directory STREQUAL "C:/Windows")
  message(FATAL_ERROR
    "Runner used '${actual_working_directory}' instead of C:/Windows")
endif()

set(stderr_args ${all_args})
list(FILTER stderr_args EXCLUDE REGEX "^-DPURE_EXECUTABLE=")
list(PREPEND stderr_args
  "-DPURE_EXECUTABLE=${TEST_ROOT}/pure/bin/stderr-pure.cmd")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    "PATH=C:/ambient-msys2/bin;C:/ambient-tools"
    "PURELIB=C:/ambient-purelib"
    "${CMAKE_COMMAND}" ${stderr_args}
    -P "${SOURCE_DIR}/cmake/RunPureTest.cmake"
  RESULT_VARIABLE stderr_result
  OUTPUT_VARIABLE stderr_output
  ERROR_VARIABLE stderr_error
  ENCODING UTF-8)
set(stderr_diagnostics "${stderr_output}\n${stderr_error}")
if(stderr_result EQUAL 0)
  message(FATAL_ERROR "Runner accepted zero-exit nonempty stderr")
endif()
if(NOT stderr_diagnostics MATCHES "pure-glpk test emitted stderr" OR
    NOT stderr_diagnostics MATCHES "ZERO_EXIT_STDERR_SENTINEL")
  message(FATAL_ERROR
    "Zero-exit stderr produced the wrong diagnostic:\n${stderr_diagnostics}")
endif()
