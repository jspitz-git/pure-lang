foreach(required
    PURE_EXECUTABLE
    PURE_SCRIPT_TEMPLATE
    PURE_FAUST_EXECUTABLE
    PURE_C_COMPILER
    PURE_SOURCE_DIR
    PURE_WORK_ROOT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "Missing inline Faust failure argument ${required}")
  endif()
endforeach()

function(quote_command output command)
  if(WIN32)
    set(${output} "\"${command}\"" PARENT_SCOPE)
  else()
    set(${output} "'${command}'" PARENT_SCOPE)
  endif()
endfunction()

function(write_exit_wrapper path status)
  if(WIN32)
    file(WRITE "${path}" "@echo off\r\nexit /b ${status}\r\n")
  else()
    file(WRITE "${path}" "#!/bin/sh\nexit ${status}\n")
    file(CHMOD "${path}" PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)
  endif()
endfunction()

function(write_corrupting_clang_wrapper path)
  if(WIN32)
    file(WRITE "${path}"
      "@echo off\r\n"
      "call \"${PURE_C_COMPILER}\" %*\r\n"
      "if errorlevel 1 exit /b %errorlevel%\r\n"
      "set \"pure_out=\"\r\n"
      ":pure_parse\r\n"
      "if \"%~1\"==\"\" goto pure_corrupt\r\n"
      "if \"%~1\"==\"-o\" set \"pure_out=%~2\"& goto pure_corrupt\r\n"
      "shift\r\n"
      "goto pure_parse\r\n"
      ":pure_corrupt\r\n"
      "if \"%pure_out%\"==\"\" exit /b 97\r\n"
      ">\"%pure_out%\" echo invalid bitcode\r\n"
      "exit /b 0\r\n")
  else()
    file(WRITE "${path}"
      "#!/bin/sh\n"
      "'${PURE_C_COMPILER}' \"$@\" || exit $?\n"
      "pure_previous=\n"
      "pure_out=\n"
      "for pure_arg in \"$@\"; do\n"
      "  if test \"$pure_previous\" = -o; then pure_out=$pure_arg; break; fi\n"
      "  pure_previous=$pure_arg\n"
      "done\n"
      "test -n \"$pure_out\" || exit 97\n"
      "printf 'invalid bitcode\\n' >\"$pure_out\"\n")
    file(CHMOD "${path}" PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)
  endif()
endfunction()

function(run_failure_case name faust_command clang_command environment expected)
  string(RANDOM LENGTH 12 ALPHABET 0123456789abcdef nonce)
  set(work_dir "${PURE_WORK_ROOT}/${name} path ${nonce}")
  set(script "${work_dir}/inline failure test.pure")
  file(MAKE_DIRECTORY "${work_dir}")
  configure_file("${PURE_SCRIPT_TEMPLATE}" "${script}" @ONLY)
  execute_process(
    COMMAND
      "${CMAKE_COMMAND}" -E env
      "PURE_FAUST=${faust_command}"
      "PURE_CC=${clang_command}"
      "PURELIB=${PURE_SOURCE_DIR}/lib"
      "PURE_INCLUDE=${PURE_SOURCE_DIR}/test"
      "srcdir=${PURE_SOURCE_DIR}"
      "LC_ALL=C"
      ${environment}
      "${PURE_EXECUTABLE}" --norc -v0
    INPUT_FILE "${script}"
    WORKING_DIRECTORY "${work_dir}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error_output
  )
  string(REPLACE "\r\n" "\n" output "${output}")
  string(REPLACE "\r\n" "\n" error_output "${error_output}")
  string(STRIP "${error_output}" diagnostic)
  file(GLOB leftovers LIST_DIRECTORIES FALSE "${work_dir}/pure Faust *")
  file(REMOVE_RECURSE "${work_dir}")
  if(NOT result EQUAL 0)
    file(REMOVE_RECURSE "${wrapper_dir}")
    message(FATAL_ERROR "${name}: Pure exited ${result}\n${error_output}")
  endif()
  if(NOT output STREQUAL "42\n")
    file(REMOVE_RECURSE "${wrapper_dir}")
    message(FATAL_ERROR "${name}: unexpected stdout [${output}]")
  endif()
  if(NOT diagnostic MATCHES "^<stdin>, line 1: ${expected}$")
    file(REMOVE_RECURSE "${wrapper_dir}")
    message(FATAL_ERROR
      "${name}: expected one exact diagnostic /${expected}/\n${error_output}")
  endif()
  if(leftovers)
    file(REMOVE_RECURSE "${wrapper_dir}")
    message(FATAL_ERROR "${name}: leftover owned files ${leftovers}")
  endif()
endfunction()

if(WIN32)
  set(wrapper_suffix ".cmd")
else()
  set(wrapper_suffix ".sh")
endif()
string(RANDOM LENGTH 12 ALPHABET 0123456789abcdef wrapper_nonce)
set(wrapper_dir
  "${PURE_WORK_ROOT}/inline failure wrappers with spaces ${wrapper_nonce}")
file(REMOVE_RECURSE "${wrapper_dir}")
file(MAKE_DIRECTORY "${wrapper_dir}")
set(faust_failure "${wrapper_dir}/Faust failure${wrapper_suffix}")
set(clang_failure "${wrapper_dir}/Clang failure${wrapper_suffix}")
set(clang_corrupt "${wrapper_dir}/Clang loader failure${wrapper_suffix}")
write_exit_wrapper("${faust_failure}" 41)
write_exit_wrapper("${clang_failure}" 42)
write_corrupting_clang_wrapper("${clang_corrupt}")

quote_command(faust "${PURE_FAUST_EXECUTABLE}")
quote_command(clang "${PURE_C_COMPILER}")
quote_command(failing_faust "${faust_failure}")
quote_command(failing_clang "${clang_failure}")
quote_command(corrupting_clang "${clang_corrupt}")

run_failure_case(
  "allocation boundary" "${faust}" "${clang}"
  "PURE_TEST_INLINE_SOURCE_FAILURE=1"
  "injected inline source allocation failure")
run_failure_case(
  "Faust failure" "${failing_faust}" "${clang}" ""
  "error compiling inline Faust code with Faust \\(status 41\\)")
run_failure_case(
  "Clang failure" "${faust}" "${failing_clang}" ""
  "error compiling inline Faust C code with Clang \\(status 42\\)")
run_failure_case(
  "loader failure" "${faust}" "${corrupting_clang}" ""
  "pure Faust bitcode\\.[A-Za-z0-9]+: Invalid bitcode signature")

file(REMOVE_RECURSE "${wrapper_dir}")
