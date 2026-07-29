include_guard(GLOBAL)

function(_pure_octave_validate_extraction_containment extraction_root work_root)
  if (NOT WIN32)
    message(FATAL_ERROR "Post-extraction containment validation is required on Windows.")
  endif ()

  file(REAL_PATH "${extraction_root}" normalized_extraction_root)
  file(REAL_PATH "${work_root}" normalized_work_root)
  cmake_path(IS_PREFIX normalized_work_root "${normalized_extraction_root}" NORMALIZE extraction_within_work_root)
  if (NOT extraction_within_work_root OR normalized_extraction_root STREQUAL normalized_work_root)
    message(FATAL_ERROR "Extraction root escaped or equals WORK_ROOT: ${extraction_root}")
  endif ()

  find_program(powershell_executable NAMES powershell.exe powershell pwsh.exe pwsh)
  if (NOT powershell_executable)
    message(FATAL_ERROR "PowerShell is required to validate materialized Windows extraction entries.")
  endif ()

  execute_process(
    COMMAND "${powershell_executable}" -NoLogo -NoProfile -NonInteractive -File
      "${CMAKE_CURRENT_LIST_DIR}/ValidateExtractionContainment.ps1"
      "${normalized_extraction_root}" "${normalized_work_root}"
    RESULT_VARIABLE containment_result
    OUTPUT_VARIABLE containment_stdout
    ERROR_VARIABLE containment_stderr)
  if (NOT containment_result EQUAL 0)
    message(FATAL_ERROR
      "Materialized extraction containment validation failed:\n${containment_stdout}${containment_stderr}")
  endif ()
  if (NOT containment_stdout MATCHES "PURE_OCTAVE_CONTAINMENT_ENTRIES:[1-9][0-9]*")
    message(FATAL_ERROR
      "Materialized extraction containment validation did not enumerate entries:\n${containment_stdout}${containment_stderr}")
  endif ()
  message(STATUS "${containment_stdout}")
endfunction ()
