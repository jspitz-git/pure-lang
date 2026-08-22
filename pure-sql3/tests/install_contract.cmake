cmake_minimum_required(VERSION 3.25)
foreach(required IN ITEMS SOURCE_DIR BINARY_DIR SQL3_TARGET_FILE
    SQLITE_RUNTIME_DLL SQLITE_RUNTIME_LICENSE PURE_EXECUTABLE
    LLVM_READOBJ_EXECUTABLE TEST_ROOT SMOKE_SCRIPT)
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
get_filename_component(pure_bin "${PURE_EXECUTABLE}" DIRECTORY)
get_filename_component(runtime_prefix "${pure_bin}" DIRECTORY)
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
set(expected bin/libsqlite3-0.dll lib/pure/sql3.pure lib/pure/sql3util.dll
  share/doc/pure-sql3/COPYING share/doc/pure-sql3/README
  share/doc/pure-sql3/examples/readme.pure
  share/doc/pure-sql3/examples/sql3_blobs.pure
  share/doc/pure-sql3/examples/sql3_demo.pure
  share/doc/pure-sql3/examples/sql3_funs.pure
  share/doc/pure-sql3/examples/sql3_lazy_exec.pure
  share/doc/pure-sql3/examples/sql3_types.pure
  share/doc/pure-sql3/examples/sql3_user_bind_types.pure
  share/doc/pure-sql3/sqlite3-LICENSE)
list(SORT expected)
if(NOT installed STREQUAL expected)
  message(FATAL_ERROR "Unexpected manifest. Expected '${expected}', got '${installed}'")
endif()
foreach(pair IN ITEMS
    "bin/libsqlite3-0.dll|${SQLITE_RUNTIME_DLL}"
    "lib/pure/sql3.pure|${SOURCE_DIR}/sql3.pure"
    "lib/pure/sql3util.dll|${SQL3_TARGET_FILE}"
    "share/doc/pure-sql3/COPYING|${SOURCE_DIR}/COPYING"
    "share/doc/pure-sql3/README|${BINARY_DIR}/README"
    "share/doc/pure-sql3/sqlite3-LICENSE|${SQLITE_RUNTIME_LICENSE}"
    "share/doc/pure-sql3/examples/readme.pure|${SOURCE_DIR}/examples/readme.pure"
    "share/doc/pure-sql3/examples/sql3_blobs.pure|${SOURCE_DIR}/examples/sql3_blobs.pure"
    "share/doc/pure-sql3/examples/sql3_demo.pure|${SOURCE_DIR}/examples/sql3_demo.pure"
    "share/doc/pure-sql3/examples/sql3_funs.pure|${SOURCE_DIR}/examples/sql3_funs.pure"
    "share/doc/pure-sql3/examples/sql3_lazy_exec.pure|${SOURCE_DIR}/examples/sql3_lazy_exec.pure"
    "share/doc/pure-sql3/examples/sql3_types.pure|${SOURCE_DIR}/examples/sql3_types.pure"
    "share/doc/pure-sql3/examples/sql3_user_bind_types.pure|${SOURCE_DIR}/examples/sql3_user_bind_types.pure")
  string(REPLACE "|" ";" parts "${pair}")
  list(GET parts 0 relative)
  list(GET parts 1 source)
  file(SHA256 "${package_stage}/${relative}" got)
  file(SHA256 "${source}" want)
  if(NOT got STREQUAL want)
    message(FATAL_ERROR "Installed ${relative} has unexpected content")
  endif()
endforeach()
file(SHA256 "${package_stage}/bin/libsqlite3-0.dll" sqlite_hash)
if(NOT sqlite_hash STREQUAL
    "91240f2e86a7648a408d2b3ea4f851c1db0fb9a778f775a823ff81978abb14f7")
  message(FATAL_ERROR "Installed SQLite has unexpected SHA-256: ${sqlite_hash}")
endif()
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
execute_process(COMMAND "${CMAKE_COMMAND}"
  "-DSQL3_DLL=${package_stage}/lib/pure/sql3util.dll"
  "-DSQLITE_DLL=${package_stage}/bin/libsqlite3-0.dll"
  "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}"
  -P "${SOURCE_DIR}/tests/verify_pe_contract.cmake"
  RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "PE contract failed:\n${output}${error}")
endif()
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
file(WRITE "${poison_dir}/sql3.pure" "unexpected token proving PURELIB leakage;\n")
set(poison_path "C:/msys64/clang64/bin;$ENV{SystemRoot}/System32;$ENV{SystemRoot}")
execute_process(COMMAND "${CMAKE_COMMAND}" -E env
  "PURELIB=${poison_dir}" "PATH=${poison_path}" "${CMAKE_COMMAND}"
  "-DPURE_EXECUTABLE=${runtime_stage}/bin/pure.exe"
  "-DMODULE_DIR=${runtime_stage}/lib/pure"
  "-DMODULE_DLL_DIR=${runtime_stage}/lib/pure"
  "-DSQLITE_RUNTIME_DIR=${runtime_stage}/bin"
  "-DTEST_SCRIPT=${SMOKE_SCRIPT}" "-DTEST_ROOT=${TEST_ROOT}/staged smoke"
  -P "${SOURCE_DIR}/cmake/RunSmokeTest.cmake"
  RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Staged smoke failed:\n${output}${error}")
endif()
