cmake_minimum_required(VERSION 3.25)

if(NOT DEFINED WORKFLOW OR NOT EXISTS "${WORKFLOW}")
  message(FATAL_ERROR
    "CI_CONTRACT_INPUT: WORKFLOW must name an existing workflow")
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

string(FIND "${workflow}" "\njobs:\n" jobs_position)
if(jobs_position EQUAL -1)
  message(FATAL_ERROR "CI_CONTRACT_STRUCTURE: jobs mapping is missing")
endif()
string(SUBSTRING "${workflow}" 0 ${jobs_position} workflow_header)

string(FIND "${workflow}" "\n  windows-pure-bonjour:\n" job_position)
if(job_position EQUAL -1)
  message(FATAL_ERROR
    "CI_CONTRACT_JOB: windows-pure-bonjour job is missing")
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
require_text("${workflow_header}" TRIGGER
  "pure-bonjour/**"
  "pure/todo/TODO-45-windows-pure-bonjour.md"
  "docs/superpowers/specs/2026-08-18-windows-pure-bonjour-design.md"
  "docs/superpowers/plans/2026-08-18-windows-pure-bonjour.md"
  ".github/workflows/non-linux-release-validation.yml")

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
  "name: Windows PureBonjour package"
  "runs-on: windows-2025"
  "working-directory: source with spaces")

extract_step("Check out source in a path containing spaces" checkout_step)
require_text("${checkout_step}" CHECKOUT
  "actions/checkout@v4" "path: source with spaces")

extract_step("Install the exact CLANG64 prerequisites" prerequisites_step)
require_text("${prerequisites_step}" PREREQUISITES
  "msys2/setup-msys2@v2"
  "msystem: CLANG64"
  "update: true"
  "release: false"
  "mingw-w64-clang-x86_64-clang"
  "mingw-w64-clang-x86_64-llvm"
  "mingw-w64-clang-x86_64-cmake"
  "mingw-w64-clang-x86_64-ninja"
  "mingw-w64-clang-x86_64-pkgconf"
  "mingw-w64-clang-x86_64-gmp"
  "mingw-w64-clang-x86_64-mpfr"
  "mingw-w64-clang-x86_64-readline"
  "mingw-w64-clang-x86_64-pcre"
  "mingw-w64-clang-x86_64-libiconv")
set(exact_prerequisite_block [=[
          install: >-
            bison
            flex
            diffutils
            mingw-w64-clang-x86_64-clang
            mingw-w64-clang-x86_64-llvm
            mingw-w64-clang-x86_64-cmake
            mingw-w64-clang-x86_64-ninja
            mingw-w64-clang-x86_64-pkgconf
            mingw-w64-clang-x86_64-gmp
            mingw-w64-clang-x86_64-mpfr
            mingw-w64-clang-x86_64-readline
            mingw-w64-clang-x86_64-pcre
            mingw-w64-clang-x86_64-libiconv
]=])
require_text("${prerequisites_step}" PREREQUISITES
  "${exact_prerequisite_block}")

extract_step("Verify the selected CLANG64 tools" tools_step)
require_text("${tools_step}" TOOLS
  "'C:/msys64/usr/bin'"
  "'C:/msys64/clang64/bin'"
  "$env:GITHUB_PATH"
  "$env:Path = \"C:/msys64/clang64/bin;C:/msys64/usr/bin;$env:Path\"")

extract_step("Build and install the matching Windows Pure SDK" pure_step)
require_text("${pure_step}" PURE
  "-S pure" "-G Ninja"
  "C:/msys64/clang64/bin/clang.exe"
  "C:/msys64/clang64/bin/clang++.exe"
  "-DLLVM_DIR=C:/msys64/clang64/lib/cmake/llvm"
  "--build $pureBuild --parallel 1"
  "--install $pureBuild"
  "PURE_PREFIX=")

extract_step("Configure and build PureBonjour" build_step)
require_text("${build_step}" BUILD
  "-S pure-bonjour" "-G Ninja"
  "-DPURE_PREFIX=$purePrefix"
  "-DPKG_CONFIG_EXECUTABLE=C:/msys64/clang64/bin/pkgconf.exe"
  "--build $build --parallel 1")

extract_step("Run the complete PureBonjour test label" test_step)
require_text("${test_step}" TEST
  "ctest.exe --test-dir" "-L bonjour" "--output-on-failure"
  "--no-tests=error")

extract_step("Install only PureBonjour and verify sanitized runtime" verify_step)
require_text("${verify_step}" VERIFY
  "--component PureBonjour"
  "Remove-Item Env:PURELIB"
  "System32/WindowsPowerShell/v1.0"
  "MSYS2 path survived sanitization"
  "VerifyInstalledPackage.cmake"
  "-DSTAGE_PREFIX=$stage"
  "-DSOURCE_PREFIX=$source"
  "-DBUILD_PREFIX=$build"
  "-DPURE_PREFIX=$purePrefix")

extract_step("Create the deterministic PureBonjour ZIP twice" zip_step)
require_text("${zip_step}" ZIP
  "windows-pure-bonjour-first.zip"
  "windows-pure-bonjour-second.zip"
  "[Array]::Sort($relativeFiles, [StringComparer]::Ordinal)"
  ".Replace('\\', '/')"
  "2000-01-01T00:00:00+00:00"
  "ExternalAttributes = 0"
  "Get-FileHash -LiteralPath $first"
  "Get-FileHash -LiteralPath $second"
  "firstHash -cne $secondHash"
  "deterministic ZIP hashes differ"
  "windows-pure-bonjour-summary.txt")

extract_step("Upload the PureBonjour package" upload_step)
require_text("${upload_step}" UPLOAD
  "actions/upload-artifact@v4"
  "name: windows-pure-bonjour"
  "source with spaces/build/pure-bonjour-artifacts/windows-pure-bonjour.zip"
  "source with spaces/build/pure-bonjour-artifacts/windows-pure-bonjour-summary.txt"
  "if-no-files-found: error")

if(NOT MUTATION_MODE)
  set(mutation_tokens
    "pure-bonjour/**"
    "pure/todo/TODO-45-windows-pure-bonjour.md"
    "docs/superpowers/specs/2026-08-18-windows-pure-bonjour-design.md"
    "docs/superpowers/plans/2026-08-18-windows-pure-bonjour.md"
    "name: Windows PureBonjour package"
    "working-directory: source with spaces"
    "path: source with spaces"
    "msys2/setup-msys2@v2"
    "            bison\n            flex\n            diffutils"
    "$env:GITHUB_PATH"
    "mingw-w64-clang-x86_64-libiconv"
    "-DPURE_PREFIX=$purePrefix"
    "-L bonjour"
    "--component PureBonjour"
    "Remove-Item Env:PURELIB"
    "VerifyInstalledPackage.cmake"
    "[Array]::Sort($relativeFiles, [StringComparer]::Ordinal)"
    "2000-01-01T00:00:00+00:00"
    "ExternalAttributes = 0"
    "firstHash -cne $secondHash"
    "actions/upload-artifact@v4"
    "name: windows-pure-bonjour"
    "source with spaces/build/pure-bonjour-artifacts/windows-pure-bonjour-summary.txt")
  set(index 0)
  foreach(token IN LISTS mutation_tokens)
    math(EXPR index "${index} + 1")
    string(REPLACE "${token}" "BROKEN_${index}" mutated "${workflow}")
    set(subject
      "${CMAKE_CURRENT_BINARY_DIR}/pure-bonjour-ci-mutation-${index}.yml")
    file(WRITE "${subject}" "${mutated}")
    execute_process(
      COMMAND "${CMAKE_COMMAND}" "-DWORKFLOW=${subject}"
        -DMUTATION_MODE=ON -P "${CMAKE_CURRENT_LIST_FILE}"
      RESULT_VARIABLE result OUTPUT_QUIET ERROR_QUIET)
    file(REMOVE "${subject}")
    if(result EQUAL 0)
      message(FATAL_ERROR
        "CI_CONTRACT_MUTATION: change survived: ${token}")
    endif()
  endforeach()
endif()
