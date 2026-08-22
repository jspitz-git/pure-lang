cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS PURE_EXECUTABLE SMOKE_SCRIPT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

if(DEFINED ENV{PURELIB})
  message(FATAL_ERROR "PURELIB survived staged-runtime sanitization")
endif()
string(TOLOWER "$ENV{PATH}" normalized_path)
if(normalized_path MATCHES "(^|;).*[/\\\\]msys64[/\\\\]")
  message(FATAL_ERROR "MSYS2 survived staged-runtime PATH sanitization")
endif()

execute_process(
  COMMAND "${PURE_EXECUTABLE}" --norc -x "${SMOKE_SCRIPT}"
  RESULT_VARIABLE smoke_result
  OUTPUT_VARIABLE smoke_stdout
  ERROR_VARIABLE smoke_stderr
)
if(NOT smoke_result EQUAL 0)
  message(FATAL_ERROR
    "Staged smoke test failed:\n${smoke_stdout}\n${smoke_stderr}")
endif()
