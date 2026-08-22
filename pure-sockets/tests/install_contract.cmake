cmake_minimum_required(VERSION 3.25)
foreach(required IN ITEMS SOURCE_DIR BINARY_DIR SOCKETS_TARGET_FILE
    AUDIT_EXECUTABLE PURE_EXECUTABLE LLVM_READOBJ_EXECUTABLE TEST_ROOT
    SMOKE_SCRIPT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()
get_filename_component(binary_root "${BINARY_DIR}" ABSOLUTE)
get_filename_component(test_root "${TEST_ROOT}" ABSOLUTE)
cmake_path(IS_PREFIX binary_root "${test_root}" NORMALIZE safe_root)
if(NOT safe_root OR test_root STREQUAL binary_root)
  message(FATAL_ERROR "TEST_ROOT must be a child of BINARY_DIR")
endif()
get_filename_component(pure_bin_dir "${PURE_EXECUTABLE}" DIRECTORY)
get_filename_component(runtime_prefix "${pure_bin_dir}" DIRECTORY)
if(NOT EXISTS "${runtime_prefix}/lib/pure/math.pure")
  message(FATAL_ERROR "PURE_EXECUTABLE must belong to an installed runtime")
endif()
set(package_stage "${TEST_ROOT}/package stage")
set(runtime_stage "${TEST_ROOT}/runtime stage")
set(poison_dir "${TEST_ROOT}/poison PURELIB")
file(REMOVE_RECURSE "${TEST_ROOT}")
file(MAKE_DIRECTORY "${package_stage}" "${poison_dir}")
execute_process(COMMAND "${CMAKE_COMMAND}" --install "${BINARY_DIR}"
  --prefix "${package_stage}" RESULT_VARIABLE result)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Package-only install failed")
endif()
file(GLOB_RECURSE installed LIST_DIRECTORIES FALSE RELATIVE "${package_stage}"
  "${package_stage}/*")
list(TRANSFORM installed REPLACE "\\\\" "/")
list(SORT installed)
set(expected lib/pure/sockets.dll lib/pure/sockets.pure
  share/doc/pure-sockets/COPYING share/doc/pure-sockets/COPYING.LESSER
  share/doc/pure-sockets/README share/doc/pure-sockets/examples/dgram.pure
  share/doc/pure-sockets/examples/stream.pure)
list(SORT expected)
if(NOT installed STREQUAL expected)
  message(FATAL_ERROR "Unexpected manifest. Expected '${expected}', got '${installed}'")
endif()
file(TO_CMAKE_PATH "${SOURCE_DIR}" normalized_source)
file(TO_CMAKE_PATH "${BINARY_DIR}" normalized_binary)
foreach(relative IN LISTS installed)
  file(STRINGS "${package_stage}/${relative}" strings)
  string(REPLACE "\\" "/" content "${strings}")
  foreach(forbidden IN ITEMS "${normalized_source}" "${normalized_binary}"
      "C:/msys64" "@version@" "|today|")
    string(FIND "${content}" "${forbidden}" offset)
    if(NOT offset EQUAL -1)
      message(FATAL_ERROR "Installed ${relative} contains ${forbidden}")
    endif()
  endforeach()
endforeach()
foreach(pair IN ITEMS
    "lib/pure/sockets.dll|${SOCKETS_TARGET_FILE}"
    "lib/pure/sockets.pure|${SOURCE_DIR}/sockets.pure"
    "share/doc/pure-sockets/COPYING|${SOURCE_DIR}/COPYING"
    "share/doc/pure-sockets/COPYING.LESSER|${SOURCE_DIR}/COPYING.LESSER"
    "share/doc/pure-sockets/README|${BINARY_DIR}/README"
    "share/doc/pure-sockets/examples/dgram.pure|${SOURCE_DIR}/examples/dgram.pure"
    "share/doc/pure-sockets/examples/stream.pure|${SOURCE_DIR}/examples/stream.pure")
  string(REPLACE "|" ";" parts "${pair}")
  list(GET parts 0 relative)
  list(GET parts 1 source)
  file(SHA256 "${package_stage}/${relative}" installed_hash)
  file(SHA256 "${source}" source_hash)
  if(NOT installed_hash STREQUAL source_hash)
    message(FATAL_ERROR "Installed ${relative} has unexpected content")
  endif()
endforeach()
execute_process(COMMAND "${CMAKE_COMMAND}"
  "-DSOCKETS_DLL=${package_stage}/lib/pure/sockets.dll"
  "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}"
  -P "${SOURCE_DIR}/tests/verify_pe_contract.cmake"
  RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "PE contract failed:\n${output}${error}")
endif()
execute_process(COMMAND "${CMAKE_COMMAND}" -E copy_directory
  "${runtime_prefix}" "${runtime_stage}" RESULT_VARIABLE result)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Could not copy installed runtime")
endif()
execute_process(COMMAND "${CMAKE_COMMAND}" --install "${BINARY_DIR}"
  --prefix "${runtime_stage}" RESULT_VARIABLE result)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Could not install into staged runtime")
endif()
file(WRITE "${poison_dir}/sockets.pure"
  "unexpected token proving inherited PURELIB was used;\n")
set(poisoned_path "C:/msys64/clang64/bin;$ENV{SystemRoot}/System32;$ENV{SystemRoot}")
execute_process(COMMAND "${CMAKE_COMMAND}" -E env
  "PURELIB=${poison_dir}" "PATH=${poisoned_path}" "${CMAKE_COMMAND}"
  "-DAUDIT_EXECUTABLE=${AUDIT_EXECUTABLE}"
  "-DSOCKETS_DLL=${runtime_stage}/lib/pure/sockets.dll"
  "-DPURE_EXECUTABLE=${runtime_stage}/bin/pure.exe"
  -P "${SOURCE_DIR}/cmake/RunNativeAudit.cmake"
  RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Staged native audit failed:\n${output}${error}")
endif()
execute_process(COMMAND "${CMAKE_COMMAND}" -E env
  "PURELIB=${poison_dir}" "PATH=${poisoned_path}" "${CMAKE_COMMAND}"
  "-DPURE_EXECUTABLE=${runtime_stage}/bin/pure.exe"
  "-DPURE_SOURCE_DIR=${runtime_stage}/lib/pure"
  "-DPURE_MODULE_DIR=${runtime_stage}/lib/pure"
  "-DTEST_SCRIPT=${SMOKE_SCRIPT}"
  -P "${SOURCE_DIR}/cmake/RunSmokeTest.cmake"
  RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Staged loopback failed:\n${output}${error}")
endif()
