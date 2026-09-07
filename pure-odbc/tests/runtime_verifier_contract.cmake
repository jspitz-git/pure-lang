cmake_minimum_required(VERSION 3.25)

include("${CMAKE_CURRENT_LIST_DIR}/ContractTestRoot.cmake")

if(NOT DEFINED PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY OR
    "${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}" STREQUAL "")
  message(FATAL_ERROR "PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY is required")
endif()

pure_odbc_validate_contract_test_root("cleanup" unused_test_root)
pure_odbc_reset_contract_test_root("cleanup")
set(runtime_root "${TEST_ROOT}/task5-runtime")
set(stage "${runtime_root}/stage")
set(stage_bin "${stage}/bin")
set(module_dir "${stage}/lib/pure")
set(windows_directory "${runtime_root}/Windows")
set(system_directory "${windows_directory}/System32")
set(fixture_dir "${runtime_root}/readobj")
file(MAKE_DIRECTORY
  "${stage_bin}" "${module_dir}" "${system_directory}" "${fixture_dir}")

# Literal manifests captured independently from the audited CLANG64 build.
set(imports_odbc_dll
  api-ms-win-crt-heap-l1-1-0.dll
  api-ms-win-crt-private-l1-1-0.dll
  api-ms-win-crt-runtime-l1-1-0.dll
  api-ms-win-crt-stdio-l1-1-0.dll
  api-ms-win-crt-string-l1-1-0.dll
  kernel32.dll libgmp-10.dll libpure.dll ODBC32.dll)
set(imports_pure_exe
  api-ms-win-crt-convert-l1-1-0.dll
  api-ms-win-crt-environment-l1-1-0.dll
  api-ms-win-crt-filesystem-l1-1-0.dll
  api-ms-win-crt-heap-l1-1-0.dll
  api-ms-win-crt-locale-l1-1-0.dll
  api-ms-win-crt-math-l1-1-0.dll
  api-ms-win-crt-private-l1-1-0.dll
  api-ms-win-crt-runtime-l1-1-0.dll
  api-ms-win-crt-stdio-l1-1-0.dll
  api-ms-win-crt-string-l1-1-0.dll
  kernel32.dll libc++.dll libpure.dll libreadline8.dll)
set(imports_libpure_dll
  advapi32.dll
  api-ms-win-crt-convert-l1-1-0.dll
  api-ms-win-crt-environment-l1-1-0.dll
  api-ms-win-crt-filesystem-l1-1-0.dll
  api-ms-win-crt-heap-l1-1-0.dll
  api-ms-win-crt-locale-l1-1-0.dll
  api-ms-win-crt-math-l1-1-0.dll
  api-ms-win-crt-private-l1-1-0.dll
  api-ms-win-crt-process-l1-1-0.dll
  api-ms-win-crt-runtime-l1-1-0.dll
  api-ms-win-crt-stdio-l1-1-0.dll
  api-ms-win-crt-string-l1-1-0.dll
  api-ms-win-crt-time-l1-1-0.dll
  api-ms-win-crt-utility-l1-1-0.dll
  kernel32.dll libc++.dll libgmp-10.dll libiconv-2.dll libmpfr-6.dll
  libpcreposix-0.dll libwinpthread-1.dll libzstd.dll ntdll.dll ole32.dll
  shell32.dll zlib1.dll)
set(imports_libc___dll
  api-ms-win-crt-convert-l1-1-0.dll
  api-ms-win-crt-environment-l1-1-0.dll
  api-ms-win-crt-filesystem-l1-1-0.dll
  api-ms-win-crt-heap-l1-1-0.dll
  api-ms-win-crt-locale-l1-1-0.dll
  api-ms-win-crt-math-l1-1-0.dll
  api-ms-win-crt-multibyte-l1-1-0.dll
  api-ms-win-crt-private-l1-1-0.dll
  api-ms-win-crt-runtime-l1-1-0.dll
  api-ms-win-crt-stdio-l1-1-0.dll
  api-ms-win-crt-string-l1-1-0.dll
  api-ms-win-crt-time-l1-1-0.dll
  api-ms-win-crt-utility-l1-1-0.dll kernel32.dll)
set(imports_libgmp_10_dll
  api-ms-win-crt-convert-l1-1-0.dll
  api-ms-win-crt-environment-l1-1-0.dll
  api-ms-win-crt-filesystem-l1-1-0.dll
  api-ms-win-crt-heap-l1-1-0.dll
  api-ms-win-crt-locale-l1-1-0.dll
  api-ms-win-crt-private-l1-1-0.dll
  api-ms-win-crt-runtime-l1-1-0.dll
  api-ms-win-crt-stdio-l1-1-0.dll
  api-ms-win-crt-string-l1-1-0.dll
  api-ms-win-crt-time-l1-1-0.dll
  api-ms-win-crt-utility-l1-1-0.dll kernel32.dll)
set(imports_libiconv_2_dll
  api-ms-win-crt-convert-l1-1-0.dll
  api-ms-win-crt-heap-l1-1-0.dll
  api-ms-win-crt-locale-l1-1-0.dll
  api-ms-win-crt-private-l1-1-0.dll
  api-ms-win-crt-runtime-l1-1-0.dll
  api-ms-win-crt-stdio-l1-1-0.dll
  api-ms-win-crt-string-l1-1-0.dll
  api-ms-win-crt-utility-l1-1-0.dll kernel32.dll)
set(imports_libmpfr_6_dll
  api-ms-win-crt-convert-l1-1-0.dll
  api-ms-win-crt-filesystem-l1-1-0.dll
  api-ms-win-crt-heap-l1-1-0.dll
  api-ms-win-crt-locale-l1-1-0.dll
  api-ms-win-crt-private-l1-1-0.dll
  api-ms-win-crt-runtime-l1-1-0.dll
  api-ms-win-crt-stdio-l1-1-0.dll
  api-ms-win-crt-string-l1-1-0.dll
  api-ms-win-crt-utility-l1-1-0.dll kernel32.dll libgmp-10.dll)
set(imports_libpcre_1_dll
  api-ms-win-crt-heap-l1-1-0.dll
  api-ms-win-crt-private-l1-1-0.dll
  api-ms-win-crt-runtime-l1-1-0.dll
  api-ms-win-crt-stdio-l1-1-0.dll
  api-ms-win-crt-string-l1-1-0.dll
  api-ms-win-crt-utility-l1-1-0.dll kernel32.dll)
set(imports_libpcreposix_0_dll
  api-ms-win-crt-convert-l1-1-0.dll
  api-ms-win-crt-heap-l1-1-0.dll
  api-ms-win-crt-locale-l1-1-0.dll
  api-ms-win-crt-private-l1-1-0.dll
  api-ms-win-crt-runtime-l1-1-0.dll
  api-ms-win-crt-stdio-l1-1-0.dll
  api-ms-win-crt-string-l1-1-0.dll
  api-ms-win-crt-utility-l1-1-0.dll kernel32.dll libpcre-1.dll)
set(imports_libreadline8_dll
  api-ms-win-crt-convert-l1-1-0.dll
  api-ms-win-crt-environment-l1-1-0.dll
  api-ms-win-crt-filesystem-l1-1-0.dll
  api-ms-win-crt-heap-l1-1-0.dll
  api-ms-win-crt-locale-l1-1-0.dll
  api-ms-win-crt-math-l1-1-0.dll
  api-ms-win-crt-private-l1-1-0.dll
  api-ms-win-crt-runtime-l1-1-0.dll
  api-ms-win-crt-stdio-l1-1-0.dll
  api-ms-win-crt-string-l1-1-0.dll
  api-ms-win-crt-utility-l1-1-0.dll kernel32.dll libtermcap-0.dll user32.dll)
set(imports_libtermcap_0_dll
  api-ms-win-crt-convert-l1-1-0.dll
  api-ms-win-crt-environment-l1-1-0.dll
  api-ms-win-crt-filesystem-l1-1-0.dll
  api-ms-win-crt-heap-l1-1-0.dll
  api-ms-win-crt-locale-l1-1-0.dll
  api-ms-win-crt-private-l1-1-0.dll
  api-ms-win-crt-runtime-l1-1-0.dll
  api-ms-win-crt-stdio-l1-1-0.dll
  api-ms-win-crt-string-l1-1-0.dll
  api-ms-win-crt-time-l1-1-0.dll kernel32.dll)
set(imports_libwinpthread_1_dll
  api-ms-win-crt-convert-l1-1-0.dll
  api-ms-win-crt-heap-l1-1-0.dll
  api-ms-win-crt-private-l1-1-0.dll
  api-ms-win-crt-runtime-l1-1-0.dll
  api-ms-win-crt-stdio-l1-1-0.dll
  api-ms-win-crt-string-l1-1-0.dll
  api-ms-win-crt-utility-l1-1-0.dll kernel32.dll)
set(imports_libzstd_dll
  api-ms-win-crt-convert-l1-1-0.dll
  api-ms-win-crt-filesystem-l1-1-0.dll
  api-ms-win-crt-heap-l1-1-0.dll
  api-ms-win-crt-locale-l1-1-0.dll
  api-ms-win-crt-private-l1-1-0.dll
  api-ms-win-crt-runtime-l1-1-0.dll
  api-ms-win-crt-stdio-l1-1-0.dll
  api-ms-win-crt-string-l1-1-0.dll
  api-ms-win-crt-time-l1-1-0.dll
  api-ms-win-crt-utility-l1-1-0.dll kernel32.dll)
set(imports_zlib1_dll
  api-ms-win-crt-convert-l1-1-0.dll
  api-ms-win-crt-heap-l1-1-0.dll
  api-ms-win-crt-locale-l1-1-0.dll
  api-ms-win-crt-private-l1-1-0.dll
  api-ms-win-crt-runtime-l1-1-0.dll
  api-ms-win-crt-stdio-l1-1-0.dll
  api-ms-win-crt-string-l1-1-0.dll
  api-ms-win-crt-utility-l1-1-0.dll kernel32.dll)

set(staged_pe_names
  pure.exe libc++.dll libgmp-10.dll libiconv-2.dll libmpfr-6.dll
  libpcre-1.dll libpcreposix-0.dll libpure.dll libreadline8.dll
  libtermcap-0.dll libwinpthread-1.dll libzstd.dll zlib1.dll)

function(manifest_variable filename output)
  string(MAKE_C_IDENTIFIER "${filename}" identifier)
  set(${output} "imports_${identifier}" PARENT_SCOPE)
endfunction()

function(write_readobj_fixture filename imports_variable)
  string(CONCAT content
    "File: ${filename}\nFormat: COFF-x86-64\nArch: x86_64\n"
    "AddressSize: 64bit\nImageFileHeader {\n"
    "  Machine: IMAGE_FILE_MACHINE_AMD64 (0x8664)\n}\n")
  foreach(import IN LISTS ${imports_variable})
    string(APPEND content "Import {\n  Name: ${import}\n}\n")
  endforeach()
  file(WRITE "${fixture_dir}/${filename}.txt" "${content}")
endfunction()

file(WRITE "${module_dir}/odbc.dll" "fixture odbc module\n")
write_readobj_fixture("odbc.dll" imports_odbc_dll)
foreach(pe IN LISTS staged_pe_names)
  file(WRITE "${stage_bin}/${pe}" "fixture ${pe}\n")
  manifest_variable("${pe}" imports_variable)
  write_readobj_fixture("${pe}" "${imports_variable}")
endforeach()
file(WRITE "${system_directory}/odbc32.dll" "native system ODBC fixture\n")
set(no_imports)
write_readobj_fixture("odbc32.dll" no_imports)

file(WRITE "${runtime_root}/fake-llvm-readobj.cmd" [=[@echo off
setlocal
if /i "%~1"=="--file-headers" (
  if not "%~2"=="--coff-imports" exit /b 91
  set "target=%~3"
) else if /i "%~1"=="--coff-imports" (
  set "target=%~2"
) else (
  exit /b 92
)
for %%F in ("%target%") do set "fixture=%~dp0readobj\%%~nxF.txt"
if not exist "%fixture%" (
  echo missing fixture for %target% 1>&2
  exit /b 93
)
type "%fixture%"
]=])

set(verifier "${SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake")
set(verifier_arguments
  "-DLLVM_READOBJ=${runtime_root}/fake-llvm-readobj.cmd"
  "-DSTAGE_PREFIX=${stage}"
  "-DODBC_MODULE=${module_dir}/odbc.dll"
  "-DGMP_DLL=${stage_bin}/libgmp-10.dll"
  "-DPURE_RUNTIME_DLL=${stage_bin}/libpure.dll"
  "-DPURE_EXECUTABLE=${stage_bin}/pure.exe"
  "-DWINDOWS_DIRECTORY=${windows_directory}"
  "-DSYSTEM_ODBC_DLL=${system_directory}/odbc32.dll"
  "-DPURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY=${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}"
)

function(run_verifier result_var diagnostics_var)
  execute_process(
    COMMAND "${CMAKE_COMMAND}" ${verifier_arguments} ${ARGN} -P "${verifier}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8
  )
  set(${result_var} "${result}" PARENT_SCOPE)
  set(${diagnostics_var} "${output}\n${error}" PARENT_SCOPE)
endfunction()

function(expect_rejected label expected)
  run_verifier(result diagnostics ${ARGN})
  if(result EQUAL 0)
    message(FATAL_ERROR "PE verifier accepted ${label}")
  endif()
  if(NOT diagnostics MATCHES "${expected}")
    message(FATAL_ERROR
      "PE verifier rejected ${label} with the wrong diagnostic\n"
      "${diagnostics}")
  endif()
endfunction()

run_verifier(pristine_result pristine_diagnostics)
if(NOT pristine_result EQUAL 0)
  message(FATAL_ERROR
    "Exact PE fixtures were rejected (${pristine_result})\n"
    "${pristine_diagnostics}")
endif()

set(odbc_fixture "${fixture_dir}/odbc.dll.txt")
file(READ "${odbc_fixture}" original_odbc_fixture)
string(APPEND original_with_extra
  "${original_odbc_fixture}" "Import {\n  Name: unexpected.dll\n}\n")
file(WRITE "${odbc_fixture}" "${original_with_extra}")
expect_rejected("an extra import" "unexpected:.*unexpected\\.dll")
file(WRITE "${odbc_fixture}" "${original_odbc_fixture}")

file(WRITE "${odbc_fixture}" "malformed output\n")
expect_rejected("malformed llvm-readobj output" "Malformed llvm-readobj output")
file(WRITE "${odbc_fixture}" "${original_odbc_fixture}")

file(APPEND "${odbc_fixture}" "MysteryImport {\n}\n")
expect_rejected("an unknown llvm-readobj record" "Unknown llvm-readobj record")
file(WRITE "${odbc_fixture}" "${original_odbc_fixture}")

file(APPEND "${odbc_fixture}" "Import {\n  Name: LiBpUrE.DlL\n}\n")
expect_rejected("a duplicate import" "duplicate import.*libpure\\.dll")
file(WRITE "${odbc_fixture}" "${original_odbc_fixture}")

string(REPLACE "Arch: x86_64" "Arch: i386" wrong_arch "${original_odbc_fixture}")
string(REPLACE "IMAGE_FILE_MACHINE_AMD64" "IMAGE_FILE_MACHINE_I386"
  wrong_arch "${wrong_arch}")
file(WRITE "${odbc_fixture}" "${wrong_arch}")
expect_rejected("a non-AMD64 module" "AMD64.*odbc\\.dll|odbc\\.dll.*AMD64")
file(WRITE "${odbc_fixture}" "${original_odbc_fixture}")

set(missing_module_record "Import {\n  Name: libpure.dll\n}\n")
string(REPLACE "${missing_module_record}" "" missing_module_import
  "${original_odbc_fixture}")
file(WRITE "${odbc_fixture}" "${missing_module_import}")
expect_rejected("a missing direct import"
  "missing:.*libpure\\.dll")
file(WRITE "${odbc_fixture}" "${original_odbc_fixture}")

set(libpure_fixture "${fixture_dir}/libpure.dll.txt")
file(READ "${libpure_fixture}" original_libpure_fixture)
set(missing_transitive_record "Import {\n  Name: libzstd.dll\n}\n")
string(REPLACE "${missing_transitive_record}" "" missing_transitive_import
  "${original_libpure_fixture}")
file(WRITE "${libpure_fixture}" "${missing_transitive_import}")
expect_rejected("a missing transitive import"
  "missing:.*libzstd\\.dll")
file(WRITE "${libpure_fixture}" "${original_libpure_fixture}")

file(APPEND "${libpure_fixture}"
  "Import {\n  Name: unexpected-transitive.dll\n}\n")
expect_rejected("an unexpected transitive import"
  "unexpected:.*unexpected-transitive\\.dll")
file(WRITE "${libpure_fixture}" "${original_libpure_fixture}")

file(REMOVE "${stage_bin}/libzstd.dll")
expect_rejected("an unresolved staged dependency"
  "Unresolved staged dependency.*libzstd\\.dll")
file(WRITE "${stage_bin}/libzstd.dll" "fixture libzstd.dll\n")

file(MAKE_DIRECTORY "${stage}/nested/manager")
file(WRITE "${stage}/nested/manager/ODBC32.dll" "bundled manager\n")
expect_rejected("a bundled ODBC manager" "bundled ODBC manager.*ODBC32\\.dll")
file(REMOVE "${stage}/nested/manager/ODBC32.dll")
file(WRITE "${stage}/nested/manager/libodbc.dll" "bundled unixODBC\n")
expect_rejected("bundled unixODBC" "bundled ODBC manager.*libodbc\\.dll")
file(REMOVE "${stage}/nested/manager/libodbc.dll")

file(MAKE_DIRECTORY "${runtime_root}/wrong-system")
file(WRITE "${runtime_root}/wrong-system/odbc32.dll" "wrong ODBC manager\n")
expect_rejected("ODBC32 outside native System32"
  "SYSTEM_ODBC_DLL.*System32"
  "-DSYSTEM_ODBC_DLL=${runtime_root}/wrong-system/odbc32.dll")

set(system_fixture "${fixture_dir}/odbc32.dll.txt")
file(READ "${system_fixture}" original_system_fixture)
string(REPLACE "Arch: x86_64" "Arch: i386" wrong_system_arch
  "${original_system_fixture}")
string(REPLACE "IMAGE_FILE_MACHINE_AMD64" "IMAGE_FILE_MACHINE_I386"
  wrong_system_arch "${wrong_system_arch}")
file(WRITE "${system_fixture}" "${wrong_system_arch}")
expect_rejected("a 32-bit System32 ODBC manager" "AMD64.*odbc32\\.dll")
file(WRITE "${system_fixture}" "${original_system_fixture}")

file(MAKE_DIRECTORY "${runtime_root}/directory-tool")
expect_rejected("a directory llvm-readobj input" "LLVM_READOBJ.*file"
  "-DLLVM_READOBJ=${runtime_root}/directory-tool")
expect_rejected("a missing llvm-readobj input" "LLVM_READOBJ.*file"
  "-DLLVM_READOBJ=${runtime_root}/missing-llvm-readobj.exe")

run_verifier(final_result final_diagnostics)
if(NOT final_result EQUAL 0)
  message(FATAL_ERROR
    "PE fixture was not pristine after mutations (${final_result})\n"
    "${final_diagnostics}")
endif()

message(STATUS
  "pure-odbc PE contract passed all exact import, parser, architecture, "
  "recursion, and native System32 mutations")
