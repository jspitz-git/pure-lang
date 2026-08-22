foreach(required IN ITEMS AUDIT_EXECUTABLE SOCKETS_DLL PURE_EXECUTABLE)
  if(NOT DEFINED ${required} OR NOT EXISTS "${${required}}")
    message(FATAL_ERROR "${required} must name an existing file")
  endif()
endforeach()

get_filename_component(pure_bin_dir "${PURE_EXECUTABLE}" DIRECTORY)
get_filename_component(runtime_prefix "${pure_bin_dir}" DIRECTORY)
if(NOT EXISTS "${runtime_prefix}/lib/pure/math.pure")
  message(FATAL_ERROR
    "PURE_EXECUTABLE must belong to an installed Pure runtime prefix")
endif()
unset(ENV{PURELIB})
set(ENV{PATH} "${pure_bin_dir};$ENV{SystemRoot}/System32;$ENV{SystemRoot}")
execute_process(COMMAND "${AUDIT_EXECUTABLE}" "${SOCKETS_DLL}"
  RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error
  TIMEOUT 10)
if(NOT result EQUAL 0 OR NOT error STREQUAL "")
  message(FATAL_ERROR "Winsock audit failed with ${result}\n${output}${error}")
endif()
if(NOT output MATCHES "(^|\r?\n)PURE_SOCKETS_WINSOCK_AUDIT_OK(\r?\n|$)")
  message(FATAL_ERROR "Winsock audit did not emit its success marker\n${output}")
endif()
