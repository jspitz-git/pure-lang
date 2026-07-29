foreach (required_variable
    HELPER LOADER IMPLEMENTATION PURE_RUNTIME_STUB TEST_BINARY_DIR OBJDUMP POISON_DLL
    SOURCE_RUNTIME_DIR SOURCE_MODULE_DIR SOURCE_FINGERPRINT WORK_ROOT)
  if (NOT DEFINED ${required_variable} OR "${${required_variable}}" STREQUAL "")
    message(FATAL_ERROR
      "${required_variable} is required for the absolute preload test.")
  endif ()
endforeach ()
cmake_path(ABSOLUTE_PATH PURE_RUNTIME_STUB NORMALIZE
  OUTPUT_VARIABLE pure_runtime_stub_path)
cmake_path(ABSOLUTE_PATH TEST_BINARY_DIR NORMALIZE
  OUTPUT_VARIABLE test_binary_dir_path)
cmake_path(IS_PREFIX test_binary_dir_path "${pure_runtime_stub_path}"
  NORMALIZE stub_is_test_artifact)
if (NOT stub_is_test_artifact)
  message(FATAL_ERROR
    "Pure runtime stub escaped test build tree: ${pure_runtime_stub_path}")
endif ()
get_filename_component(stub_name "${pure_runtime_stub_path}" NAME)
if (NOT stub_name STREQUAL "libpure.dll")
  message(FATAL_ERROR "Pure runtime stub has unexpected name: ${stub_name}")
endif ()
if (NOT EXISTS "${pure_runtime_stub_path}" OR NOT EXISTS "${OBJDUMP}")
  message(FATAL_ERROR "Pure runtime stub audit input is missing.")
endif ()
include("${CMAKE_CURRENT_LIST_DIR}/AuditPureRuntimeStub.cmake")

set(source_runtime_dll "${SOURCE_RUNTIME_DIR}/liboctinterp-15.dll")
set(source_module_candidate "${SOURCE_MODULE_DIR}/liboctinterp-15.dll")
if (NOT EXISTS "${source_runtime_dll}" OR
    NOT EXISTS "${SOURCE_FINGERPRINT}")
  message(FATAL_ERROR "The signed source root is incomplete.")
endif ()
if (EXISTS "${source_module_candidate}")
  message(FATAL_ERROR
    "Signed source module directory already contains liboctinterp-15.dll.")
endif ()
file(SHA256 "${source_runtime_dll}" source_runtime_hash_before)

set(fixture_root "${WORK_ROOT}/fixture-root")
set(fixture_runtime_dir "${fixture_root}/mingw64/bin")
set(fixture_module_dir "${fixture_root}/mingw64/lib/octave/11.3.0")
set(fixture_m_dir "${fixture_root}/mingw64/share/octave/11.3.0/m")
set(fixture_runtime_dll "${fixture_runtime_dir}/liboctinterp-15.dll")
set(injected_dll "${fixture_module_dir}/liboctinterp-15.dll")
set(poison_marker "${WORK_ROOT}/poison-octinterp.marker")

file(REMOVE_RECURSE "${fixture_root}")
file(REMOVE "${poison_marker}")
file(MAKE_DIRECTORY
  "${fixture_runtime_dir}" "${fixture_module_dir}" "${fixture_m_dir}")
file(COPY_FILE
  "${SOURCE_FINGERPRINT}" "${fixture_root}/pure-octave.fingerprint")
file(GLOB source_runtime_dlls "${SOURCE_RUNTIME_DIR}/*.dll")
foreach (source_dll IN LISTS source_runtime_dlls)
  get_filename_component(dll_name "${source_dll}" NAME)
  file(CREATE_LINK "${source_dll}" "${fixture_runtime_dir}/${dll_name}"
    COPY_ON_ERROR RESULT link_result)
  if (NOT link_result STREQUAL "0")
    message(FATAL_ERROR
      "Could not stage runtime DLL ${dll_name}: ${link_result}")
  endif ()
endforeach ()
file(COPY_FILE "${pure_runtime_stub_path}"
  "${fixture_runtime_dir}/libpure.dll"
  ONLY_IF_DIFFERENT)
if (NOT EXISTS "${fixture_runtime_dll}")
  message(FATAL_ERROR "Disposable fixture omitted liboctinterp-15.dll.")
endif ()
file(COPY_FILE "${POISON_DLL}" "${injected_dll}" ONLY_IF_DIFFERENT)
set(ENV{PURE_OCTAVE_POISON_MARKER} "${poison_marker}")

execute_process(
  COMMAND "${HELPER}" "${LOADER}" "${fixture_root}"
    "${fixture_runtime_dll}"
  RESULT_VARIABLE helper_result
  OUTPUT_VARIABLE helper_stdout
  ERROR_VARIABLE helper_stderr)

set(marker_was_written FALSE)
set(marker_contents "")
if (EXISTS "${poison_marker}")
  set(marker_was_written TRUE)
  file(READ "${poison_marker}" marker_contents)
  file(REMOVE "${poison_marker}")
endif ()
file(REMOVE_RECURSE "${fixture_root}")
if (EXISTS "${fixture_root}" OR EXISTS "${poison_marker}")
  message(FATAL_ERROR
    "Absolute preload test left fixture or poison-marker artifacts.")
endif ()

file(SHA256 "${source_runtime_dll}" source_runtime_hash_after)
if (NOT source_runtime_hash_before STREQUAL source_runtime_hash_after)
  message(FATAL_ERROR "Signed source runtime DLL changed during the test.")
endif ()
if (EXISTS "${source_module_candidate}")
  message(FATAL_ERROR
    "Test polluted the signed source module directory.")
endif ()

if (NOT helper_result EQUAL 0)
  message(FATAL_ERROR
    "Absolute preload helper failed (${helper_result}); "
    "poison marker written=${marker_was_written} '${marker_contents}':\n"
    "${helper_stdout}${helper_stderr}")
endif ()
if (marker_was_written)
  message(FATAL_ERROR
    "Poison DLL executed despite successful helper: ${marker_contents}")
endif ()
if (NOT helper_stdout MATCHES "PURE_OCTAVE_ABSOLUTE_PRELOAD_OK")
  message(FATAL_ERROR
    "Absolute preload helper omitted success marker:\n"
    "${helper_stdout}${helper_stderr}")
endif ()
