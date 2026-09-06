cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS SOURCE_DIR BINARY_DIR PURE_EXECUTABLE RUNTIME_BIN_DIR
    TEST_ROOT)
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

set(bad_script "${TEST_ROOT}/bad-smoke.pure")
file(REMOVE_RECURSE "${TEST_ROOT}")
file(MAKE_DIRECTORY "${TEST_ROOT}")
file(WRITE "${bad_script}"
  "using xml;\n"
  "todo29_contract_invalid = @@@;\n"
  "puts \"PURE_XML_SMOKE_OK\";\n")

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
    "-DPACKAGE_DIR=${SOURCE_DIR}"
    "-DMODULE_DIR=${BINARY_DIR}"
    "-DRUNTIME_BIN_DIR=${RUNTIME_BIN_DIR}"
    "-DTEST_SCRIPT=${bad_script}"
    "-DTEST_DATA_DIR=${SOURCE_DIR}/tests"
    -P "${SOURCE_DIR}/cmake/RunSmokeTest.cmake"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
)
if(result EQUAL 0)
  message(FATAL_ERROR "Smoke runner accepted parser diagnostics")
endif()
if(NOT "${output}\n${error}" MATCHES "emitted stderr")
  message(FATAL_ERROR
    "Smoke runner rejected the fixture for the wrong reason:\n${output}${error}")
endif()

set(fake_prefix "${TEST_ROOT}/fake runtime")
set(fake_module "${TEST_ROOT}/fake module")
set(fake_deps "${TEST_ROOT}/fake dependencies")
file(MAKE_DIRECTORY
  "${fake_prefix}/bin" "${fake_prefix}/lib/pure"
  "${fake_module}" "${fake_deps}")
file(WRITE "${fake_prefix}/lib/pure/math.pure" "// fixture\n")
file(WRITE "${fake_prefix}/bin/pure.cmd"
  "@echo off\r\necho EFFECTIVE_PATH=%PATH%\r\n"
  "echo PURE_XML_SMOKE_OK\r\n")
foreach(runtime IN ITEMS
    libxml2-16.dll libxslt-1.dll libiconv-2.dll zlib1.dll)
  file(WRITE "${fake_deps}/${runtime}" "fixture")
endforeach()
execute_process(COMMAND "${CMAKE_COMMAND}"
  "-DPURE_EXECUTABLE=${fake_prefix}/bin/pure.cmd"
  "-DPACKAGE_DIR=${SOURCE_DIR}"
  "-DMODULE_DIR=${fake_module}"
  "-DRUNTIME_BIN_DIR=${fake_deps}"
  "-DTEST_SCRIPT=${bad_script}"
  "-DTEST_DATA_DIR=${SOURCE_DIR}/tests"
  -P "${SOURCE_DIR}/cmake/RunSmokeTest.cmake"
  RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "PATH fixture failed:\n${output}${error}")
endif()
set(expected_path
  "${fake_module};${fake_deps};${fake_prefix}/bin;$ENV{SystemRoot}/System32;$ENV{SystemRoot}")
string(REGEX MATCH "EFFECTIVE_PATH=([^\r\n]+)" unused "${output}")
set(actual_path "${CMAKE_MATCH_1}")
string(REPLACE "\\" "/" expected_normalized "${expected_path}")
string(REPLACE "\\" "/" actual_normalized "${actual_path}")
if(NOT actual_normalized STREQUAL expected_normalized)
  message(FATAL_ERROR
    "Smoke subprocess PATH differs. Expected '${expected_path}', got '${actual_path}'")
endif()
