foreach(required IN ITEMS
    BUILD_DIR STAGE_PREFIX PURE_EXECUTABLE PURE_PREFIX MISSING_FIXTURE_BASE
    RUNTIME_SMOKE_SCRIPT FALSE_PASS_STAGE_PREFIX FALSE_PASS_FIXTURE_BASE
    FALSE_PASS_SCRIPT DRIVER_SOURCE)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DBUILD_DIR=${BUILD_DIR}"
    "-DSTAGE_PREFIX=${STAGE_PREFIX}"
    "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
    "-DPURE_PREFIX=${PURE_PREFIX}"
    "-DFIXTURE_BASE=${MISSING_FIXTURE_BASE}"
    "-DRUNTIME_SMOKE_SCRIPT=${RUNTIME_SMOKE_SCRIPT}"
    -P "${DRIVER_SOURCE}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
  ENCODING UTF-8)

set(transcript "${output}\n${error}")
if(result EQUAL 0)
  message(FATAL_ERROR "Missing fixture unexpectedly passed\n${transcript}")
endif()
if(NOT transcript MATCHES "Missing runtime smoke fixture")
  message(FATAL_ERROR
    "Missing fixture produced the wrong diagnostic (${result})\n${transcript}")
endif()

message(STATUS "Missing runtime smoke fixture was rejected")

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DBUILD_DIR=${BUILD_DIR}"
    "-DSTAGE_PREFIX=${FALSE_PASS_STAGE_PREFIX}"
    "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
    "-DPURE_PREFIX=${PURE_PREFIX}"
    "-DFIXTURE_BASE=${FALSE_PASS_FIXTURE_BASE}"
    "-DRUNTIME_SMOKE_SCRIPT=${FALSE_PASS_SCRIPT}"
    -P "${DRIVER_SOURCE}"
  RESULT_VARIABLE false_pass_result
  OUTPUT_VARIABLE false_pass_output
  ERROR_VARIABLE false_pass_error
  ENCODING UTF-8)

cmake_path(GET PURE_EXECUTABLE FILENAME pure_executable_name)
cmake_path(GET FALSE_PASS_FIXTURE_BASE PARENT_PATH false_pass_fixture_dir)
set(control_work_dir "${BUILD_DIR}/false pass control work")
file(REMOVE_RECURSE "${control_work_dir}")
file(MAKE_DIRECTORY "${control_work_dir}")
set(ENV{PATH}
  "${FALSE_PASS_STAGE_PREFIX}/bin;C:/Windows/System32;C:/Windows")
unset(ENV{PURELIB})
execute_process(
  COMMAND "${FALSE_PASS_STAGE_PREFIX}/bin/${pure_executable_name}" --norc
    -I "${FALSE_PASS_STAGE_PREFIX}/lib/pure"
    -L "${false_pass_fixture_dir}"
    -x "${FALSE_PASS_SCRIPT}" "${FALSE_PASS_FIXTURE_BASE}"
  WORKING_DIRECTORY "${control_work_dir}"
  TIMEOUT 90
  RESULT_VARIABLE control_result
  OUTPUT_VARIABLE control_output
  ERROR_VARIABLE control_error
  ENCODING UTF-8)
file(REMOVE_RECURSE "${control_work_dir}")

string(FIND "${control_output}" "pure-faust runtime smoke: PASS"
  control_pass_marker)
if(NOT control_result EQUAL 0 OR control_pass_marker EQUAL -1 OR
    NOT control_error MATCHES "synthetic runtime error")
  message(FATAL_ERROR
    "False-PASS control did not produce status 0, PASS, and stderr\n"
    "status: ${control_result}\nstdout:\n${control_output}"
    "stderr:\n${control_error}")
endif()

set(false_pass_transcript "${false_pass_output}\n${false_pass_error}")
if(false_pass_result EQUAL 0)
  message(FATAL_ERROR
    "Runtime diagnostic plus PASS marker unexpectedly passed\n"
    "${false_pass_transcript}")
endif()
if(NOT false_pass_transcript MATCHES "synthetic runtime error")
  message(FATAL_ERROR
    "False-PASS rejection lost its runtime diagnostic (${false_pass_result})\n"
    "${false_pass_transcript}")
endif()

message(STATUS "Runtime diagnostic plus PASS marker was rejected")
