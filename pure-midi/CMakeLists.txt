cmake_minimum_required(VERSION 3.25)

option(PURE_MIDI_STRICT_WINDOWS_AUDIT "Require the explicit audited Windows toolchain and PE closure" OFF)
if(PURE_MIDI_STRICT_WINDOWS_AUDIT)
  if(NOT CMAKE_HOST_WIN32 OR NOT CMAKE_GENERATOR STREQUAL "Ninja")
    message(FATAL_ERROR "midi audit: strict Windows audit requires native Windows and Ninja")
  endif()
  if(CMAKE_SUPPRESS_REGENERATION)
    message(FATAL_ERROR "midi audit: CMAKE_SUPPRESS_REGENERATION would disable frozen input checks")
  endif()
  set(CMAKE_SUPPRESS_REGENERATION OFF CACHE BOOL "Strict input revalidation is mandatory" FORCE)
  set(PURE_MIDI_VERIFIER_HELPERS_ONLY ON)
  include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake")
  unset(PURE_MIDI_VERIFIER_HELPERS_ONLY)
  set(audit_directories PURE_MIDI_CLANG64_PREFIX PURE_MIDI_PURE_PREFIX
    PURE_MIDI_WINDOWS_SYSTEM_DIRECTORY PURE_INCLUDE_DIR)
  set(audit_files CMAKE_C_COMPILER CMAKE_MAKE_PROGRAM PKG_CONFIG_EXECUTABLE
    LLVM_READOBJ PURE_EXECUTABLE PURE_HEADER PURE_GLOB_HEADER PURE_IMPORT_LIBRARY PURE_RUNTIME_DLL
    PORTMIDI_HEADER PORTTIME_HEADER PORTMIDI_IMPORT_LIBRARY PORTMIDI_RUNTIME_DLL GMP_HEADER MPFR_HEADER
    PURE_MIDI_WINDOWS_HEADER PURE_MIDI_MAKE_EXECUTABLE PURE_MIDI_SH_EXECUTABLE)
  foreach(var IN LISTS audit_directories audit_files)
    if(NOT DEFINED ${var} OR "${${var}}" STREQUAL "")
      message(FATAL_ERROR "midi audit: explicit ${var} is required (no environment fallback)")
    endif()
    if(var IN_LIST audit_directories)
      midi_path("${${var}}" directory canonical)
    else()
      midi_path("${${var}}" file canonical)
    endif()
    set(${var} "${canonical}" CACHE STRING "Explicit immutable audit input" FORCE)
    list(APPEND audit_paths "${canonical}")
  endforeach()
  if(NOT DEFINED PURE_MIDI_RUNTIME_SOURCES OR "${PURE_MIDI_RUNTIME_SOURCES}" STREQUAL "")
    message(FATAL_ERROR "midi audit: explicit PURE_MIDI_RUNTIME_SOURCES is required")
  endif()
  midi_windows_authority()
  set(expected_CMAKE_C_COMPILER "${PURE_MIDI_CLANG64_PREFIX}/bin/clang.exe")
  set(expected_CMAKE_MAKE_PROGRAM "${PURE_MIDI_CLANG64_PREFIX}/bin/ninja.exe")
  set(expected_PKG_CONFIG_EXECUTABLE "${PURE_MIDI_CLANG64_PREFIX}/bin/pkgconf.exe")
  set(expected_LLVM_READOBJ "${PURE_MIDI_CLANG64_PREFIX}/bin/llvm-readobj.exe")
  set(expected_PURE_EXECUTABLE "${PURE_MIDI_PURE_PREFIX}/bin/pure.exe")
  set(expected_PURE_HEADER "${PURE_MIDI_PURE_PREFIX}/include/pure/runtime.h")
  set(expected_PURE_GLOB_HEADER "${PURE_MIDI_PURE_PREFIX}/include/glob.h")
  set(expected_PURE_INCLUDE_DIR "${PURE_MIDI_PURE_PREFIX}/include")
  set(expected_PURE_IMPORT_LIBRARY "${PURE_MIDI_PURE_PREFIX}/lib/libpure.dll.a")
  set(expected_PURE_RUNTIME_DLL "${PURE_MIDI_PURE_PREFIX}/bin/libpure.dll")
  set(expected_PORTMIDI_HEADER "${PURE_MIDI_CLANG64_PREFIX}/include/portmidi.h")
  set(expected_PORTMIDI_IMPORT_LIBRARY "${PURE_MIDI_CLANG64_PREFIX}/lib/libportmidi.dll.a")
  set(expected_PORTTIME_HEADER "${PURE_MIDI_CLANG64_PREFIX}/include/porttime.h")
  set(expected_PORTMIDI_RUNTIME_DLL "${PURE_MIDI_CLANG64_PREFIX}/bin/libportmidi.dll")
  set(expected_GMP_HEADER "${PURE_MIDI_CLANG64_PREFIX}/include/gmp.h")
  set(expected_MPFR_HEADER "${PURE_MIDI_CLANG64_PREFIX}/include/mpfr.h")
  set(expected_PURE_MIDI_WINDOWS_HEADER "${PURE_MIDI_CLANG64_PREFIX}/include/windows.h")
  set(expected_PURE_MIDI_MAKE_EXECUTABLE "${PURE_MIDI_CLANG64_PREFIX}/bin/mingw32-make.exe")
  set(expected_PURE_MIDI_SH_EXECUTABLE "${PURE_MIDI_CLANG64_PREFIX}/../usr/bin/sh.exe")
  cmake_path(NORMAL_PATH expected_PURE_MIDI_SH_EXECUTABLE)
  foreach(var IN LISTS audit_files)
    midi_equal_path("${${var}}" "${expected_${var}}")
  endforeach()
  midi_equal_path("${PURE_INCLUDE_DIR}" "${expected_PURE_INCLUDE_DIR}")
  midi_runtime_rows("${PURE_MIDI_RUNTIME_SOURCES}" FALSE runtime_paths runtime_manifest)
  midi_no_reparse(${audit_paths} ${runtime_paths})
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
        message(FATAL_ERROR "midi audit: undeclared flags ${var}")
      endif()
    elseif(var MATCHES "^CMAKE_(TOOLCHAIN_FILE|SYSROOT|C_COMPILER_ARG1|C_COMPILER_EXTERNAL_TOOLCHAIN|C_COMPILER_LAUNCHER|C_LINKER_LAUNCHER|C_STANDARD_INCLUDE_DIRECTORIES|C_STANDARD_LIBRARIES|C_LINK_EXECUTABLE|C_CREATE_SHARED_LIBRARY|C_CREATE_SHARED_MODULE|C_CREATE_STATIC_LIBRARY|C_COMPILE_OBJECT|LINKER_TYPE|INTERPROCEDURAL_OPTIMIZATION|USER_MAKE_RULES_OVERRIDE)(_|$)" OR
        var MATCHES "^CMAKE_PROJECT_.*INCLUDE")
      if(NOT "${${var}}" STREQUAL "")
        message(FATAL_ERROR "midi audit: undeclared toolchain override ${var}")
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
    message(FATAL_ERROR "midi audit: undeclared build configuration ${CMAKE_BUILD_TYPE}")
  endif()
  foreach(property RULE_LAUNCH_COMPILE RULE_LAUNCH_LINK)
    get_property(value GLOBAL PROPERTY "${property}")
    if(value)
      message(FATAL_ERROR "midi audit: undeclared rule launcher ${property}")
    endif()
  endforeach()
  if(DEFINED CMAKE_CONFIGURATION_TYPES AND NOT CMAKE_CONFIGURATION_TYPES STREQUAL "")
    message(FATAL_ERROR "midi audit: multi-configuration overrides are not allowed")
  endif()
  if(NOT DEFINED CMAKE_C_COMPILER_TARGET OR NOT CMAKE_C_COMPILER_TARGET STREQUAL "x86_64-w64-windows-gnu")
    message(FATAL_ERROR "midi audit: explicit compiler target x86_64-w64-windows-gnu is required")
  endif()
  set(CMAKE_C_COMPILER_TARGET "x86_64-w64-windows-gnu" CACHE STRING "Audited target" FORCE)
  # Freeze all ambient discovery used by compiler probes and legacy install
  # metadata. Strict library targets below use only explicit headers/libraries.
  set(ENV{PATH} "${PURE_MIDI_PURE_PREFIX}/bin;${PURE_MIDI_CLANG64_PREFIX}/bin;${MIDI_SYSTEM_DIR}")
  set(ENV{MSYSTEM_PREFIX} "${PURE_MIDI_CLANG64_PREFIX}")
  set(ENV{PKG_CONFIG_PATH} "")
  set(ENV{PKG_CONFIG_LIBDIR} "${PURE_MIDI_PURE_PREFIX}/lib/pkgconfig;${PURE_MIDI_CLANG64_PREFIX}/lib/pkgconfig")
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
      OUTPUT_VARIABLE version ERROR_VARIABLE err OUTPUT_STRIP_TRAILING_WHITESPACE TIMEOUT 30)
    if(NOT rc EQUAL 0 OR NOT err STREQUAL "")
      message(FATAL_ERROR "midi audit: cannot identify ${tool}: ${rc} ${err}")
    endif()
    if(tool STREQUAL "CMAKE_C_COMPILER" AND
        NOT version MATCHES "^clang version 22\\.[0-9]+\\.[0-9]+")
      message(FATAL_ERROR "midi audit: Clang major 22 required: ${version}")
    elseif(tool STREQUAL "LLVM_READOBJ" AND NOT version MATCHES "LLVM version 22\\.")
      message(FATAL_ERROR "midi audit: llvm-readobj major 22 required")
    elseif(tool STREQUAL "CMAKE_MAKE_PROGRAM" AND NOT version MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+[\\r\\n]*$")
      message(FATAL_ERROR "midi audit: Ninja version required")
    elseif(tool STREQUAL "PKG_CONFIG_EXECUTABLE" AND NOT version MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+[\\r\\n]*$")
      message(FATAL_ERROR "midi audit: pkgconf version required")
    elseif(tool STREQUAL "PURE_EXECUTABLE" AND NOT version MATCHES "[Pp]ure 0\\.68([^0-9]|$)")
      message(FATAL_ERROR "midi audit: Pure 0.68 required: ${version}")
    endif()
    string(STRIP "${version}" version)
    message(STATUS "midi audit: ${tool}: ${version}")
  endforeach()
  execute_process(COMMAND "${CMAKE_C_COMPILER}" --no-default-config -dumpmachine RESULT_VARIABLE rc
    OUTPUT_VARIABLE triple ERROR_VARIABLE err OUTPUT_STRIP_TRAILING_WHITESPACE)
  if(NOT rc EQUAL 0 OR NOT err STREQUAL "" OR NOT triple STREQUAL "x86_64-w64-windows-gnu")
    message(FATAL_ERROR "midi audit: Clang target must be x86_64-w64-windows-gnu: ${triple}")
  endif()
  foreach(var IN LISTS audit_files)
    if(var MATCHES "_IMPORT_LIBRARY$")
      midi_import_library("${${var}}")
    endif()
  endforeach()
  foreach(path IN LISTS runtime_paths)
    midi_inspect_pe("${path}" unused_imports)
  endforeach()

  # Payload hashes from MSYS2 mingw-w64-clang-x86_64-portmidi 1~2.0.8-1
  # pacman mtree. Its shipped pkg-config file reports 2.0.7; it is not the
  # authoritative package version. Keep headers, import library and DLL paired.
  set(portmidi_PORTMIDI_HEADER 0262c749a289d95e17e2dbdb746113ad52ae0999d07f9701115cc761a6846ce0)
  set(portmidi_PORTTIME_HEADER 67aedea702f1069b71f07d5dd29b53b9d4d4bb870d5de92b4d651ee15e45d277)
  set(portmidi_PORTMIDI_IMPORT_LIBRARY fa117992656c4344369f640832004121ad2d4e539f9ac0344b74190f7c6b7829)
  set(portmidi_PORTMIDI_RUNTIME_DLL 99454395751bfad786db9c457b93db62f31f7d68dc2bebb2281f33289d43cb49)
  foreach(var PORTMIDI_HEADER PORTTIME_HEADER PORTMIDI_IMPORT_LIBRARY PORTMIDI_RUNTIME_DLL)
    file(SHA256 "${${var}}" actual)
    if(NOT actual STREQUAL portmidi_${var})
      message(FATAL_ERROR "midi audit: PortMidi package mismatch: ${var} (requires 1~2.0.8-1)")
    endif()
  endforeach()
  message(STATUS "midi audit: PortMidi package 1~2.0.8-1 payload SHA-256 verified")
  # A generated Ninja rule must clear its own environment: configure-time
  # set(ENV) cannot affect a later cmake --build process. Use the declared
  # prefix's pinned CMake executable as both compiler and linker launcher;
  # the actual compiler command remains the validated absolute clang.exe.
  midi_path("${PURE_MIDI_CLANG64_PREFIX}/bin/cmake.exe" file audit_launcher_tool)
  midi_no_reparse("${audit_launcher_tool}")
  file(SHA256 "${audit_launcher_tool}" audit_launcher_hash)
  set(audit_launcher "${audit_launcher_tool};-E;env")
  foreach(var IN LISTS audit_clear_environment)
    list(APPEND audit_launcher "--unset=${var}")
  endforeach()
  string(REPLACE ";" "\\;" audit_path_argument "PATH=$ENV{PATH}")
  list(APPEND audit_launcher "${audit_path_argument}" --)
  set(CMAKE_C_COMPILER_LAUNCHER "${audit_launcher}")
  set(CMAKE_C_LINKER_LAUNCHER "${audit_launcher}")
  set(audit_pin "${runtime_manifest}${audit_launcher}\n${audit_launcher_hash}\n${audit_config}\n${CMAKE_C_COMPILER_TARGET}\n")
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
  if(DEFINED PURE_MIDI_CONFIGURED_INPUT_PIN AND NOT PURE_MIDI_CONFIGURED_INPUT_PIN STREQUAL audit_pin)
    message(FATAL_ERROR "midi audit: configured inputs changed; use a fresh audit build directory")
  endif()
  set(PURE_MIDI_CONFIGURED_INPUT_PIN "${audit_pin}" CACHE INTERNAL "Frozen audit inputs")
  set(PURE_MIDI_RUNTIME_MANIFEST "${CMAKE_CURRENT_BINARY_DIR}/windows-runtime-sources.txt")
  file(SHA256 "${LLVM_READOBJ}" PURE_MIDI_LLVM_READOBJ_SHA256)
  set(PURE_MIDI_LLVM_READOBJ_SHA256 "${PURE_MIDI_LLVM_READOBJ_SHA256}" CACHE INTERNAL "Configured inspection tool hash")
  file(WRITE "${PURE_MIDI_RUNTIME_MANIFEST}" "${runtime_manifest}")
  set(PURE_MIDI_INPUT_MANIFEST "${CMAKE_CURRENT_BINARY_DIR}/windows-configured-inputs.txt")
  file(WRITE "${PURE_MIDI_INPUT_MANIFEST}" "target|${CMAKE_C_COMPILER_TARGET}\n")
  foreach(var IN LISTS audit_files)
    file(SHA256 "${${var}}" hash)
    file(APPEND "${PURE_MIDI_INPUT_MANIFEST}" "${var}|${${var}}|${hash}\n")
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${${var}}")
  endforeach()
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    ${runtime_paths} "${audit_launcher_tool}")
  # Expose only the declared header names, with absolute includes selecting the
  # pinned files themselves. Searching the entire Pure include tree first can
  # otherwise hide CLANG64 headers behind unrelated/stale copies.
  set(PURE_MIDI_AUDITED_INCLUDE_DIR "${CMAKE_CURRENT_BINARY_DIR}/strict-include")
  midi_no_reparse("${CMAKE_CURRENT_BINARY_DIR}")
  foreach(directory "${PURE_MIDI_AUDITED_INCLUDE_DIR}" "${PURE_MIDI_AUDITED_INCLUDE_DIR}/pure")
    if(EXISTS "${directory}" OR IS_SYMLINK "${directory}")
      midi_path("${directory}" directory checked)
      midi_no_reparse("${directory}")
    else()
      file(MAKE_DIRECTORY "${directory}")
    endif()
  endforeach()
  set(audit_header_rows
    "PURE_HEADER|pure/runtime.h" "PURE_GLOB_HEADER|glob.h"
    "PORTMIDI_HEADER|portmidi.h" "PORTTIME_HEADER|porttime.h"
    "GMP_HEADER|gmp.h" "MPFR_HEADER|mpfr.h" "PURE_MIDI_WINDOWS_HEADER|windows.h")
  set(audit_wrappers)
  set(existing_wrappers)
  foreach(row IN LISTS audit_header_rows)
    string(REPLACE "|" ";" fields "${row}")
    list(GET fields 1 relative)
    set(wrapper "${PURE_MIDI_AUDITED_INCLUDE_DIR}/${relative}")
    list(APPEND audit_wrappers "${wrapper}")
    if(EXISTS "${wrapper}" OR IS_SYMLINK "${wrapper}")
      midi_path("${wrapper}" file checked)
      list(APPEND existing_wrappers "${wrapper}")
    endif()
  endforeach()
  if(existing_wrappers)
    midi_no_reparse(${existing_wrappers})
  endif()
  foreach(row IN LISTS audit_header_rows)
    string(REPLACE "|" ";" fields "${row}")
    list(GET fields 0 var)
    list(GET fields 1 relative)
    file(CONFIGURE OUTPUT "${PURE_MIDI_AUDITED_INCLUDE_DIR}/${relative}"
      CONTENT "#include \"${${var}}\"\n" @ONLY)
  endforeach()
  # No additional search input may be introduced into this generated namespace.
  # GLOB verification also catches an extra header added after configuration.
  file(GLOB audit_include_entries CONFIGURE_DEPENDS LIST_DIRECTORIES TRUE
    "${PURE_MIDI_AUDITED_INCLUDE_DIR}/*" "${PURE_MIDI_AUDITED_INCLUDE_DIR}/pure/*")
  midi_no_reparse(${audit_include_entries})
  foreach(entry IN LISTS audit_include_entries)
    if(NOT entry IN_LIST audit_wrappers AND
        NOT entry STREQUAL "${PURE_MIDI_AUDITED_INCLUDE_DIR}/pure")
      message(FATAL_ERROR "midi audit: undeclared isolated header input: ${entry}")
    endif()
  endforeach()
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${audit_wrappers})
endif()

project(pure-midi VERSION 0.6 LANGUAGES C)

if(PURE_MIDI_STRICT_WINDOWS_AUDIT)
  set(PURE_PREFIX "${PURE_MIDI_PURE_PREFIX}")
  set(PORTMIDI_INCLUDE_DIRS "${PURE_MIDI_AUDITED_INCLUDE_DIR}")
  foreach(package PURE PORTMIDI)
    add_library(PkgConfig::${package} INTERFACE IMPORTED)
    set_target_properties(PkgConfig::${package} PROPERTIES
      INTERFACE_INCLUDE_DIRECTORIES "${PURE_MIDI_AUDITED_INCLUDE_DIR}"
      INTERFACE_LINK_LIBRARIES "${${package}_IMPORT_LIBRARY}")
  endforeach()
else()
find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(PORTMIDI REQUIRED IMPORTED_TARGET portmidi)
endif()

function(add_pure_midi_module target)
  add_library(${target} MODULE ${ARGN})
  target_compile_features(${target} PRIVATE c_std_11)
  target_link_libraries(${target} PRIVATE PkgConfig::PURE)
  if(MINGW)
    target_compile_options(${target} PRIVATE -Wall -Wextra -Werror)
    target_link_options(${target} PRIVATE "LINKER:--enable-auto-import")
  endif()
  set_target_properties(${target} PROPERTIES
    PREFIX ""
    WINDOWS_EXPORT_ALL_SYMBOLS ON)
endfunction()

add_pure_midi_module(pmlib pmdev.c midi_bounds.c midi_stream.c)
target_link_libraries(pmlib PRIVATE PkgConfig::PORTMIDI)
if(NOT WIN32)
  find_package(Threads REQUIRED)
  target_link_libraries(pmlib PRIVATE Threads::Threads)
endif()

add_pure_midi_module(midifile midifile/midifile.c midifile/mf.c midi_bounds.c)

if(WIN32)
  if(PURE_MIDI_STRICT_WINDOWS_AUDIT)
    add_custom_target(verify-windows-dependencies
      COMMAND "${CMAKE_COMMAND}" "-DLLVM_READOBJ=${LLVM_READOBJ}"
        "-DPURE_MIDI_LLVM_READOBJ_SHA256=${PURE_MIDI_LLVM_READOBJ_SHA256}"
        "-DMIDI_MODULE_DIR=$<TARGET_FILE_DIR:pmlib>"
        "-DPURE_MIDI_CLANG64_PREFIX=${PURE_MIDI_CLANG64_PREFIX}"
        "-DPURE_MIDI_PURE_PREFIX=${PURE_MIDI_PURE_PREFIX}"
        "-DPURE_MIDI_WINDOWS_SYSTEM_DIRECTORY=${PURE_MIDI_WINDOWS_SYSTEM_DIRECTORY}"
        "-DPURE_MIDI_RUNTIME_MANIFEST=${PURE_MIDI_RUNTIME_MANIFEST}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
      DEPENDS pmlib midifile
      COMMENT "Verifying the pure-midi Windows dependency closure" VERBATIM)
  else()
    find_file(PORTMIDI_RUNTIME_DLL NAMES libportmidi.dll
      HINTS "$ENV{MSYSTEM_PREFIX}/bin" NO_DEFAULT_PATH REQUIRED)
  endif()
endif()

include(CTest)
if(BUILD_TESTING)
	if(WIN32)
		foreach(variant IN ITEMS release asan)
			set(lifecycle_target "pure-midi-lifecycle-${variant}")
			add_executable(${lifecycle_target} tests/midi_lifecycle_harness.c midi_stream.c)
			target_compile_features(${lifecycle_target} PRIVATE c_std_11)
			target_compile_definitions(${lifecycle_target} PRIVATE PURE_MIDI_TEST_SEAM=1)
			target_link_libraries(${lifecycle_target} PRIVATE PkgConfig::PORTMIDI)
			target_compile_options(${lifecycle_target} PRIVATE -Wall -Wextra -Werror)
			if(variant STREQUAL "asan")
				target_compile_options(${lifecycle_target} PRIVATE -fsanitize=address -fno-omit-frame-pointer)
				target_link_options(${lifecycle_target} PRIVATE -fsanitize=address)
			endif()
			add_test(NAME ${lifecycle_target} COMMAND ${lifecycle_target})
			set_tests_properties(${lifecycle_target} PROPERTIES
				LABELS "midi;lifecycle;fault;${variant};no-hardware"
				ENVIRONMENT "ASAN_OPTIONS=detect_leaks=0:halt_on_error=1:strict_string_checks=1"
				ENVIRONMENT_MODIFICATION "PATH=path_list_prepend:$ENV{MSYSTEM_PREFIX}/bin"
				TIMEOUT 180)
		endforeach()
	endif()
	set(MIDI_BOUNDARY_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/midi-boundary")
	set(MIDI_BOUNDARY_FAKE_DIRECTORY "${MIDI_BOUNDARY_DIRECTORY}/fake")
	file(MAKE_DIRECTORY "${MIDI_BOUNDARY_DIRECTORY}" "${MIDI_BOUNDARY_FAKE_DIRECTORY}")

	add_library(pure-midi-boundary-fake MODULE tests/midi_boundary_harness.c midi_bounds.c midi_stream.c pmdev.c)
	target_compile_features(pure-midi-boundary-fake PRIVATE c_std_11)
	target_compile_definitions(pure-midi-boundary-fake PRIVATE PURE_MIDI_BOUNDARY_FAKE=1)
	target_link_libraries(pure-midi-boundary-fake PRIVATE PkgConfig::PURE)
	target_include_directories(pure-midi-boundary-fake PRIVATE ${PORTMIDI_INCLUDE_DIRS})
	if(NOT WIN32)
		target_link_libraries(pure-midi-boundary-fake PRIVATE Threads::Threads)
	endif()
	set_target_properties(pure-midi-boundary-fake PROPERTIES
		PREFIX ""
		OUTPUT_NAME "pmlib"
		LIBRARY_OUTPUT_DIRECTORY "${MIDI_BOUNDARY_FAKE_DIRECTORY}"
		RUNTIME_OUTPUT_DIRECTORY "${MIDI_BOUNDARY_FAKE_DIRECTORY}"
		WINDOWS_EXPORT_ALL_SYMBOLS ON)
	if(MINGW)
		target_compile_options(pure-midi-boundary-fake PRIVATE -Wall -Wextra -Werror)
		target_link_options(pure-midi-boundary-fake PRIVATE "LINKER:--enable-auto-import")
	endif()

	add_executable(pure-midi-boundary
		tests/midi_boundary_harness.c
		midifile/mf.c
		midi_bounds.c
		midifile/midifile.c)
	target_compile_features(pure-midi-boundary PRIVATE c_std_11)
	target_compile_definitions(pure-midi-boundary PRIVATE PURE_MIDI_TEST_SEAM=1)
	target_include_directories(pure-midi-boundary PRIVATE midifile tests)
	target_link_libraries(pure-midi-boundary PRIVATE PkgConfig::PURE)
	if(MINGW)
		target_compile_options(pure-midi-boundary PRIVATE
			-Wall -Wextra -Werror -fsanitize=address -fno-omit-frame-pointer)
		target_link_options(pure-midi-boundary PRIVATE -fsanitize=address)
	endif()
	add_test(NAME pure-midi-boundary COMMAND pure-midi-boundary)
	set_tests_properties(pure-midi-boundary PROPERTIES
		LABELS "midi;boundary;asan;no-hardware"
		ENVIRONMENT "ASAN_OPTIONS=detect_leaks=0:halt_on_error=1:strict_string_checks=1"
		ENVIRONMENT_MODIFICATION "PATH=path_list_prepend:${PURE_PREFIX}/bin;PATH=path_list_prepend:$ENV{MSYSTEM_PREFIX}/bin"
		WORKING_DIRECTORY "${MIDI_BOUNDARY_DIRECTORY}"
		TIMEOUT 30)
	add_executable(pure-midi-boundary-release
		tests/midi_boundary_harness.c midifile/mf.c midifile/midifile.c midi_bounds.c)
	target_compile_features(pure-midi-boundary-release PRIVATE c_std_11)
	target_compile_definitions(pure-midi-boundary-release PRIVATE PURE_MIDI_TEST_SEAM=1)
	target_include_directories(pure-midi-boundary-release PRIVATE midifile tests)
	target_link_libraries(pure-midi-boundary-release PRIVATE PkgConfig::PURE)
	if(MINGW)
		target_compile_options(pure-midi-boundary-release PRIVATE -Wall -Wextra -Werror)
	endif()
	add_test(NAME pure-midi-boundary-release COMMAND pure-midi-boundary-release)
	set_tests_properties(pure-midi-boundary-release PROPERTIES
		LABELS "midi;boundary;no-hardware"
		ENVIRONMENT_MODIFICATION "PATH=path_list_prepend:${PURE_PREFIX}/bin;PATH=path_list_prepend:$ENV{MSYSTEM_PREFIX}/bin"
		WORKING_DIRECTORY "${MIDI_BOUNDARY_DIRECTORY}" TIMEOUT 30)

	set(MIDIFILE_FAULT_RELEASE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/midifile-fault-release")
	set(MIDIFILE_FAULT_ASAN_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/midifile-fault-asan")
	set(MIDIFILE_FAULT_DEADLINE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/midifile-fault-deadline")
	file(MAKE_DIRECTORY
		"${MIDIFILE_FAULT_RELEASE_DIRECTORY}"
		"${MIDIFILE_FAULT_ASAN_DIRECTORY}"
		"${MIDIFILE_FAULT_DEADLINE_DIRECTORY}")

	add_executable(pure-midi-midifile-fault
		tests/midifile_fault_harness.c
		midifile/midifile.c)
	target_compile_features(pure-midi-midifile-fault PRIVATE c_std_11)
	target_compile_definitions(pure-midi-midifile-fault PRIVATE PURE_MIDI_TEST_SEAM=1)
	target_include_directories(pure-midi-midifile-fault PRIVATE midifile tests)
	if(MINGW)
		target_compile_options(pure-midi-midifile-fault PRIVATE -Wall -Wextra -Werror)
	endif()
	add_test(NAME pure-midi-midifile-fault
		COMMAND pure-midi-midifile-fault "${CMAKE_CURRENT_SOURCE_DIR}/examples/prelude3.mid")
	set_tests_properties(pure-midi-midifile-fault PROPERTIES
		LABELS "midi;midifile;fault;no-hardware"
		WORKING_DIRECTORY "${MIDIFILE_FAULT_RELEASE_DIRECTORY}"
		TIMEOUT 20)
	add_test(NAME pure-midi-midifile-deadline-contract
		COMMAND pure-midi-midifile-fault
			"${CMAKE_CURRENT_SOURCE_DIR}/examples/prelude3.mid"
			--deadline-contract)
	set_tests_properties(pure-midi-midifile-deadline-contract PROPERTIES
		LABELS "midi;midifile;fault;deadline;no-hardware"
		PASS_REGULAR_EXPRESSION "malformed fixture exceeded two-second deadline"
		WORKING_DIRECTORY "${MIDIFILE_FAULT_DEADLINE_DIRECTORY}"
		TIMEOUT 5)

	if(MINGW AND CMAKE_C_COMPILER_ID MATCHES "Clang")
		add_executable(pure-midi-midifile-fault-asan
			tests/midifile_fault_harness.c
			midifile/midifile.c)
		target_compile_features(pure-midi-midifile-fault-asan PRIVATE c_std_11)
		target_compile_definitions(pure-midi-midifile-fault-asan PRIVATE PURE_MIDI_TEST_SEAM=1)
		target_include_directories(pure-midi-midifile-fault-asan PRIVATE midifile tests)
		target_compile_options(pure-midi-midifile-fault-asan PRIVATE
			-Wall -Wextra -Werror -fsanitize=address -fno-omit-frame-pointer)
		target_link_options(pure-midi-midifile-fault-asan PRIVATE -fsanitize=address)
		add_test(NAME pure-midi-midifile-fault-asan
			COMMAND pure-midi-midifile-fault-asan "${CMAKE_CURRENT_SOURCE_DIR}/examples/prelude3.mid")
		set_tests_properties(pure-midi-midifile-fault-asan PROPERTIES
			LABELS "midi;midifile;fault;asan;no-hardware"
			ENVIRONMENT "ASAN_OPTIONS=detect_leaks=0:halt_on_error=1:strict_string_checks=1"
			WORKING_DIRECTORY "${MIDIFILE_FAULT_ASAN_DIRECTORY}"
			TIMEOUT 30)
	endif()

  if(WIN32)
    set(MIDI_CONTRACT_ROOT "${CMAKE_CURRENT_BINARY_DIR}/pure-midi-contract-root")
    file(MAKE_DIRECTORY "${MIDI_CONTRACT_ROOT}")
    get_filename_component(MIDI_RUNTIME_DIR "${PORTMIDI_RUNTIME_DLL}" DIRECTORY)
    add_executable(run_pure_test tests/run_pure_test.c)
    target_compile_features(run_pure_test PRIVATE c_std_11)
    target_compile_definitions(run_pure_test PRIVATE
      "PURE_MIDI_CONTRACT_ROOT=\"${MIDI_CONTRACT_ROOT}\"")
    target_compile_options(run_pure_test PRIVATE -Wall -Wextra -Werror)
    target_link_options(run_pure_test PRIVATE -municode)
    target_link_libraries(run_pure_test PRIVATE bcrypt)

    add_executable(pure-midi-runner-fixture tests/runner_fixture.c)
    target_compile_options(pure-midi-runner-fixture PRIVATE -Wall -Wextra -Werror)
    add_test(NAME pure-midi-native-environment-contract COMMAND pure-midi-runner-fixture --native-environment)
    set_tests_properties(pure-midi-native-environment-contract PROPERTIES
      LABELS "midi;contract;no-hardware" TIMEOUT 5)
    if(PURE_MIDI_STRICT_WINDOWS_AUDIT)
      set(midi_system "${MIDI_SYSTEM_DIR}")
      get_filename_component(midi_windows "${MIDI_SYSTEM_DIR}" DIRECTORY)
    else()
      set(midi_system "$ENV{SystemRoot}/System32")
      set(midi_windows "$ENV{SystemRoot}")
    endif()
    # Native fault harnesses also embed Pure. An inherited PURELIB can skip its
    # normal prelude initialization while their low-level assertions still run.
    # Preserve the existing harnesses/counters but give them the declared loader
    # path and remove the same parent settings as the native Pure supervisor.
    foreach(native IN ITEMS pure-midi-lifecycle-release pure-midi-lifecycle-asan
        pure-midi-boundary pure-midi-boundary-release pure-midi-midifile-fault
        pure-midi-midifile-deadline-contract pure-midi-midifile-fault-asan
        pure-midi-native-environment-contract)
      if(TEST ${native})
        set_property(TEST ${native} APPEND PROPERTY ENVIRONMENT_MODIFICATION
          "PURELIB=unset:" "PURE_INCLUDE=unset:" "PURE_LIBRARY=unset:"
          "PURE_MIDI_OUT=unset:" "PURE_MIDI_IN=unset:" "PURE_RUNNER_POISON=unset:"
          "PATH=set:${PURE_PREFIX}/bin" "PATH=path_list_append:${MIDI_RUNTIME_DIR}"
          "PATH=path_list_append:${midi_system}" "PATH=path_list_append:${midi_windows}")
      endif()
    endforeach()
    add_library(pure-midi-hardware-fixture MODULE
      tests/runner_hardware_fixture.c midi_bounds.c midi_stream.c pmdev.c)
    target_compile_definitions(pure-midi-hardware-fixture PRIVATE PURE_MIDI_BOUNDARY_FAKE=1)
    target_compile_options(pure-midi-hardware-fixture PRIVATE -Wall -Wextra -Werror)
    target_link_libraries(pure-midi-hardware-fixture PRIVATE PkgConfig::PURE)
    target_include_directories(pure-midi-hardware-fixture PRIVATE ${PORTMIDI_INCLUDE_DIRS})
    target_link_options(pure-midi-hardware-fixture PRIVATE "LINKER:--enable-auto-import")
    set_target_properties(pure-midi-hardware-fixture PROPERTIES PREFIX "" OUTPUT_NAME pmlib
      LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/hardware-fake"
      RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/hardware-fake"
      WINDOWS_EXPORT_ALL_SYMBOLS ON)
    find_program(PURE_EXECUTABLE NAMES pure
      HINTS "${PURE_PREFIX}/bin" NO_DEFAULT_PATH REQUIRED)
    if(PURE_MIDI_STRICT_WINDOWS_AUDIT)
      set(MIDI_MAKE_EXECUTABLE "${PURE_MIDI_MAKE_EXECUTABLE}")
      set(MIDI_MAKE_SHELL "${PURE_MIDI_SH_EXECUTABLE}")
    else()
      set(MIDI_POWERSHELL "$ENV{SystemRoot}/System32/WindowsPowerShell/v1.0/powershell.exe")
      find_program(MIDI_MAKE_EXECUTABLE NAMES mingw32-make REQUIRED)
      find_program(MIDI_MAKE_SHELL NAMES sh HINTS "${MIDI_RUNTIME_DIR}/../../usr/bin" REQUIRED)
    endif()
    foreach(contract IN ITEMS runner cleanup hardware-runner)
      set(contract_script "${contract}")
      set(extra)
      if(contract STREQUAL hardware-runner)
        set(contract_script runner)
        set(extra -DHARDWARE_ONLY=ON)
      endif()
      add_test(NAME pure-midi-${contract}-contract
        COMMAND "${CMAKE_COMMAND}" "-DRUNNER=$<TARGET_FILE:run_pure_test>"
          "-DFIXTURE_EXE=$<TARGET_FILE:pure-midi-runner-fixture>"
          "-DCONTRACT_ROOT=${MIDI_CONTRACT_ROOT}"
          "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
          "-DRUNTIME_DIR=${MIDI_RUNTIME_DIR}" "-DPOWERSHELL=${MIDI_POWERSHELL}"
          "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}" "-DMODULE_DIR=$<TARGET_FILE_DIR:midifile>"
          "-DHARDWARE_MODULE=$<TARGET_FILE:pure-midi-hardware-fixture>"
          "-DMAKE_EXE=${MIDI_MAKE_EXECUTABLE}" "-DMAKE_SHELL=${MIDI_MAKE_SHELL}"
          ${extra} -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/${contract_script}_contract.cmake")
      set_tests_properties(pure-midi-${contract}-contract PROPERTIES
        LABELS "midi;contract;no-hardware" TIMEOUT 90 RUN_SERIAL TRUE)
    endforeach()

    if(PURE_MIDI_STRICT_WINDOWS_AUDIT)
      foreach(contract configure runtime_verifier)
        add_test(NAME pure-midi-${contract}-contract
          COMMAND "${CMAKE_COMMAND}" "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
            "-DMODULE_DIR=$<TARGET_FILE_DIR:pmlib>"
            "-DCLANG64_PREFIX=${PURE_MIDI_CLANG64_PREFIX}"
            "-DPURE_PREFIX=${PURE_MIDI_PURE_PREFIX}"
            "-DRUNNER=$<TARGET_FILE:run_pure_test>"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/${contract}_contract.cmake")
        set_tests_properties(pure-midi-${contract}-contract PROPERTIES
          LABELS "midi;contract;no-hardware" TIMEOUT 600 RUN_SERIAL TRUE)
      endforeach()
    endif()

    foreach(case IN ITEMS bounds device-timing smoke)
      set(test_pmlib "$<TARGET_FILE:pmlib>")
      if(case STREQUAL bounds)
        set(test_pmlib "$<TARGET_FILE:pure-midi-boundary-fake>")
      endif()
      add_test(NAME pure-midi-${case}
        COMMAND "${CMAKE_COMMAND}" "-DRUNNER=$<TARGET_FILE:run_pure_test>"
          "-DCONTRACT_ROOT=${MIDI_CONTRACT_ROOT}"
          "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
          "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
          "-DPURE_STDLIB=${PURE_PREFIX}/lib/pure"
          "-DMODULE_DIR=$<TARGET_FILE_DIR:midifile>"
          "-DPMLIB_MODULE=${test_pmlib}"
          "-DRUNTIME_DIRS=${MIDI_RUNTIME_DIR}"
          "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/${case}.pure"
          "-DFIXTURE=${CMAKE_CURRENT_SOURCE_DIR}/examples/prelude3.mid"
          -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake")
      set_tests_properties(pure-midi-${case} PROPERTIES
        LABELS "midi;pure;no-hardware" TIMEOUT 45
        REQUIRED_FILES "${test_pmlib};$<TARGET_FILE:midifile>")
    endforeach()

    add_custom_target(check-midi-output
      COMMAND "${CMAKE_COMMAND}" "-DRUNNER=$<TARGET_FILE:run_pure_test>"
        "-DCONTRACT_ROOT=${MIDI_CONTRACT_ROOT}"
        "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
        "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
        "-DPURE_STDLIB=${PURE_PREFIX}/lib/pure"
        "-DMODULE_DIR=$<TARGET_FILE_DIR:pmlib>"
        "-DRUNTIME_DIRS=${MIDI_RUNTIME_DIR}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunHardwareTest.cmake"
      DEPENDS run_pure_test pmlib midifile
      COMMENT "Running optional bounded MIDI output (PURE_MIDI_TEST_OUTPUT selects device)"
      VERBATIM)
  else()
    # Preserve the upstream non-Windows public tests. The native Windows job,
    # path and owned-cleanup contracts above make no POSIX verification claim.
    find_program(PURE_EXECUTABLE NAMES pure HINTS "${PURE_PREFIX}/bin" REQUIRED)
    string(RANDOM LENGTH 64 ALPHABET 0123456789abcdef portable_token)
    foreach(case IN ITEMS bounds device-timing smoke)
      set(test_pmlib "$<TARGET_FILE_DIR:pmlib>")
      if(case STREQUAL bounds)
        set(test_pmlib "$<TARGET_FILE_DIR:pure-midi-boundary-fake>")
      endif()
      file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/portable-${case}")
      add_test(NAME pure-midi-${case}
        COMMAND "${CMAKE_COMMAND}" -E env --unset=PURELIB --unset=PURE_INCLUDE --unset=PURE_LIBRARY
          "PURE_MIDI_TEST_TOKEN=${portable_token}"
          "PURE_MIDI_TEST_FIXTURE=${CMAKE_CURRENT_SOURCE_DIR}/examples/prelude3.mid"
          "${PURE_EXECUTABLE}" --norc -I "${CMAKE_CURRENT_SOURCE_DIR}"
          -I "${CMAKE_CURRENT_SOURCE_DIR}/midifile" -L "${test_pmlib}"
          -L "$<TARGET_FILE_DIR:midifile>" -x "${CMAKE_CURRENT_SOURCE_DIR}/tests/${case}.pure")
      set_tests_properties(pure-midi-${case} PROPERTIES LABELS "midi;pure;no-hardware"
        TIMEOUT 45 PASS_REGULAR_EXPRESSION "${portable_token}"
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/portable-${case}")
    endforeach()
  endif()
endif()

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/Install.cmake")
if(BUILD_TESTING AND PURE_MIDI_STRICT_WINDOWS_AUDIT)
  add_test(NAME pure-midi-install-contract
    COMMAND "${CMAKE_COMMAND}" "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DMODULE_DIR=${CMAKE_CURRENT_BINARY_DIR}" "-DPURE_PREFIX=${PURE_MIDI_PURE_PREFIX}"
      "-DRUNNER=$<TARGET_FILE:run_pure_test>"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/install_contract.cmake")
  add_test(NAME pure-midi-install-guard-contract
    COMMAND "${MIDI_POWERSHELL}" -NoProfile -NonInteractive -ExecutionPolicy Bypass
      -File "${CMAKE_CURRENT_SOURCE_DIR}/tests/install_guard_contract.ps1"
      -SourceDir "${CMAKE_CURRENT_SOURCE_DIR}" -BuildDir "${CMAKE_CURRENT_BINARY_DIR}"
      -PurePrefix "${PURE_MIDI_PURE_PREFIX}" -Runner "$<TARGET_FILE:run_pure_test>" -Suite guard)
  set_tests_properties(pure-midi-install-contract pure-midi-install-guard-contract
    PROPERTIES LABELS "midi;contract;install;no-hardware" TIMEOUT 600 RUN_SERIAL TRUE)
endif()
