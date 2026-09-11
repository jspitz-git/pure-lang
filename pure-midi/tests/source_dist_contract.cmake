cmake_minimum_required(VERSION 3.25)
foreach(required SOURCE_DIR CLANG64_PREFIX DIST_ROOT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "source contract requires ${required}")
  endif()
endforeach()
set(extra)
if(RED_ONLY)
  list(APPEND extra -RedOnly)
endif()
execute_process(COMMAND "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
  -NoProfile -NonInteractive -ExecutionPolicy Bypass
  -File "${SOURCE_DIR}/tests/source_dist_tools.ps1"
  -SourceDir "${SOURCE_DIR}" -Clang64Prefix "${CLANG64_PREFIX}"
  -DistRoot "${DIST_ROOT}" ${extra}
  RESULT_VARIABLE rc)
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "source distribution contract failed (${rc})")
endif()
