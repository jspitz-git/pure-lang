if(NOT DEFINED PURE_EXECUTABLE OR
   NOT DEFINED PURE_SCRIPT OR
   NOT DEFINED PURE_EXPECTED)
  message(FATAL_ERROR "Missing Pure evaluation recovery test arguments")
endif()

set(summary "")
set(failures)
foreach(mode doeval-add doeval-lookup dodefn-add dodefn-lookup)
  set(failure_environment "PURE_TEST_ORC_FAILURE=${mode}")
  if(mode MATCHES "^doeval-")
    list(APPEND failure_environment "PURE_TEST_ORC_FAILURE_SKIP=${mode}")
  endif()
  execute_process(
    COMMAND
      "${CMAKE_COMMAND}" -E env
      ${failure_environment}
      "${PURE_EXECUTABLE}" --norc --noprelude -q
      --disable=doeval-add --disable=doeval-lookup
      --disable=dodefn-add --disable=dodefn-lookup "--enable=${mode}"
    INPUT_FILE "${PURE_SCRIPT}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE stdout
    ERROR_VARIABLE stderr
  )
  set(output "${stdout}${stderr}")
  message("[${mode}]\n${output}")

  if(NOT result EQUAL 0)
    list(APPEND failures "Pure ${mode} child exited with status ${result}")
  endif()
  if(NOT output MATCHES "injected .*ORC .* failure")
    list(APPEND failures
      "Pure ${mode} child did not report the injected failure")
  endif()
  if(NOT output MATCHES "(^|[\r\n])1([\r\n]|$)")
    list(APPEND failures
      "Pure ${mode} child did not restore nested evaluation state")
  endif()
  if(NOT output MATCHES "(^|[\r\n])42([\r\n]|$)")
    list(APPEND failures
      "Pure ${mode} child did not recover with literal 42")
  endif()

  if(mode MATCHES "^dodefn-")
    if(NOT output MATCHES "(^|[\r\n])failed_definition([\r\n]|$)")
      list(APPEND failures
        "Pure ${mode} child exposed the failed definition")
    endif()
    string(APPEND summary
      "${mode}: failed definition hidden; recovered 42\n")
  else()
    string(APPEND summary "${mode}: recovered 42\n")
  endif()
endforeach()

if(failures)
  string(JOIN "\n" failure_message ${failures})
  message(FATAL_ERROR "${failure_message}")
endif()

file(READ "${PURE_EXPECTED}" expected)
string(STRIP "${summary}" summary)
string(STRIP "${expected}" expected)
if(NOT summary STREQUAL expected)
  message(FATAL_ERROR "Pure evaluation recovery summary did not match")
endif()
