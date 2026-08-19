cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS STAGER TEST_ROOT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "SDK_RUNTIME_FIXTURE: ${required} is required")
  endif()
endforeach()

set(runtime_dlls
  libc++.dll
  libgmp-10.dll
  libiconv-2.dll
  libmpfr-6.dll
  libpcre-1.dll
  libpcreposix-0.dll
  libreadline8.dll
  libtermcap-0.dll
  libwinpthread-1.dll
  libzstd.dll
  zlib1.dll)

set(source "${TEST_ROOT}/toolchain/bin")
set(prefix "${TEST_ROOT}/Pure SDK prefix")
file(REMOVE_RECURSE "${TEST_ROOT}")
file(MAKE_DIRECTORY "${source}" "${prefix}/bin")
foreach(dll IN LISTS runtime_dlls)
  file(WRITE "${source}/${dll}" "MZfixture:${dll}\n")
endforeach()

function(run_stager mode expected_result expected_category)
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DMODE=${mode}"
      "-DPURE_PREFIX=${prefix}"
      "-DTOOLCHAIN_BIN=${source}"
      -P "${STAGER}"
    RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
  if(expected_result STREQUAL "pass")
    if(NOT result EQUAL 0)
      message(FATAL_ERROR
        "SDK_RUNTIME_FIXTURE: ${mode} should pass: ${output}${error}")
    endif()
  elseif(result EQUAL 0 OR NOT "${output}${error}" MATCHES
      "SDK_RUNTIME_${expected_category}")
    message(FATAL_ERROR
      "SDK_RUNTIME_FIXTURE: ${mode} should fail as ${expected_category}: "
      "exit=${result} output=[${output}${error}]")
  endif()
endfunction()

run_stager(STAGE pass "")

file(GLOB staged RELATIVE "${prefix}/bin" "${prefix}/bin/*.dll")
list(SORT staged)
set(expected "${runtime_dlls}")
list(SORT expected)
if(NOT staged STREQUAL expected)
  message(FATAL_ERROR
    "SDK_RUNTIME_FIXTURE: staged DLL set differs: [${staged}]")
endif()

file(REMOVE "${prefix}/bin/libmpfr-6.dll")
run_stager(VERIFY fail MISSING)

run_stager(STAGE pass "")
file(APPEND "${prefix}/bin/libmpfr-6.dll" "corruption")
run_stager(VERIFY fail HASH)

message(STATUS "Pure Windows SDK runtime closure contract passed")
