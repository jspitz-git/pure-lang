foreach(required IN ITEMS
    STAGE_PREFIX SOURCE_RUNTIME_DIR LLVM_READOBJ)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE stage)
cmake_path(ABSOLUTE_PATH SOURCE_RUNTIME_DIR NORMALIZE OUTPUT_VARIABLE source_bin)
set(module_dir "${stage}/lib/pure")
set(doc_dir "${stage}/share/doc/pure-odbc")

set(expected_files
  "${module_dir}/odbc.dll"
  "${module_dir}/odbc.pure"
  "${doc_dir}/README"
  "${doc_dir}/COPYING"
  "${doc_dir}/COPYING.LESSER"
  "${doc_dir}/WINDOWS.md"
  "${doc_dir}/examples/menagerie.pure"
  "${doc_dir}/tests/smoke.pure"
  "${doc_dir}/tests/data/people.csv"
  "${doc_dir}/tests/data/Schema.ini"
)
foreach(expected IN LISTS expected_files)
  if(NOT EXISTS "${expected}")
    message(FATAL_ERROR "Missing installed pure-odbc file: ${expected}")
  endif()
endforeach()

set(staged_gmp "${stage}/bin/libgmp-10.dll")
set(source_gmp "${source_bin}/libgmp-10.dll")
if(NOT EXISTS "${staged_gmp}" OR NOT EXISTS "${source_gmp}")
  message(FATAL_ERROR "Missing reused GMP runtime")
endif()
file(SHA256 "${staged_gmp}" staged_gmp_hash)
file(SHA256 "${source_gmp}" source_gmp_hash)
if(NOT staged_gmp_hash STREQUAL source_gmp_hash)
  message(FATAL_ERROR
    "Conflicting staged GMP: ${staged_gmp_hash} != ${source_gmp_hash}")
endif()

foreach(forbidden IN ITEMS odbc32.dll ODBC32.dll libodbc.dll libodbc32.dll)
  if(EXISTS "${stage}/bin/${forbidden}")
    message(FATAL_ERROR
      "System ODBC manager must not be bundled: ${stage}/bin/${forbidden}")
  endif()
endforeach()

set(ENV{PATH} "${stage}/bin;C:/Windows/System32;C:/Windows")
set(ENV{PURELIB} "")
execute_process(
  COMMAND "${stage}/bin/pure.exe" --norc
    -I "${module_dir}"
    -L "${module_dir}"
    -x "${doc_dir}/tests/smoke.pure"
  WORKING_DIRECTORY "${doc_dir}/tests/data"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
  ENCODING UTF-8
)
if(NOT result EQUAL 0)
  message(FATAL_ERROR
    "Installed pure-odbc smoke test failed (${result})\n"
    "stdout:\n${output}\nstderr:\n${error}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    "-DODBC_MODULE=${module_dir}/odbc.dll"
    "-DGMP_DLL=${staged_gmp}"
    -P "${CMAKE_CURRENT_LIST_DIR}/VerifyWindowsDependencies.cmake"
  RESULT_VARIABLE audit_result
  OUTPUT_VARIABLE audit_output
  ERROR_VARIABLE audit_error
  ENCODING UTF-8
)
if(NOT audit_result EQUAL 0)
  message(FATAL_ERROR
    "Installed pure-odbc PE audit failed (${audit_result})\n"
    "stdout:\n${audit_output}\nstderr:\n${audit_error}")
endif()

list(LENGTH expected_files expected_count)
message(STATUS
  "Verified installed pure-odbc: ${expected_count} package files, "
  "reused GMP, system ODBC manager, sanitized smoke test, and staged PE closure")
