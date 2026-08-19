cmake_minimum_required(VERSION 3.25)

if(NOT DEFINED WORKFLOW OR NOT EXISTS "${WORKFLOW}")
  message(FATAL_ERROR
    "CI_CONTRACT_INPUT: WORKFLOW must name an existing workflow")
endif()

file(READ "${WORKFLOW}" workflow)
string(REPLACE "\r\n" "\n" workflow "${workflow}")
string(REPLACE "\r" "\n" workflow "${workflow}")
if(workflow MATCHES "\t")
  message(FATAL_ERROR "CI_CONTRACT_SYNTAX: tabs are forbidden")
endif()

# This is an indentation-aware parser for the workflow subset used below, not
# a general YAML semantic parser. Protect semicolons before representing the
# source as a CMake list of lines.
set(semicolon_placeholder "__PURE_BONJOUR_CI_SEMICOLON__")
if(workflow MATCHES "${semicolon_placeholder}")
  message(FATAL_ERROR "CI_CONTRACT_SYNTAX: reserved parser token is present")
endif()
string(REPLACE ";" "${semicolon_placeholder}" protected "${workflow}")
string(REPLACE "\n" ";" workflow_lines "${protected}")

set(line_number 0)
foreach(protected_line IN LISTS workflow_lines)
  math(EXPR line_number "${line_number} + 1")
  string(REPLACE "${semicolon_placeholder}" ";" line "${protected_line}")
  if(line STREQUAL "" OR line MATCHES "^ *#")
    continue()
  endif()
  if(line MATCHES " #")
    message(FATAL_ERROR
      "CI_CONTRACT_SYNTAX: inline comments are forbidden at line ${line_number}")
  endif()
  string(REGEX MATCH "^ *" leading "${line}")
  string(LENGTH "${leading}" indentation)
  math(EXPR odd "${indentation} % 2")
  if(odd)
    message(FATAL_ERROR
      "CI_CONTRACT_SYNTAX: line ${line_number} has odd indentation")
  endif()
endforeach()

function(ci_line index output)
  list(GET workflow_lines ${index} protected_line)
  string(REPLACE "${semicolon_placeholder}" ";" line "${protected_line}")
  set(${output} "${line}" PARENT_SCOPE)
endfunction()

function(ci_indent line output)
  string(REGEX MATCH "^ *" leading "${line}")
  string(LENGTH "${leading}" indentation)
  set(${output} "${indentation}" PARENT_SCOPE)
endfunction()

function(ci_find_unique_line expected begin finish category output)
  set(found -1)
  set(count 0)
  set(index ${begin})
  while(index LESS finish)
    ci_line(${index} line)
    if(line STREQUAL "${expected}")
      set(found ${index})
      math(EXPR count "${count} + 1")
    endif()
    math(EXPR index "${index} + 1")
  endwhile()
  if(NOT count EQUAL 1)
    message(FATAL_ERROR
      "CI_CONTRACT_${category}: expected one [${expected}], found ${count}")
  endif()
  set(${output} ${found} PARENT_SCOPE)
endfunction()

function(ci_block_end start parent_indent limit output)
  math(EXPR index "${start} + 1")
  set(finish ${limit})
  while(index LESS limit)
    ci_line(${index} line)
    if(NOT line STREQUAL "" AND NOT line MATCHES "^ *#")
      ci_indent("${line}" indentation)
      if(indentation LESS_EQUAL parent_indent)
        set(finish ${index})
        break()
      endif()
    endif()
    math(EXPR index "${index} + 1")
  endwhile()
  set(${output} ${finish} PARENT_SCOPE)
endfunction()

function(ci_block_code begin finish output)
  set(code "")
  set(index ${begin})
  while(index LESS finish)
    ci_line(${index} line)
    if(NOT line MATCHES "^ *#")
      string(APPEND code "${line}\n")
    endif()
    math(EXPR index "${index} + 1")
  endwhile()
  set(${output} "${code}" PARENT_SCOPE)
endfunction()

function(ci_require_text scope category)
  foreach(required IN LISTS ARGN)
    string(FIND "${scope}" "${required}" position)
    if(position EQUAL -1)
      message(FATAL_ERROR "CI_CONTRACT_${category}: missing ${required}")
    endif()
  endforeach()
endfunction()

function(ci_count_text scope needle output)
  set(rest "${scope}")
  set(count 0)
  string(LENGTH "${needle}" needle_length)
  while(TRUE)
    string(FIND "${rest}" "${needle}" position)
    if(position EQUAL -1)
      break()
    endif()
    math(EXPR after "${position} + ${needle_length}")
    string(SUBSTRING "${rest}" ${after} -1 rest)
    math(EXPR count "${count} + 1")
  endwhile()
  set(${output} ${count} PARENT_SCOPE)
endfunction()

list(LENGTH workflow_lines workflow_line_count)
ci_find_unique_line("jobs:" 0 ${workflow_line_count} STRUCTURE jobs_index)
ci_find_unique_line("  windows-pure-bonjour:" ${jobs_index}
  ${workflow_line_count} JOB job_index)
ci_block_end(${job_index} 2 ${workflow_line_count} job_end)
ci_block_code(${job_index} ${job_end} job_code)

function(ci_validate_trigger trigger)
  ci_find_unique_line("  ${trigger}:" 0 ${jobs_index} TRIGGER trigger_index)
  ci_block_end(${trigger_index} 2 ${jobs_index} trigger_end)
  ci_find_unique_line("    paths:" ${trigger_index} ${trigger_end}
    TRIGGER paths_index)
  ci_block_end(${paths_index} 4 ${trigger_end} paths_end)
  set(actual)
  math(EXPR index "${paths_index} + 1")
  while(index LESS paths_end)
    ci_line(${index} line)
    if(NOT line STREQUAL "" AND NOT line MATCHES "^ *#")
      if(NOT line MATCHES "^      - \"([^\"]+)\"$")
        message(FATAL_ERROR
          "CI_CONTRACT_TRIGGER: malformed ${trigger}.paths entry: ${line}")
      endif()
      list(APPEND actual "${CMAKE_MATCH_1}")
    endif()
    math(EXPR index "${index} + 1")
  endwhile()
  set(expected
    ".github/workflows/non-linux-release-validation.yml"
    "docs/superpowers/plans/2026-08-18-windows-pure-bonjour.md"
    "docs/superpowers/specs/2026-08-18-windows-pure-bonjour-design.md"
    "pure/**"
    "pure-bonjour/**"
    "pure/todo/TODO-45-windows-pure-bonjour.md")
  list(SORT actual)
  list(SORT expected)
  if(NOT actual STREQUAL expected)
    message(FATAL_ERROR
      "CI_CONTRACT_TRIGGER: ${trigger}.paths must be the exact set; "
      "actual=[${actual}]")
  endif()
endfunction()

ci_validate_trigger(push)
ci_validate_trigger(pull_request)

ci_find_unique_line("    name: Windows PureBonjour package" ${job_index}
  ${job_end} JOB job_name_index)
ci_find_unique_line("    runs-on: windows-2025" ${job_index}
  ${job_end} JOB runner_index)
ci_find_unique_line("        working-directory: source with spaces" ${job_index}
  ${job_end} JOB working_directory_index)
ci_find_unique_line("    steps:" ${job_index} ${job_end} STRUCTURE steps_index)

# Persistent workflow/job PATH mutation is forbidden. Individual run/uses
# steps set only their own process environment.
string(TOLOWER "${job_code}" job_code_lower)
if(job_code_lower MATCHES "github_path")
  message(FATAL_ERROR "CI_CONTRACT_PATH: GITHUB_PATH persistence is forbidden")
endif()
if(job_code_lower MATCHES "\"path=" OR job_code_lower MATCHES "'path=")
  message(FATAL_ERROR
    "CI_CONTRACT_PATH: GITHUB_ENV PATH persistence is forbidden")
endif()
set(index ${job_index})
while(index LESS steps_index)
  ci_line(${index} line)
  if(line MATCHES "^      (PATH|Path|path):")
    message(FATAL_ERROR "CI_CONTRACT_PATH: job-level PATH is forbidden")
  endif()
  math(EXPR index "${index} + 1")
endwhile()

function(ci_extract_step title start_output end_output code_output)
  ci_find_unique_line("      - name: ${title}" ${steps_index} ${job_end}
    STEP step_start)
  ci_block_end(${step_start} 6 ${job_end} step_end)
  ci_block_code(${step_start} ${step_end} step_code)
  set(${start_output} ${step_start} PARENT_SCOPE)
  set(${end_output} ${step_end} PARENT_SCOPE)
  set(${code_output} "${step_code}" PARENT_SCOPE)
endfunction()

function(ci_extract_run step_start step_end category output)
  ci_find_unique_line("        run: |" ${step_start} ${step_end}
    ${category} run_index)
  ci_block_code(${run_index} ${step_end} run_code)
  set(${output} "${run_code}" PARENT_SCOPE)
endfunction()

ci_extract_step("Check out source in a path containing spaces"
  checkout_start checkout_end checkout_code)
ci_find_unique_line("        uses: actions/checkout@v4" ${checkout_start}
  ${checkout_end} CHECKOUT checkout_uses)
ci_find_unique_line("          path: source with spaces" ${checkout_start}
  ${checkout_end} CHECKOUT checkout_path)

ci_extract_step("Install the exact CLANG64 prerequisites"
  prerequisites_start prerequisites_end prerequisites_code)
foreach(required IN ITEMS
    "        uses: msys2/setup-msys2@v2"
    "          msystem: CLANG64"
    "          update: true"
    "          release: false")
  ci_find_unique_line("${required}" ${prerequisites_start} ${prerequisites_end}
    PREREQUISITES required_index)
endforeach()
ci_find_unique_line("          install: >-" ${prerequisites_start}
  ${prerequisites_end} PREREQUISITES install_index)
set(actual_packages)
math(EXPR index "${install_index} + 1")
while(index LESS prerequisites_end)
  ci_line(${index} line)
  if(NOT line STREQUAL "" AND NOT line MATCHES "^ *#")
    ci_indent("${line}" indentation)
    if(indentation LESS_EQUAL 10)
      break()
    endif()
    if(NOT line MATCHES "^            ([A-Za-z0-9.+_-]+)$")
      message(FATAL_ERROR
        "CI_CONTRACT_PREREQUISITES: malformed install token: ${line}")
    endif()
    list(APPEND actual_packages "${CMAKE_MATCH_1}")
  endif()
  math(EXPR index "${index} + 1")
endwhile()
set(expected_packages
  bison
  diffutils
  flex
  mingw-w64-clang-x86_64-clang
  mingw-w64-clang-x86_64-cmake
  mingw-w64-clang-x86_64-gmp
  mingw-w64-clang-x86_64-libiconv
  mingw-w64-clang-x86_64-llvm
  mingw-w64-clang-x86_64-mpfr
  mingw-w64-clang-x86_64-ninja
  mingw-w64-clang-x86_64-pcre
  mingw-w64-clang-x86_64-pkgconf
  mingw-w64-clang-x86_64-readline)
list(SORT actual_packages)
list(SORT expected_packages)
if(NOT actual_packages STREQUAL expected_packages)
  message(FATAL_ERROR
    "CI_CONTRACT_PREREQUISITES: install must be the exact package set; "
    "actual=[${actual_packages}]")
endif()

set(toolchain_path
  "$env:Path = \"C:/msys64/clang64/bin;C:/msys64/usr/bin;$env:Path\"")
set(safe_path
  "$env:Path = \"$purePrefix/bin;$env:SystemRoot/System32/WindowsPowerShell/v1.0;$env:SystemRoot/System32;$env:SystemRoot\"")

ci_extract_step("Verify the selected CLANG64 tools"
  tools_start tools_end tools_code)
ci_extract_run(${tools_start} ${tools_end} TOOLS tools_run)
ci_require_text("${tools_run}" TOOLS
  "${toolchain_path}" "C:/msys64/clang64/bin/clang.exe"
  "C:/msys64/usr/bin/bison.exe" "C:/msys64/usr/bin/flex.exe")

ci_extract_step("Build and install the matching Windows Pure SDK"
  pure_start pure_end pure_code)
ci_extract_run(${pure_start} ${pure_end} PURE pure_run)
ci_require_text("${pure_run}" PURE
  "${toolchain_path}" "-S pure" "-G Ninja"
  "-DCMAKE_MAKE_PROGRAM=C:/msys64/clang64/bin/ninja.exe"
  "C:/msys64/clang64/bin/clang.exe"
  "C:/msys64/clang64/bin/clang++.exe"
  "-DLLVM_DIR=C:/msys64/clang64/lib/cmake/llvm"
  "& $env:CMAKE_EXE --build $pureBuild --parallel 1"
  "& $env:CMAKE_EXE --build $pureBuild --target install --parallel 1"
  "PURE_PREFIX=")

ci_extract_step("Configure and build PureBonjour"
  build_start build_end build_code)
ci_extract_run(${build_start} ${build_end} BUILD build_run)
ci_require_text("${build_run}" BUILD
  "${toolchain_path}" "-S pure-bonjour" "-G Ninja"
  "-DCMAKE_MAKE_PROGRAM=C:/msys64/clang64/bin/ninja.exe"
  "-DPURE_PREFIX=$purePrefix"
  "-DPKG_CONFIG_EXECUTABLE=C:/msys64/clang64/bin/pkgconf.exe"
  "& $env:CMAKE_EXE --build $build --parallel 1")
if(build_run MATCHES "--target")
  message(FATAL_ERROR
    "CI_CONTRACT_BUILD: PureBonjour build must build all targets")
endif()
ci_count_text("${build_run}" "--build $build" build_count)
if(NOT build_count EQUAL 1)
  message(FATAL_ERROR
    "CI_CONTRACT_BUILD: expected one exact PureBonjour build, found ${build_count}")
endif()

ci_extract_step("Run the complete PureBonjour test label"
  test_start test_end test_code)
ci_extract_run(${test_start} ${test_end} TEST test_run)
ci_require_text("${test_run}" TEST
  "$purePrefix = [IO.Path]::GetFullPath($env:PURE_PREFIX)"
  "${safe_path}" "MSYS2 path survived sanitization"
  "C:/msys64/clang64/bin/ctest.exe" "-L bonjour"
  "--output-on-failure" "--no-tests=error")

ci_extract_step("Install only PureBonjour and verify sanitized runtime"
  verify_start verify_end verify_code)
ci_extract_run(${verify_start} ${verify_end} VERIFY verify_run)
ci_require_text("${verify_run}" VERIFY
  "--component PureBonjour" "Remove-Item Env:PURELIB"
  "${safe_path}" "MSYS2 path survived sanitization"
  "VerifyInstalledPackage.cmake" "-DSTAGE_PREFIX=$stage"
  "-DSOURCE_PREFIX=$source" "-DBUILD_PREFIX=$build"
  "-DPURE_PREFIX=$purePrefix")

# Exactly one cmake --install is allowed in the entire job, and it is the
# component-bounded PureBonjour install in the verifier step.
ci_count_text("${job_code}" "--install" install_count)
ci_count_text("${job_code}" "--component PureBonjour" component_count)
ci_count_text("${verify_run}" "--install $build --prefix $stage" verify_install_count)
if(NOT install_count EQUAL 1 OR NOT component_count EQUAL 1 OR
    NOT verify_install_count EQUAL 1)
  message(FATAL_ERROR
    "CI_CONTRACT_INSTALL: expected one component-only install; "
    "install=${install_count} component=${component_count} "
    "verify=${verify_install_count}")
endif()

ci_extract_step("Create the deterministic PureBonjour ZIP twice"
  zip_start zip_end zip_code)
ci_extract_run(${zip_start} ${zip_end} ZIP zip_run)
ci_require_text("${zip_run}" ZIP
  "$purePrefix = [IO.Path]::GetFullPath($env:PURE_PREFIX)"
  "${safe_path}" "MSYS2 path survived sanitization"
  "windows-pure-bonjour-first.zip" "windows-pure-bonjour-second.zip"
  "[Array]::Sort($relativeFiles, [StringComparer]::Ordinal)"
  ".Replace('\\', '/')" "2000-01-01T00:00:00+00:00"
  "ExternalAttributes = 0" "Get-FileHash -LiteralPath $first"
  "Get-FileHash -LiteralPath $second" "firstHash -cne $secondHash"
  "deterministic ZIP hashes differ" "Copy-Item -LiteralPath $first -Destination $archive"
  "$env:GITHUB_STEP_SUMMARY")
if(zip_run MATCHES "windows-pure-bonjour-summary\\.txt")
  message(FATAL_ERROR "CI_CONTRACT_ZIP: summary must not be an upload file")
endif()

foreach(runtime_run IN ITEMS test_run verify_run zip_run)
  ci_count_text("${${runtime_run}}" "${safe_path}" safe_path_count)
  ci_count_text("${${runtime_run}}" "$env:Path =" path_assignment_count)
  if(NOT safe_path_count EQUAL 1 OR NOT path_assignment_count EQUAL 1)
    message(FATAL_ERROR
      "CI_CONTRACT_PATH: ${runtime_run} must set exactly one sanitized PATH")
  endif()
endforeach()
foreach(build_run_variable IN ITEMS pure_run build_run)
  ci_count_text("${${build_run_variable}}" "${toolchain_path}"
    toolchain_path_count)
  if(NOT toolchain_path_count EQUAL 1)
    message(FATAL_ERROR
      "CI_CONTRACT_PATH: ${build_run_variable} must set one local toolchain PATH")
  endif()
endforeach()

ci_extract_step("Upload the PureBonjour package"
  upload_start upload_end upload_code)
foreach(required IN ITEMS
    "        uses: actions/upload-artifact@v4"
    "          name: windows-pure-bonjour"
    "          path: source with spaces/build/pure-bonjour-artifacts/windows-pure-bonjour.zip"
    "          if-no-files-found: error"
    "          PATH: \${{ env.PURE_PREFIX }}/bin;C:/Windows/System32/WindowsPowerShell/v1.0;C:/Windows/System32;C:/Windows")
  ci_find_unique_line("${required}" ${upload_start} ${upload_end}
    UPLOAD upload_property)
endforeach()
ci_count_text("${upload_code}" ".zip" upload_zip_count)
ci_count_text("${upload_code}" "          path:" upload_path_count)
ci_count_text("${upload_code}" "          PATH:" upload_env_path_count)
if(NOT upload_zip_count EQUAL 1 OR NOT upload_path_count EQUAL 1 OR
    NOT upload_env_path_count EQUAL 1 OR upload_code MATCHES "summary\\.txt")
  message(FATAL_ERROR
    "CI_CONTRACT_UPLOAD: upload must contain exactly the final ZIP")
endif()

if(NOT MUTATION_MODE)
  function(ci_expect_rejected name subject category)
    set(path "${CMAKE_CURRENT_BINARY_DIR}/ci-contract-${name}.yml")
    file(WRITE "${path}" "${subject}")
    execute_process(
      COMMAND "${CMAKE_COMMAND}" "-DWORKFLOW=${path}" -DMUTATION_MODE=ON
        -P "${CMAKE_CURRENT_LIST_FILE}"
      RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
    file(REMOVE "${path}")
    if(result EQUAL 0 OR NOT "${output}${error}" MATCHES
        "CI_CONTRACT_${category}")
      message(FATAL_ERROR
        "CI_CONTRACT_MUTATION: ${name} was not rejected as ${category}; "
        "exit=${result} output=[${output}${error}]")
    endif()
  endfunction()

  string(REPLACE "    name: Windows PureBonjour package"
    "    # name: Windows PureBonjour package" mutated "${workflow}")
  ci_expect_rejected(comment-cannot-satisfy-job "${mutated}" JOB)

  string(REPLACE "            -L bonjour --output-on-failure --no-tests=error"
    "            --output-on-failure --no-tests=error\n          # -L bonjour"
    mutated "${workflow}")
  ci_expect_rejected(comment-cannot-satisfy-test "${mutated}" TEST)

  string(REPLACE "            -L bonjour --output-on-failure --no-tests=error"
    "            --output-on-failure --no-tests=error" mutated "${workflow}")
  string(REPLACE "          $artifactDirectory ="
    "          Write-Host '-L bonjour'\n          $artifactDirectory ="
    mutated "${mutated}")
  ci_expect_rejected(other-step-cannot-satisfy-test "${mutated}" TEST)

  string(REPLACE
    "  push:\n    branches:\n      - master\n      - \"todo/**\"\n    paths:\n      - \"pure/**\""
    "  push:\n    branches:\n      - master\n      - \"todo/**\"\n    paths:"
    mutated "${workflow}")
  ci_expect_rejected(push-path-missing "${mutated}" TRIGGER)

  string(REPLACE
    "  pull_request:\n    branches:\n      - master\n    paths:\n      - \"pure/**\""
    "  pull_request:\n    branches:\n      - master\n    paths:"
    mutated "${workflow}")
  ci_expect_rejected(pull-path-missing "${mutated}" TRIGGER)

  string(REPLACE "      - \"pure-bonjour/**\""
    "      - \"pure-bonjour/**\"\n      - \"unrelated/**\""
    mutated "${workflow}")
  ci_expect_rejected(extra-trigger-path "${mutated}" TRIGGER)

  string(REPLACE "  windows-pure-bonjour:"
    "   windows-pure-bonjour:" mutated "${workflow}")
  ci_expect_rejected(odd-job-indentation "${mutated}" SYNTAX)

  string(REPLACE "            bison"
    "            bison\n            forbidden-extra-package"
    mutated "${workflow}")
  ci_expect_rejected(extra-prerequisite "${mutated}" PREREQUISITES)

  string(REPLACE "            mingw-w64-clang-x86_64-libiconv\n"
    "" mutated "${workflow}")
  ci_expect_rejected(missing-prerequisite "${mutated}" PREREQUISITES)

  string(REPLACE "& $env:CMAKE_EXE --build $build --parallel 1"
    "& $env:CMAKE_EXE --build $build --target pure-bonjour --parallel 1"
    mutated "${workflow}")
  ci_expect_rejected(targeted-component-build "${mutated}" BUILD)

  string(REPLACE "& $env:CMAKE_EXE --build $build --parallel 1"
    "& $env:CMAKE_EXE --build $build --parallel 1\n          & $env:CMAKE_EXE --build $build --parallel 1"
    mutated "${workflow}")
  ci_expect_rejected(second-component-build "${mutated}" BUILD)

  string(REPLACE "          if ($LASTEXITCODE -ne 0) { throw \"PureBonjour build failed\" }"
    "          & $env:CMAKE_EXE --install $build\n          if ($LASTEXITCODE -ne 0) { throw \"PureBonjour build failed\" }"
    mutated "${workflow}")
  ci_expect_rejected(unrestricted-install "${mutated}" INSTALL)

  string(REPLACE "            --component PureBonjour" ""
    mutated "${workflow}")
  ci_expect_rejected(missing-component "${mutated}" VERIFY)

  string(REPLACE "          Remove-Item Env:PURELIB"
    "          & $env:CMAKE_EXE --install $build --prefix $stage --component PureBonjour\n          Remove-Item Env:PURELIB"
    mutated "${workflow}")
  ci_expect_rejected(second-component-install "${mutated}" INSTALL)

  string(REPLACE "          $tools = [ordered]@{"
    "          'C:/msys64/clang64/bin' | Out-File $env:GITHUB_PATH -Append\n          $tools = [ordered]@{"
    mutated "${workflow}")
  ci_expect_rejected(persistent-github-path "${mutated}" PATH)

  string(REPLACE "          $tools = [ordered]@{"
    "          \"PATH=C:/msys64/clang64/bin\" | Out-File $env:GITHUB_ENV -Append\n          $tools = [ordered]@{"
    mutated "${workflow}")
  ci_expect_rejected(persistent-github-env-path "${mutated}" PATH)

  string(REPLACE "      CTEST_EXE: C:/msys64/clang64/bin/ctest.exe"
    "      CTEST_EXE: C:/msys64/clang64/bin/ctest.exe\n      PATH: C:/msys64/clang64/bin"
    mutated "${workflow}")
  ci_expect_rejected(job-level-path "${mutated}" PATH)

  string(REPLACE "${safe_path}" ""
    mutated "${workflow}")
  ci_expect_rejected(missing-runtime-sanitization "${mutated}" TEST)

  string(REPLACE "${safe_path}"
    "${safe_path}\n          $env:Path = \"C:/msys64/clang64/bin;$env:Path\""
    mutated "${workflow}")
  ci_expect_rejected(second-runtime-path "${mutated}" PATH)

  string(REPLACE
    "          path: source with spaces/build/pure-bonjour-artifacts/windows-pure-bonjour.zip"
    "          path: |\n            source with spaces/build/pure-bonjour-artifacts/windows-pure-bonjour.zip\n            source with spaces/build/pure-bonjour-artifacts/extra.zip"
    mutated "${workflow}")
  ci_expect_rejected(extra-upload-zip "${mutated}" UPLOAD)

  string(REPLACE
    "          path: source with spaces/build/pure-bonjour-artifacts/windows-pure-bonjour.zip"
    "          path: source with spaces/build/pure-bonjour-artifacts/windows-pure-bonjour-summary.txt"
    mutated "${workflow}")
  ci_expect_rejected(summary-instead-of-zip "${mutated}" UPLOAD)

  string(REPLACE
    "          PATH: \${{ env.PURE_PREFIX }}/bin;C:/Windows/System32/WindowsPowerShell/v1.0;C:/Windows/System32;C:/Windows"
    "          PATH: C:/msys64/clang64/bin"
    mutated "${workflow}")
  ci_expect_rejected(unsafe-upload-path "${mutated}" UPLOAD)

  string(REPLACE
    "          PATH: \${{ env.PURE_PREFIX }}/bin;C:/Windows/System32/WindowsPowerShell/v1.0;C:/Windows/System32;C:/Windows"
    "          PATH: \${{ env.PURE_PREFIX }}/bin;C:/Windows/System32/WindowsPowerShell/v1.0;C:/Windows/System32;C:/Windows\n          PATH: C:/Windows"
    mutated "${workflow}")
  ci_expect_rejected(duplicate-upload-path "${mutated}" UPLOAD)

  string(REPLACE "      - name: Run the complete PureBonjour test label"
    "       - name: Run the complete PureBonjour test label"
    mutated "${workflow}")
  ci_expect_rejected(odd-step-indentation "${mutated}" SYNTAX)
endif()
