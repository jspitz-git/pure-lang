foreach(required IN ITEMS STAGE_PREFIX SOURCE_PREFIX LLVM_READOBJ)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE stage)
cmake_path(ABSOLUTE_PATH SOURCE_PREFIX NORMALIZE OUTPUT_VARIABLE source)
set(module_dir "${stage}/lib/pure")
set(doc_dir "${stage}/share/doc/pure-tk")
set(work_dir "${stage}/Pure Tk Verification")

set(expected_files
  "${module_dir}/tk.dll"
  "${module_dir}/tk.pure"
  "${stage}/bin/tcl86.dll"
  "${stage}/bin/tk86.dll"
  "${stage}/bin/zlib1.dll"
  "${stage}/lib/tcl8.6/init.tcl"
  "${stage}/lib/tcl8.6/encoding/cp1250.enc"
  "${stage}/lib/tcl8.6/tzdata/Europe/Prague"
  "${stage}/lib/tk8.6/tk.tcl"
  "${stage}/lib/tk8.6/ttk/ttk.tcl"
  "${doc_dir}/README"
  "${doc_dir}/COPYING"
  "${doc_dir}/WINDOWS.md"
  "${doc_dir}/tcl-tk-license.terms"
  "${doc_dir}/zlib-LICENSE"
  "${doc_dir}/tests/relocatable.pure"
  "${doc_dir}/tests/smoke.pure"
)
foreach(expected IN LISTS expected_files)
  if(NOT EXISTS "${expected}")
    message(FATAL_ERROR "Missing installed pure-tk file: ${expected}")
  endif()
endforeach()

foreach(reused IN ITEMS libpure.dll zlib1.dll)
  set(staged_file "${stage}/bin/${reused}")
  set(source_file "${source}/bin/${reused}")
  if(NOT EXISTS "${staged_file}" OR NOT EXISTS "${source_file}")
    message(FATAL_ERROR "Missing reused dependency ${reused}")
  endif()
  file(SHA256 "${staged_file}" staged_hash)
  file(SHA256 "${source_file}" source_hash)
  if(NOT staged_hash STREQUAL source_hash)
    message(FATAL_ERROR
      "Conflicting staged ${reused}: ${staged_hash} != ${source_hash}")
  endif()
endforeach()

file(REMOVE_RECURSE "${work_dir}")
file(MAKE_DIRECTORY "${work_dir}")
unset(ENV{PURELIB})
unset(ENV{TCL_LIBRARY})
unset(ENV{TK_LIBRARY})
unset(ENV{TCLLIBPATH})
set(ENV{PURE_TK_EXPECTED_PREFIX} "${stage}")
set(ENV{PATH} "${stage}/bin;C:/Windows/System32;C:/Windows")

function(run_pure_test script marker)
  execute_process(
    COMMAND "${stage}/bin/pure.exe" --norc -q
      -I "${module_dir}"
      -L "${module_dir}"
    INPUT_FILE "${script}"
    WORKING_DIRECTORY "${work_dir}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    TIMEOUT 25
    ENCODING UTF-8
  )
  if(NOT "${result}" STREQUAL "0")
    message(FATAL_ERROR
      "Installed pure-tk test exited with ${result}\n"
      "stdout:\n${output}\nstderr:\n${error}")
  endif()
  if(NOT output MATCHES "(^|\r?\n)${marker}(\r?\n|$)")
    message(FATAL_ERROR
      "Installed pure-tk test did not emit ${marker}\n"
      "stdout:\n${output}\nstderr:\n${error}")
  endif()
endfunction()

run_pure_test(
  "${doc_dir}/tests/relocatable.pure"
  "PURE_TK_RELOCATABLE_OK")
run_pure_test("${doc_dir}/tests/smoke.pure" "PURE_TK_SMOKE_OK")
file(REMOVE_RECURSE "${work_dir}")

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    "-DPURE_TK_MODULE=${module_dir}/tk.dll"
    "-DTCL_DLL=${stage}/bin/tcl86.dll"
    "-DTK_DLL=${stage}/bin/tk86.dll"
    "-DZLIB_DLL=${stage}/bin/zlib1.dll"
    -P "${CMAKE_CURRENT_LIST_DIR}/VerifyWindowsDependencies.cmake"
  RESULT_VARIABLE audit_result
  OUTPUT_VARIABLE audit_output
  ERROR_VARIABLE audit_error
  ENCODING UTF-8
)
if(NOT audit_result EQUAL 0)
  message(FATAL_ERROR
    "Installed pure-tk PE audit failed (${audit_result})\n"
    "stdout:\n${audit_output}\nstderr:\n${audit_error}")
endif()

file(GLOB_RECURSE tcl_files LIST_DIRECTORIES FALSE "${stage}/lib/tcl8.6/*")
file(GLOB_RECURSE tk_files LIST_DIRECTORIES FALSE "${stage}/lib/tk8.6/*")
list(LENGTH tcl_files tcl_count)
list(LENGTH tk_files tk_count)
message(STATUS
  "Verified installed pure-tk: ${tcl_count} Tcl files, ${tk_count} Tk "
  "files, reused Pure/zlib runtimes, two sanitized GUI tests, and staged "
  "PE closure")
