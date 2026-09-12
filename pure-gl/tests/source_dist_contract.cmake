cmake_minimum_required(VERSION 3.25)
foreach(required SOURCE_DIR BINARY_DIR GNU_MAKE_EXECUTABLE)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()
include("${SOURCE_DIR}/tests/AuditHelpers.cmake")
gl_audit_require_disjoint_layout()
gl_audit_open(source-dist-contract work)
gl_audit_open(source-dist-input input)
set(copy "${input}/source with spaces")
file(MAKE_DIRECTORY "${copy}")
execute_process(COMMAND "${BINARY_DIR}/pure-gl-install-guard.exe" --check-tree "${SOURCE_DIR}"
  COMMAND_ERROR_IS_FATAL ANY)
file(COPY "${SOURCE_DIR}/" DESTINATION "${copy}")

# Independent, reviewed release policy, not a parse of the production Makefile.
set(expected_files
  .pure-gl-source CMakeLists.txt COPYING Makefile README THIRD_PARTY.md WINDOWS.md
  GL.c GL.pure GL_ARB.c GL_ARB.pure GL_ATI.c GL_ATI.pure GL_EXT.c GL_EXT.pure
  GL_NV.c GL_NV.pure GLU.c GLU.pure GLUT.c GLUT.pure gl.templ
  GL/all_gl.h GL/all_gl_freeglut.h
  cmake/Install.cmake cmake/LegacyPathPolicy.cmake cmake/LegacyWorkflow.cmake cmake/LegacyWorkflow.ps1
  cmake/PeHelpers.cmake cmake/RunPureTest.cmake cmake/VerifyInstalledPackage.cmake
  cmake/VerifyWindowsDependencies.cmake cmake/pure_gl_install_guard.c cmake/pure_gl_runner.c
  debian/changelog debian/compat debian/control debian/copyright debian/docs
  debian/rules debian/source/format debian/watch
  examples/Imlib2.pure examples/fractal.jpg examples/simple_glut_example.pure
  examples/teapot.pure examples/texture.pure
  examples/flexi-line/flexi-line-auto.pure examples/flexi-line/flexi-line.pure
  examples/flexi-line/glamour.pure examples/flexi-line/vector_math.pure
  tests/AuditHelpers.cmake tests/ReleaseChecks.cmake tests/cleanup_contract.cmake tests/configure_contract.cmake
  tests/hidden-render.pure tests/install_contract.cmake tests/install_guard_contract.cmake
  tests/interactive.pure tests/load.pure tests/render_contract.cmake tests/runner_contract.cmake
  tests/runner_probe.pure tests/runtime_verifier_contract.cmake tests/source_dist_contract.cmake tests/workflow_contract.cmake
  tests/fixtures/freeglut-imports.txt tests/fixtures/libc++-imports.txt
  tests/fixtures/libgmp-10-imports.txt tests/fixtures/libiconv-2-imports.txt
  tests/fixtures/libmpfr-6-imports.txt tests/fixtures/libpcre-1-imports.txt
  tests/fixtures/libpcreposix-0-imports.txt tests/fixtures/libpure-imports.txt
  tests/fixtures/libwinpthread-1-imports.txt tests/fixtures/libzstd-imports.txt
  tests/fixtures/pure-gl-imports.txt tests/fixtures/zlib1-imports.txt)
list(SORT expected_files)
set(expected_dirs GL cmake debian debian/source examples examples/flexi-line tests tests/fixtures)
file(GLOB_RECURSE support_files LIST_DIRECTORIES FALSE RELATIVE "${SOURCE_DIR}"
  "${SOURCE_DIR}/cmake/*" "${SOURCE_DIR}/tests/*")
foreach(path IN LISTS support_files)
  if(NOT path IN_LIST expected_files)
    message(FATAL_ERROR "Required helper/contract is absent from the reviewed archive policy: ${path}")
  endif()
endforeach()
foreach(path IN LISTS expected_files)
  file(SHA256 "${SOURCE_DIR}/${path}" "source_hash_${path}")
endforeach()
file(READ "${SOURCE_DIR}/README" readme_template)
set(archive "${copy}/pure-gl-0.9.tar.gz")
set(ENV{PKG_CONFIG_PATH} "")
set(ENV{PKG_CONFIG_LIBDIR} "${PURE_GL_PURE_PREFIX}/lib/pkgconfig;${PURE_GL_CLANG64_PREFIX}/lib/pkgconfig")
unset(ENV{PKG_CONFIG_SYSROOT_DIR})
foreach(name MAKEFLAGS MFLAGS MAKEOVERRIDES)
  unset(ENV{${name}})
endforeach()
execute_process(COMMAND "${GNU_MAKE_EXECUTABLE}" --no-print-directory dist
    "CMAKE=${CMAKE_COMMAND}" "PKG_CONFIG=${PKG_CONFIG_EXECUTABLE}"
  WORKING_DIRECTORY "${copy}" RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 120)
file(WRITE "${work}/make-dist.log" "exit=${rc}\n${out}${err}")
if(NOT EXISTS "${archive}")
  message(FATAL_ERROR "Public make dist produced no archive (${rc}): ${out}${err}")
endif()
execute_process(COMMAND "${CMAKE_COMMAND}" -E tar tf "${archive}"
  RESULT_VARIABLE list_rc OUTPUT_VARIABLE entries ERROR_VARIABLE list_err)
string(REPLACE "\r" "" entries "${entries}")
if(NOT entries MATCHES "(^|\n)pure-gl-0.9/CMakeLists.txt(\n|$)")
  message(FATAL_ERROR "Source archive missing required CMakeLists.txt")
endif()
if(NOT rc EQUAL 0 OR NOT list_rc EQUAL 0)
  message(FATAL_ERROR "Public make dist/archive listing failed: ${out}${err}${list_err}")
endif()
string(REPLACE "\n" ";" actual_inventory "${entries}")
list(FILTER actual_inventory EXCLUDE REGEX "^$")
set(expected_inventory "pure-gl-0.9/")
foreach(path IN LISTS expected_dirs)
  list(APPEND expected_inventory "pure-gl-0.9/${path}/")
endforeach()
foreach(path IN LISTS expected_files)
  list(APPEND expected_inventory "pure-gl-0.9/${path}")
endforeach()
list(SORT actual_inventory)
list(SORT expected_inventory)
if(NOT actual_inventory STREQUAL expected_inventory)
  message(FATAL_ERROR "Exact source inventory mismatch\nexpected=${expected_inventory}\nactual=${actual_inventory}")
endif()
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
validate_archive_types("${archive}" problem)
if(problem)
  message(FATAL_ERROR "Archive type validation failed: ${problem}")
endif()
file(COPY_FILE "${archive}" "${work}/pure-gl-0.9.tar.gz")
file(SHA256 "${archive}" archive_hash)
foreach(path IN LISTS expected_files)
  file(SHA256 "${copy}/${path}" copy_hash)
  if(NOT copy_hash STREQUAL "${source_hash_${path}}")
    message(FATAL_ERROR "Public dist changed a source input: ${path}")
  endif()
endforeach()
# Drop the entire copied-source leaf before extraction; every subsequent driver
# and helper comes from the archive. Only immutable external tools/prefixes remain.
gl_audit_clean(source-dist-input)
if(EXISTS "${copy}")
  message(FATAL_ERROR "Copied source remains accessible after archive creation")
endif()
file(MAKE_DIRECTORY "${work}/extracted elsewhere")
execute_process(COMMAND "${CMAKE_COMMAND}" -E tar xfz "${work}/pure-gl-0.9.tar.gz"
  WORKING_DIRECTORY "${work}/extracted elsewhere" COMMAND_ERROR_IS_FATAL ANY)
set(extracted "${work}/extracted elsewhere/pure-gl-0.9")
function(validate_extracted output)
  set(${output} "" PARENT_SCOPE)
  execute_process(COMMAND "${BINARY_DIR}/pure-gl-install-guard.exe" --check-tree "${extracted}"
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
gl_audit_clean(source-dist-contract)
