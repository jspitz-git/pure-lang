cmake_minimum_required(VERSION 3.25)
if(NOT DEFINED WORKFLOW OR NOT EXISTS "${WORKFLOW}")
  message(FATAL_ERROR "CI_CONTRACT_INPUT: WORKFLOW must name an existing file")
endif()
file(READ "${WORKFLOW}" workflow)
string(REPLACE "\r\n" "\n" workflow "${workflow}")
function(require_text scope category)
  foreach(required IN LISTS ARGN)
    string(FIND "${scope}" "${required}" position)
    if(position EQUAL -1)
      message(FATAL_ERROR "CI_CONTRACT_${category}: missing ${required}")
    endif()
  endforeach()
endfunction()
function(reject_text scope category)
  foreach(forbidden IN LISTS ARGN)
    string(FIND "${scope}" "${forbidden}" position)
    if(NOT position EQUAL -1)
      message(FATAL_ERROR "CI_CONTRACT_${category}: obsolete ${forbidden}")
    endif()
  endforeach()
endfunction()
string(FIND "${workflow}" "\njobs:\n" jobs_position)
if(jobs_position EQUAL -1)
  message(FATAL_ERROR "CI_CONTRACT_STRUCTURE: jobs mapping is missing")
endif()
string(SUBSTRING "${workflow}" 0 ${jobs_position} workflow_header)
require_text("${workflow_header}" TRIGGER "pure-fastcgi/**")
string(FIND "${workflow}" "\n  windows-pure-fastcgi:\n" job_position)
if(job_position EQUAL -1)
  message(FATAL_ERROR "CI_CONTRACT_JOB: windows-pure-fastcgi job is missing")
endif()
string(SUBSTRING "${workflow}" ${job_position} -1 job_tail)
string(SUBSTRING "${job_tail}" 1 -1 job_tail)
string(REGEX MATCH "\n  [a-zA-Z0-9_-]+:\n" next_job "${job_tail}")
if(next_job STREQUAL "")
  set(job "${job_tail}")
else()
  string(FIND "${job_tail}" "${next_job}" next_position)
  string(SUBSTRING "${job_tail}" 0 ${next_position} job)
endif()
function(extract_step title output)
  set(marker "      - name: ${title}\n")
  string(FIND "${job}" "${marker}" begin)
  if(begin EQUAL -1)
    message(FATAL_ERROR "CI_CONTRACT_STEP: missing step ${title}")
  endif()
  string(SUBSTRING "${job}" ${begin} -1 tail)
  string(SUBSTRING "${tail}" 1 -1 tail_without_first)
  string(FIND "${tail_without_first}" "\n      - name:" finish)
  if(finish EQUAL -1)
    set(step "${tail}")
  else()
    math(EXPR length "${finish} + 1")
    string(SUBSTRING "${tail}" 0 ${length} step)
  endif()
  set(${output} "${step}" PARENT_SCOPE)
endfunction()
require_text("${job}" JOB
  "name: Windows PureFastCGI package" "runs-on: windows-2025"
  "working-directory: source with spaces"
  "FCGI2_URL: https://github.com/FastCGI-Archives/fcgi2/archive/refs/tags/2.4.7.tar.gz"
  "FCGI2_RELEASE: 2.4.7"
  "FCGI2_COMMIT: 47f2c03b7771f0ef61d887734ef91e6fa747f837"
  "FCGI2_SIZE: 263969"
  "FCGI2_SHA256: e41ddc3a473b555bdc0cbd80703dcb1f4610c1a7700d3b9d3d0c14a416e1074b")
extract_step("Install the CLANG64 PureFastCGI prerequisites" prerequisites_step)
require_text("${prerequisites_step}" PREREQUISITES "patch")
extract_step("Build and install the matching Windows Pure runtime" pure_step)
require_text("${pure_step}" PURE "-S pure" "-G Ninja"
  "C:/msys64/clang64/bin/clang.exe" "C:/msys64/clang64/bin/clang++.exe"
  "-DBISON_EXECUTABLE=C:/msys64/usr/bin/bison.exe"
  "-DFLEX_EXECUTABLE=C:/msys64/usr/bin/flex.exe"
  "--build $pureBuild --parallel 1" "--install $pureBuild"
  "PURE_FASTCGI_PURE_PREFIX=" "PURE_BUILD_SECONDS=")
extract_step("Explicitly fetch and verify pinned fcgi2" fetch_step)
require_text("${fetch_step}" FETCH "FetchFcgi2Entry.cmake" "-DOUTPUT=$archive"
  "Get-FileHash" "FCGI2_SIZE" "FCGI2_SHA256" "PURE_FASTCGI_ARCHIVE=")
extract_step("Configure and build PureFastCGI with CLANG64" build_step)
require_text("${build_step}" BUILD "-S pure-fastcgi" "-G Ninja"
  "C:/msys64/clang64/bin/clang.exe" "PURE_FASTCGI_FCGI2_ARCHIVE="
  "-DPATCH_EXECUTABLE=C:/msys64/usr/bin/patch.exe"
  "PURE_FASTCGI_PURE_EXECUTABLE=" "PURE_FASTCGI_PURE_RUNTIME_DIR="
  "--build $build --parallel 1" "FASTCGI_BUILD_SECONDS=")
extract_step("Run the complete PureFastCGI CTest label" test_step)
require_text("${test_step}" TEST "ctest.exe --test-dir" "-L fastcgi" "--no-tests=error")
extract_step("Install only PureFastCGI and verify sanitized runtime" verify_step)
require_text("${verify_step}" VERIFY "--component PureFastCGI"
  "Remove-Item Env:PURELIB" "System32/WindowsPowerShell/v1.0"
  "VerifyInstalledPackage.cmake" "RUN_RUNTIME_TESTS=ON"
  "-DSOURCE_PREFIX=$repo/pure-fastcgi"
  "-DORIGINAL_BUILD_PREFIX=$env:PURE_FASTCGI_BUILD"
  "-DORIGINAL_STAGE_PREFIX=$stage"
  "PROTOCOL_HARNESS=" "PROTOCOL_WORKER=")
reject_text("${verify_step}" VERIFY "-DSOURCE_DIR=")
extract_step("Record fail-closed package metrics and recursive PE imports" metrics_step)
require_text("${metrics_step}" METRICS "clang.exe --version" "cmakeVersion"
  "ninjaVersion" "pkgconfVersion" "gmpVersion" "mpfrVersion"
  "PURE_BUILD_SECONDS" "FASTCGI_BUILD_SECONDS" "workers: $env:PURE_BUILD_SECONDS / 1"
  "module bytes / stage bytes / staged files" "files.Count -ne 6"
  "inventory SHA-256" "Collections.Generic.Queue[string]"
  "PURE_FASTCGI_IMPORT_PARSER_BEGIN" "function Get-CoffImportNames"
  "nonEmptyLines.Count -lt 4" "duplicate or misplaced PE header"
  "PE headers are not in the required order"
  "Import Name must be the first inner line"
  "unrecognized Import field"
  "Import block has multiple Name fields"
  "truncated Import block" "Import syntax was not fully accounted"
  "Get-CoffImportNames -Readobj $readobj -Pe $pe"
  "expectedRuntimeImports"
  "resolvedRuntimeNames" "visited.Count -le 1"
  "recursive PE import closure did not resolve runtime dependencies"
  "Complete fastcgi.dll imports")
reject_text("${metrics_step}" METRICS "DLLName:")
reject_text("${metrics_step}" METRICS "readobj -notmatch 'Import'")
extract_step("Create the deterministic PureFastCGI ZIP twice" zip_step)
require_text("${zip_step}" ZIP "windows-pure-fastcgi-first.zip"
  "windows-pure-fastcgi-second.zip" "[Array]::Sort($relative, [StringComparer]::Ordinal)"
  ".Replace('\\', '/')" "2000-01-01T00:00:00+00:00"
  "Get-FileHash $first" "Get-FileHash $second" "firstHash -cne $secondHash"
  "deterministic ZIP hashes differ" "Copy-Item -LiteralPath $first -Destination $archive")
extract_step("Upload the PureFastCGI package" upload_step)
require_text("${upload_step}" UPLOAD "actions/upload-artifact@v4"
  "name: windows-pure-fastcgi"
  "source with spaces/build/pure-fastcgi-artifacts/windows-pure-fastcgi.zip"
  "if-no-files-found: error")
if(NOT MUTATION_MODE)
  set(mutation_tokens "pure-fastcgi/**" "name: Windows PureFastCGI package"
    "working-directory: source with spaces"
    "            patch"
    "FCGI2_URL: https://github.com/FastCGI-Archives/fcgi2/archive/refs/tags/2.4.7.tar.gz"
    "FCGI2_COMMIT: 47f2c03b7771f0ef61d887734ef91e6fa747f837"
    "FCGI2_SIZE: 263969"
    "FCGI2_SHA256: e41ddc3a473b555bdc0cbd80703dcb1f4610c1a7700d3b9d3d0c14a416e1074b"
    "-DBISON_EXECUTABLE=C:/msys64/usr/bin/bison.exe"
    "-DFLEX_EXECUTABLE=C:/msys64/usr/bin/flex.exe"
    "--install $pureBuild" "PURE_FASTCGI_PURE_PREFIX="
    "FetchFcgi2Entry.cmake" "PURE_FASTCGI_FCGI2_ARCHIVE="
    "-DPATCH_EXECUTABLE=C:/msys64/usr/bin/patch.exe"
    "-L fastcgi" "--component PureFastCGI" "Remove-Item Env:PURELIB"
    "-DSOURCE_PREFIX=$repo/pure-fastcgi"
    "-DORIGINAL_BUILD_PREFIX=$env:PURE_FASTCGI_BUILD"
    "-DORIGINAL_STAGE_PREFIX=$stage"
    "RUN_RUNTIME_TESTS=ON" "files.Count -ne 6" "gmpVersion"
    "inventory SHA-256" "Collections.Generic.Queue[string]"
    "function Get-CoffImportNames" "duplicate or misplaced PE header"
    "PE headers are not in the required order"
    "Import Name must be the first inner line" "unrecognized Import field"
    "Import block has multiple Name fields"
    "truncated Import block" "Import syntax was not fully accounted"
    "Get-CoffImportNames -Readobj $readobj -Pe $pe" "expectedRuntimeImports"
    "resolvedRuntimeNames" "visited.Count -le 1"
    "[Array]::Sort($relative, [StringComparer]::Ordinal)"
    "2000-01-01T00:00:00+00:00" "firstHash -cne $secondHash"
    "actions/upload-artifact@v4"
    "source with spaces/build/pure-fastcgi-artifacts/windows-pure-fastcgi.zip")
  set(index 0)
  foreach(token IN LISTS mutation_tokens)
    math(EXPR index "${index} + 1")
    string(REPLACE "${token}" "BROKEN_${index}" mutated "${workflow}")
    set(subject "${CMAKE_CURRENT_BINARY_DIR}/ci-contract-mutation-${index}.yml")
    file(WRITE "${subject}" "${mutated}")
    execute_process(COMMAND "${CMAKE_COMMAND}" "-DWORKFLOW=${subject}"
        -DMUTATION_MODE=ON -P "${CMAKE_CURRENT_LIST_FILE}"
      RESULT_VARIABLE result OUTPUT_QUIET ERROR_QUIET)
    file(REMOVE "${subject}")
    if(result EQUAL 0)
      message(FATAL_ERROR "CI_CONTRACT_MUTATION: change survived: ${token}")
    endif()
  endforeach()
  string(REPLACE "FetchFcgi2Entry.cmake" "MOVED_FETCH_ENTRY" moved "${workflow}")
  string(APPEND moved "\n# inert token outside job: FetchFcgi2Entry.cmake\n")
  set(subject "${CMAKE_CURRENT_BINARY_DIR}/ci-contract-inert-move.yml")
  file(WRITE "${subject}" "${moved}")
  execute_process(COMMAND "${CMAKE_COMMAND}" "-DWORKFLOW=${subject}"
      -DMUTATION_MODE=ON -P "${CMAKE_CURRENT_LIST_FILE}"
    RESULT_VARIABLE result OUTPUT_QUIET ERROR_QUIET)
  file(REMOVE "${subject}")
  if(result EQUAL 0)
    message(FATAL_ERROR "CI_CONTRACT_MUTATION: inert cross-job move survived")
  endif()

  string(FIND "${metrics_step}" "# PURE_FASTCGI_IMPORT_PARSER_BEGIN" parser_begin)
  string(FIND "${metrics_step}" "# PURE_FASTCGI_IMPORT_PARSER_END" parser_end)
  if(parser_begin EQUAL -1 OR parser_end EQUAL -1 OR parser_end LESS parser_begin)
    message(FATAL_ERROR "CI_CONTRACT_IMPORT_PARSER: parser markers are malformed")
  endif()
  string(LENGTH "# PURE_FASTCGI_IMPORT_PARSER_END" end_marker_length)
  math(EXPR parser_length "${parser_end} - ${parser_begin} + ${end_marker_length}")
  string(SUBSTRING "${metrics_step}" ${parser_begin} ${parser_length} parser_script)
  set(parser_fixture "${CMAKE_CURRENT_BINARY_DIR}/ci-import-parser-fixture.ps1")
  file(WRITE "${parser_fixture}" "${parser_script}\n")
  file(APPEND "${parser_fixture}" [=[
$header = "File: fixture.dll`r`nFormat: COFF-x86-64`r`nArch: x86_64`r`nAddressSize: 64bit`r`n"
$callerExitCode = 0
if ($callerExitCode -ne 0) { throw 'caller readobj failed' }
$zero = @(Get-CoffImportNames -Readobj $header -Pe 'transitive-zero.dll')
if ($zero.Count -ne 0) { throw 'caller-equivalent valid transitive zero-import PE was not empty' }
$valid = $header + "Import {`n  Name: runtime.dll`n  ImportLookupTableRVA: 0x1`n  ImportAddressTableRVA: 0x2`n  Symbol: Name: not-a-dll (0)`n}`n"
$names = @(Get-CoffImportNames -Readobj $valid -Pe 'valid.dll')
if ($names.Count -ne 1 -or $names[0] -cne 'runtime.dll') {
  throw 'valid Import Name was not parsed exactly'
}
foreach ($malformed in @(
    ($header + "Import {`n  Name: runtime.dll`n"),
    ($header + "Import {`n  Name: one.dll`n  Name: two.dll`n}`n"),
    ($header + "Import [`n  Name: runtime.dll`n]`n"),
    ($header + "Format: COFF-x86-64`r`n"),
    ("File: fixture.dll`r`nArch: x86_64`r`nFormat: COFF-x86-64`r`nAddressSize: 64bit`r`n"),
    ($header + "Import {`n  Symbol: before-name (0)`n  Name: late.dll`n}`n"))) {
  $rejected = $false
  try { $null = @(Get-CoffImportNames -Readobj $malformed -Pe 'transitive.dll') }
  catch { $rejected = $true }
  if (-not $rejected) { throw 'malformed transitive import output was accepted' }
}
]=])
  find_program(contract_powershell NAMES pwsh.exe powershell.exe REQUIRED)
  execute_process(COMMAND "${contract_powershell}" -NoProfile -NonInteractive
      -ExecutionPolicy Bypass -File "${parser_fixture}"
    RESULT_VARIABLE parser_result OUTPUT_VARIABLE parser_out ERROR_VARIABLE parser_err)
  file(REMOVE "${parser_fixture}")
  if(NOT parser_result EQUAL 0)
    message(FATAL_ERROR
      "CI_CONTRACT_IMPORT_PARSER: behavioral fixture failed\n${parser_out}\n${parser_err}")
  endif()
endif()
