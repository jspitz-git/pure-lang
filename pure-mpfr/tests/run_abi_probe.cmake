cmake_minimum_required(VERSION 3.25)
foreach(required IN ITEMS ABI_PROBE PURE_EXECUTABLE)
  if(NOT DEFINED ${required} OR NOT EXISTS "${${required}}")
    message(FATAL_ERROR "${required} must name an existing file")
  endif()
endforeach()
get_filename_component(pure_bin_dir "${PURE_EXECUTABLE}" DIRECTORY)
get_filename_component(runtime_prefix "${pure_bin_dir}" DIRECTORY)
if(NOT EXISTS "${runtime_prefix}/lib/pure/math.pure")
  message(FATAL_ERROR "PURE_EXECUTABLE must belong to an installed runtime")
endif()
execute_process(COMMAND "${CMAKE_COMMAND}" -E env
  "PATH=${pure_bin_dir};$ENV{SystemRoot}/System32;$ENV{SystemRoot}"
  "${ABI_PROBE}" RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
if(NOT result EQUAL 0 OR NOT error STREQUAL "" OR
    NOT output MATCHES "(^|\r?\n)PURE_MPFR_ABI_OK(\r?\n|$)")
  message(FATAL_ERROR "MPFR ABI probe failed (${result}):\n${output}${error}")
endif()
