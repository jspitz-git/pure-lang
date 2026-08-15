foreach(required IN ITEMS
    BUILD_DIR STAGE_PREFIX PURE_EXECUTABLE PURE_PREFIX FIXTURE_BASE
    RUNTIME_SMOKE_SCRIPT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

foreach(required_file IN ITEMS "${PURE_EXECUTABLE}" "${RUNTIME_SMOKE_SCRIPT}")
  if(NOT EXISTS "${required_file}")
    message(FATAL_ERROR "Missing runtime smoke input: ${required_file}")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH BUILD_DIR NORMALIZE OUTPUT_VARIABLE build_dir)
cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE stage)
cmake_path(ABSOLUTE_PATH PURE_PREFIX NORMALIZE OUTPUT_VARIABLE pure_prefix)
cmake_path(ABSOLUTE_PATH FIXTURE_BASE NORMALIZE OUTPUT_VARIABLE fixture_base)

set(package_stage "${build_dir}/runtime package stage")
execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DBUILD_DIR=${build_dir}"
    "-DSTAGE_PREFIX=${package_stage}"
    "-DEXPECT_DEVELOPER=OFF"
    -P "${CMAKE_CURRENT_LIST_DIR}/VerifyInstalledPackage.cmake"
  RESULT_VARIABLE package_result
  OUTPUT_VARIABLE package_output
  ERROR_VARIABLE package_error
  ENCODING UTF-8)
if(NOT package_result EQUAL 0)
  message(FATAL_ERROR
    "Runtime package staging failed (${package_result})\n"
    "stdout:\n${package_output}\nstderr:\n${package_error}")
endif()

file(REMOVE_RECURSE "${stage}")
file(COPY "${pure_prefix}/bin/" DESTINATION "${stage}/bin")
file(COPY "${pure_prefix}/lib/pure/" DESTINATION "${stage}/lib/pure")
execute_process(
  COMMAND "${CMAKE_COMMAND}" --install "${build_dir}"
    --prefix "${stage}" --component Runtime
  RESULT_VARIABLE install_result
  OUTPUT_VARIABLE install_output
  ERROR_VARIABLE install_error
  ENCODING UTF-8)
if(NOT install_result EQUAL 0)
  message(FATAL_ERROR
    "Runtime smoke install failed (${install_result})\n"
    "stdout:\n${install_output}\nstderr:\n${install_error}")
endif()

if(NOT EXISTS "${fixture_base}.bc")
  message(FATAL_ERROR "Missing runtime smoke fixture: ${fixture_base}.bc")
endif()

cmake_path(GET PURE_EXECUTABLE FILENAME pure_executable_name)
set(staged_pure_executable "${stage}/bin/${pure_executable_name}")
if(NOT EXISTS "${staged_pure_executable}")
  message(FATAL_ERROR
    "Missing staged Pure executable: ${staged_pure_executable}")
endif()

cmake_path(GET fixture_base PARENT_PATH fixture_dir)
set(work_dir "${build_dir}/runtime smoke work")
file(REMOVE_RECURSE "${work_dir}")
file(MAKE_DIRECTORY "${work_dir}")

set(ENV{PATH} "${stage}/bin;C:/Windows/System32;C:/Windows")
unset(ENV{PURELIB})
execute_process(
  COMMAND "${staged_pure_executable}" --norc
    -I "${stage}/lib/pure"
    -L "${fixture_dir}"
    -x "${RUNTIME_SMOKE_SCRIPT}" "${fixture_base}"
  WORKING_DIRECTORY "${work_dir}"
  TIMEOUT 90
  RESULT_VARIABLE smoke_result
  OUTPUT_VARIABLE smoke_output
  ERROR_VARIABLE smoke_error
  ENCODING UTF-8)
file(REMOVE_RECURSE "${work_dir}")

set(smoke_transcript "${smoke_output}\n${smoke_error}")
string(FIND "${smoke_transcript}" "pure-faust runtime smoke: PASS" pass_marker)
if(NOT smoke_result EQUAL 0 OR NOT "${smoke_error}" STREQUAL "" OR
    pass_marker EQUAL -1)
  message(FATAL_ERROR
    "Pure runtime smoke failed (${smoke_result})\n"
    "stdout:\n${smoke_output}\nstderr:\n${smoke_error}")
endif()

message(STATUS "Pure runtime smoke passed: ${stage}")
