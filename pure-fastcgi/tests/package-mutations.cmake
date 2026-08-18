cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS
    BUILD_DIR STAGE_PREFIX SOURCE_DIR PURE_RUNTIME_ROOT LLVM_READOBJ
    POWERSHELL_EXECUTABLE VERIFIER)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

foreach(directory IN ITEMS BUILD_DIR SOURCE_DIR PURE_RUNTIME_ROOT)
  cmake_path(ABSOLUTE_PATH ${directory} NORMALIZE
    OUTPUT_VARIABLE normalized_${directory})
endforeach()
set(build_dir "${normalized_BUILD_DIR}")
set(source_dir "${normalized_SOURCE_DIR}")
set(runtime_root "${normalized_PURE_RUNTIME_ROOT}")
cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE stage)
set(append_text_helper "${stage}-append-encoded-text.ps1")
file(WRITE "${append_text_helper}" [=[
param(
  [Parameter(Mandatory = $true)][string]$FilePath,
  [Parameter(Mandatory = $true)][string]$Text,
  [Parameter(Mandatory = $true)]
  [ValidateSet('ASCII', 'UTF16LE')][string]$Encoding
)
$codec = if ($Encoding -eq 'ASCII') {
  [System.Text.Encoding]::ASCII
} else {
  [System.Text.Encoding]::Unicode
}
$bytes = $codec.GetBytes($Text)
$stream = [System.IO.File]::Open(
  $FilePath,
  [System.IO.FileMode]::Append,
  [System.IO.FileAccess]::Write,
  [System.IO.FileShare]::Read)
try {
  $stream.Write($bytes, 0, $bytes.Length)
} finally {
  $stream.Dispose()
}
]=])

execute_process(
  COMMAND "${CMAKE_COMMAND}" --build "${build_dir}"
    --target pure-fastcgi-package-oracles pure-fastcgi-protocol-harness
  RESULT_VARIABLE build_result
  OUTPUT_VARIABLE build_output
  ERROR_VARIABLE build_error
  ENCODING UTF-8)
if(NOT build_result EQUAL 0)
  message(FATAL_ERROR
    "PureFastCGI package inputs failed to build (${build_result})\n"
    "stdout:\n${build_output}\nstderr:\n${build_error}")
endif()

file(REMOVE_RECURSE "${stage}")
execute_process(
  COMMAND "${CMAKE_COMMAND}" --install "${build_dir}"
    --prefix "${stage}" --component PureFastCGI
  RESULT_VARIABLE install_result
  OUTPUT_VARIABLE install_output
  ERROR_VARIABLE install_error
  ENCODING UTF-8)
if(NOT install_result EQUAL 0)
  message(FATAL_ERROR
    "PureFastCGI component install failed (${install_result})\n"
    "stdout:\n${install_output}\nstderr:\n${install_error}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DBUILD_DIR=${build_dir}"
    "-DSTAGE_PREFIX=${stage}"
    "-DPURE_RUNTIME_ROOT=${runtime_root}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    "-DPOWERSHELL_EXECUTABLE=${POWERSHELL_EXECUTABLE}"
    "-DSOURCE_PREFIX=${source_dir}"
    "-DORIGINAL_BUILD_PREFIX=${build_dir}"
    "-DORIGINAL_STAGE_PREFIX=${stage}"
    -DRUN_RUNTIME_TESTS=ON
    "-DPROTOCOL_HARNESS=${build_dir}/pure-fastcgi-protocol-harness.exe"
    "-DPROTOCOL_WORKER=${source_dir}/tests/protocol_worker.pure"
    -P "${VERIFIER}"
  RESULT_VARIABLE verify_result
  OUTPUT_VARIABLE verify_output
  ERROR_VARIABLE verify_error
  ENCODING UTF-8)
if(NOT verify_result EQUAL 0)
  message(FATAL_ERROR
    "valid PureFastCGI package was rejected (${verify_result})\n"
    "stdout:\n${verify_output}\nstderr:\n${verify_error}")
endif()

function(clone_case case_name out_build out_stage)
  set(case_build "${stage}-oracles-${case_name}")
  set(case_stage "${stage}-mutation-${case_name}")
  file(REMOVE_RECURSE "${case_build}" "${case_stage}")
  file(MAKE_DIRECTORY "${case_build}" "${case_stage}")
  file(COPY "${stage}/" DESTINATION "${case_stage}")
  file(COPY
    "${build_dir}/PureFastCGIExpected.sha256"
    "${build_dir}/PureFastCGIInventory.tsv"
    DESTINATION "${case_build}")
  set(${out_build} "${case_build}" PARENT_SCOPE)
  set(${out_stage} "${case_stage}" PARENT_SCOPE)
endfunction()

function(run_rejected_case case_name case_build case_stage expected_category)
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DBUILD_DIR=${case_build}"
      "-DSTAGE_PREFIX=${case_stage}"
      "-DPURE_RUNTIME_ROOT=${runtime_root}"
      "-DLLVM_READOBJ=${LLVM_READOBJ}"
      "-DPOWERSHELL_EXECUTABLE=${POWERSHELL_EXECUTABLE}"
      "-DSOURCE_PREFIX=${source_dir}"
      "-DORIGINAL_BUILD_PREFIX=${build_dir}"
      "-DORIGINAL_STAGE_PREFIX=${stage}"
      -DRUN_RUNTIME_TESTS=OFF
      -P "${VERIFIER}"
    RESULT_VARIABLE case_result
    OUTPUT_VARIABLE case_output
    ERROR_VARIABLE case_error
    ENCODING UTF-8)
  set(case_log "${case_output}${case_error}")
  if(case_result EQUAL 0)
    message(FATAL_ERROR
      "mutation ${case_name} was accepted; expected ${expected_category}")
  endif()
  if(NOT case_log MATCHES "${expected_category}")
    message(FATAL_ERROR
      "mutation ${case_name} failed without ${expected_category}\n${case_log}")
  endif()
endfunction()

function(run_prefix_input_case case_name expected_category)
  set(verifier_arguments
    "-DBUILD_DIR=${build_dir}"
    "-DSTAGE_PREFIX=${stage}"
    "-DPURE_RUNTIME_ROOT=${runtime_root}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    "-DPOWERSHELL_EXECUTABLE=${POWERSHELL_EXECUTABLE}"
    -DRUN_RUNTIME_TESTS=OFF)
  if(case_name STREQUAL "relative-source")
    list(APPEND verifier_arguments "-DSOURCE_PREFIX=relative/source")
  elseif(NOT case_name STREQUAL "missing-source")
    list(APPEND verifier_arguments "-DSOURCE_PREFIX=${source_dir}")
  endif()
  if(NOT case_name STREQUAL "missing-original-build")
    list(APPEND verifier_arguments "-DORIGINAL_BUILD_PREFIX=${build_dir}")
  endif()
  if(NOT case_name STREQUAL "missing-original-stage")
    list(APPEND verifier_arguments "-DORIGINAL_STAGE_PREFIX=${stage}")
  endif()
  execute_process(
    COMMAND "${CMAKE_COMMAND}" ${verifier_arguments} -P "${VERIFIER}"
    RESULT_VARIABLE case_result
    OUTPUT_VARIABLE case_output
    ERROR_VARIABLE case_error
    ENCODING UTF-8)
  set(case_log "${case_output}${case_error}")
  if(case_result EQUAL 0)
    message(FATAL_ERROR
      "prefix-input case ${case_name} was accepted; expected ${expected_category}")
  endif()
  if(NOT case_log MATCHES "${expected_category}")
    message(FATAL_ERROR
      "prefix-input case ${case_name} failed without ${expected_category}\n"
      "${case_log}")
  endif()
endfunction()

function(append_encoded_text file_path text_value encoding)
  execute_process(
    COMMAND "${POWERSHELL_EXECUTABLE}"
      -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass
      -File "${append_text_helper}"
      -FilePath "${file_path}"
      -Text "${text_value}"
      -Encoding "${encoding}"
    RESULT_VARIABLE append_result
    OUTPUT_VARIABLE append_output
    ERROR_VARIABLE append_error
    ENCODING UTF-8)
  if(NOT append_result EQUAL 0)
    message(FATAL_ERROR
      "failed to append ${encoding} test data (${append_result})\n"
      "${append_output}${append_error}")
  endif()
endfunction()

function(write_fake_readobj output_file mode import_name)
  if(mode STREQUAL "failure")
    file(WRITE "${output_file}"
      "@echo off\r\necho synthetic parser failure 1>&2\r\nexit /b 7\r\n")
  elseif(mode STREQUAL "recursive-undeclared")
    file(WRITE "${output_file}"
      "@echo off\r\n"
      "set dependency=\r\n"
      "if /I \"%~nx2\"==\"fastcgi.dll\" set dependency=libgmp-10.dll\r\n"
      "if /I \"%~nx2\"==\"libgmp-10.dll\" set dependency=evil-runtime.dll\r\n"
      "echo File: %~2\r\n"
      "echo Format: COFF-x86-64\r\n"
      "if defined dependency (\r\n"
      "  echo Import {\r\n"
      "  echo   Name: %dependency%\r\n"
      "  echo }\r\n"
      ")\r\n"
      "exit /b 0\r\n")
  else()
    file(WRITE "${output_file}"
      "@echo off\r\n"
      "echo File: %~2\r\n"
      "echo Format: COFF-x86-64\r\n"
      "echo Import {\r\n"
      "echo   Name: ${import_name}\r\n"
      "echo }\r\n"
      "exit /b 0\r\n")
  endif()
endfunction()

function(run_mocked_pe_case case_name fake_readobj case_runtime_root
    expected_category)
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DBUILD_DIR=${build_dir}"
      "-DSTAGE_PREFIX=${stage}"
      "-DPURE_RUNTIME_ROOT=${case_runtime_root}"
      "-DLLVM_READOBJ=${fake_readobj}"
      "-DPOWERSHELL_EXECUTABLE=${POWERSHELL_EXECUTABLE}"
      "-DSOURCE_PREFIX=${source_dir}"
      "-DORIGINAL_BUILD_PREFIX=${build_dir}"
      "-DORIGINAL_STAGE_PREFIX=${stage}"
      -DRUN_RUNTIME_TESTS=OFF
      -P "${VERIFIER}"
    RESULT_VARIABLE case_result
    OUTPUT_VARIABLE case_output
    ERROR_VARIABLE case_error
    ENCODING UTF-8)
  set(case_log "${case_output}${case_error}")
  if(case_result EQUAL 0)
    message(FATAL_ERROR
      "mocked PE case ${case_name} was accepted; expected ${expected_category}")
  endif()
  if(NOT case_log MATCHES "${expected_category}")
    message(FATAL_ERROR
      "mocked PE case ${case_name} failed without ${expected_category}\n"
      "${case_log}")
  endif()
endfunction()

function(rewrite_staged_inventory mutation case_stage)
  set(staged_inventory
    "${case_stage}/share/doc/pure-fastcgi/PureFastCGIInventory.tsv")
  file(STRINGS "${staged_inventory}" lines ENCODING UTF-8)
  list(POP_FRONT lines header)
  string(ASCII 9 local_tab)
  set(rewritten "${header}\n")
  set(first_payload_row "")
  if(mutation STREQUAL "reverse-order")
    list(REVERSE lines)
  endif()
  foreach(line IN LISTS lines)
    if(first_payload_row STREQUAL "")
      set(first_payload_row "${line}")
    endif()
    if(mutation STREQUAL "forged-hash" AND
        line MATCHES "^lib/pure/fastcgi\\.dll${local_tab}")
      string(REPLACE "${local_tab}" ";" fields "${line}")
      list(REMOVE_AT fields 4)
      list(INSERT fields 4
        "0000000000000000000000000000000000000000000000000000000000000000")
      string(JOIN "${local_tab}" line ${fields})
    endif()
    string(APPEND rewritten "${line}\n")
  endforeach()
  if(mutation STREQUAL "case-collision")
    string(REPLACE "${local_tab}" ";" collision_fields "${first_payload_row}")
    list(REMOVE_AT collision_fields 0)
    list(INSERT collision_fields 0 "LIB/pure/fastcgi.dll")
    string(JOIN "${local_tab}" collision_row ${collision_fields})
    string(APPEND rewritten "${collision_row}\n")
  elseif(mutation STREQUAL "duplicate")
    string(APPEND rewritten "${first_payload_row}\n")
  elseif(mutation STREQUAL "absolute" OR mutation STREQUAL "traversal")
    string(REPLACE "${local_tab}" ";" unsafe_fields "${first_payload_row}")
    list(REMOVE_AT unsafe_fields 0)
    if(mutation STREQUAL "absolute")
      list(INSERT unsafe_fields 0 "C:/outside/fastcgi.dll")
    else()
      list(INSERT unsafe_fields 0 "../outside/fastcgi.dll")
    endif()
    string(JOIN "${local_tab}" unsafe_row ${unsafe_fields})
    string(APPEND rewritten "${unsafe_row}\n")
  elseif(mutation STREQUAL "malformed")
    string(APPEND rewritten "malformed-row\n")
  endif()
  file(WRITE "${staged_inventory}" "${rewritten}")
endfunction()

clone_case("changed-module" case_build case_stage)
file(APPEND "${case_stage}/lib/pure/fastcgi.dll" "changed")
run_rejected_case(
  "changed-module" "${case_build}" "${case_stage}" "PACKAGE_HASH_MISMATCH")

clone_case("undeclared-file" case_build case_stage)
file(WRITE "${case_stage}/share/doc/pure-fastcgi/undeclared.txt" "undeclared\n")
run_rejected_case(
  "undeclared-file" "${case_build}" "${case_stage}"
  "PACKAGE_FILE_SET_MISMATCH")

clone_case("deleted-license" case_build case_stage)
file(REMOVE "${case_stage}/share/doc/pure-fastcgi/LICENSE.fcgi2")
run_rejected_case(
  "deleted-license" "${case_build}" "${case_stage}"
  "PACKAGE_FILE_SET_MISMATCH")

clone_case("forged-inventory-hash" case_build case_stage)
rewrite_staged_inventory("forged-hash" "${case_stage}")
run_rejected_case(
  "forged-inventory-hash" "${case_build}" "${case_stage}"
  "INVENTORY_ORACLE_MISMATCH")

clone_case("case-colliding-path" case_build case_stage)
rewrite_staged_inventory("case-collision" "${case_stage}")
run_rejected_case(
  "case-colliding-path" "${case_build}" "${case_stage}"
  "INVENTORY_CASE_COLLISION")

clone_case("malformed-inventory" case_build case_stage)
rewrite_staged_inventory("malformed" "${case_stage}")
run_rejected_case(
  "malformed-inventory" "${case_build}" "${case_stage}"
  "INVENTORY_MALFORMED")

clone_case("duplicate-inventory-path" case_build case_stage)
rewrite_staged_inventory("duplicate" "${case_stage}")
run_rejected_case(
  "duplicate-inventory-path" "${case_build}" "${case_stage}"
  "INVENTORY_DUPLICATE_PATH")

clone_case("absolute-inventory-path" case_build case_stage)
rewrite_staged_inventory("absolute" "${case_stage}")
run_rejected_case(
  "absolute-inventory-path" "${case_build}" "${case_stage}"
  "INVENTORY_UNSAFE_PATH")

clone_case("traversal-inventory-path" case_build case_stage)
rewrite_staged_inventory("traversal" "${case_stage}")
run_rejected_case(
  "traversal-inventory-path" "${case_build}" "${case_stage}"
  "INVENTORY_UNSAFE_PATH")

clone_case("unordered-inventory" case_build case_stage)
rewrite_staged_inventory("reverse-order" "${case_stage}")
run_rejected_case(
  "unordered-inventory" "${case_build}" "${case_stage}"
  "INVENTORY_ORDER_MISMATCH")

clone_case("synthetic-libfcgi" case_build case_stage)
file(COPY_FILE
  "${case_stage}/lib/pure/fastcgi.dll"
  "${case_stage}/lib/pure/libfcgi.dll")
run_rejected_case(
  "synthetic-libfcgi" "${case_build}" "${case_stage}"
  "FORBIDDEN_FASTCGI_DLL")

run_prefix_input_case("missing-source" "VERIFY_INPUT_MISSING")
run_prefix_input_case("relative-source" "PREFIX_INPUT_INVALID")
run_prefix_input_case("missing-original-build" "VERIFY_INPUT_MISSING")
run_prefix_input_case("missing-original-stage" "VERIFY_INPUT_MISSING")

clone_case("ascii-prefix-leak" case_build case_stage)
append_encoded_text(
  "${case_stage}/lib/pure/fastcgi.dll" "${case_build}" "ASCII")
run_rejected_case(
  "ascii-prefix-leak" "${case_build}" "${case_stage}"
  "PACKAGE_PREFIX_LEAK")

clone_case("utf16-prefix-leak" case_build case_stage)
append_encoded_text(
  "${case_stage}/lib/pure/fastcgi.dll" "${case_stage}" "UTF16LE")
run_rejected_case(
  "utf16-prefix-leak" "${case_build}" "${case_stage}"
  "PACKAGE_PREFIX_LEAK")

set(fake_bogus_api "${stage}-fake-bogus-api-readobj.cmd")
write_fake_readobj(
  "${fake_bogus_api}" "import" "api-ms-win-crt-bogus-l9-9-9.dll")
run_mocked_pe_case(
  "bogus-api-set" "${fake_bogus_api}" "${runtime_root}"
  "PE_UNDECLARED_IMPORT")

set(fake_unreviewed_system "${stage}-fake-unreviewed-system-readobj.cmd")
write_fake_readobj("${fake_unreviewed_system}" "import" "user32.dll")
run_mocked_pe_case(
  "unreviewed-system-dll" "${fake_unreviewed_system}" "${runtime_root}"
  "PE_UNDECLARED_IMPORT")

set(fake_parser_failure "${stage}-fake-parser-failure-readobj.cmd")
write_fake_readobj("${fake_parser_failure}" "failure" "")
run_mocked_pe_case(
  "parser-failure" "${fake_parser_failure}" "${runtime_root}"
  "PE_PARSE_FAILED")

set(fake_recursive "${stage}-fake-recursive-readobj.cmd")
write_fake_readobj("${fake_recursive}" "recursive-undeclared" "")
run_mocked_pe_case(
  "recursive-undeclared-import" "${fake_recursive}" "${runtime_root}"
  "PE_UNDECLARED_IMPORT")

set(fake_missing_runtime "${stage}-fake-missing-runtime-readobj.cmd")
set(empty_runtime_root "${stage}-empty-runtime-root")
file(REMOVE_RECURSE "${empty_runtime_root}")
file(MAKE_DIRECTORY "${empty_runtime_root}")
write_fake_readobj(
  "${fake_missing_runtime}" "import" "libgmp-10.dll")
run_mocked_pe_case(
  "missing-runtime" "${fake_missing_runtime}" "${empty_runtime_root}"
  "PE_RUNTIME_MISSING")

file(REMOVE_RECURSE
  "${stage}-oracles-changed-module"
  "${stage}-mutation-changed-module"
  "${stage}-oracles-undeclared-file"
  "${stage}-mutation-undeclared-file"
  "${stage}-oracles-deleted-license"
  "${stage}-mutation-deleted-license"
  "${stage}-oracles-forged-inventory-hash"
  "${stage}-mutation-forged-inventory-hash"
  "${stage}-oracles-case-colliding-path"
  "${stage}-mutation-case-colliding-path"
  "${stage}-oracles-malformed-inventory"
  "${stage}-mutation-malformed-inventory"
  "${stage}-oracles-duplicate-inventory-path"
  "${stage}-mutation-duplicate-inventory-path"
  "${stage}-oracles-absolute-inventory-path"
  "${stage}-mutation-absolute-inventory-path"
  "${stage}-oracles-traversal-inventory-path"
  "${stage}-mutation-traversal-inventory-path"
  "${stage}-oracles-unordered-inventory"
  "${stage}-mutation-unordered-inventory"
  "${stage}-oracles-synthetic-libfcgi"
  "${stage}-mutation-synthetic-libfcgi"
  "${stage}-oracles-ascii-prefix-leak"
  "${stage}-mutation-ascii-prefix-leak"
  "${stage}-oracles-utf16-prefix-leak"
  "${stage}-mutation-utf16-prefix-leak"
  "${fake_bogus_api}"
  "${fake_unreviewed_system}"
  "${fake_parser_failure}"
  "${fake_recursive}"
  "${fake_missing_runtime}"
  "${empty_runtime_root}"
  "${append_text_helper}")
