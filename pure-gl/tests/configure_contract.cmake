cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS SOURCE_DIR BINARY_DIR GENERATOR MAKE_PROGRAM C_COMPILER
    PKG_CONFIG_EXECUTABLE LLVM_READOBJ_EXECUTABLE LLVM_STRINGS_EXECUTABLE
    GNU_MAKE_EXECUTABLE PURE_EXECUTABLE PURE_GL_PURE_PREFIX
    PURE_GL_CLANG64_PREFIX PURE_GL_WINDOWS_SYSTEM_DIRECTORY)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

set(test_root "${BINARY_DIR}/configure contract")
file(REMOVE_RECURSE "${test_root}")
file(MAKE_DIRECTORY "${test_root}")

set(base_args
  "-DCMAKE_MAKE_PROGRAM=${MAKE_PROGRAM}"
  "-DCMAKE_C_COMPILER=${C_COMPILER}"
  -DCMAKE_C_COMPILER_WORKS=1
  -DCMAKE_C_ABI_COMPILED=1
  -DBUILD_TESTING=OFF
  -DPURE_GL_STRICT_AUDIT=ON
  "-DPKG_CONFIG_EXECUTABLE=${PKG_CONFIG_EXECUTABLE}"
  "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}"
  "-DLLVM_STRINGS_EXECUTABLE=${LLVM_STRINGS_EXECUTABLE}"
  "-DGNU_MAKE_EXECUTABLE=${GNU_MAKE_EXECUTABLE}"
  "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
  "-DPURE_GL_PURE_PREFIX=${PURE_GL_PURE_PREFIX}"
  "-DPURE_GL_CLANG64_PREFIX=${PURE_GL_CLANG64_PREFIX}"
  "-DPURE_GL_WINDOWS_SYSTEM_DIRECTORY=${PURE_GL_WINDOWS_SYSTEM_DIRECTORY}"
  # Legacy inputs keep the pre-contract configure alive for a meaningful RED.
  "-DLLVM_READOBJ=${LLVM_READOBJ_EXECUTABLE}"
  "-DLLVM_STRINGS=${LLVM_STRINGS_EXECUTABLE}"
  "-DFREEGLUT_RUNTIME_DLL=${PURE_GL_CLANG64_PREFIX}/bin/libfreeglut.dll")

function(run_configure name expected)
  set(args ${base_args})
  foreach(override IN LISTS ARGN)
    string(REGEX REPLACE "^-D([^:=]+)(:[^=]+)?=.*$" "\\1" key "${override}")
    list(FILTER args EXCLUDE REGEX "^-D${key}=")
    list(APPEND args "${override}")
  endforeach()
  set(build_dir "${test_root}/${name}")
  file(REMOVE_RECURSE "${build_dir}")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env
      "PATH=${PURE_GL_CLANG64_PREFIX}/bin;${PURE_GL_WINDOWS_SYSTEM_DIRECTORY}"
      "MSYSTEM_PREFIX=${test_root}/ambient-msystem-poison"
      "PKG_CONFIG_PATH=${test_root}/ambient-pkgconfig-poison"
      "${CMAKE_COMMAND}" -S "${SOURCE_DIR}" -B "${build_dir}"
        -G "${GENERATOR}" ${args}
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    TIMEOUT 45)
  set(diagnostics "${output}\n${error}")
  if(expected STREQUAL "PASS")
    if(NOT result EQUAL 0)
      message(FATAL_ERROR "${name} configuration failed:\n${diagnostics}")
    endif()
  else()
    if(result EQUAL 0)
      message(FATAL_ERROR "${name} configuration unexpectedly succeeded")
    endif()
    if(NOT diagnostics MATCHES "${expected}")
      message(FATAL_ERROR
        "${name} produced the wrong diagnostic; expected '${expected}':\n${diagnostics}")
    endif()
  endif()
endfunction()

foreach(required IN ITEMS PURE_EXECUTABLE PKG_CONFIG_EXECUTABLE
    LLVM_READOBJ_EXECUTABLE LLVM_STRINGS_EXECUTABLE GNU_MAKE_EXECUTABLE
    PURE_GL_PURE_PREFIX PURE_GL_CLANG64_PREFIX
    PURE_GL_WINDOWS_SYSTEM_DIRECTORY)
  run_configure("missing-${required}" "${required}.*required" "-D${required}=")
endforeach()

file(MAKE_DIRECTORY "${test_root}/directory-as-executable")
run_configure(directory-executable "LLVM_READOBJ_EXECUTABLE.*regular file"
  "-DLLVM_READOBJ_EXECUTABLE=${test_root}/directory-as-executable")
run_configure(wrong-pure-prefix
  "PURE_EXECUTABLE.*below PURE_GL_PURE_PREFIX"
  "-DPURE_GL_PURE_PREFIX=${PURE_GL_CLANG64_PREFIX}")
run_configure(nonnormal-pure-prefix
  "PURE_GL_PURE_PREFIX.*normalized absolute directory"
  "-DPURE_GL_PURE_PREFIX:STRING=${PURE_GL_PURE_PREFIX}/bin/..")
run_configure(system-below-package
  "PURE_GL_WINDOWS_SYSTEM_DIRECTORY.*outside.*package prefix"
  "-DPURE_GL_WINDOWS_SYSTEM_DIRECTORY=${PURE_GL_PURE_PREFIX}/bin")

set(alias "${test_root}/clang64-alias")
execute_process(
  COMMAND "${PURE_GL_WINDOWS_SYSTEM_DIRECTORY}/WindowsPowerShell/v1.0/powershell.exe"
    -NoProfile -NonInteractive -Command
    "New-Item -ItemType Junction -Path '${alias}' -Target '${PURE_GL_CLANG64_PREFIX}' | Out-Null"
  RESULT_VARIABLE junction_result
  ERROR_VARIABLE junction_error)
if(NOT junction_result EQUAL 0)
  message(FATAL_ERROR "Cannot establish FreeGLUT prefix junction: ${junction_error}")
endif()
run_configure(aliased-freeglut-prefix
  "PURE_GL_CLANG64_PREFIX.*canonical directory"
  "-DPURE_GL_CLANG64_PREFIX=${alias}")
# Unlink exactly the junction itself; never recursively traverse its target.
execute_process(
  COMMAND "${PURE_GL_WINDOWS_SYSTEM_DIRECTORY}/WindowsPowerShell/v1.0/powershell.exe"
    -NoProfile -NonInteractive -Command "[IO.Directory]::Delete('${alias}')"
  RESULT_VARIABLE unlink_result)
if(NOT unlink_result EQUAL 0)
  message(FATAL_ERROR "Cannot unlink FreeGLUT prefix junction")
endif()

run_configure(pristine PASS)
message(STATUS "PURE_GL_CONFIGURE_CONTRACT_OK")
