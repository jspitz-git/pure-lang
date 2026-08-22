cmake_minimum_required(VERSION 3.25)
foreach(required IN ITEMS SOURCE_DIR BINARY_DIR HASHDICT_TARGET_FILE
    ORDDICT_TARGET_FILE PURE_EXECUTABLE LLVM_READOBJ_EXECUTABLE TEST_ROOT
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
set(cxx_runtime "${pure_bin_dir}/libc++.dll")
if(NOT EXISTS "${runtime_prefix}/lib/pure/math.pure" OR
    NOT EXISTS "${cxx_runtime}")
  message(FATAL_ERROR
    "PURE_EXECUTABLE must belong to a portable runtime containing libc++.dll")
endif()
file(SHA256 "${cxx_runtime}" cxx_hash)
if(NOT cxx_hash STREQUAL
    "7344daed05388589e9bd691ed1d30c568c374da4b8b6a12e1502185948c03cd4")
  message(FATAL_ERROR "Portable libc++.dll has unexpected SHA-256: ${cxx_hash}")
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
set(expected lib/pure/hashdict.dll lib/pure/hashdict.pure
  lib/pure/orddict.dll lib/pure/orddict.pure lib/pure/stldict.pure
  lib/pure/stldictbase.pure share/doc/pure-stldict/COPYING
  share/doc/pure-stldict/COPYING.LESSER share/doc/pure-stldict/README
  share/doc/pure-stldict/examples/hashdict_examp.pure
  share/doc/pure-stldict/examples/life.pure
  share/doc/pure-stldict/examples/orddict_examp.pure
  share/doc/pure-stldict/examples/test.pure)
list(SORT expected)
if(NOT installed STREQUAL expected)
  message(FATAL_ERROR "Unexpected manifest. Expected '${expected}', got '${installed}'")
endif()
if(EXISTS "${package_stage}/bin/libc++.dll")
  message(FATAL_ERROR "Package duplicated the portable libc++.dll")
endif()
foreach(pair IN ITEMS
    "lib/pure/hashdict.dll|${HASHDICT_TARGET_FILE}"
    "lib/pure/orddict.dll|${ORDDICT_TARGET_FILE}"
    "lib/pure/hashdict.pure|${SOURCE_DIR}/hashdict.pure"
    "lib/pure/orddict.pure|${SOURCE_DIR}/orddict.pure"
    "lib/pure/stldict.pure|${SOURCE_DIR}/stldict.pure"
    "lib/pure/stldictbase.pure|${SOURCE_DIR}/stldictbase.pure"
    "share/doc/pure-stldict/COPYING|${SOURCE_DIR}/COPYING"
    "share/doc/pure-stldict/COPYING.LESSER|${SOURCE_DIR}/COPYING.LESSER"
    "share/doc/pure-stldict/README|${BINARY_DIR}/README"
    "share/doc/pure-stldict/examples/hashdict_examp.pure|${SOURCE_DIR}/examples/hashdict_examp.pure"
    "share/doc/pure-stldict/examples/life.pure|${SOURCE_DIR}/examples/life.pure"
    "share/doc/pure-stldict/examples/orddict_examp.pure|${SOURCE_DIR}/examples/orddict_examp.pure"
    "share/doc/pure-stldict/examples/test.pure|${SOURCE_DIR}/examples/test.pure")
  string(REPLACE "|" ";" parts "${pair}")
  list(GET parts 0 relative)
  list(GET parts 1 source)
  file(SHA256 "${package_stage}/${relative}" got)
  file(SHA256 "${source}" want)
  if(NOT got STREQUAL want)
    message(FATAL_ERROR "Installed ${relative} has unexpected content")
  endif()
endforeach()
file(TO_CMAKE_PATH "${SOURCE_DIR}" source_path)
file(TO_CMAKE_PATH "${BINARY_DIR}" binary_path)
foreach(relative IN LISTS installed)
  file(STRINGS "${package_stage}/${relative}" strings)
  string(REPLACE "\\" "/" content "${strings}")
  foreach(forbidden IN ITEMS "${source_path}" "${binary_path}" "C:/msys64"
      "@version@" "|today|")
    string(FIND "${content}" "${forbidden}" offset)
    if(NOT offset EQUAL -1)
      message(FATAL_ERROR "Installed ${relative} contains ${forbidden}")
    endif()
  endforeach()
endforeach()
foreach(module IN ITEMS hashdict orddict)
  execute_process(COMMAND "${CMAKE_COMMAND}"
    "-DMODULE_DLL=${package_stage}/lib/pure/${module}.dll"
    "-DMODULE_SOURCE=${SOURCE_DIR}/${module}.pure"
    "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}"
    -P "${SOURCE_DIR}/tests/verify_pe_contract.cmake"
    RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
  if(NOT result EQUAL 0)
    message(FATAL_ERROR "Installed ${module} PE contract failed:\n${output}${error}")
  endif()
endforeach()
execute_process(COMMAND "${CMAKE_COMMAND}" -E copy_directory
  "${runtime_prefix}" "${runtime_stage}" RESULT_VARIABLE result)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Could not copy portable runtime")
endif()
execute_process(COMMAND "${CMAKE_COMMAND}" --install "${BINARY_DIR}"
  --prefix "${runtime_stage}" RESULT_VARIABLE result)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Could not install into staged runtime")
endif()
file(WRITE "${poison_dir}/stldict.pure"
  "unexpected token proving inherited PURELIB leakage;\n")
set(poison_path "C:/msys64/clang64/bin;$ENV{SystemRoot}/System32;$ENV{SystemRoot}")
execute_process(COMMAND "${CMAKE_COMMAND}" -E env
  "PURELIB=${poison_dir}" "PATH=${poison_path}" "${CMAKE_COMMAND}"
  "-DPURE_EXECUTABLE=${runtime_stage}/bin/pure.exe"
  "-DPURE_SOURCE_DIR=${runtime_stage}/lib/pure"
  "-DMODULE_DIR=${runtime_stage}/lib/pure"
  "-DTEST_SCRIPT=${SMOKE_SCRIPT}"
  -P "${SOURCE_DIR}/cmake/RunSmokeTest.cmake"
  RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Staged smoke failed:\n${output}${error}")
endif()
