set(PURE_LIBRARY_INSTALL_DIR "lib/pure" CACHE STRING "Relative Pure module destination")
set(PURE_DOCUMENTATION_INSTALL_DIR "share/doc/pure-gl" CACHE STRING "Relative documentation destination")
set(PURE_EXAMPLES_INSTALL_DIR "share/doc/pure-gl/examples" CACHE STRING "Relative examples destination")
if(NOT PURE_LIBRARY_INSTALL_DIR STREQUAL "lib/pure" OR
    NOT PURE_DOCUMENTATION_INSTALL_DIR STREQUAL "share/doc/pure-gl" OR
    NOT PURE_EXAMPLES_INSTALL_DIR STREQUAL "share/doc/pure-gl/examples")
  message(FATAL_ERROR "pure-gl installation requires the fixed audited package layout")
endif()
if(NOT WIN32 OR CMAKE_CONFIGURATION_TYPES)
  message(FATAL_ERROR "pure-gl installation requires a single-configuration Windows build")
endif()
set(version "${PROJECT_VERSION}")
string(TIMESTAMP today "%B %d, %Y")
configure_file("${CMAKE_CURRENT_SOURCE_DIR}/README" "${CMAKE_CURRENT_BINARY_DIR}/README" @ONLY NEWLINE_STYLE UNIX)
file(READ "${CMAKE_CURRENT_BINARY_DIR}/README" readme)
string(REPLACE "|today|" "${today}" readme "${readme}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/README" "${readme}")

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/PeHelpers.cmake")
set(GL_PE_POWERSHELL "${PURE_GL_WINDOWS_SYSTEM_DIRECTORY}/WindowsPowerShell/v1.0/powershell.exe")
set(FREEGLUT_RUNTIME_LICENSE "${PURE_GL_CLANG64_PREFIX}/share/licenses/freeglut/COPYING")
gl_pe_equal_path("${FREEGLUT_RUNTIME_DLL}" "${PURE_GL_CLANG64_PREFIX}/bin/libfreeglut.dll")
gl_pe_pin("${FREEGLUT_RUNTIME_DLL}" "a297e3b3fa824de6eb21285e23a409fbbf0bc573c60dd04c227bbc89d8398519")
gl_pe_pin("${FREEGLUT_RUNTIME_LICENSE}" "b6593d5ec4c113a274abb85b10e8615895cb0ddb89f7912af5fe5aa8df38a275")
if(NOT FREEGLUT_VERSION STREQUAL "3.8.0")
  message(FATAL_ERROR "The audited FreeGLUT runtime/license pair requires FreeGLUT 3.8.0")
endif()

# component|relative destination|canonical source|SHA256|project|version|URL|
# SPDX/license name|installed license. Only the linked module is sealed on build.
function(gl_install_artifact component destination source project version url license mapping)
  if(source STREQUAL "${CMAKE_CURRENT_BINARY_DIR}/pure-gl.dll")
    set(hash BUILD)
  else()
    gl_pe_path("${source}" file)
    file(SHA256 "${source}" hash)
  endif()
  string(APPEND GL_INSTALL_POLICY "${component}|${destination}|${source}|${hash}|${project}|${version}|${url}|${license}|${mapping}\n")
  set(GL_INSTALL_POLICY "${GL_INSTALL_POLICY}" PARENT_SCOPE)
endfunction()
function(gl_install_own component destination source)
  gl_install_artifact("${component}" "${destination}" "${source}" pure-gl
    "${PROJECT_VERSION}" "https://github.com/agraef/pure-lang/tree/master/pure-gl"
    BSD-3-Clause "share/doc/pure-gl/COPYING")
  set(GL_INSTALL_POLICY "${GL_INSTALL_POLICY}" PARENT_SCOPE)
endfunction()
gl_install_own(runtime lib/pure/pure-gl.dll "${CMAKE_CURRENT_BINARY_DIR}/pure-gl.dll")
foreach(name GL GL_ARB GL_EXT GL_NV GL_ATI GLU GLUT)
  gl_install_own(runtime "lib/pure/${name}.pure" "${CMAKE_CURRENT_SOURCE_DIR}/${name}.pure")
endforeach()
foreach(name README COPYING WINDOWS.md THIRD_PARTY.md)
  if(name STREQUAL README)
    set(source "${CMAKE_CURRENT_BINARY_DIR}/README")
  else()
    set(source "${CMAKE_CURRENT_SOURCE_DIR}/${name}")
  endif()
  gl_install_own(documentation "share/doc/pure-gl/${name}" "${source}")
endforeach()
foreach(name simple_glut_example.pure teapot.pure texture.pure Imlib2.pure fractal.jpg
    flexi-line/vector_math.pure flexi-line/glamour.pure flexi-line/flexi-line.pure
    flexi-line/flexi-line-auto.pure)
  gl_install_own(documentation "share/doc/pure-gl/examples/${name}" "${CMAKE_CURRENT_SOURCE_DIR}/examples/${name}")
endforeach()
foreach(name load hidden-render interactive)
  gl_install_own(documentation "share/doc/pure-gl/tests/${name}.pure" "${CMAKE_CURRENT_SOURCE_DIR}/tests/${name}.pure")
endforeach()
set(freeglut_url "https://github.com/FreeGLUTProject/freeglut/releases/download/v3.8.0/freeglut-3.8.0.tar.gz")
set(freeglut_mapping "share/doc/pure-gl/licenses/FreeGLUT.txt")
gl_install_artifact(runtime bin/libfreeglut.dll "${FREEGLUT_RUNTIME_DLL}"
  FreeGLUT 3.8.0 "${freeglut_url}" MIT "${freeglut_mapping}")
gl_install_artifact(documentation "${freeglut_mapping}" "${FREEGLUT_RUNTIME_LICENSE}"
  FreeGLUT 3.8.0 "${freeglut_url}" MIT "${freeglut_mapping}")

set(GL_INSTALL_CONTEXT "${CMAKE_CURRENT_BINARY_DIR}/pure-gl-install-context.cmake")
set(GL_INSTALL_INVENTORY "${CMAKE_CURRENT_BINARY_DIR}/pure-gl-install-inventory.tsv")
set(GL_INSTALL_BUILD_DIR "${CMAKE_CURRENT_BINARY_DIR}")
set(GL_INSTALL_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
set(GL_INSTALL_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyInstalledPackage.cmake")
set(GL_INSTALL_GUARD "${CMAKE_CURRENT_BINARY_DIR}/pure-gl-install-guard.exe")
set(GL_INSTALL_RUNNER "${CMAKE_CURRENT_BINARY_DIR}/pure-gl-test-runner.exe")
set(GL_INSTALL_BASELINE_PIN "${CMAKE_CURRENT_BINARY_DIR}/pure-gl-install-baseline.tsv")
set(GL_INSTALL_HELPERS_ONLY ON)
include("${GL_INSTALL_SCRIPT}")
unset(GL_INSTALL_HELPERS_ONLY)
install_tree("${PURE_GL_PURE_PREFIX}" baseline_rows)
string(REPLACE "\n" ";" configured_artifacts "${GL_INSTALL_POLICY}")
foreach(row IN LISTS configured_artifacts)
  if(row STREQUAL "")
    continue()
  endif()
  string(REPLACE "|" ";" fields "${row}")
  list(GET fields 1 destination)
  if(EXISTS "${PURE_GL_PURE_PREFIX}/${destination}")
    message(FATAL_ERROR "install audit: portable Pure baseline collides with ${destination}")
  endif()
endforeach()
list(JOIN baseline_rows "\n" GL_INSTALL_BASELINE_POLICY)
string(APPEND GL_INSTALL_BASELINE_POLICY "\n")
if(EXISTS "${GL_INSTALL_BASELINE_PIN}")
  gl_pe_no_reparse("${GL_INSTALL_BASELINE_PIN}")
  file(READ "${GL_INSTALL_BASELINE_PIN}" frozen)
  if(NOT frozen STREQUAL GL_INSTALL_BASELINE_POLICY)
    message(FATAL_ERROR "install audit: frozen portable baseline changed; use a fresh build")
  endif()
elseif(EXISTS "${GL_INSTALL_CONTEXT}" OR EXISTS "${GL_INSTALL_INVENTORY}")
  message(FATAL_ERROR "install audit: missing frozen portable baseline; use a fresh build")
else()
  file(CONFIGURE OUTPUT "${GL_INSTALL_BASELINE_PIN}" CONTENT "${GL_INSTALL_BASELINE_POLICY}" @ONLY NEWLINE_STYLE UNIX)
endif()
string(SHA256 GL_INSTALL_BASELINE_SHA256 "${GL_INSTALL_BASELINE_POLICY}")

# Configure output is authority; mutable TSVs are only data. The helper embeds
# this context's identity, path and verifier hash into its native image.
set(context "# Trusted pure-gl configure output.\n")
set(GL_INSTALL_TRUSTED_SOURCES)
foreach(path CMakeLists.txt cmake/Install.cmake cmake/VerifyInstalledPackage.cmake
    cmake/pure_gl_install_guard.c cmake/pure_gl_runner.c cmake/RunPureTest.cmake
    cmake/PeHelpers.cmake cmake/VerifyWindowsDependencies.cmake
    GL.c GL_ARB.c GL_EXT.c GL_NV.c GL_ATI.c GLU.c GLUT.c)
  file(SHA256 "${CMAKE_CURRENT_SOURCE_DIR}/${path}" hash)
  string(APPEND GL_INSTALL_TRUSTED_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/${path}|${hash}\n")
endforeach()
file(GLOB pe_fixtures "${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/*-imports.txt")
list(SORT pe_fixtures)
foreach(path IN LISTS pe_fixtures)
  file(SHA256 "${path}" hash)
  string(APPEND GL_INSTALL_TRUSTED_SOURCES "${path}|${hash}\n")
endforeach()
foreach(var GL_INSTALL_POLICY GL_INSTALL_INVENTORY GL_INSTALL_BUILD_DIR
    GL_INSTALL_SOURCE_DIR GL_INSTALL_SCRIPT GL_INSTALL_GUARD GL_INSTALL_RUNNER
    GL_INSTALL_BASELINE_PIN GL_INSTALL_BASELINE_SHA256 GL_INSTALL_BASELINE_POLICY
    GL_INSTALL_TRUSTED_SOURCES PURE_GL_PURE_PREFIX PURE_GL_CLANG64_PREFIX
    PURE_GL_WINDOWS_SYSTEM_DIRECTORY LLVM_READOBJ_EXECUTABLE LLVM_READOBJ_SHA256
    LLVM_STRINGS_EXECUTABLE LLVM_STRINGS_SHA256)
  string(APPEND context "set(${var} [==[${${var}}]==])\n")
endforeach()
file(CONFIGURE OUTPUT "${GL_INSTALL_CONTEXT}" CONTENT "${context}" @ONLY NEWLINE_STYLE UNIX)
file(SHA256 "${GL_INSTALL_CONTEXT}" GL_NATIVE_CONTEXT_HASH)
file(SHA256 "${GL_INSTALL_SCRIPT}" GL_NATIVE_SCRIPT_HASH)
gl_pe_path("${CMAKE_COMMAND}" file)
gl_pe_no_reparse("${CMAKE_COMMAND}")
file(SHA256 "${CMAKE_COMMAND}" GL_NATIVE_CMAKE_HASH)
set(header "/* Generated configure authority; never an installable payload. */\n")
foreach(pair BUILD_DIR SOURCE_DIR CONTEXT SCRIPT)
  string(APPEND header "#define GL_NATIVE_${pair} L\"${GL_INSTALL_${pair}}\"\n")
endforeach()
string(APPEND header "#define GL_NATIVE_CONTEXT_HASH L\"${GL_NATIVE_CONTEXT_HASH}\"\n#define GL_NATIVE_SCRIPT_HASH L\"${GL_NATIVE_SCRIPT_HASH}\"\n")
string(APPEND header "#define GL_NATIVE_CMAKE L\"${CMAKE_COMMAND}\"\n#define GL_NATIVE_CMAKE_HASH L\"${GL_NATIVE_CMAKE_HASH}\"\n")
string(APPEND header "#define GL_NATIVE_PURE_PREFIX L\"${PURE_GL_PURE_PREFIX}\"\n#define GL_NATIVE_CLANG64_PREFIX L\"${PURE_GL_CLANG64_PREFIX}\"\n#define GL_NATIVE_SYSTEM L\"${PURE_GL_WINDOWS_SYSTEM_DIRECTORY}\"\n")
file(CONFIGURE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/pure_gl_install_authority.h" CONTENT "${header}" @ONLY NEWLINE_STYLE UNIX)
add_executable(pure-gl-install-guard cmake/pure_gl_install_guard.c)
target_include_directories(pure-gl-install-guard PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")
target_compile_features(pure-gl-install-guard PRIVATE c_std_11)
target_compile_options(pure-gl-install-guard PRIVATE -Wall -Wextra -Werror)
target_link_libraries(pure-gl-install-guard PRIVATE bcrypt)
target_link_options(pure-gl-install-guard PRIVATE -municode)
add_custom_target(pure-gl-install-inventory ALL
  COMMAND "${CMAKE_COMMAND}" "-DGL_INSTALL_CONTEXT=${GL_INSTALL_CONTEXT}"
    -DGL_INSTALL_MODE=seal -P "${GL_INSTALL_SCRIPT}"
  DEPENDS pure-gl pure-gl-install-guard pure-gl-test-runner VERBATIM)

# Handle every component, including unknown ones, before CMake's unguarded
# conventional manifest write. Empty component and "all" select the exact union.
install(CODE "set(GL_INSTALL_CONTEXT [==[${GL_INSTALL_CONTEXT}]==])\nset(GL_INSTALL_MODE install)\nset(GL_INSTALL_COMPONENT \"\${CMAKE_INSTALL_COMPONENT}\")\nif(\"\${CMAKE_INSTALL_COMPONENT}\" STREQUAL \"\")\n  set(GL_INSTALL_COMPONENT all)\nendif()\nif(NOT GL_INSTALL_COMPONENT MATCHES \"^(runtime|documentation|all)$\")\n  message(FATAL_ERROR \"install audit: unknown component\")\nendif()\nset(STAGE_PREFIX \"\${CMAKE_INSTALL_PREFIX}\")\ninclude([==[${GL_INSTALL_SCRIPT}]==])\nreturn()" ALL_COMPONENTS)

if(BUILD_TESTING)
  foreach(test install-contract install-guard-contract)
    string(REPLACE "-" "_" script "${test}")
    add_test(NAME "pure-gl-${test}" COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}" "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DPURE_PREFIX=${PURE_GL_PURE_PREFIX}" "-DCLANG64_PREFIX=${PURE_GL_CLANG64_PREFIX}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/${script}.cmake")
    set_tests_properties("pure-gl-${test}" PROPERTIES LABELS "gl;contract;install"
      TIMEOUT 900 RUN_SERIAL TRUE)
  endforeach()
endif()
