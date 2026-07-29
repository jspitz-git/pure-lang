if (DEFINED PURE_OCTAVE_CONTAINMENT_WORKER)
  include("${CMAKE_CURRENT_LIST_DIR}/AcquireWindowsOctave.cmake")
  _pure_octave_validate_extraction_containment(
    "${PURE_OCTAVE_EXTRACTION_ROOT}" "${PURE_OCTAVE_WORK_ROOT}")
  return ()
endif ()

string(RANDOM LENGTH 12 ALPHABET 0123456789abcdef test_nonce)
set(test_root "${CMAKE_CURRENT_BINARY_DIR}/pure-octave-containment-regression-${test_nonce}")
set(extraction_root "${test_root}/extract")
set(outside_root "${test_root}/outside")
file(MAKE_DIRECTORY "${extraction_root}" "${outside_root}")
file(WRITE "${outside_root}/sentinel.txt" "outside controlled extraction root")
execute_process(
  COMMAND cmd /c mklink /J "${extraction_root}/escape" "${outside_root}"
  RESULT_VARIABLE link_result
  OUTPUT_VARIABLE link_stdout
  ERROR_VARIABLE link_stderr)
if (NOT link_result EQUAL 0)
  message(FATAL_ERROR "Containment regression requires a Windows junction fixture: ${link_stdout}${link_stderr}")
endif ()

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DPURE_OCTAVE_CONTAINMENT_WORKER=ON"
    "-DPURE_OCTAVE_EXTRACTION_ROOT=${extraction_root}"
    "-DPURE_OCTAVE_WORK_ROOT=${test_root}"
    -P "${CMAKE_CURRENT_LIST_FILE}"
  RESULT_VARIABLE containment_result
  OUTPUT_VARIABLE containment_stdout
  ERROR_VARIABLE containment_stderr)
if (containment_result EQUAL 0)
  message(FATAL_ERROR "Escaping materialized entry unexpectedly passed containment validation.")
endif ()
set(containment_output "${containment_stdout}${containment_stderr}")
if (NOT containment_output MATCHES "link-like")
  message(FATAL_ERROR "Containment rejection omitted the link-like diagnostic:\n${containment_output}")
endif ()
if (NOT containment_output MATCHES "PURE_OCTAVE_CONTAINMENT_ENTRIES:[1-9][0-9]*")
  message(FATAL_ERROR "Containment rejection omitted its enumeration count:\n${containment_output}")
endif ()
