cmake_minimum_required(VERSION 3.25)
if(NOT DEFINED VALIDATOR OR NOT DEFINED TEST_ROOT OR NOT DEFINED GENERATOR)
  message(FATAL_ERROR "test inputs missing")
endif()
file(REMOVE_RECURSE "${TEST_ROOT}")
file(MAKE_DIRECTORY "${TEST_ROOT}/Pure Prefix/include" "${TEST_ROOT}/Pure Prefix/lib")
file(WRITE "${TEST_ROOT}/Pure Prefix/lib/libpure.dll.a" "fixture")
file(MAKE_DIRECTORY "${TEST_ROOT}/outside/include")
file(WRITE "${TEST_ROOT}/outside/libpure.dll.a" "fixture")

function(run_case name expect_success prefix include library)
  execute_process(COMMAND "${CMAKE_COMMAND}"
    "-DTEST_PREFIX=${prefix}"
    "-DTEST_INCLUDE=${include}" "-DTEST_LIBRARY=${library}"
    -P "${VALIDATOR}" RESULT_VARIABLE result OUTPUT_VARIABLE output
    ERROR_VARIABLE error)
  if(expect_success AND NOT result EQUAL 0)
    message(FATAL_ERROR "${name} unexpectedly failed:\n${output}${error}")
  elseif(NOT expect_success AND result EQUAL 0)
    message(FATAL_ERROR "${name} unexpectedly passed")
  endif()
endfunction()

set(prefix "${TEST_ROOT}/Pure Prefix")
run_case(valid TRUE "${prefix}"
  "${prefix}/include" "${prefix}/lib/libpure.dll.a")
run_case(relative FALSE "Pure Prefix"
  "${prefix}/include" "${prefix}/lib/libpure.dll.a")
run_case(wrong-include FALSE "${prefix}"
  "${TEST_ROOT}/outside/include" "${prefix}/lib/libpure.dll.a")
run_case(wrong-library FALSE "${prefix}"
  "${prefix}/include" "${TEST_ROOT}/outside/libpure.dll.a")

set(probe_source "${TEST_ROOT}/target probe source")
file(MAKE_DIRECTORY "${probe_source}")
file(WRITE "${probe_source}/CMakeLists.txt"
  "cmake_minimum_required(VERSION 3.25)\nproject(target_probe C)\n"
  "include(\"${VALIDATOR}\")\npure_bonjour_validate_target()\n")
execute_process(COMMAND "${CMAKE_COMMAND}" -S "${probe_source}"
  -B "${TEST_ROOT}/target valid" -G "${GENERATOR}"
  "-DCMAKE_C_COMPILER=${C_COMPILER}" "-DCMAKE_MAKE_PROGRAM=${MAKE_PROGRAM}"
  RESULT_VARIABLE valid_target_result OUTPUT_VARIABLE valid_target_output
  ERROR_VARIABLE valid_target_error)
if(NOT valid_target_result EQUAL 0)
  message(FATAL_ERROR "configured x86-64 target rejected:\n${valid_target_output}${valid_target_error}")
endif()
execute_process(COMMAND "${CMAKE_COMMAND}" -S "${probe_source}"
  -B "${TEST_ROOT}/target arm64 mutation" -G "${GENERATOR}"
  "-DCMAKE_C_COMPILER=${C_COMPILER}" "-DCMAKE_MAKE_PROGRAM=${MAKE_PROGRAM}"
  "-DCMAKE_C_COMPILER_TARGET=x86_64-w64-windows-gnu"
  "-DCMAKE_C_FLAGS=-U__x86_64__ -D_M_ARM64=1"
  RESULT_VARIABLE arm_target_result OUTPUT_VARIABLE arm_target_output
  ERROR_VARIABLE arm_target_error)
if(arm_target_result EQUAL 0)
  message(FATAL_ERROR "ARM64 macro mutation bypassed configured compile probe")
endif()
if(NOT "${arm_target_output}${arm_target_error}" MATCHES
       "configured target to be Windows x86-64")
  message(FATAL_ERROR
    "ARM64 mutation failed outside the configured compile probe:\n"
    "${arm_target_output}${arm_target_error}")
endif()
