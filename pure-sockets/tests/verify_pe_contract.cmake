cmake_minimum_required(VERSION 3.25)
foreach(required IN ITEMS SOCKETS_DLL LLVM_READOBJ_EXECUTABLE)
  if(NOT DEFINED ${required} OR NOT EXISTS "${${required}}")
    message(FATAL_ERROR "${required} must name an existing file")
  endif()
endforeach()
function(read_pe out option)
  execute_process(COMMAND "${LLVM_READOBJ_EXECUTABLE}" "${option}" "${SOCKETS_DLL}"
    RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
  if(NOT result EQUAL 0)
    message(FATAL_ERROR "llvm-readobj ${option} failed:\n${output}${error}")
  endif()
  set(${out} "${output}" PARENT_SCOPE)
endfunction()
read_pe(headers --file-headers)
if(NOT headers MATCHES "Format: COFF-x86-64" OR
    NOT headers MATCHES "Machine: IMAGE_FILE_MACHINE_AMD64")
  message(FATAL_ERROR "sockets.dll is not an AMD64 PE image:\n${headers}")
endif()
read_pe(exports --coff-exports)
string(REGEX MATCHALL "Name: [A-Za-z_][A-Za-z0-9_]*" export_lines "${exports}")
list(TRANSFORM export_lines REPLACE "Name: " "")
list(SORT export_lines)
set(expected_exports __socket_defs gai_strerrorA gai_strerrorW local_sockaddr
  make_sockaddr make_sockaddrs new_sockaddr pure_accept pure_bind
  pure_closesocket pure_connect pure_getpeername pure_getsockname
  pure_getsockopt pure_listen pure_recv pure_recvfrom pure_send pure_sendto
  pure_setsockopt pure_shutdown pure_socket pure_socket_cleanup
  pure_socket_errno pure_socket_startup pure_socket_strerror pure_socketpair
  sockaddr_family sockaddr_hostname sockaddr_ip sockaddr_len sockaddr_path
  sockaddr_port sockaddr_service socketpair)
list(SORT expected_exports)
if(NOT export_lines STREQUAL expected_exports)
  message(FATAL_ERROR "Unexpected exports. Expected '${expected_exports}', got '${export_lines}'")
endif()
read_pe(imports --coff-imports)
string(REGEX MATCHALL "Name: [^\r\n]+" import_lines "${imports}")
list(TRANSFORM import_lines REPLACE "Name: " "")
list(TRANSFORM import_lines TOLOWER)
list(SORT import_lines)
set(expected_imports api-ms-win-crt-convert-l1-1-0.dll
  api-ms-win-crt-heap-l1-1-0.dll api-ms-win-crt-private-l1-1-0.dll
  api-ms-win-crt-runtime-l1-1-0.dll api-ms-win-crt-stdio-l1-1-0.dll
  api-ms-win-crt-string-l1-1-0.dll kernel32.dll libpure.dll ws2_32.dll)
list(SORT expected_imports)
if(NOT import_lines STREQUAL expected_imports)
  message(FATAL_ERROR "Unexpected imports. Expected '${expected_imports}', got '${import_lines}'")
endif()
