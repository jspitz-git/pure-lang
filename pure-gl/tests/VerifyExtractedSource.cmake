cmake_minimum_required(VERSION 3.25)
include("${ARCHIVE_AUTHORITY}")
include("${extracted}/tests/AuditHelpers.cmake")
# An accidental checkout include must fail while the isolation owner is active.
file(WRITE "${work}/original-source-probe.cmake" "file(READ [==[${SOURCE_DIR}/CMakeLists.txt]==] original)\n")
execute_process(COMMAND "${CMAKE_COMMAND}" -P "${work}/original-source-probe.cmake"
  RESULT_VARIABLE source_rc OUTPUT_VARIABLE source_out ERROR_VARIABLE source_err)
if(source_rc EQUAL 0)
  message(FATAL_ERROR "Original checkout remains readable during extracted verification")
endif()
execute_process(COMMAND "${BINARY_DIR}/pure-gl-install-guard.exe" --check-tree "${extracted}"
  RESULT_VARIABLE helper_rc OUTPUT_VARIABLE helper_out ERROR_VARIABLE helper_err)
if(helper_rc EQUAL 0)
  message(FATAL_ERROR "Original build helper remains executable during extracted verification")
endif()
message(STATUS "SOURCE_DIST_ORIGINAL_DEPENDENCY_REJECT_OK")
function(validate_archive_types candidate output)
  set(${output} "" PARENT_SCOPE)
  execute_process(COMMAND "${CMAKE_COMMAND}" -E tar tvf "${candidate}"
    RESULT_VARIABLE rc OUTPUT_VARIABLE typed_entries ERROR_VARIABLE err)
  if(NOT rc EQUAL 0)
    set(${output} "archive listing failed: ${err}" PARENT_SCOPE)
    return()
  endif()
  string(REPLACE "\r" "" typed_entries "${typed_entries}")
  string(REPLACE "\n" ";" typed_entries "${typed_entries}")
  foreach(entry IN LISTS typed_entries)
    if(NOT entry STREQUAL "" AND NOT entry MATCHES "^[-d][rwxstST-]+ ")
      set(${output} "non-regular/symlink entry: ${entry}" PARENT_SCOPE)
      return()
    endif()
  endforeach()
endfunction()
function(validate_extracted output)
  set(${output} "" PARENT_SCOPE)
  execute_process(COMMAND "${PURE_GL_WINDOWS_SYSTEM_DIRECTORY}/WindowsPowerShell/v1.0/powershell.exe"
    -NoProfile -NonInteractive -File "${extracted}/tests/IsolateSource.ps1" -CheckTree "${extracted}"
    RESULT_VARIABLE rc OUTPUT_QUIET ERROR_VARIABLE err)
  if(NOT rc EQUAL 0)
    set(${output} "non-regular/reparse extracted tree: ${err}" PARENT_SCOPE)
    return()
  endif()
  file(GLOB_RECURSE actual_files LIST_DIRECTORIES FALSE RELATIVE "${extracted}" "${extracted}/*")
  list(SORT actual_files)
  if(NOT actual_files STREQUAL expected_files)
    set(${output} "exact extracted file inventory mismatch" PARENT_SCOPE)
    return()
  endif()
  foreach(path IN LISTS expected_files)
    if(IS_DIRECTORY "${extracted}/${path}" OR IS_SYMLINK "${extracted}/${path}")
      set(${output} "non-regular file: ${path}" PARENT_SCOPE)
      return()
    endif()
    if(path STREQUAL README)
      file(READ "${extracted}/README" readme)
      string(REGEX MATCH "[A-Z][a-z]+ [0-9]+, [0-9][0-9][0-9][0-9]" date "${readme}")
      string(REPLACE "@version@" "0.9" expected_readme "${readme_template}")
      string(REPLACE "|today|" "${date}" expected_readme "${expected_readme}")
      if(date STREQUAL "" OR NOT readme STREQUAL expected_readme)
        set(${output} "README version/date substitution mismatch" PARENT_SCOPE)
        return()
      endif()
    else()
      file(SHA256 "${extracted}/${path}" hash)
      if(NOT hash STREQUAL "${source_hash_${path}}")
        set(${output} "stale or changed bytes: ${path}" PARENT_SCOPE)
        return()
      endif()
    endif()
  endforeach()
endfunction()
validate_extracted(problem)
if(problem)
  message(FATAL_ERROR "Extracted source validation failed: ${problem}")
endif()
# Prove the validator catches missing/extra inputs, changed generated C bytes,
# and links, then restore and revalidate before building the pristine release.
file(RENAME "${extracted}/GL.c" "${work}/GL.c.saved")
validate_extracted(problem)
if(NOT problem MATCHES "inventory mismatch")
  message(FATAL_ERROR "Missing archived wrapper escaped validation")
endif()
file(RENAME "${work}/GL.c.saved" "${extracted}/GL.c")
file(WRITE "${extracted}/unexpected.txt" "unexpected archive input\n")
validate_extracted(problem)
if(NOT problem MATCHES "inventory mismatch")
  message(FATAL_ERROR "Extra archived input escaped validation")
endif()
file(REMOVE "${extracted}/unexpected.txt")
file(COPY_FILE "${extracted}/GL.c" "${work}/GL.c.saved")
file(APPEND "${extracted}/GL.c" "\n/* stale generated wrapper */\n")
validate_extracted(problem)
if(NOT problem MATCHES "stale or changed bytes")
  message(FATAL_ERROR "Stale archived wrapper escaped validation")
endif()
file(COPY_FILE "${work}/GL.c.saved" "${extracted}/GL.c")
# A literal ustar symlink header needs no Windows symlink privilege. Reject it
# from the table of contents before extraction can create any link endpoint.
file(WRITE "${work}/archive-link-fixture.ps1" [=[
param([string]$Destination)
$ErrorActionPreference='Stop'
$bytes=New-Object byte[] 1536
function Field([int]$offset,[string]$text) {
 $part=[Text.Encoding]::ASCII.GetBytes($text)
 [Array]::Copy($part,0,$bytes,$offset,$part.Length)
}
Field 0 'pure-gl-0.9/GL.c'
Field 100 "0000777`0"
Field 108 "0000000`0"
Field 116 "0000000`0"
Field 124 "00000000000`0"
Field 136 "00000000000`0"
Field 148 '        '
Field 156 '2'
Field 157 'owned-target.c'
Field 257 "ustar`0"
Field 263 '00'
$sum=0; for($i=0;$i -lt 512;$i++) { $sum+=$bytes[$i] }
Field 148 ([Convert]::ToString($sum,8).PadLeft(6,'0')+"`0 ")
$file=New-Object IO.FileStream($Destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try { $file.Write($bytes,0,$bytes.Length) } finally { $file.Dispose() }
]=])
execute_process(COMMAND "${PURE_GL_WINDOWS_SYSTEM_DIRECTORY}/WindowsPowerShell/v1.0/powershell.exe"
  -NoProfile -NonInteractive -File "${work}/archive-link-fixture.ps1"
  -Destination "${work}/symlink.tar" COMMAND_ERROR_IS_FATAL ANY)
validate_archive_types("${work}/symlink.tar" problem)
if(NOT problem MATCHES "non-regular/symlink")
  message(FATAL_ERROR "Symlink archive entry escaped pre-extraction validation")
endif()
validate_extracted(problem)
if(problem)
  message(FATAL_ERROR "Pristine archive restoration failed: ${problem}")
endif()
message(STATUS "SOURCE_DIST_MUTATIONS_OK missing=1 extra=1 stale_generated=1 symlink=1")
# Keep this internally owned name short: downstream transaction fixtures add
# their own stage and private-sibling names within the Win32 path budget.
set(build "${work}/b")
set(configure "${CMAKE_COMMAND}" -S "${extracted}" -B "${build}" -G "${GENERATOR}"
  "-DCMAKE_MAKE_PROGRAM=${MAKE_PROGRAM}" "-DCMAKE_C_COMPILER=${C_COMPILER}"
  -DCMAKE_C_COMPILER_WORKS=1 -DCMAKE_C_ABI_COMPILED=1 -DCMAKE_BUILD_TYPE=Release
  -DPURE_GL_STRICT_AUDIT=ON -DBUILD_TESTING=ON)
foreach(name PKG_CONFIG_EXECUTABLE LLVM_READOBJ_EXECUTABLE LLVM_READOBJ_SHA256
    LLVM_STRINGS_EXECUTABLE LLVM_STRINGS_SHA256 GNU_MAKE_EXECUTABLE PURE_EXECUTABLE
    PURE_GL_PURE_PREFIX PURE_GL_CLANG64_PREFIX PURE_GL_WINDOWS_SYSTEM_DIRECTORY)
  list(APPEND configure "-D${name}=${${name}}")
endforeach()
set(ENV{PATH} "${PURE_GL_CLANG64_PREFIX}/bin;${PURE_GL_WINDOWS_SYSTEM_DIRECTORY};C:/Windows")
gl_audit_run(extracted-configure ${configure})
gl_audit_run(extracted-build "${CMAKE_COMMAND}" --build "${build}" --parallel 4)
gl_audit_run(extracted-inventory "${CMAKE_COMMAND}" "-DBINARY_DIR=${build}"
  -P "${extracted}/tests/VerifyCTestInventory.cmake")
gl_audit_run(extracted-pe "${CMAKE_COMMAND}" --build "${build}" --target verify-windows-dependencies --parallel 4)
message(STATUS "${last_output}")
get_filename_component(tool_dir "${CMAKE_COMMAND}" DIRECTORY)
set(ENV{PATH} "${PURE_GL_WINDOWS_SYSTEM_DIRECTORY};C:/Windows")
unset(ENV{PURELIB})
gl_audit_run(extracted-tests "${tool_dir}/ctest.exe" --test-dir "${build}"
  -L gl -E "^pure-gl-source-dist-contract$" --output-on-failure)
message(STATUS "${last_output}")
file(STRINGS "${build}/pure-gl-install-inventory.tsv" sealed)
list(LENGTH sealed sealed_count)
if(NOT sealed_count EQUAL 26)
  message(FATAL_ERROR "Extracted build failed to seal all 26 package payloads")
endif()
list(LENGTH expected_files file_count)
list(LENGTH expected_dirs dir_count)
math(EXPR dir_count "${dir_count}+1")
message(STATUS "PURE_GL_SOURCE_DIST_CONTRACT_OK files=${file_count} directories=${dir_count} workers=4 sealed=26 copied_source_absent=1 mutations=4 archive_sha256=${archive_hash}")
