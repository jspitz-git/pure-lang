cmake_minimum_required(VERSION 3.25)

foreach(required_variable IN ITEMS
    PUREPAD_CMAKE_COMMAND
    PUREPAD_SOURCE_POLICY_VERIFIER)
  if(NOT DEFINED ${required_variable} OR "${${required_variable}}" STREQUAL "")
    message(FATAL_ERROR "${required_variable} is required")
  endif()
endforeach()

string(RANDOM LENGTH 12 ALPHABET 0123456789abcdef purepad_policy_suffix)
set(purepad_fixture_root
  "${CMAKE_CURRENT_BINARY_DIR}/purepad-source-policy-${purepad_policy_suffix}")
set(purepad_fixture_source "${purepad_fixture_root}/source")
set(purepad_fixture_build "${purepad_fixture_root}/build")
file(MAKE_DIRECTORY "${purepad_fixture_source}" "${purepad_fixture_build}")

function(purepad_run_source_policy expected_result expected_message label)
  execute_process(
    COMMAND "${PUREPAD_CMAKE_COMMAND}"
      "-DPUREPAD_SOURCE_DIR=${purepad_fixture_source}"
      "-DPUREPAD_BUILD_DIR=${purepad_fixture_build}"
      -P "${PUREPAD_SOURCE_POLICY_VERIFIER}"
    RESULT_VARIABLE actual_result
    OUTPUT_VARIABLE actual_stdout
    ERROR_VARIABLE actual_stderr)
  set(actual_output "${actual_stdout}${actual_stderr}")
  if(expected_result STREQUAL "success")
    if(NOT actual_result EQUAL 0)
      message(FATAL_ERROR
        "Source-policy verifier rejected ${label}:\n${actual_output}")
    endif()
  else()
    if(actual_result EQUAL 0)
      message(FATAL_ERROR
        "Source-policy verifier accepted forbidden fixture ${label}")
    endif()
    if(NOT actual_output MATCHES "${expected_message}")
      message(FATAL_ERROR
        "Source-policy verifier rejected ${label} for the wrong reason:\n"
        "${actual_output}")
    endif()
  endif()
endfunction()

file(WRITE "${purepad_fixture_source}/allowed.cpp"
  "void purepad_allowed_source() {}\n")
purepad_run_source_policy(success "" "allowed source")

string(CONCAT purepad_thread_api "Terminate" "Thread")
file(WRITE "${purepad_fixture_source}/forbidden-thread.cpp"
  "void purepad_forbidden_source() { ${purepad_thread_api}(0, 0); }\n")
purepad_run_source_policy(failure "forbidden process-lifecycle API"
  "worker termination API")
file(REMOVE "${purepad_fixture_source}/forbidden-thread.cpp")

string(CONCAT purepad_association_api "RegisterShell" "FileTypes")
file(WRITE "${purepad_fixture_source}/forbidden-association.h"
  "inline void purepad_forbidden_header() { ${purepad_association_api}(1); }\n")
purepad_run_source_policy(failure "forbidden startup-association API"
  "startup association API")

file(REMOVE_RECURSE "${purepad_fixture_root}")
if(EXISTS "${purepad_fixture_root}")
  message(FATAL_ERROR
    "Source-policy contract cleanup left ${purepad_fixture_root}")
endif()
