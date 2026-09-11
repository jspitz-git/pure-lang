cmake_minimum_required(VERSION 3.25)

project(pure-gl VERSION 0.9 LANGUAGES C)

include(CTest)
option(PURE_GL_STRICT_AUDIT
  "Require explicit canonical inputs for the Windows package audit" OFF)

set(PURE_EXECUTABLE "" CACHE FILEPATH "Installed Pure interpreter")
set(PKG_CONFIG_EXECUTABLE "" CACHE FILEPATH "pkg-config executable")
set(LLVM_READOBJ_EXECUTABLE "" CACHE FILEPATH
  "llvm-readobj used for Windows PE validation")
set(LLVM_STRINGS_EXECUTABLE "" CACHE FILEPATH
  "llvm-strings used for Windows PE validation")
set(GNU_MAKE_EXECUTABLE "" CACHE FILEPATH
  "GNU make used by source distribution contracts")
set(PURE_GL_PURE_PREFIX "" CACHE PATH "Canonical staged Pure prefix")
set(PURE_GL_CLANG64_PREFIX "" CACHE PATH "Canonical CLANG64 FreeGLUT prefix")
set(PURE_GL_WINDOWS_SYSTEM_DIRECTORY "" CACHE PATH
  "Canonical Windows system directory")

function(pure_gl_require_path name kind)
  if(NOT DEFINED ${name} OR "${${name}}" STREQUAL "")
    message(FATAL_ERROR "${name} is required in PURE_GL_STRICT_AUDIT mode")
  endif()
  file(TO_CMAKE_PATH "${${name}}" input)
  cmake_path(IS_ABSOLUTE input absolute)
  cmake_path(NORMAL_PATH input OUTPUT_VARIABLE normalized)
  if(NOT absolute OR NOT input STREQUAL normalized)
    message(FATAL_ERROR
      "${name} must be a normalized absolute ${kind}: ${${name}}")
  endif()
  if(NOT EXISTS "${input}" OR
      (kind STREQUAL "regular file" AND IS_DIRECTORY "${input}") OR
      (kind STREQUAL "directory" AND NOT IS_DIRECTORY "${input}"))
    message(FATAL_ERROR "${name} must name an existing ${kind}: ${input}")
  endif()
  file(REAL_PATH "${input}" real)
  file(TO_CMAKE_PATH "${real}" real)
  string(TOLOWER "${input}" input_casefolded)
  string(TOLOWER "${real}" real_casefolded)
  if(NOT input_casefolded STREQUAL real_casefolded)
    message(FATAL_ERROR
      "${name} must name a canonical ${kind} without aliases: ${input}")
  endif()
  set(${name} "${input}" PARENT_SCOPE)
endfunction()

function(pure_gl_require_below path_name prefix_name)
  cmake_path(IS_PREFIX ${prefix_name} "${${path_name}}" NORMALIZE below)
  if(NOT below OR "${${path_name}}" STREQUAL "${${prefix_name}}")
    message(FATAL_ERROR
      "${path_name} must be below ${prefix_name}: ${${path_name}}")
  endif()
endfunction()

if(PURE_GL_STRICT_AUDIT)
  foreach(file_var IN ITEMS PURE_EXECUTABLE PKG_CONFIG_EXECUTABLE
      LLVM_READOBJ_EXECUTABLE LLVM_STRINGS_EXECUTABLE GNU_MAKE_EXECUTABLE)
    pure_gl_require_path(${file_var} "regular file")
  endforeach()
  foreach(directory_var IN ITEMS PURE_GL_PURE_PREFIX PURE_GL_CLANG64_PREFIX
      PURE_GL_WINDOWS_SYSTEM_DIRECTORY)
    pure_gl_require_path(${directory_var} "directory")
  endforeach()
  pure_gl_require_below(PURE_EXECUTABLE PURE_GL_PURE_PREFIX)
  foreach(prefix IN ITEMS PURE_GL_PURE_PREFIX PURE_GL_CLANG64_PREFIX)
    cmake_path(IS_PREFIX ${prefix} "${PURE_GL_WINDOWS_SYSTEM_DIRECTORY}"
      NORMALIZE system_below_package)
    if(system_below_package)
      message(FATAL_ERROR
        "PURE_GL_WINDOWS_SYSTEM_DIRECTORY must be outside each package prefix")
    endif()
  endforeach()

  set(FREEGLUT_INCLUDE_DIR "${PURE_GL_CLANG64_PREFIX}/include")
  set(FREEGLUT_HEADER
    "${PURE_GL_CLANG64_PREFIX}/include/GL/freeglut.h")
  set(FREEGLUT_IMPORT_LIBRARY
    "${PURE_GL_CLANG64_PREFIX}/lib/libfreeglut.dll.a")
  set(FREEGLUT_RUNTIME_DLL
    "${PURE_GL_CLANG64_PREFIX}/bin/libfreeglut.dll")
  set(FREEGLUT_RUNTIME_LICENSE
    "${PURE_GL_CLANG64_PREFIX}/share/licenses/freeglut/COPYING")
  foreach(file_var IN ITEMS FREEGLUT_HEADER FREEGLUT_IMPORT_LIBRARY
      FREEGLUT_RUNTIME_DLL FREEGLUT_RUNTIME_LICENSE)
    pure_gl_require_path(${file_var} "regular file")
    pure_gl_require_below(${file_var} PURE_GL_CLANG64_PREFIX)
  endforeach()
  pure_gl_require_path(FREEGLUT_INCLUDE_DIR "directory")
  pure_gl_require_below(FREEGLUT_INCLUDE_DIR PURE_GL_CLANG64_PREFIX)

  set(ENV{PKG_CONFIG_PATH} "")
  set(ENV{PKG_CONFIG_LIBDIR}
    "${PURE_GL_PURE_PREFIX}/lib/pkgconfig;${PURE_GL_CLANG64_PREFIX}/lib/pkgconfig")
  unset(ENV{PKG_CONFIG_SYSROOT_DIR})
  set(PKG_CONFIG_USE_CMAKE_PREFIX_PATH FALSE)
else()
  if(NOT PKG_CONFIG_EXECUTABLE)
    unset(PKG_CONFIG_EXECUTABLE CACHE)
  endif()
  find_program(PKG_CONFIG_EXECUTABLE NAMES pkg-config REQUIRED)
endif()

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(FREEGLUT REQUIRED IMPORTED_TARGET freeglut)
pkg_get_variable(discovered_pure_prefix pure prefix)
pkg_get_variable(discovered_freeglut_prefix freeglut prefix)
file(TO_CMAKE_PATH "${discovered_pure_prefix}" discovered_pure_prefix)
file(TO_CMAKE_PATH "${discovered_freeglut_prefix}" discovered_freeglut_prefix)

if(PURE_GL_STRICT_AUDIT)
  string(TOLOWER "${discovered_pure_prefix}" discovered_pure_casefolded)
  string(TOLOWER "${PURE_GL_PURE_PREFIX}" pure_prefix_casefolded)
  if(NOT discovered_pure_casefolded STREQUAL pure_prefix_casefolded)
    message(FATAL_ERROR
      "pure pkg-config prefix must equal PURE_GL_PURE_PREFIX: ${discovered_pure_prefix}")
  endif()
  string(TOLOWER "${discovered_freeglut_prefix}" discovered_glut_casefolded)
  string(TOLOWER "${PURE_GL_CLANG64_PREFIX}" clang_prefix_casefolded)
  if(NOT discovered_glut_casefolded STREQUAL clang_prefix_casefolded)
    message(FATAL_ERROR
      "freeglut pkg-config prefix must equal PURE_GL_CLANG64_PREFIX: ${discovered_freeglut_prefix}")
  endif()
else()
  set(PURE_GL_PURE_PREFIX "${discovered_pure_prefix}" CACHE PATH
    "Canonical staged Pure prefix" FORCE)
  set(PURE_GL_CLANG64_PREFIX "${discovered_freeglut_prefix}" CACHE PATH
    "Canonical CLANG64 FreeGLUT prefix" FORCE)
  foreach(program_var IN ITEMS LLVM_READOBJ_EXECUTABLE
      LLVM_STRINGS_EXECUTABLE GNU_MAKE_EXECUTABLE PURE_EXECUTABLE)
    if(NOT ${program_var})
      unset(${program_var} CACHE)
    endif()
  endforeach()
  find_program(LLVM_READOBJ_EXECUTABLE NAMES llvm-readobj REQUIRED)
  find_program(LLVM_STRINGS_EXECUTABLE NAMES llvm-strings REQUIRED)
  find_program(GNU_MAKE_EXECUTABLE NAMES make mingw32-make REQUIRED)
  find_program(PURE_EXECUTABLE NAMES pure
    HINTS "${PURE_GL_PURE_PREFIX}/bin" REQUIRED)
  find_file(FREEGLUT_RUNTIME_DLL NAMES libfreeglut.dll
    HINTS "$ENV{MSYSTEM_PREFIX}/bin" "${PURE_GL_CLANG64_PREFIX}/bin"
    REQUIRED)
  if(NOT PURE_GL_WINDOWS_SYSTEM_DIRECTORY)
    set(PURE_GL_WINDOWS_SYSTEM_DIRECTORY "C:/Windows/System32" CACHE PATH
      "Canonical Windows system directory" FORCE)
  endif()
endif()

add_library(pure-gl MODULE
  GL.c GL_ARB.c GL_EXT.c GL_NV.c GL_ATI.c GLU.c GLUT.c)
target_compile_features(pure-gl PRIVATE c_std_11)
target_link_libraries(pure-gl PRIVATE
  PkgConfig::PURE PkgConfig::FREEGLUT opengl32 glu32)
if(MINGW)
  target_compile_options(pure-gl PRIVATE -Wall -Wextra -Werror)
  target_link_options(pure-gl PRIVATE "LINKER:--enable-auto-import")
endif()
set_target_properties(pure-gl PROPERTIES
  PREFIX "" WINDOWS_EXPORT_ALL_SYMBOLS ON)

if(WIN32)
  add_executable(pure-gl-test-runner cmake/pure_gl_runner.c)
  target_compile_features(pure-gl-test-runner PRIVATE c_std_11)
  target_link_libraries(pure-gl-test-runner PRIVATE bcrypt)
  target_link_options(pure-gl-test-runner PRIVATE -municode)
  if(MINGW)
    target_compile_options(pure-gl-test-runner PRIVATE -Wall -Wextra -Werror)
  endif()
  if(BUILD_TESTING)
    add_executable(pure-gl-runner-fixture cmake/pure_gl_runner.c)
    target_compile_features(pure-gl-runner-fixture PRIVATE c_std_11)
    target_compile_definitions(pure-gl-runner-fixture PRIVATE
      PURE_GL_RUNNER_FIXTURE=1)
    if(MINGW)
      target_compile_options(pure-gl-runner-fixture PRIVATE
        -Wall -Wextra -Werror)
    endif()
  endif()
endif()

add_custom_target(verify-windows-dependencies
  COMMAND "${CMAKE_COMMAND}"
    "-DLLVM_READOBJ=${LLVM_READOBJ_EXECUTABLE}"
    "-DLLVM_STRINGS=${LLVM_STRINGS_EXECUTABLE}"
    "-DPURE_GL_MODULE=$<TARGET_FILE:pure-gl>"
    "-DFREEGLUT_DLL=${FREEGLUT_RUNTIME_DLL}"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
  DEPENDS pure-gl VERBATIM)

set(pure_gl_runner_arguments
  "-DPURE_GL_RUNNER=$<TARGET_FILE:pure-gl-test-runner>"
  "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
  "-DPURE_GL_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
  "-DPURE_GL_MODULE=$<TARGET_FILE:pure-gl>"
  "-DFREEGLUT_RUNTIME_DLL=${FREEGLUT_RUNTIME_DLL}"
  "-DPURE_GL_PURE_PREFIX=${PURE_GL_PURE_PREFIX}"
  "-DPURE_GL_CLANG64_PREFIX=${PURE_GL_CLANG64_PREFIX}"
  "-DPURE_GL_WINDOWS_SYSTEM_DIRECTORY=${PURE_GL_WINDOWS_SYSTEM_DIRECTORY}"
  -DTEST_WORKING_DIRECTORY=C:/Windows
  -DTIMEOUT_MS=45000)

add_custom_target(check-gl-interactive
  COMMAND "${CMAKE_COMMAND}" ${pure_gl_runner_arguments}
    "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/interactive.pure"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake"
  DEPENDS pure-gl pure-gl-test-runner
  COMMENT "Displaying the bounded pure-gl Windows desktop test"
  USES_TERMINAL VERBATIM)

if(BUILD_TESTING)
  add_test(NAME pure-gl.load-all-modules
    COMMAND "${CMAKE_COMMAND}" ${pure_gl_runner_arguments}
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/load.pure"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake")
  set_tests_properties(pure-gl.load-all-modules PROPERTIES
    LABELS "gl;load" TIMEOUT 55 RUN_SERIAL TRUE
    REQUIRED_FILES "$<TARGET_FILE:pure-gl>")
  add_test(NAME pure-gl.hidden-render
    COMMAND "${CMAKE_COMMAND}" ${pure_gl_runner_arguments}
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/hidden-render.pure"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake")
  set_tests_properties(pure-gl.hidden-render PROPERTIES
    LABELS "gl;render" TIMEOUT 55 RUN_SERIAL TRUE
    REQUIRED_FILES "$<TARGET_FILE:pure-gl>")
  if(WIN32)
    add_test(NAME pure-gl-configure-contract
      COMMAND "${CMAKE_COMMAND}"
        "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
        "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
        "-DGENERATOR=${CMAKE_GENERATOR}"
        "-DMAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}"
        "-DC_COMPILER=${CMAKE_C_COMPILER}"
        "-DPKG_CONFIG_EXECUTABLE=${PKG_CONFIG_EXECUTABLE}"
        "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}"
        "-DLLVM_STRINGS_EXECUTABLE=${LLVM_STRINGS_EXECUTABLE}"
        "-DGNU_MAKE_EXECUTABLE=${GNU_MAKE_EXECUTABLE}"
        "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
        "-DPURE_GL_PURE_PREFIX=${PURE_GL_PURE_PREFIX}"
        "-DPURE_GL_CLANG64_PREFIX=${PURE_GL_CLANG64_PREFIX}"
        "-DPURE_GL_WINDOWS_SYSTEM_DIRECTORY=${PURE_GL_WINDOWS_SYSTEM_DIRECTORY}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/configure_contract.cmake")
    add_test(NAME pure-gl-runner-contract
      COMMAND "${CMAKE_COMMAND}"
        "-DRUNNER=$<TARGET_FILE:pure-gl-test-runner>"
        "-DFIXTURE=$<TARGET_FILE:pure-gl-runner-fixture>"
        "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
        "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
        "-DC_COMPILER=${CMAKE_C_COMPILER}"
        "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
        "-DPURE_GL_PURE_PREFIX=${PURE_GL_PURE_PREFIX}"
        "-DPURE_GL_CLANG64_PREFIX=${PURE_GL_CLANG64_PREFIX}"
        "-DPURE_GL_WINDOWS_SYSTEM_DIRECTORY=${PURE_GL_WINDOWS_SYSTEM_DIRECTORY}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/runner_contract.cmake")
    set_tests_properties(pure-gl-configure-contract pure-gl-runner-contract
      PROPERTIES LABELS "gl;contract" TIMEOUT 90 RUN_SERIAL TRUE)
  endif()
endif()

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/Install.cmake")
