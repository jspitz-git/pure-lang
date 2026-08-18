cmake_minimum_required(VERSION 3.25)

foreach(required_path IN ITEMS
    PURE_EXECUTABLE MODULE_PATH WRAPPER_PATH SMOKE_SCRIPT)
  if(NOT DEFINED ${required_path} OR "${${required_path}}" STREQUAL "")
    message(FATAL_ERROR "${required_path} is required")
  endif()
  if(NOT IS_ABSOLUTE "${${required_path}}")
    message(FATAL_ERROR "${required_path} must be absolute: ${${required_path}}")
  endif()
  if(NOT EXISTS "${${required_path}}")
    message(FATAL_ERROR "${required_path} does not exist: ${${required_path}}")
  endif()
endforeach()

if(NOT DEFINED SMOKE_ROOT OR NOT IS_ABSOLUTE "${SMOKE_ROOT}")
  message(FATAL_ERROR "SMOKE_ROOT must be an absolute path")
endif()

set(powershell "$ENV{SystemRoot}/System32/WindowsPowerShell/v1.0/powershell.exe")
if(NOT EXISTS "${powershell}")
  message(FATAL_ERROR "Windows PowerShell is required to reserve an ephemeral port")
endif()

set(probe_command [=[
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
try {
  $listener.Start()
  $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
  [Console]::Out.Write(('{0}|{1}|{2}' -f $PID, [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(), $port))
} finally {
  $listener.Stop()
}
]=])
execute_process(
  COMMAND "${powershell}" -NoLogo -NoProfile -NonInteractive
    -Command "${probe_command}"
  RESULT_VARIABLE probe_result
  OUTPUT_VARIABLE probe_output
  ERROR_VARIABLE probe_error
  TIMEOUT 5)
if(NOT probe_result STREQUAL "0" OR
   NOT probe_output MATCHES "^[0-9]+\\|[0-9]+\\|[0-9]+$")
  message(FATAL_ERROR
    "Could not choose the unique service identity and ephemeral port. "
    "exit=${probe_result} stdout=[${probe_output}] stderr=[${probe_error}]")
endif()

string(REPLACE "|" ";" probe_fields "${probe_output}")
list(GET probe_fields 0 probe_pid)
list(GET probe_fields 1 probe_time)
list(GET probe_fields 2 test_port)
set(service_name "PureTodo45-${probe_pid}-${probe_time}")
string(RANDOM LENGTH 8 ALPHABET 0123456789abcdef directory_nonce)
set(test_directory
  "${SMOKE_ROOT}/pure-bonjour-smoke-${probe_pid}-${probe_time}-${directory_nonce}")
set(test_library "${test_directory}/lib")

file(MAKE_DIRECTORY "${test_library}")
file(COPY_FILE "${WRAPPER_PATH}" "${test_library}/bonjour.pure"
  ONLY_IF_DIFFERENT RESULT wrapper_copy_result)
file(COPY_FILE "${MODULE_PATH}" "${test_library}/bonjour.dll"
  ONLY_IF_DIFFERENT RESULT module_copy_result)

set(failure "")
if(NOT wrapper_copy_result STREQUAL "0")
  set(failure "Could not stage bonjour.pure: ${wrapper_copy_result}")
elseif(NOT module_copy_result STREQUAL "0")
  set(failure "Could not stage bonjour.dll: ${module_copy_result}")
else()
  get_filename_component(pure_bin "${PURE_EXECUTABLE}" DIRECTORY)
  get_filename_component(pure_prefix "${pure_bin}" DIRECTORY)
  set(pure_standard_library "${pure_prefix}/lib/pure")
  if(NOT IS_DIRECTORY "${pure_standard_library}")
    set(failure
      "Pure standard library does not exist: ${pure_standard_library}")
  endif()
  set(safe_path
    "${pure_bin};$ENV{SystemRoot}/System32;$ENV{SystemRoot};$ENV{SystemRoot}/System32/Wbem")
  if(failure STREQUAL "")
    execute_process(
      COMMAND "${CMAKE_COMMAND}" -E env
        "PURELIB=${test_library}"
        "PATH=${safe_path}"
        "${PURE_EXECUTABLE}" -q -n -b -I "${pure_standard_library}"
        "${pure_standard_library}/prelude.pure" "${SMOKE_SCRIPT}"
        -- "${service_name}" "${test_port}"
      WORKING_DIRECTORY "${test_directory}"
      RESULT_VARIABLE smoke_result
      OUTPUT_VARIABLE smoke_output
      ERROR_VARIABLE smoke_error
      TIMEOUT 25)
    string(REPLACE "\r\n" "\n" smoke_output "${smoke_output}")
    if(NOT smoke_result STREQUAL "0")
      set(failure
        "Pure smoke failed. exit=${smoke_result} name=${service_name} "
        "port=${test_port} stdout=[${smoke_output}] stderr=[${smoke_error}]")
    elseif(NOT smoke_output STREQUAL "PURE_BONJOUR_LOOPBACK_OK\n")
      set(failure
        "Pure smoke did not emit the exact success marker. "
        "stdout=[${smoke_output}] stderr=[${smoke_error}]")
    endif()
  endif()
endif()

file(REMOVE_RECURSE "${test_directory}")
if(NOT failure STREQUAL "")
  message(FATAL_ERROR "${failure}")
endif()
