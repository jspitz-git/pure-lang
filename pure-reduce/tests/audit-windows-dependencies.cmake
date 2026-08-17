cmake_minimum_required(VERSION 3.25)

foreach(_required IN ITEMS
    PURE_REDUCE_SOURCE_DIR
    PURE_REDUCE_LLVM_READOBJ
    PURE_REDUCE_CXX_COMPILER)
  if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
    message(FATAL_ERROR "${_required} is required")
  endif()
endforeach()

include("${PURE_REDUCE_SOURCE_DIR}/cmake/AuditWindowsDependencies.cmake")

if(PURE_REDUCE_AUDIT_PROBE)
  pure_reduce_audit_pe(
    "${PURE_REDUCE_AUDIT_ROOT_FILES}"
    "${PURE_REDUCE_AUDIT_SEARCH_DIRS}"
    _unused_closure)
  message(FATAL_ERROR "dependency audit probe unexpectedly succeeded")
endif()

foreach(_required IN ITEMS PURE_REDUCE_DLL PURE_REDUCE_TEST_ROOT)
  if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
    message(FATAL_ERROR "${_required} is required")
  endif()
endforeach()

file(REAL_PATH "${PURE_REDUCE_DLL}" _canonical_reduce)
pure_reduce_audit_pe(
  "${PURE_REDUCE_DLL};${PURE_REDUCE_DLL}"
  "${PURE_REDUCE_SEARCH_DIRS}"
  _real_closure)
if(NOT _real_closure STREQUAL _canonical_reduce)
  message(FATAL_ERROR
    "real bridge closure is not canonical, sorted, and duplicate-free: "
    "${_real_closure}")
endif()

file(REMOVE_RECURSE "${PURE_REDUCE_TEST_ROOT}")
file(MAKE_DIRECTORY
  "${PURE_REDUCE_TEST_ROOT}/dependency"
  "${PURE_REDUCE_TEST_ROOT}/one"
  "${PURE_REDUCE_TEST_ROOT}/two")
set(_dependency_source "${PURE_REDUCE_TEST_ROOT}/dependency.cpp")
set(_root_source "${PURE_REDUCE_TEST_ROOT}/root.cpp")
set(_dependency_dll "${PURE_REDUCE_TEST_ROOT}/dependency/synthetic+audit.dll")
set(_import_library "${PURE_REDUCE_TEST_ROOT}/dependency/synthetic+audit.dll.a")
set(_root_dll "${PURE_REDUCE_TEST_ROOT}/synthetic-root.dll")
file(WRITE "${_dependency_source}"
  "extern \"C\" __declspec(dllexport) int synthetic_audit_value() { return 7; }\n")
file(WRITE "${_root_source}"
  "extern \"C\" __declspec(dllimport) int synthetic_audit_value();\n"
  "extern \"C\" __declspec(dllexport) int synthetic_root() { return synthetic_audit_value(); }\n")
execute_process(
  COMMAND "${PURE_REDUCE_CXX_COMPILER}" -shared "${_dependency_source}"
    -o "${_dependency_dll}"
    "-Wl,--out-implib,${_import_library}"
  RESULT_VARIABLE _dependency_result
  OUTPUT_VARIABLE _dependency_output
  ERROR_VARIABLE _dependency_error
  ENCODING UTF-8)
if(NOT _dependency_result EQUAL 0)
  message(FATAL_ERROR
    "synthetic dependency build failed (${_dependency_result})\n"
    "stdout:\n${_dependency_output}\nstderr:\n${_dependency_error}")
endif()
execute_process(
  COMMAND "${PURE_REDUCE_CXX_COMPILER}" -shared "${_root_source}"
    "${_import_library}" -o "${_root_dll}"
  RESULT_VARIABLE _root_result
  OUTPUT_VARIABLE _root_output
  ERROR_VARIABLE _root_error
  ENCODING UTF-8)
if(NOT _root_result EQUAL 0)
  message(FATAL_ERROR
    "synthetic root build failed (${_root_result})\n"
    "stdout:\n${_root_output}\nstderr:\n${_root_error}")
endif()

file(COPY_FILE "${_dependency_dll}"
  "${PURE_REDUCE_TEST_ROOT}/one/synthetic+audit.dll")
file(COPY_FILE "${_dependency_dll}"
  "${PURE_REDUCE_TEST_ROOT}/two/synthetic+audit.dll")
file(REMOVE "${_dependency_dll}")

function(_expect_audit_rejection ROOT_FILE SEARCH_DIRS EXPECTED)
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      -DPURE_REDUCE_AUDIT_PROBE=ON
      "-DPURE_REDUCE_SOURCE_DIR=${PURE_REDUCE_SOURCE_DIR}"
      "-DPURE_REDUCE_LLVM_READOBJ=${PURE_REDUCE_LLVM_READOBJ}"
      "-DPURE_REDUCE_CXX_COMPILER=${PURE_REDUCE_CXX_COMPILER}"
      "-DPURE_REDUCE_AUDIT_ROOT_FILES=${ROOT_FILE}"
      "-DPURE_REDUCE_AUDIT_SEARCH_DIRS=${SEARCH_DIRS}"
      -P "${CMAKE_CURRENT_LIST_FILE}"
    RESULT_VARIABLE _result
    OUTPUT_VARIABLE _output
    ERROR_VARIABLE _error
    ENCODING UTF-8)
  if(_result EQUAL 0 OR NOT _error MATCHES "${EXPECTED}")
    message(FATAL_ERROR
      "expected audit rejection '${EXPECTED}'\n"
      "stdout:\n${_output}\nstderr:\n${_error}")
  endif()
endfunction()

_expect_audit_rejection("${_root_dll}"
  "${PURE_REDUCE_TEST_ROOT}/dependency"
  "unresolved PE import.*synthetic\\+audit\\.dll")
_expect_audit_rejection("${_root_dll}"
  "${PURE_REDUCE_TEST_ROOT}/one;${PURE_REDUCE_TEST_ROOT}/two"
  "ambiguous PE import.*synthetic\\+audit\\.dll")
_expect_audit_rejection("${_import_library}"
  "${PURE_REDUCE_TEST_ROOT}/dependency"
  "forbidden PE audit payload")

file(COPY_FILE "${PURE_REDUCE_TEST_ROOT}/one/synthetic+audit.dll"
  "${PURE_REDUCE_TEST_ROOT}/dependency/synthetic+audit.dll")
pure_reduce_audit_pe(
  "${_root_dll};${_root_dll}"
  "${PURE_REDUCE_TEST_ROOT}/dependency"
  _synthetic_closure)
file(REAL_PATH "${_root_dll}" _canonical_root)
file(REAL_PATH
  "${PURE_REDUCE_TEST_ROOT}/dependency/synthetic+audit.dll"
  _canonical_dependency)
set(_expected_closure "${_canonical_dependency};${_canonical_root}")
list(SORT _expected_closure COMPARE NATURAL CASE INSENSITIVE)
if(NOT _synthetic_closure STREQUAL _expected_closure)
  message(FATAL_ERROR
    "recursive closure is not sorted and duplicate-free\n"
    "expected: ${_expected_closure}\nactual: ${_synthetic_closure}")
endif()
list(LENGTH PURE_REDUCE_AUDIT_PARENT_RECORDS _parent_record_count)
if(NOT _parent_record_count EQUAL 2 OR
    NOT PURE_REDUCE_AUDIT_PARENT_RECORDS MATCHES
      "synthetic\\+audit\\.dll\\|.*synthetic-root\\.dll")
  message(FATAL_ERROR
    "audit parent records are incomplete: ${PURE_REDUCE_AUDIT_PARENT_RECORDS}")
endif()

set(_forbidden_dll "${PURE_REDUCE_TEST_ROOT}/dependency/msys-2.0.dll")
set(_forbidden_import "${PURE_REDUCE_TEST_ROOT}/dependency/msys-2.0.dll.a")
set(_forbidden_root "${PURE_REDUCE_TEST_ROOT}/forbidden-root.dll")
execute_process(
  COMMAND "${PURE_REDUCE_CXX_COMPILER}" -shared "${_dependency_source}"
    -o "${_forbidden_dll}"
    "-Wl,--out-implib,${_forbidden_import}"
  RESULT_VARIABLE _forbidden_dependency_result
  ERROR_VARIABLE _forbidden_dependency_error
  ENCODING UTF-8)
if(NOT _forbidden_dependency_result EQUAL 0)
  message(FATAL_ERROR
    "forbidden dependency fixture build failed: ${_forbidden_dependency_error}")
endif()
execute_process(
  COMMAND "${PURE_REDUCE_CXX_COMPILER}" -shared "${_root_source}"
    "${_forbidden_import}" -o "${_forbidden_root}"
  RESULT_VARIABLE _forbidden_root_result
  ERROR_VARIABLE _forbidden_root_error
  ENCODING UTF-8)
if(NOT _forbidden_root_result EQUAL 0)
  message(FATAL_ERROR
    "forbidden root fixture build failed: ${_forbidden_root_error}")
endif()
_expect_audit_rejection("${_forbidden_root}"
  "${PURE_REDUCE_TEST_ROOT}/dependency"
  "forbidden MSYS/Cygwin PE import msys-2\\.0\\.dll")

message(STATUS "pure-reduce recursive Windows dependency audit passed")
