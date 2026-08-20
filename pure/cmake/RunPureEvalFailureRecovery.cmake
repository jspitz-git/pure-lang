if(NOT DEFINED PURE_EXECUTABLE OR
   NOT DEFINED PURE_SCRIPT OR
   NOT DEFINED PURE_EXPECTED)
  message(FATAL_ERROR "Missing Pure evaluation recovery test arguments")
endif()

set(summary "")
set(failures)
foreach(mode doeval-add doeval-lookup doeval-nested-lookup dodefn-add dodefn-lookup dodefn-remove dodefn-remove-persistent dodefn-publish)
  set(failure_mode "${mode}")
  if(mode STREQUAL "doeval-nested-lookup")
    set(failure_mode "doeval-lookup")
  endif()
  set(failure_environment "PURE_TEST_ORC_FAILURE=${failure_mode}")
  if(mode STREQUAL "doeval-add")
    set(failure_environment
      "PURE_TEST_ORC_FAILURE=doeval-add,generic-compile-remove"
      "PURE_TEST_CLEAN_SHUTDOWN=1")
  endif()
  if(mode STREQUAL "dodefn-remove")
    list(APPEND failure_environment
      "PURE_TEST_TRACKER_RETRY=1")
  endif()
  if(mode STREQUAL "dodefn-remove-persistent")
    list(APPEND failure_environment "PURE_TEST_CLEAN_SHUTDOWN=1")
  endif()
  set(child_timeout 30)
  if(mode STREQUAL "dodefn-remove-persistent")
    set(child_timeout 8)
  endif()
  if(mode MATCHES "^doeval-")
    list(APPEND failure_environment "PURE_TEST_ORC_FAILURE_SKIP=${failure_mode}")
  endif()
  if(mode STREQUAL "doeval-nested-lookup")
    list(APPEND failure_environment "PURE_TEST_NESTED_ENVIRONMENT=1")
  endif()
  execute_process(
    COMMAND
      "${CMAKE_COMMAND}" -E env
      ${failure_environment}
      "${PURE_EXECUTABLE}" --norc --noprelude -q
      --disable=doeval-add --disable=doeval-lookup
      --disable=doeval-nested-lookup --disable=dodefn-add
      --disable=dodefn-lookup --disable=dodefn-remove
      --disable=dodefn-remove-persistent --disable=dodefn-publish
      "--enable=${mode}"
    INPUT_FILE "${PURE_SCRIPT}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE stdout
    ERROR_VARIABLE stderr
    TIMEOUT ${child_timeout}
  )
  set(output "${stdout}${stderr}")
  if(mode STREQUAL "dodefn-remove-persistent")
    message("[${mode}] persistent cleanup output captured")
  else()
    message("[${mode}]\n${output}")
  endif()

  if(NOT result EQUAL 0)
    list(APPEND failures "Pure ${mode} child exited with status ${result}")
  endif()
  if(NOT output MATCHES "injected .* failure")
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

  if(mode STREQUAL "dodefn-remove-persistent")
    if(NOT output MATCHES "(^|[\r\n])7([\r\n]|$)")
      list(APPEND failures
        "Pure ${mode} child did not restore the previous definition value")
    endif()
    string(REGEX MATCHALL
      "failed to roll back temporary ORC unit" rollback_diagnostics
      "${output}")
    list(LENGTH rollback_diagnostics rollback_count)
    string(REGEX MATCHALL
      "failed to remove ORC compilation unit" shutdown_diagnostics
      "${output}")
    list(LENGTH shutdown_diagnostics shutdown_count)
    if(NOT rollback_count EQUAL 1)
      list(APPEND failures
        "Pure ${mode} child did not report exactly one guard cleanup failure")
    endif()
    if(NOT shutdown_count EQUAL 1)
      list(APPEND failures
        "Pure ${mode} child did not report exactly one bounded shutdown failure")
    endif()
    if(output MATCHES "failed to remove ORC environment unit")
      list(APPEND failures
        "Pure ${mode} child retried cleanup through a freed Env key")
    endif()
    string(APPEND summary
      "${mode}: orphaned tracker cleaned once; shutdown returned\n")
  elseif(mode STREQUAL "doeval-add")
    string(REGEX MATCHALL
      "failed to roll back temporary ORC unit" rollback_diagnostics
      "${output}")
    list(LENGTH rollback_diagnostics rollback_count)
    if(NOT rollback_count EQUAL 1)
      list(APPEND failures
        "Pure ${mode} child did not report exactly one stable cleanup failure")
    endif()
    if(output MATCHES "failed to remove ORC compilation unit")
      list(APPEND failures
        "Pure ${mode} child did not retry its cleanup owner at shutdown")
    endif()
    string(APPEND summary
      "${mode}: failed add retained cleanup owner; recovered 42\n")
  elseif(mode STREQUAL "dodefn-publish")
    foreach(symbol publish_first publish_second)
      if(NOT output MATCHES "(^|[\r\n])${symbol}([\r\n]|$)")
        list(APPEND failures
          "Pure ${mode} child exposed partially published ${symbol}")
      endif()
    endforeach()
    if(NOT output MATCHES "(^|[\r\n])43([\r\n]|$)")
      list(APPEND failures
        "Pure ${mode} child could not redefine both bindings after rollback")
    endif()
    string(APPEND summary
      "${mode}: partial publication hidden; redefined both bindings\n")
  elseif(mode STREQUAL "dodefn-remove")
    if(NOT output MATCHES "(^|[\r\n])7([\r\n]|$)")
      list(APPEND failures
        "Pure ${mode} child did not restore the previous definition value")
    endif()
    string(APPEND summary
      "${mode}: restored previous value; retried cleanup; recovered 42\n")
  elseif(mode MATCHES "^dodefn-")
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
