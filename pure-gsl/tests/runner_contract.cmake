cmake_minimum_required(VERSION 3.25)
foreach(required IN ITEMS SOURCE_DIR BINARY_DIR TEST_ROOT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()
set(prefix "${TEST_ROOT}/runtime")
set(module "${TEST_ROOT}/module")
set(deps "${TEST_ROOT}/deps")
file(REMOVE_RECURSE "${TEST_ROOT}")
file(MAKE_DIRECTORY "${prefix}/bin" "${prefix}/lib/pure" "${module}" "${deps}")
file(WRITE "${prefix}/lib/pure/math.pure" "// fixture\n")
file(WRITE "${prefix}/bin/pure.cmd"
  "@echo off\r\necho EFFECTIVE_PATH=%%PATH%%\r\n"
  "echo parser diagnostic 1>&2\r\necho PURE_GSL_LOAD_OK\r\n")
foreach(dll IN ITEMS libgsl-28.dll libgslcblas-0.dll)
  file(WRITE "${deps}/${dll}" "fixture")
endforeach()
file(WRITE "${TEST_ROOT}/test.pure" "// fixture\n")
execute_process(COMMAND "${CMAKE_COMMAND}"
  "-DPURE_EXECUTABLE=${prefix}/bin/pure.cmd"
  "-DPACKAGE_DIR=${SOURCE_DIR}"
  "-DMODULE_DIR=${module}"
  "-DRUNTIME_BIN_DIR=${deps}"
  "-DTEST_SCRIPT=${TEST_ROOT}/test.pure"
  -P "${SOURCE_DIR}/cmake/RunPureTest.cmake"
  RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
if(result EQUAL 0)
  message(FATAL_ERROR "Runner accepted a Pure diagnostic on stderr")
endif()
if(NOT "${output}\n${error}" MATCHES "emitted stderr")
  message(FATAL_ERROR "Runner failed for the wrong reason:\n${output}${error}")
endif()

file(WRITE "${prefix}/bin/pure.cmd" "@echo off\r\necho EFFECTIVE_PATH=%PATH%\r\n")
execute_process(COMMAND "${CMAKE_COMMAND}"
  "-DPURE_EXECUTABLE=${prefix}/bin/pure.cmd"
  "-DPACKAGE_DIR=${SOURCE_DIR}" "-DMODULE_DIR=${module}"
  "-DRUNTIME_BIN_DIR=${deps}" "-DTEST_SCRIPT=${TEST_ROOT}/test.pure"
  -P "${SOURCE_DIR}/cmake/RunPureTest.cmake"
  RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "PATH fixture failed:\n${output}${error}")
endif()
string(REGEX MATCH "EFFECTIVE_PATH=([^\r\n]+)" unused "${output}")
set(actual "${CMAKE_MATCH_1}")
set(expected "${module};${deps};${prefix}/bin;$ENV{SystemRoot}/System32;$ENV{SystemRoot}")
string(REPLACE "\\" "/" actual "${actual}")
string(REPLACE "\\" "/" expected "${expected}")
if(NOT actual STREQUAL expected)
  message(FATAL_ERROR "Subprocess PATH differs. Expected '${expected}', got '${actual}'")
endif()
