cmake_minimum_required(VERSION 3.25)
foreach(required SOURCE_DIR MODULE_DIR PURE_PREFIX RUNNER)
  if(NOT DEFINED ${required})
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()
set(extra)
if(RED_ONLY)
  list(APPEND extra -RedOnly)
endif()
execute_process(COMMAND "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
  -NoProfile -NonInteractive -ExecutionPolicy Bypass
  -File "${SOURCE_DIR}/tests/install_guard_contract.ps1"
  -SourceDir "${SOURCE_DIR}" -BuildDir "${MODULE_DIR}" -PurePrefix "${PURE_PREFIX}"
  -Runner "${RUNNER}" -Suite component ${extra}
  RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 550)
message(STATUS "${out}")
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "Install contract failed (${rc})\n${err}")
endif()
