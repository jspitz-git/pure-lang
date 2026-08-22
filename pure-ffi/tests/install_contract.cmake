cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS SOURCE_DIR BINARY_DIR FFI_TARGET_FILE
    FFI_SMOKE_NATIVE_FILE PURE_EXECUTABLE LLVM_READOBJ_EXECUTABLE TEST_ROOT
    SMOKE_SCRIPT RUNTIME_DLL RUNTIME_LICENSE)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

get_filename_component(binary_root "${BINARY_DIR}" ABSOLUTE)
get_filename_component(test_root "${TEST_ROOT}" ABSOLUTE)
cmake_path(IS_PREFIX binary_root "${test_root}" NORMALIZE test_root_is_safe)
if(NOT test_root_is_safe OR test_root STREQUAL binary_root)
  message(FATAL_ERROR "TEST_ROOT must be a child of BINARY_DIR")
endif()
get_filename_component(pure_bin_dir "${PURE_EXECUTABLE}" DIRECTORY)
get_filename_component(runtime_prefix "${pure_bin_dir}" DIRECTORY)
if(NOT EXISTS "${runtime_prefix}/lib/pure/math.pure")
  message(FATAL_ERROR "PURE_EXECUTABLE must belong to an installed runtime")
endif()

set(package_stage "${TEST_ROOT}/package stage")
set(runtime_stage "${TEST_ROOT}/runtime stage")
set(native_stage "${TEST_ROOT}/native helper")
set(poison_dir "${TEST_ROOT}/poison PURELIB")
file(REMOVE_RECURSE "${TEST_ROOT}")
file(MAKE_DIRECTORY "${package_stage}" "${native_stage}" "${poison_dir}")
execute_process(COMMAND "${CMAKE_COMMAND}" --install "${BINARY_DIR}"
  --prefix "${package_stage}" RESULT_VARIABLE install_result
  OUTPUT_VARIABLE install_output ERROR_VARIABLE install_error)
if(NOT install_result EQUAL 0)
  message(FATAL_ERROR "Package install failed:\n${install_output}${install_error}")
endif()

file(GLOB_RECURSE installed_files LIST_DIRECTORIES FALSE
  RELATIVE "${package_stage}" "${package_stage}/*")
list(TRANSFORM installed_files REPLACE "\\\\" "/")
list(SORT installed_files)
set(expected_files
  bin/libffi-8.dll lib/pure/ffi.dll lib/pure/ffi.pure
  share/doc/pure-ffi/COPYING share/doc/pure-ffi/COPYING.LESSER
  share/doc/pure-ffi/README share/doc/pure-ffi/examples/ffi_examp.pure
  share/doc/pure-ffi/examples/sort.pure share/doc/pure-ffi/examples/time.pure
  share/doc/pure-ffi/libffi-LICENSE)
list(SORT expected_files)
if(NOT installed_files STREQUAL expected_files)
  message(FATAL_ERROR
    "Unexpected package manifest. Expected '${expected_files}', got '${installed_files}'")
endif()

foreach(pair IN ITEMS
    "bin/libffi-8.dll|${RUNTIME_DLL}"
    "lib/pure/ffi.dll|${FFI_TARGET_FILE}"
    "lib/pure/ffi.pure|${SOURCE_DIR}/ffi.pure"
    "share/doc/pure-ffi/COPYING|${SOURCE_DIR}/COPYING"
    "share/doc/pure-ffi/COPYING.LESSER|${SOURCE_DIR}/COPYING.LESSER"
    "share/doc/pure-ffi/README|${BINARY_DIR}/README"
    "share/doc/pure-ffi/examples/ffi_examp.pure|${SOURCE_DIR}/examples/ffi_examp.pure"
    "share/doc/pure-ffi/examples/sort.pure|${SOURCE_DIR}/examples/sort.pure"
    "share/doc/pure-ffi/examples/time.pure|${SOURCE_DIR}/examples/time.pure"
    "share/doc/pure-ffi/libffi-LICENSE|${RUNTIME_LICENSE}")
  string(REPLACE "|" ";" parts "${pair}")
  list(GET parts 0 installed_relative)
  list(GET parts 1 expected_file)
  file(SHA256 "${package_stage}/${installed_relative}" installed_hash)
  file(SHA256 "${expected_file}" expected_hash)
  if(NOT installed_hash STREQUAL expected_hash)
    message(FATAL_ERROR "Installed ${installed_relative} has unexpected content")
  endif()
endforeach()

file(TO_CMAKE_PATH "${SOURCE_DIR}" normalized_source)
file(TO_CMAKE_PATH "${BINARY_DIR}" normalized_binary)
foreach(relative IN LISTS installed_files)
  file(STRINGS "${package_stage}/${relative}" printable_strings)
  string(REPLACE "\\" "/" normalized_content "${printable_strings}")
  foreach(forbidden IN ITEMS "${normalized_source}" "${normalized_binary}"
      "C:/msys64" "@version@" "|today|")
    string(FIND "${normalized_content}" "${forbidden}" offset)
    if(NOT offset EQUAL -1)
      message(FATAL_ERROR "Installed ${relative} contains forbidden text: ${forbidden}")
    endif()
  endforeach()
endforeach()

execute_process(COMMAND "${CMAKE_COMMAND}"
  "-DFFI_DLL=${package_stage}/lib/pure/ffi.dll"
  "-DLIBFFI_DLL=${package_stage}/bin/libffi-8.dll"
  "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}"
  -P "${SOURCE_DIR}/tests/verify_pe_contract.cmake"
  RESULT_VARIABLE pe_result OUTPUT_VARIABLE pe_output ERROR_VARIABLE pe_error)
if(NOT pe_result EQUAL 0)
  message(FATAL_ERROR "PE contract failed:\n${pe_output}${pe_error}")
endif()

execute_process(COMMAND "${CMAKE_COMMAND}" -E copy_directory
  "${runtime_prefix}" "${runtime_stage}" RESULT_VARIABLE copy_result)
if(NOT copy_result EQUAL 0)
  message(FATAL_ERROR "Could not copy the installed Pure runtime")
endif()
execute_process(COMMAND "${CMAKE_COMMAND}" --install "${BINARY_DIR}"
  --prefix "${runtime_stage}" RESULT_VARIABLE runtime_install_result)
if(NOT runtime_install_result EQUAL 0)
  message(FATAL_ERROR "Could not install pure-ffi into staged runtime")
endif()
file(COPY "${FFI_SMOKE_NATIVE_FILE}" DESTINATION "${native_stage}")
file(WRITE "${poison_dir}/ffi.pure" "unexpected token proving PURELIB leakage;\n")
set(poisoned_path "C:/msys64/clang64/bin;$ENV{SystemRoot}/System32;$ENV{SystemRoot}")
execute_process(COMMAND "${CMAKE_COMMAND}" -E env
  "PURELIB=${poison_dir}" "PATH=${poisoned_path}"
  "${CMAKE_COMMAND}"
    "-DPURE_EXECUTABLE=${runtime_stage}/bin/pure.exe"
    "-DPURE_SOURCE_DIR=${runtime_stage}/lib/pure"
    "-DPURE_MODULE_DIR=${runtime_stage}/lib/pure"
    "-DNATIVE_MODULE_DIR=${native_stage}"
    "-DTEST_SCRIPT=${SMOKE_SCRIPT}"
    -P "${SOURCE_DIR}/cmake/RunSmokeTest.cmake"
  RESULT_VARIABLE smoke_result OUTPUT_VARIABLE smoke_output ERROR_VARIABLE smoke_error)
if(NOT smoke_result EQUAL 0)
  message(FATAL_ERROR "Sanitized staged smoke failed:\n${smoke_output}${smoke_error}")
endif()
