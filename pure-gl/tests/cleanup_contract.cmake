cmake_minimum_required(VERSION 3.25)
foreach(required SOURCE_DIR BINARY_DIR GNU_MAKE_EXECUTABLE)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()
include("${SOURCE_DIR}/tests/AuditHelpers.cmake")
gl_audit_require_disjoint_layout()
include("${SOURCE_DIR}/tests/ReleaseChecks.cmake")
set(ENV{PKG_CONFIG_PATH} "")
set(ENV{PKG_CONFIG_LIBDIR} "${PURE_GL_PURE_PREFIX}/lib/pkgconfig;${PURE_GL_CLANG64_PREFIX}/lib/pkgconfig")
unset(ENV{PKG_CONFIG_SYSROOT_DIR})
gl_audit_open(cleanup-contract work)
execute_process(COMMAND "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
  -NoProfile -NonInteractive -File "${SOURCE_DIR}/tests/LegacyRetention.ps1"
  -Source "${SOURCE_DIR}" -Root "${work}" -Compiler "${C_COMPILER}" -CMake "${CMAKE_COMMAND}"
  RESULT_VARIABLE retain_rc OUTPUT_VARIABLE retain_out ERROR_VARIABLE retain_err TIMEOUT 90)
if(NOT retain_rc EQUAL 0)
  message(FATAL_ERROR "Legacy retention contract failed: ${retain_out}${retain_err}")
endif()
message(STATUS "${retain_out}")
set(copy "${work}/source with spaces")
file(MAKE_DIRECTORY "${copy}")
execute_process(COMMAND "${BINARY_DIR}/pure-gl-install-guard.exe" --check-tree "${SOURCE_DIR}"
  COMMAND_ERROR_IS_FATAL ANY)
file(COPY "${SOURCE_DIR}/" DESTINATION "${copy}")
# The former *$(DLL)* expansion is demonstrated with make -n only: it must
# reject the invalid suffix before even producing a deletion command.
execute_process(COMMAND "${GNU_MAKE_EXECUTABLE}" -n clean DLL=
    "CMAKE=${CMAKE_COMMAND}" "PKG_CONFIG=${PKG_CONFIG_EXECUTABLE}"
  WORKING_DIRECTORY "${copy}" RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
file(WRITE "${work}/empty-suffix-dry-run.log" "exit=${rc}\n${out}${err}")
if(rc EQUAL 0 AND out MATCHES "rm -Rf \\*\\*")
  message(FATAL_ERROR "Unsafe empty DLL expansion: ${out}")
endif()
set(make "${GNU_MAKE_EXECUTABLE}" --no-print-directory
  "CMAKE=${CMAKE_COMMAND}" "PKG_CONFIG=${PKG_CONFIG_EXECUTABLE}")
release_check_build_binding()
release_check_containment()
release_check_posix_policy()
set(powershell "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe")
file(MAKE_DIRECTORY "${work}/empty-pkg" "${work}/junction-target")
file(WRITE "${work}/junction-target/keep.txt" "protected external target\n")
file(WRITE "${copy}/unrelated.dll" "not a package output\n")
file(WRITE "${copy}/unrelated.o" "not a package output\n")
file(WRITE "${copy}/pure-gl.dll.note" "not a package output\n")
file(WRITE "${copy}/pure-gl.dll" "owned module output\n")
file(READ "${copy}/.pure-gl-source" source_owner)
foreach(target clean realclean generate dist distcheck)
  reject("${target}-empty-suffix" "${copy}" "DLL suffix" ${make} "${target}" DLL=)
  set(saved_pc "$ENV{PKG_CONFIG_LIBDIR}")
  set(ENV{PKG_CONFIG_LIBDIR} "${work}/empty-pkg")
  reject("${target}-missing-pure-pc" "${copy}" "pure.pc" ${make} "${target}" DLL=.dll)
  set(ENV{PKG_CONFIG_LIBDIR} "${saved_pc}")
  file(WRITE "${copy}/.pure-gl-source" "invalid source owner\n")
  reject("${target}-invalid-sentinel" "${copy}" "sentinel" ${make} "${target}" DLL=.dll)
  file(WRITE "${copy}/.pure-gl-source" "${source_owner}")
  file(MAKE_DIRECTORY "${copy}/.pure-gl-dist")
  file(WRITE "${copy}/.pure-gl-dist/.pure-gl-owner" "wrong work owner\n")
  reject("${target}-invalid-work-sentinel" "${copy}" "sentinel" ${make} "${target}" DLL=.dll)
  file(REMOVE "${copy}/.pure-gl-dist/.pure-gl-owner")
  execute_process(COMMAND "${powershell}" -NoProfile -NonInteractive -Command
    "[IO.Directory]::Delete('${copy}/.pure-gl-dist')" COMMAND_ERROR_IS_FATAL ANY)
  file(RENAME "${copy}/pure-gl.dll" "${copy}/PURE-GL.DLL")
  reject("${target}-case-alias" "${copy}" "case|alias" ${make} "${target}" DLL=.dll)
  file(RENAME "${copy}/PURE-GL.DLL" "${copy}/pure-gl.dll")
  file(MAKE_DIRECTORY "${copy}/protected")
  file(WRITE "${copy}/protected/.pure-gl-protected" "protected descendant\n")
  reject("${target}-protected-descendant" "${copy}" "protected descendant" ${make} "${target}" DLL=.dll)
  # These are exact, nonrecursive removals of files created by this fixture.
  file(REMOVE "${copy}/protected/.pure-gl-protected")
  execute_process(COMMAND "${powershell}" -NoProfile -NonInteractive -Command
    "[IO.Directory]::Delete('${copy}/protected')" COMMAND_ERROR_IS_FATAL ANY)
  execute_process(COMMAND "${powershell}" -NoProfile -NonInteractive -Command
    "New-Item -ItemType Junction -Path '${copy}/.pure-gl-dist' -Target '${work}/junction-target' | Out-Null"
    COMMAND_ERROR_IS_FATAL ANY)
  reject("${target}-junction" "${copy}" "reparse" ${make} "${target}" DLL=.dll)
  file(SHA256 "${work}/junction-target/keep.txt" target_hash)
  string(SHA256 expected_target "protected external target\r\n")
  if(NOT target_hash STREQUAL expected_target)
    message(FATAL_ERROR "Junction target bytes changed")
  endif()
  execute_process(COMMAND "${powershell}" -NoProfile -NonInteractive -Command
    "[IO.Directory]::Delete('${copy}/.pure-gl-dist')" COMMAND_ERROR_IS_FATAL ANY)
endforeach()

# The three real inherited drivers must reject each compromised fixture root
# before configuring a child, compiling a probe, or starting a rendering test.
set(driver_args)
foreach(name SOURCE_DIR BINARY_DIR GENERATOR MAKE_PROGRAM C_COMPILER
    PKG_CONFIG_EXECUTABLE LLVM_READOBJ_EXECUTABLE LLVM_READOBJ_SHA256
    LLVM_STRINGS_EXECUTABLE LLVM_STRINGS_SHA256 GNU_MAKE_EXECUTABLE PURE_EXECUTABLE
    PURE_GL_PURE_PREFIX PURE_GL_CLANG64_PREFIX PURE_GL_WINDOWS_SYSTEM_DIRECTORY)
  list(APPEND driver_args "-D${name}=${${name}}")
endforeach()
list(APPEND driver_args "-DRUNNER=${BINARY_DIR}/pure-gl-test-runner.exe"
  "-DFIXTURE=${BINARY_DIR}/pure-gl-runner-fixture.exe"
  "-DPURE_GL_RUNNER=${BINARY_DIR}/pure-gl-test-runner.exe"
  "-DPURE_GL_MODULE=${BINARY_DIR}/pure-gl.dll"
  "-DCONFIGURED_FREEGLUT_RUNTIME_DLL=${BINARY_DIR}/pure-gl-runtime/libfreeglut.dll"
  "-DFREEGLUT_RUNTIME_DLL=${BINARY_DIR}/pure-gl-runtime/libfreeglut.dll")
foreach(driver configure runner render)
  gl_audit_open("${driver}-contract" probe)
  set(command "${CMAKE_COMMAND}" ${driver_args} -P "${SOURCE_DIR}/tests/${driver}_contract.cmake")
  file(READ "${probe}/.pure-gl-owner" probe_owner)
  file(WRITE "${probe}/keep.txt" "owned protected bytes\n")
  file(WRITE "${probe}/.pure-gl-owner" "wrong audit owner\n")
  reject("${driver}-invalid-sentinel" "${probe}" "sentinel" ${command})
  file(WRITE "${probe}/.pure-gl-owner" "${probe_owner}")
  file(MAKE_DIRECTORY "${probe}/protected")
  file(WRITE "${probe}/protected/.pure-gl-protected" "protected descendant\n")
  reject("${driver}-protected-descendant" "${probe}" "protected descendant" ${command})
  file(REMOVE "${probe}/protected/.pure-gl-protected")
  execute_process(COMMAND "${powershell}" -NoProfile -NonInteractive -Command
    "[IO.Directory]::Delete('${probe}/protected')" COMMAND_ERROR_IS_FATAL ANY)
  execute_process(COMMAND "${powershell}" -NoProfile -NonInteractive -Command
    "New-Item -ItemType Junction -Path '${probe}/junction' -Target '${work}/junction-target' | Out-Null"
    COMMAND_ERROR_IS_FATAL ANY)
  reject("${driver}-junction" "${probe}" "reparse" ${command})
  execute_process(COMMAND "${powershell}" -NoProfile -NonInteractive -Command
    "[IO.Directory]::Delete('${probe}/junction')" COMMAND_ERROR_IS_FATAL ANY)
  file(RENAME "${probe}" "${probe}-saved")
  execute_process(COMMAND "${powershell}" -NoProfile -NonInteractive -Command
    "New-Item -ItemType Junction -Path '${probe}' -Target '${probe}-saved' | Out-Null"
    COMMAND_ERROR_IS_FATAL ANY)
  reject("${driver}-junctioned-leaf" "${probe}-saved" "reparse" ${command})
  execute_process(COMMAND "${powershell}" -NoProfile -NonInteractive -Command
    "[IO.Directory]::Delete('${probe}')" COMMAND_ERROR_IS_FATAL ANY)
  file(RENAME "${probe}-saved" "${probe}")
  string(REPLACE "${driver}-contract" "${driver}-CONTRACT" alias "${probe}")
  file(RENAME "${probe}" "${alias}")
  reject("${driver}-case-alias" "${alias}" "case|alias" ${command})
  file(RENAME "${alias}" "${probe}")
  gl_audit_clean("${driver}-contract")
endforeach()

foreach(name GL GL_ARB GL_EXT GL_NV GL_ATI GLU GLUT)
  file(WRITE "${copy}/${name}.o" "owned object output\n")
endforeach()
snapshot("${copy}" pristine)
release_expected_clean("${pristine}" expected_clean)
foreach(name GL GL_ARB GL_EXT GL_NV GL_ATI GLU GLUT)
  foreach(extension c pure)
    file(SHA256 "${copy}/${name}.${extension}" "wrapper_${name}_${extension}")
  endforeach()
endforeach()
execute_process(COMMAND ${make} clean DLL=.dll WORKING_DIRECTORY "${copy}"
  COMMAND_ERROR_IS_FATAL ANY)
release_assert_clean("${expected_clean}")
file(MAKE_DIRECTORY "${work}/tool with spaces & sign")
set(spaced_make "${work}/tool with spaces & sign/mingw32-make.exe")
file(COPY_FILE "${GNU_MAKE_EXECUTABLE}" "${spaced_make}")
# The pinned native GNU Make imports libintl, which imports libiconv. Copy this
# explicit closure beside the selected executable; keep the parent PATH clean.
get_filename_component(make_dir "${GNU_MAKE_EXECUTABLE}" DIRECTORY)
foreach(dll libintl-8.dll libiconv-2.dll)
  file(COPY_FILE "${make_dir}/${dll}" "${work}/tool with spaces & sign/${dll}")
endforeach()
execute_process(COMMAND "${spaced_make}" --version COMMAND_ERROR_IS_FATAL ANY OUTPUT_QUIET)
execute_process(COMMAND ${make} --jobs=4 generate DLL=.dll "CC=${C_COMPILER}" "MAKE=${spaced_make}"
  WORKING_DIRECTORY "${copy}" RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 120)
file(WRITE "${work}/generate-pristine.log" "exit=${rc}\n${out}${err}")
if(NOT rc EQUAL 0 OR NOT EXISTS "${copy}/pure-gl.dll")
  message(FATAL_ERROR "Pristine generate did not build the module: ${out}${err}")
endif()
foreach(name GL GL_ARB GL_EXT GL_NV GL_ATI GLU GLUT)
  foreach(extension c pure)
    file(SHA256 "${copy}/${name}.${extension}" hash)
    if(NOT hash STREQUAL "${wrapper_${name}_${extension}}")
      message(FATAL_ERROR "Generate changed a wrapper without explicit realclean")
    endif()
  endforeach()
endforeach()
execute_process(COMMAND ${make} realclean DLL=.dll WORKING_DIRECTORY "${copy}"
  COMMAND_ERROR_IS_FATAL ANY)
foreach(name GL GL_ARB GL_EXT GL_NV GL_ATI GLU GLUT)
  if(EXISTS "${copy}/${name}.c" OR EXISTS "${copy}/${name}.pure")
    message(FATAL_ERROR "Realclean retained explicitly requested generated wrappers")
  endif()
endforeach()
message(STATUS "PURE_GL_CLEANUP_CONTRACT_OK legacy_negative=35 inherited_negative=15 source_binding=1 layouts=4 posix_names=8 protected_writes=0 clean_inventory_and_hashes=1 realclean=1 generate=1 spaced_make=1 workers=4")
gl_audit_clean(cleanup-contract)
