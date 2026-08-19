cmake_minimum_required(VERSION 3.25)
if(NOT DEFINED VALIDATOR OR NOT DEFINED TEST_ROOT)
  message(FATAL_ERROR "test inputs missing")
endif()
file(REMOVE_RECURSE "${TEST_ROOT}")
file(MAKE_DIRECTORY "${TEST_ROOT}/Pure Prefix/include" "${TEST_ROOT}/Pure Prefix/lib")
file(WRITE "${TEST_ROOT}/Pure Prefix/lib/libpure.dll.a" "fixture")
file(MAKE_DIRECTORY "${TEST_ROOT}/outside/include")
file(WRITE "${TEST_ROOT}/outside/libpure.dll.a" "fixture")

function(run_case name expect_success triple prefix include library)
  execute_process(COMMAND "${CMAKE_COMMAND}"
    "-DTEST_TRIPLE=${triple}" "-DTEST_PREFIX=${prefix}"
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
run_case(valid TRUE x86_64-w64-windows-gnu "${prefix}"
  "${prefix}/include" "${prefix}/lib/libpure.dll.a")
run_case(arm64 FALSE aarch64-w64-windows-gnu "${prefix}"
  "${prefix}/include" "${prefix}/lib/libpure.dll.a")
run_case(relative FALSE x86_64-w64-windows-gnu "Pure Prefix"
  "${prefix}/include" "${prefix}/lib/libpure.dll.a")
run_case(wrong-include FALSE x86_64-w64-windows-gnu "${prefix}"
  "${TEST_ROOT}/outside/include" "${prefix}/lib/libpure.dll.a")
run_case(wrong-library FALSE x86_64-w64-windows-gnu "${prefix}"
  "${prefix}/include" "${TEST_ROOT}/outside/libpure.dll.a")
