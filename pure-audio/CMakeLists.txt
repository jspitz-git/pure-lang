cmake_minimum_required(VERSION 3.25)

option(PURE_AUDIO_STRICT_WINDOWS_AUDIT "Require the explicit audited Windows toolchain and PE closure" OFF)
if(PURE_AUDIO_STRICT_WINDOWS_AUDIT)
  if(NOT CMAKE_HOST_WIN32 OR NOT CMAKE_GENERATOR STREQUAL "Ninja")
    message(FATAL_ERROR "audio audit: strict Windows audit requires native Windows and Ninja")
  endif()
  set(PURE_AUDIO_VERIFIER_HELPERS_ONLY ON)
  include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake")
  unset(PURE_AUDIO_VERIFIER_HELPERS_ONLY)
  set(audit_directories PURE_AUDIO_CLANG64_PREFIX PURE_AUDIO_PURE_PREFIX
    PURE_AUDIO_WINDOWS_SYSTEM_DIRECTORY PURE_INCLUDE_DIR)
  set(audit_files CMAKE_C_COMPILER CMAKE_MAKE_PROGRAM PKG_CONFIG_EXECUTABLE
    LLVM_READOBJ PURE_EXECUTABLE PURE_HEADER PURE_IMPORT_LIBRARY PURE_RUNTIME_DLL
    PORTAUDIO_HEADER PORTAUDIO_IMPORT_LIBRARY FFTW_HEADER FFTW_IMPORT_LIBRARY
    SAMPLERATE_HEADER SAMPLERATE_IMPORT_LIBRARY SNDFILE_HEADER SNDFILE_IMPORT_LIBRARY
    PTHREAD_HEADER PTHREAD_IMPORT_LIBRARY GMP_HEADER MPFR_HEADER
    PURE_AUDIO_WINDOWS_HEADER PURE_AUDIO_MAKE_EXECUTABLE PURE_AUDIO_SH_EXECUTABLE)
  foreach(var IN LISTS audit_directories audit_files)
    if(NOT DEFINED ${var} OR "${${var}}" STREQUAL "")
      message(FATAL_ERROR "audio audit: explicit ${var} is required (no environment fallback)")
    endif()
    if(var IN_LIST audit_directories)
      audio_path("${${var}}" directory canonical)
    else()
      audio_path("${${var}}" file canonical)
    endif()
    set(${var} "${canonical}" CACHE STRING "Explicit immutable audit input" FORCE)
    list(APPEND audit_paths "${canonical}")
  endforeach()
  if(NOT DEFINED PURE_AUDIO_RUNTIME_SOURCES OR "${PURE_AUDIO_RUNTIME_SOURCES}" STREQUAL "")
    message(FATAL_ERROR "audio audit: explicit PURE_AUDIO_RUNTIME_SOURCES is required")
  endif()
  audio_windows_authority()
  set(expected_CMAKE_C_COMPILER "${PURE_AUDIO_CLANG64_PREFIX}/bin/clang.exe")
  set(expected_CMAKE_MAKE_PROGRAM "${PURE_AUDIO_CLANG64_PREFIX}/bin/ninja.exe")
  set(expected_PKG_CONFIG_EXECUTABLE "${PURE_AUDIO_CLANG64_PREFIX}/bin/pkgconf.exe")
  set(expected_LLVM_READOBJ "${PURE_AUDIO_CLANG64_PREFIX}/bin/llvm-readobj.exe")
  set(expected_PURE_EXECUTABLE "${PURE_AUDIO_PURE_PREFIX}/bin/pure.exe")
  set(expected_PURE_HEADER "${PURE_AUDIO_PURE_PREFIX}/include/pure/runtime.h")
  set(expected_PURE_INCLUDE_DIR "${PURE_AUDIO_PURE_PREFIX}/include")
  set(expected_PURE_IMPORT_LIBRARY "${PURE_AUDIO_PURE_PREFIX}/lib/libpure.dll.a")
  set(expected_PURE_RUNTIME_DLL "${PURE_AUDIO_PURE_PREFIX}/bin/libpure.dll")
  set(expected_PORTAUDIO_HEADER "${PURE_AUDIO_CLANG64_PREFIX}/include/portaudio.h")
  set(expected_PORTAUDIO_IMPORT_LIBRARY "${PURE_AUDIO_CLANG64_PREFIX}/lib/libportaudio.dll.a")
  set(expected_FFTW_HEADER "${PURE_AUDIO_CLANG64_PREFIX}/include/fftw3.h")
  set(expected_FFTW_IMPORT_LIBRARY "${PURE_AUDIO_CLANG64_PREFIX}/lib/libfftw3.dll.a")
  set(expected_SAMPLERATE_HEADER "${PURE_AUDIO_CLANG64_PREFIX}/include/samplerate.h")
  set(expected_SAMPLERATE_IMPORT_LIBRARY "${PURE_AUDIO_CLANG64_PREFIX}/lib/libsamplerate.dll.a")
  set(expected_SNDFILE_HEADER "${PURE_AUDIO_CLANG64_PREFIX}/include/sndfile.h")
  set(expected_SNDFILE_IMPORT_LIBRARY "${PURE_AUDIO_CLANG64_PREFIX}/lib/libsndfile.dll.a")
  set(expected_PTHREAD_HEADER "${PURE_AUDIO_CLANG64_PREFIX}/include/pthread.h")
  set(expected_PTHREAD_IMPORT_LIBRARY "${PURE_AUDIO_CLANG64_PREFIX}/lib/libpthread.dll.a")
  set(expected_GMP_HEADER "${PURE_AUDIO_CLANG64_PREFIX}/include/gmp.h")
  set(expected_MPFR_HEADER "${PURE_AUDIO_CLANG64_PREFIX}/include/mpfr.h")
  set(expected_PURE_AUDIO_WINDOWS_HEADER "${PURE_AUDIO_CLANG64_PREFIX}/include/windows.h")
  set(expected_PURE_AUDIO_MAKE_EXECUTABLE "${PURE_AUDIO_CLANG64_PREFIX}/bin/mingw32-make.exe")
  set(expected_PURE_AUDIO_SH_EXECUTABLE "${PURE_AUDIO_CLANG64_PREFIX}/../usr/bin/sh.exe")
  cmake_path(NORMAL_PATH expected_PURE_AUDIO_SH_EXECUTABLE)
  foreach(var IN LISTS audit_files)
    audio_equal_path("${${var}}" "${expected_${var}}")
  endforeach()
  audio_equal_path("${PURE_INCLUDE_DIR}" "${expected_PURE_INCLUDE_DIR}")
  audio_runtime_rows("${PURE_AUDIO_RUNTIME_SOURCES}" FALSE runtime_paths runtime_manifest)
  audio_no_reparse(${audit_paths} ${runtime_paths})
  # Check every configuration, not only the selected one. Cache values survive
  # reconfigure, so permit exactly our fixed defaults and reject unknown suffixes.
  set(audit_flag_names CMAKE_C_FLAGS CMAKE_C_STANDARD_LIBRARIES)
  # This applies during CMake probes as well as generated compile/link rules.
  set(audit_CMAKE_C_FLAGS "--no-default-config")
  set(audit_CMAKE_C_STANDARD_LIBRARIES "-lkernel32 -luser32 -lgdi32 -lwinspool -lshell32 -lole32 -loleaut32 -luuid -lcomdlg32 -ladvapi32")
  foreach(config DEBUG RELEASE RELWITHDEBINFO MINSIZEREL)
    list(APPEND audit_flag_names "CMAKE_C_FLAGS_${config}")
  endforeach()
  set(audit_CMAKE_C_FLAGS_DEBUG "-g")
  set(audit_CMAKE_C_FLAGS_RELEASE "-O3 -DNDEBUG")
  set(audit_CMAKE_C_FLAGS_RELWITHDEBINFO "-O2 -g -DNDEBUG")
  set(audit_CMAKE_C_FLAGS_MINSIZEREL "-Os -DNDEBUG")
  foreach(kind EXE SHARED MODULE STATIC)
    list(APPEND audit_flag_names "CMAKE_${kind}_LINKER_FLAGS")
    set(audit_CMAKE_${kind}_LINKER_FLAGS "")
    foreach(config DEBUG RELEASE RELWITHDEBINFO MINSIZEREL)
      list(APPEND audit_flag_names "CMAKE_${kind}_LINKER_FLAGS_${config}")
      set(audit_CMAKE_${kind}_LINKER_FLAGS_${config} "")
    endforeach()
  endforeach()
  get_cmake_property(audit_variables VARIABLES)
  foreach(var IN LISTS audit_variables)
    if(var MATCHES "^CMAKE_(C_FLAGS|C_STANDARD_LIBRARIES|EXE_LINKER_FLAGS|SHARED_LINKER_FLAGS|MODULE_LINKER_FLAGS|STATIC_LINKER_FLAGS)(_|$)" AND
        NOT var MATCHES "-ADVANCED$")
      if(NOT var IN_LIST audit_flag_names OR NOT "${${var}}" STREQUAL "${audit_${var}}")
        message(FATAL_ERROR "audio audit: undeclared flags ${var}")
      endif()
    elseif(var MATCHES "^CMAKE_(TOOLCHAIN_FILE|SYSROOT|C_COMPILER_ARG1|C_COMPILER_EXTERNAL_TOOLCHAIN|C_COMPILER_LAUNCHER|C_LINKER_LAUNCHER|C_STANDARD_INCLUDE_DIRECTORIES|C_STANDARD_LIBRARIES|C_LINK_EXECUTABLE|C_CREATE_SHARED_LIBRARY|C_CREATE_SHARED_MODULE|C_CREATE_STATIC_LIBRARY|C_COMPILE_OBJECT|LINKER_TYPE|INTERPROCEDURAL_OPTIMIZATION|USER_MAKE_RULES_OVERRIDE)(_|$)" OR
        var MATCHES "^CMAKE_PROJECT_.*INCLUDE")
      if(NOT "${${var}}" STREQUAL "")
        message(FATAL_ERROR "audio audit: undeclared toolchain override ${var}")
      endif()
    endif()
  endforeach()
  foreach(var IN LISTS audit_flag_names)
    set(${var} "${audit_${var}}" CACHE STRING "Fixed strict audit flags" FORCE)
  endforeach()
  if(NOT DEFINED CMAKE_BUILD_TYPE OR CMAKE_BUILD_TYPE STREQUAL "")
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Strict audit configuration" FORCE)
  endif()
  string(TOUPPER "${CMAKE_BUILD_TYPE}" audit_config)
  if(NOT audit_config MATCHES "^(DEBUG|RELEASE|RELWITHDEBINFO|MINSIZEREL)$")
    message(FATAL_ERROR "audio audit: undeclared build configuration ${CMAKE_BUILD_TYPE}")
  endif()
  foreach(property RULE_LAUNCH_COMPILE RULE_LAUNCH_LINK)
    get_property(value GLOBAL PROPERTY "${property}")
    if(value)
      message(FATAL_ERROR "audio audit: undeclared rule launcher ${property}")
    endif()
  endforeach()
  if(DEFINED CMAKE_CONFIGURATION_TYPES AND NOT CMAKE_CONFIGURATION_TYPES STREQUAL "")
    message(FATAL_ERROR "audio audit: multi-configuration overrides are not allowed")
  endif()
  if(DEFINED CMAKE_C_COMPILER_TARGET AND NOT CMAKE_C_COMPILER_TARGET STREQUAL "x86_64-w64-windows-gnu")
    message(FATAL_ERROR "audio audit: wrong compiler target override")
  endif()
  set(CMAKE_C_COMPILER_TARGET "x86_64-w64-windows-gnu" CACHE STRING "Audited target" FORCE)
  # Freeze all ambient discovery used by compiler probes and legacy install
  # metadata. Strict library targets below use only explicit headers/libraries.
  set(ENV{PATH} "${PURE_AUDIO_PURE_PREFIX}/bin;${PURE_AUDIO_CLANG64_PREFIX}/bin;${AUDIO_SYSTEM_DIR}")
  set(ENV{MSYSTEM_PREFIX} "${PURE_AUDIO_CLANG64_PREFIX}")
  set(ENV{PKG_CONFIG_PATH} "")
  set(ENV{PKG_CONFIG_LIBDIR} "${PURE_AUDIO_PURE_PREFIX}/lib/pkgconfig;${PURE_AUDIO_CLANG64_PREFIX}/lib/pkgconfig")
  set(audit_clear_environment PURELIB PURE_INCLUDE PURE_LIBRARY CC CFLAGS CPPFLAGS LDFLAGS
    CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH LIBRARY_PATH COMPILER_PATH
    GCC_EXEC_PREFIX INCLUDE LIB LIBPATH CL _CL_ LINK _LINK_ CCC_OVERRIDE_OPTIONS
    CCC_ADD_ARGS SDKROOT DEVELOPER_DIR MACOSX_DEPLOYMENT_TARGET
    CLANG_CONFIG_FILE_SYSTEM_DIR CLANG_CONFIG_FILE_USER_DIR)
  foreach(var IN LISTS audit_clear_environment)
    unset(ENV{${var}})
  endforeach()
  foreach(tool CMAKE_C_COMPILER CMAKE_MAKE_PROGRAM PKG_CONFIG_EXECUTABLE LLVM_READOBJ PURE_EXECUTABLE)
    set(version_arguments --version)
    if(tool STREQUAL "CMAKE_C_COMPILER")
      list(PREPEND version_arguments --no-default-config)
    endif()
    execute_process(COMMAND "${${tool}}" ${version_arguments} RESULT_VARIABLE rc
      OUTPUT_VARIABLE version ERROR_VARIABLE err TIMEOUT 30)
    if(NOT rc EQUAL 0 OR NOT err STREQUAL "")
      message(FATAL_ERROR "audio audit: cannot identify ${tool}: ${rc} ${err}")
    endif()
    if(tool STREQUAL "CMAKE_C_COMPILER" AND
        NOT version MATCHES "^clang version 22\\.[0-9]+\\.[0-9]+")
      message(FATAL_ERROR "audio audit: Clang major 22 required: ${version}")
    elseif(tool STREQUAL "LLVM_READOBJ" AND NOT version MATCHES "LLVM version 22\\.")
      message(FATAL_ERROR "audio audit: llvm-readobj major 22 required")
    elseif(tool STREQUAL "PURE_EXECUTABLE" AND NOT version MATCHES "[Pp]ure 0\\.68([^0-9]|$)")
      message(FATAL_ERROR "audio audit: Pure 0.68 required: ${version}")
    endif()
    string(STRIP "${version}" version)
    message(STATUS "audio audit: ${tool}: ${version}")
  endforeach()
  execute_process(COMMAND "${CMAKE_C_COMPILER}" --no-default-config -dumpmachine RESULT_VARIABLE rc
    OUTPUT_VARIABLE triple ERROR_VARIABLE err OUTPUT_STRIP_TRAILING_WHITESPACE)
  if(NOT rc EQUAL 0 OR NOT err STREQUAL "" OR NOT triple STREQUAL "x86_64-w64-windows-gnu")
    message(FATAL_ERROR "audio audit: Clang target must be x86_64-w64-windows-gnu: ${triple}")
  endif()
  foreach(var IN LISTS audit_files)
    if(var MATCHES "_IMPORT_LIBRARY$")
      audio_import_library("${${var}}")
    endif()
  endforeach()
  foreach(path IN LISTS runtime_paths)
    audio_inspect_pe("${path}" unused_imports)
  endforeach()
  # A generated Ninja rule must clear its own environment: configure-time
  # set(ENV) cannot affect a later cmake --build process. Use the declared
  # prefix's pinned CMake executable as both compiler and linker launcher;
  # the actual compiler command remains the validated absolute clang.exe.
  audio_path("${PURE_AUDIO_CLANG64_PREFIX}/bin/cmake.exe" file audit_launcher_tool)
  audio_no_reparse("${audit_launcher_tool}")
  file(SHA256 "${audit_launcher_tool}" audit_launcher_hash)
  set(audit_launcher "${audit_launcher_tool};-E;env")
  foreach(var IN LISTS audit_clear_environment)
    list(APPEND audit_launcher "--unset=${var}")
  endforeach()
  string(REPLACE ";" "\\;" audit_path_argument "PATH=$ENV{PATH}")
  list(APPEND audit_launcher "${audit_path_argument}" --)
  set(CMAKE_C_COMPILER_LAUNCHER "${audit_launcher}")
  set(CMAKE_C_LINKER_LAUNCHER "${audit_launcher}")
  set(audit_pin "${runtime_manifest}${audit_launcher}\n${audit_launcher_hash}\n${audit_config}\n")
  foreach(var IN LISTS audit_flag_names)
    string(APPEND audit_pin "${var}|${${var}}\n")
  endforeach()
  foreach(var IN LISTS audit_files audit_directories)
    string(APPEND audit_pin "${var}|${${var}}\n")
    if(var IN_LIST audit_files)
      file(SHA256 "${${var}}" hash)
      string(APPEND audit_pin "${hash}\n")
    endif()
  endforeach()
  string(SHA256 audit_pin "${audit_pin}")
  if(DEFINED PURE_AUDIO_CONFIGURED_INPUT_PIN AND NOT PURE_AUDIO_CONFIGURED_INPUT_PIN STREQUAL audit_pin)
    message(FATAL_ERROR "audio audit: configured inputs changed; use a fresh audit build directory")
  endif()
  set(PURE_AUDIO_CONFIGURED_INPUT_PIN "${audit_pin}" CACHE INTERNAL "Frozen audit inputs")
  set(PURE_AUDIO_RUNTIME_MANIFEST "${CMAKE_CURRENT_BINARY_DIR}/windows-runtime-sources.txt")
  file(SHA256 "${LLVM_READOBJ}" PURE_AUDIO_LLVM_READOBJ_SHA256)
  set(PURE_AUDIO_LLVM_READOBJ_SHA256 "${PURE_AUDIO_LLVM_READOBJ_SHA256}" CACHE INTERNAL "Configured inspection tool hash")
  file(WRITE "${PURE_AUDIO_RUNTIME_MANIFEST}" "${runtime_manifest}")
endif()

project(pure-audio VERSION 0.6 LANGUAGES C)

if(PURE_AUDIO_STRICT_WINDOWS_AUDIT)
  set(PURE_PREFIX "${PURE_AUDIO_PURE_PREFIX}")
  foreach(package PURE PORTAUDIO FFTW SAMPLERATE SNDFILE)
    add_library(PkgConfig::${package} INTERFACE IMPORTED)
    if(package STREQUAL "PURE")
      set(include_dir "${PURE_INCLUDE_DIR}")
    else()
      get_filename_component(include_dir "${${package}_HEADER}" DIRECTORY)
    endif()
    set_target_properties(PkgConfig::${package} PROPERTIES
      INTERFACE_INCLUDE_DIRECTORIES "${include_dir}"
      INTERFACE_LINK_LIBRARIES "${${package}_IMPORT_LIBRARY}")
  endforeach()
  add_library(Threads::Threads INTERFACE IMPORTED)
  set_target_properties(Threads::Threads PROPERTIES
    INTERFACE_LINK_LIBRARIES "${PTHREAD_IMPORT_LIBRARY}")
else()
  find_package(PkgConfig REQUIRED)
  find_package(Threads REQUIRED)
  pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
  pkg_check_modules(PORTAUDIO REQUIRED IMPORTED_TARGET portaudio-2.0)
  pkg_check_modules(FFTW REQUIRED IMPORTED_TARGET fftw3)
  pkg_check_modules(SAMPLERATE REQUIRED IMPORTED_TARGET samplerate)
  pkg_check_modules(SNDFILE REQUIRED IMPORTED_TARGET sndfile)
endif()

function(add_pure_audio_module target source)
  add_library(${target} MODULE "${source}")
  target_compile_features(${target} PRIVATE c_std_11)
  target_link_libraries(${target} PRIVATE PkgConfig::PURE)
  if(MINGW)
    target_compile_options(${target} PRIVATE -Wall -Wextra -Werror)
    target_link_options(${target} PRIVATE "LINKER:--enable-auto-import")
  endif()
  set_target_properties(
    ${target}
    PROPERTIES
      PREFIX ""
      WINDOWS_EXPORT_ALL_SYMBOLS ON
  )
endfunction()

add_pure_audio_module(audio audio.c)
target_link_libraries(audio PRIVATE PkgConfig::PORTAUDIO Threads::Threads)

add_pure_audio_module(fftw fftw/fftw.c)
target_link_libraries(fftw PRIVATE PkgConfig::FFTW)

add_pure_audio_module(srcprocess samplerate/srcprocess.c)
target_link_libraries(srcprocess PRIVATE PkgConfig::SAMPLERATE)

add_pure_audio_module(sfinfo sndfile/sfinfo.c)
target_link_libraries(sfinfo PRIVATE PkgConfig::SNDFILE)

add_pure_audio_module(realtime realtime/realtime.c)
target_link_libraries(realtime PRIVATE Threads::Threads)

if(WIN32)
  set(AUDIO_RUNTIME_FILENAMES
    libportaudio.dll
    libfftw3-3.dll
    libsamplerate-0.dll
    libsndfile-1.dll
    libogg-0.dll
    libvorbisenc-2.dll
    libFLAC.dll
    libopus-0.dll
    libmpg123-0.dll
    libmp3lame-0.dll
    libvorbis-0.dll
    libwinpthread-1.dll
    libc++.dll
  )
  foreach(runtime_file IN LISTS AUDIO_RUNTIME_FILENAMES)
    string(MAKE_C_IDENTIFIER "${runtime_file}" runtime_id)
    string(TOUPPER "${runtime_id}" runtime_id)
    if(PURE_AUDIO_STRICT_WINDOWS_AUDIT)
      if(runtime_file MATCHES "^(libc\\+\\+|libwinpthread-1)\\.dll$")
        set("AUDIO_RUNTIME_${runtime_id}" "${PURE_AUDIO_PURE_PREFIX}/bin/${runtime_file}")
      else()
        set("AUDIO_RUNTIME_${runtime_id}" "${PURE_AUDIO_CLANG64_PREFIX}/bin/${runtime_file}")
      endif()
    else()
      find_file(
      "AUDIO_RUNTIME_${runtime_id}"
      NAMES "${runtime_file}"
      HINTS "$ENV{MSYSTEM_PREFIX}/bin"
      NO_DEFAULT_PATH
      REQUIRED
    )
    endif()
  endforeach()
  if(PURE_AUDIO_STRICT_WINDOWS_AUDIT)
  add_custom_target(
    verify-windows-dependencies
    COMMAND "${CMAKE_COMMAND}"
      "-DLLVM_READOBJ=${LLVM_READOBJ}"
      "-DPURE_AUDIO_LLVM_READOBJ_SHA256=${PURE_AUDIO_LLVM_READOBJ_SHA256}"
      "-DAUDIO_MODULE_DIR=$<TARGET_FILE_DIR:audio>"
      "-DPURE_AUDIO_CLANG64_PREFIX=${PURE_AUDIO_CLANG64_PREFIX}"
      "-DPURE_AUDIO_PURE_PREFIX=${PURE_AUDIO_PURE_PREFIX}"
      "-DPURE_AUDIO_WINDOWS_SYSTEM_DIRECTORY=${PURE_AUDIO_WINDOWS_SYSTEM_DIRECTORY}"
      "-DPURE_AUDIO_RUNTIME_MANIFEST=${PURE_AUDIO_RUNTIME_MANIFEST}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
    DEPENDS audio fftw srcprocess sfinfo realtime
    COMMENT "Verifying the pure-audio Windows dependency closure"
    VERBATIM
  )
  endif()
endif()

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/Install.cmake")

include(CTest)
if(BUILD_TESTING)
  set(PURE_AUDIO_SNDFILE_INT64_SIGNATURES
    "int64 sf_seek(SNDFILE*, int64, int)"
    "int64 sf_read_raw(SNDFILE*, void*, int64)"
    "int64 sf_write_raw(SNDFILE*, void*, int64)"
    "int64 sf_readf_short(SNDFILE*, short*, int64)"
    "int64 sf_writef_short(SNDFILE*, short*, int64)"
    "int64 sf_readf_int(SNDFILE*, int*, int64)"
    "int64 sf_writef_int(SNDFILE*, int*, int64)"
    "int64 sf_readf_float(SNDFILE*, float*, int64)"
    "int64 sf_writef_float(SNDFILE*, float*, int64)"
    "int64 sf_readf_double(SNDFILE*, double*, int64)"
    "int64 sf_writef_double(SNDFILE*, double*, int64)"
    "int64 sf_read_short(SNDFILE*, short*, int64)"
    "int64 sf_write_short(SNDFILE*, short*, int64)"
    "int64 sf_read_int(SNDFILE*, int*, int64)"
    "int64 sf_write_int(SNDFILE*, int*, int64)"
    "int64 sf_read_float(SNDFILE*, float*, int64)"
    "int64 sf_write_float(SNDFILE*, float*, int64)"
    "int64 sf_read_double(SNDFILE*, double*, int64)"
    "int64 sf_write_double(SNDFILE*, double*, int64)"
  )
  file(READ "${CMAKE_CURRENT_SOURCE_DIR}/sndfile/sndfile.pure"
       sndfile_pure_source)
  foreach(signature IN LISTS PURE_AUDIO_SNDFILE_INT64_SIGNATURES)
    string(FIND "${sndfile_pure_source}" "extern ${signature};"
           signature_offset)
    if(signature_offset EQUAL -1)
      message(FATAL_ERROR
        "sndfile.pure ABI regression: expected 'extern ${signature};'")
    endif()
  endforeach()
  string(REGEX MATCHALL
    "extern[ \t]+(int|int64)[ \t]+sf_(seek|read_raw|write_raw|readf_short|writef_short|readf_int|writef_int|readf_float|writef_float|readf_double|writef_double|read_short|write_short|read_int|write_int|read_float|write_float|read_double|write_double)\\([^;]*\\)"
    sndfile_count_declarations "${sndfile_pure_source}")
  list(LENGTH sndfile_count_declarations sndfile_count_declaration_count)
  if(NOT sndfile_count_declaration_count EQUAL 19)
    message(FATAL_ERROR
      "sndfile.pure ABI regression: expected exactly 19 sf_count_t declarations, found ${sndfile_count_declaration_count}")
  endif()

  if(NOT PURE_AUDIO_STRICT_WINDOWS_AUDIT)
    pkg_get_variable(PURE_PREFIX pure prefix)
  endif()
  set(PURE_AUDIO_COMPILER_RUNTIME_PATH "")
  if(MINGW AND CMAKE_C_COMPILER_ID MATCHES "Clang")
    set(resource_arguments --print-resource-dir)
    if(PURE_AUDIO_STRICT_WINDOWS_AUDIT)
      list(PREPEND resource_arguments --no-default-config)
    endif()
    execute_process(
      COMMAND "${CMAKE_C_COMPILER}" ${resource_arguments}
      RESULT_VARIABLE compiler_resource_result
      OUTPUT_VARIABLE compiler_resource_dir
      OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    if(compiler_resource_result EQUAL 0 AND
       EXISTS "${compiler_resource_dir}/lib/windows")
      set(PURE_AUDIO_COMPILER_RUNTIME_PATH
        "${compiler_resource_dir}/lib/windows\;")
    endif()
  endif()
  set(
    PURE_AUDIO_TEST_RUNTIME_PATH
    "${PURE_PREFIX}/bin\;${PURE_AUDIO_COMPILER_RUNTIME_PATH}$ENV{MSYSTEM_PREFIX}/bin\;$ENV{SystemRoot}/System32\;$ENV{SystemRoot}"
  )
  if(PURE_AUDIO_STRICT_WINDOWS_AUDIT)
    get_filename_component(audio_windows_root "${AUDIO_SYSTEM_DIR}" DIRECTORY)
    set(PURE_AUDIO_TEST_RUNTIME_PATH
      "${PURE_PREFIX}/bin\\;${PURE_AUDIO_COMPILER_RUNTIME_PATH}${PURE_AUDIO_CLANG64_PREFIX}/bin\\;${AUDIO_SYSTEM_DIR}\\;${audio_windows_root}")
  endif()

  string(REPLACE "\\;" ";" PURE_AUDIO_RUNNER_RUNTIME_DIRS
    "${PURE_AUDIO_TEST_RUNTIME_PATH}")

  add_executable(audio_fault_harness tests/audio_fault_harness.c)
  target_compile_features(audio_fault_harness PRIVATE c_std_11)
  target_link_libraries(
    audio_fault_harness
    PRIVATE PkgConfig::PURE PkgConfig::PORTAUDIO PkgConfig::SNDFILE
            Threads::Threads
  )
  if(MINGW)
    target_compile_options(audio_fault_harness PRIVATE -Wall -Wextra -Werror)
  endif()
  add_test(NAME pure-audio-fault-bounds COMMAND audio_fault_harness)
  set_tests_properties(
    pure-audio-fault-bounds
    PROPERTIES
      LABELS "audio;fault;bounds;no-hardware"
      ENVIRONMENT "PATH=${PURE_AUDIO_TEST_RUNTIME_PATH}"
      ENVIRONMENT_MODIFICATION "PURELIB=unset:;PURE_INCLUDE=unset:;PURE_LIBRARY=unset:"
      # Real Pure sentry aliases require interpreter startup; the ASan runtime
      # alone brings this harness close to 30 seconds on Windows.
      TIMEOUT 90
  )

  add_pure_audio_module(audio_bounds_seam tests/audio_fault_harness.c)
  target_link_libraries(
    audio_bounds_seam PRIVATE PkgConfig::PORTAUDIO PkgConfig::SNDFILE
                              Threads::Threads
  )
  set_target_properties(
    audio_bounds_seam
    PROPERTIES
      OUTPUT_NAME audio
      LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/bounds-modules"
      RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/bounds-modules"
  )
  add_dependencies(audio_bounds_seam fftw srcprocess sfinfo)
  add_custom_command(
    TARGET audio_bounds_seam POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
      "$<TARGET_FILE:fftw>"
      "$<TARGET_FILE:srcprocess>"
      "$<TARGET_FILE:sfinfo>"
      "$<TARGET_FILE_DIR:audio_bounds_seam>"
    VERBATIM
  )
  foreach(bounds_dependency IN ITEMS fftw srcprocess sfinfo)
    add_custom_command(
      TARGET "${bounds_dependency}" POST_BUILD
      COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "$<TARGET_FILE:${bounds_dependency}>"
        "$<TARGET_FILE_DIR:audio_bounds_seam>"
      VERBATIM
    )
  endforeach()

  # Native Windows launch/cleanup contracts; other platforms retain the fault harness.
  if(WIN32)
    add_executable(run_pure_test tests/run_pure_test.c)
    add_executable(run_pure_fixture tests/run_pure_test.c)
    target_compile_definitions(run_pure_fixture PRIVATE PURE_AUDIO_RUNNER_FIXTURE)
    target_link_libraries(run_pure_test PRIVATE bcrypt)
    target_link_options(run_pure_test PRIVATE -municode)
    foreach(runner_target run_pure_test run_pure_fixture)
      target_compile_features(${runner_target} PRIVATE c_std_11)
      target_compile_options(${runner_target} PRIVATE -Wall -Wextra -Werror -fno-sanitize=all)
      target_link_options(${runner_target} PRIVATE -fno-sanitize=all)
    endforeach()
    find_program(
      PURE_EXECUTABLE
      NAMES pure
      HINTS "${PURE_PREFIX}/bin"
      NO_DEFAULT_PATH
      REQUIRED
    )
    add_test(
      NAME pure-audio-load
      COMMAND "${CMAKE_COMMAND}"
        "-DPURE_AUDIO_RUNNER=$<TARGET_FILE:run_pure_test>"
        "-DRUNTIME_DIRS=${PURE_AUDIO_RUNNER_RUNTIME_DIRS}"
        "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
        "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
        "-DMODULE_DIR=$<TARGET_FILE_DIR:audio>"
        "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/load.pure"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake"
    )
    set_tests_properties(
      pure-audio-load
      PROPERTIES
        LABELS "audio;load;no-hardware"
        REQUIRED_FILES
          "$<TARGET_FILE:audio>;$<TARGET_FILE:fftw>;$<TARGET_FILE:srcprocess>;$<TARGET_FILE:sfinfo>;$<TARGET_FILE:realtime>"
        TIMEOUT 45
    )
    add_test(
      NAME pure-audio-processing
      COMMAND "${CMAKE_COMMAND}"
        "-DPURE_AUDIO_RUNNER=$<TARGET_FILE:run_pure_test>"
        "-DRUNTIME_DIRS=${PURE_AUDIO_RUNNER_RUNTIME_DIRS}"
        "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
        "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
        "-DMODULE_DIR=$<TARGET_FILE_DIR:audio>"
        "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake"
    )
    set_tests_properties(
      pure-audio-processing
      PROPERTIES
        LABELS "audio;fftw;samplerate;sndfile;realtime;no-hardware"
        REQUIRED_FILES "${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
        TIMEOUT 60
    )
    add_test(
      NAME pure-audio-public-bounds
      COMMAND "${CMAKE_COMMAND}"
        "-DPURE_AUDIO_RUNNER=$<TARGET_FILE:run_pure_test>"
        "-DRUNTIME_DIRS=${PURE_AUDIO_RUNNER_RUNTIME_DIRS}"
        "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
        "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
        "-DMODULE_DIR=$<TARGET_FILE_DIR:audio_bounds_seam>"
        "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/bounds.pure"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake"
    )
    set_tests_properties(
      pure-audio-public-bounds
      PROPERTIES
        LABELS "audio;fftw;samplerate;sndfile;bounds;no-hardware"
        REQUIRED_FILES
          "$<TARGET_FILE:audio_bounds_seam>;${CMAKE_CURRENT_SOURCE_DIR}/tests/bounds.pure"
        TIMEOUT 60
    )
    foreach(mode IN ITEMS playback capture)
      add_custom_target(
        "check-audio-${mode}"
        COMMAND "${CMAKE_COMMAND}"
          "-DPURE_AUDIO_RUNNER=$<TARGET_FILE:run_pure_test>"
          "-DRUNTIME_DIRS=${PURE_AUDIO_RUNNER_RUNTIME_DIRS}"
          "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
          "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
          "-DMODULE_DIR=$<TARGET_FILE_DIR:audio>"
          "-DMODE=${mode}"
          -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunHardwareTest.cmake"
        DEPENDS audio run_pure_test
        COMMENT "Running bounded pure-audio ${mode} validation"
        VERBATIM
      )
    endforeach()
    get_filename_component(pure_audio_tool_dir "${CMAKE_C_COMPILER}" DIRECTORY)
    find_program(PURE_AUDIO_MAKE_EXECUTABLE NAMES mingw32-make
      HINTS "${pure_audio_tool_dir}" NO_DEFAULT_PATH REQUIRED)
    find_program(PURE_AUDIO_SH_EXECUTABLE NAMES sh
      HINTS "$ENV{MSYSTEM_PREFIX}/../usr/bin" NO_DEFAULT_PATH REQUIRED)
    foreach(contract runner cleanup)
      add_test(NAME pure-audio-${contract}-contract
        COMMAND "${CMAKE_COMMAND}"
          "-DRUNNER=$<TARGET_FILE:run_pure_test>"
          "-DFIXTURE=$<TARGET_FILE:run_pure_fixture>"
          "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
          "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
          "-DMODULE_DIR=${CMAKE_CURRENT_BINARY_DIR}"
          "-DRUNTIME_DIRS=${PURE_AUDIO_RUNNER_RUNTIME_DIRS}"
          "-DMAKE_EXECUTABLE=${PURE_AUDIO_MAKE_EXECUTABLE}"
          "-DSH_EXECUTABLE=${PURE_AUDIO_SH_EXECUTABLE}"
          -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/${contract}_contract.cmake")
      set_tests_properties(pure-audio-${contract}-contract PROPERTIES
        LABELS "audio;contract;no-hardware" TIMEOUT 90)
    endforeach()
    if(PURE_AUDIO_STRICT_WINDOWS_AUDIT)
      add_executable(install_guard_fixture cmake/install_guard.c)
      target_compile_definitions(install_guard_fixture PRIVATE PURE_AUDIO_INSTALL_GUARD_FIXTURE)
      target_compile_features(install_guard_fixture PRIVATE c_std_11)
      target_compile_options(install_guard_fixture PRIVATE -Wall -Wextra -Werror -fno-sanitize=all)
      target_link_options(install_guard_fixture PRIVATE -municode -fno-sanitize=all)
      target_link_libraries(install_guard_fixture PRIVATE bcrypt)
      add_test(NAME pure-audio-install-guard-contract
        COMMAND "${PURE_AUDIO_WINDOWS_SYSTEM_DIRECTORY}/WindowsPowerShell/v1.0/powershell.exe"
          -NoProfile -NonInteractive -ExecutionPolicy Bypass
          -File "${CMAKE_CURRENT_SOURCE_DIR}/tests/install_guard_contract.ps1"
          -SourceDir "${CMAKE_CURRENT_SOURCE_DIR}" -BuildDir "${CMAKE_CURRENT_BINARY_DIR}"
          -PurePrefix "${PURE_AUDIO_PURE_PREFIX}")
      set_tests_properties(pure-audio-install-guard-contract PROPERTIES
        LABELS "audio;contract;no-hardware" TIMEOUT 600 RUN_SERIAL TRUE)
      foreach(contract configure runtime_verifier install)
        add_test(NAME pure-audio-${contract}-contract
          COMMAND "${CMAKE_COMMAND}"
            "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
            "-DMODULE_DIR=${CMAKE_CURRENT_BINARY_DIR}"
            "-DCLANG64_PREFIX=${PURE_AUDIO_CLANG64_PREFIX}"
            "-DPURE_PREFIX=${PURE_AUDIO_PURE_PREFIX}"
            "-DRUNNER=$<TARGET_FILE:run_pure_test>"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/${contract}_contract.cmake")
        set_tests_properties(pure-audio-${contract}-contract PROPERTIES
          LABELS "audio;contract;no-hardware" TIMEOUT 600)
        if(contract STREQUAL "install")
          set_tests_properties(pure-audio-install-contract PROPERTIES TIMEOUT 1800)
        endif()
      endforeach()
      add_test(NAME pure-audio-source-dist-contract
        COMMAND "${CMAKE_COMMAND}"
          "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
          "-DMODULE_DIR=${CMAKE_CURRENT_BINARY_DIR}"
          "-DCLANG64_PREFIX=${PURE_AUDIO_CLANG64_PREFIX}"
          "-DPURE_PREFIX=${PURE_AUDIO_PURE_PREFIX}"
          "-DRUNNER=$<TARGET_FILE:run_pure_test>"
          -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/source_dist_contract.cmake")
      set_tests_properties(pure-audio-source-dist-contract PROPERTIES
        LABELS "audio;contract;no-hardware" TIMEOUT 3600 RUN_SERIAL TRUE)
    endif()
  endif()
endif()
