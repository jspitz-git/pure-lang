cmake_minimum_required(VERSION 3.25)
# Runs after linking, before compiling the native authority. Verification never
# invokes this producer: its exact output and artifact hashes live in the guard.
file(SHA256 "${MODULE}" module_hash)
file(SHA256 "${RUNNER}" runner_hash)
set(seal "${BUILD_DIR}/pure-gl-built-authority.cmake")
file(CONFIGURE OUTPUT "${seal}" CONTENT
  "set(GL_INSTALL_MODULE_SHA256 ${module_hash})\nset(GL_INSTALL_RUNNER_SHA256 ${runner_hash})\n" @ONLY NEWLINE_STYLE UNIX)
file(SHA256 "${seal}" seal_hash)
set(header "/* Completed build authority, embedded in the native owner. */\n")
foreach(pair MODULE RUNNER)
  string(TOLOWER "${pair}" lower)
  string(APPEND header "#define GL_NATIVE_${pair} L\"${${pair}}\"\n#define GL_NATIVE_${pair}_HASH L\"${${lower}_hash}\"\n")
endforeach()
string(APPEND header "#define GL_NATIVE_BUILT_SEAL L\"${seal}\"\n#define GL_NATIVE_BUILT_SEAL_HASH L\"${seal_hash}\"\n")
file(CONFIGURE OUTPUT "${BUILD_DIR}/pure_gl_built_authority.h" CONTENT "${header}" @ONLY NEWLINE_STYLE UNIX)
