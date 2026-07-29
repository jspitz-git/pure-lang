cmake_minimum_required(VERSION 3.20)

project(PureOctaveWindowsToolchain LANGUAGES C)

include(CTest)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

set(PURE_PREFIX "${PURE_PREFIX}" CACHE PATH "Relocatable Pure prefix")
set(OCTAVE_ROOT "${OCTAVE_ROOT}" CACHE PATH "Root of the validated Octave distribution")
set(GPG_EXECUTABLE "${GPG_EXECUTABLE}" CACHE FILEPATH "GnuPG executable used to validate Octave")
set(PURE_OCTAVE_WORK_ROOT "${CMAKE_BINARY_DIR}/pure-octave-work" CACHE PATH
  "Temporary work root for a signed Octave distribution")

if (NOT OCTAVE_ROOT)
  include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/AcquireWindowsOctave.cmake")
  acquire_windows_octave(OCTAVE_ROOT
    WORK_ROOT "${PURE_OCTAVE_WORK_ROOT}"
    GPG_EXECUTABLE "${GPG_EXECUTABLE}")
endif ()

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/OctaveToolchain.cmake")
pure_octave_validate_toolchain()

set(PURE_OCTAVE_ABI "pure-octave/11.3.0/windows-x86_64/v1")
set(PURE_OCTAVE_FINGERPRINT
  "DBD9C84E39FE1AAE99F04446B05F05B75D36644B")
if (NOT OCTAVE_SIGNING_FINGERPRINT STREQUAL PURE_OCTAVE_FINGERPRINT)
  message(FATAL_ERROR
    "The configured Octave root is not the signature-validated Task 1 root.")
endif ()
file(WRITE "${OCTAVE_ROOT_NORMALIZED}/pure-octave.fingerprint"
  "${PURE_OCTAVE_FINGERPRINT}\n")

set(PURE_OCTAVE_LIBRARY_DIR "${CMAKE_CURRENT_BINARY_DIR}/lib/pure")
file(MAKE_DIRECTORY "${PURE_OCTAVE_LIBRARY_DIR}")

add_library(octave_embed SHARED octave_loader.c)
target_compile_definitions(octave_embed PRIVATE PURE_OCTAVE_LOADER_BUILD)
target_include_directories(octave_embed PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
set_target_properties(octave_embed PROPERTIES
  PREFIX ""
  OUTPUT_NAME "octave_embed"
  RUNTIME_OUTPUT_DIRECTORY "${PURE_OCTAVE_LIBRARY_DIR}"
  LIBRARY_OUTPUT_DIRECTORY "${PURE_OCTAVE_LIBRARY_DIR}")

set(PURE_OCTAVE_IMPL "${PURE_OCTAVE_LIBRARY_DIR}/octave_bridge_impl.dll")
set(PURE_OCTAVE_IMPL_SCRIPT
  "${CMAKE_CURRENT_BINARY_DIR}/build-octave-implementation.cmake")
file(CONFIGURE OUTPUT "${PURE_OCTAVE_IMPL_SCRIPT}" CONTENT [=[
set(ENV{PATH} "@OCTAVE_RUNTIME_DIR@;C:/Windows/System32;C:/Windows")
unset(ENV{OCTAVE_HOME})
unset(ENV{OCTAVE_EXEC_HOME})
unset(ENV{OCTAVE_PATH})
unset(ENV{OCTAVE_EXEC_PATH})
execute_process(
  COMMAND "@OCTAVE_MKOCTFILE@" --link-stand-alone -shared
    -DPURE_OCTAVE_IMPL_BUILD "-I@CMAKE_CURRENT_SOURCE_DIR@"
    "-I@PURE_PREFIX@/include/pure" "-L@PURE_PREFIX@/lib" -lpure
    "-I@PURE_PREFIX@/include"
    -o "octave_bridge_impl.dll" "@CMAKE_CURRENT_SOURCE_DIR@/embed.cc"
  WORKING_DIRECTORY "@PURE_OCTAVE_LIBRARY_DIR@"
  RESULT_VARIABLE build_result
  OUTPUT_VARIABLE build_stdout
  ERROR_VARIABLE build_stderr)
if (NOT build_result EQUAL 0)
  message(FATAL_ERROR
    "mkoctfile failed (${build_result}):\n${build_stdout}${build_stderr}")
endif ()
]=] @ONLY)
add_custom_command(
  OUTPUT "${PURE_OCTAVE_IMPL}"
  COMMAND "${CMAKE_COMMAND}" -P "${PURE_OCTAVE_IMPL_SCRIPT}"
  DEPENDS embed.cc embed.h octave_bridge_api.h
  VERBATIM)
add_custom_target(octave_bridge_impl ALL DEPENDS "${PURE_OCTAVE_IMPL}")

if (BUILD_TESTING)
  set(PURE_OCTAVE_TEST_BINARY_DIR
    "${CMAKE_CURRENT_BINARY_DIR}/pure-octave-tests")
  add_library(pure_octave_poison SHARED tests/poison_octinterp.c)
  set_target_properties(pure_octave_poison PROPERTIES
    PREFIX ""
    OUTPUT_NAME "liboctinterp-15"
    RUNTIME_OUTPUT_DIRECTORY "${PURE_OCTAVE_TEST_BINARY_DIR}/poison")
  add_library(pure_octave_runtime_stub SHARED tests/pure_runtime_stub.c)
  set_target_properties(pure_octave_runtime_stub PROPERTIES
    PREFIX ""
    OUTPUT_NAME "libpure"
    RUNTIME_OUTPUT_DIRECTORY "${PURE_OCTAVE_TEST_BINARY_DIR}/runtime-stub")
  add_executable(pure_octave_absolute_preload tests/absolute_preload.c)
  set_target_properties(pure_octave_absolute_preload PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${PURE_OCTAVE_TEST_BINARY_DIR}")

  if (NOT EXISTS "${PURE_PREFIX}/bin/pure.exe")
    message(FATAL_ERROR "PURE_PREFIX does not contain bin/pure.exe: ${PURE_PREFIX}")
  endif ()
  if (NOT EXISTS "${OCTAVE_RUNTIME_DIR}/objdump.exe")
    message(FATAL_ERROR
      "The validated Octave root does not contain objdump.exe.")
  endif ()

  set(rejected_root_test "${CMAKE_CURRENT_BINARY_DIR}/pure-octave-rejected-root.cmake")
  file(CONFIGURE OUTPUT "${rejected_root_test}" CONTENT [=[
set(fake_root "@CMAKE_CURRENT_BINARY_DIR@/fake-octave-root")
file(MAKE_DIRECTORY "${fake_root}/bin")
file(WRITE "${fake_root}/bin/octave-cli.exe" "")
execute_process(
  COMMAND "@CMAKE_COMMAND@" -S "@CMAKE_CURRENT_SOURCE_DIR@" -B "@CMAKE_CURRENT_BINARY_DIR@/fake-octave-build"
    -G "@CMAKE_GENERATOR@" "-DCMAKE_C_COMPILER=@CMAKE_C_COMPILER@"
    -DBUILD_TESTING=OFF "-DPURE_PREFIX=@PURE_PREFIX@"
    "-DOCTAVE_ROOT=${fake_root}"
  RESULT_VARIABLE configure_result
  OUTPUT_VARIABLE configure_stdout
  ERROR_VARIABLE configure_stderr)
set(configure_output "${configure_stdout}${configure_stderr}")
if (configure_result EQUAL 0)
  message(FATAL_ERROR "The incomplete fake Octave root unexpectedly configured.")
endif ()
foreach (required_text
    "Missing required Octave 11.3.0 toolchain paths:"
    "mkoctfile"
    "public headers"
    "import libraries"
    "runtime directory"
    "module directory"
    "share directory")
  string(FIND "${configure_output}" "${required_text}" found_text)
  if (found_text EQUAL -1)
    message(FATAL_ERROR "Rejected-root diagnostic omitted '${required_text}':\n${configure_output}")
  endif ()
endforeach ()
]=] @ONLY)
  add_test(NAME pure-octave-rejected-root
    COMMAND "${CMAKE_COMMAND}" -P "${rejected_root_test}")
  add_test(NAME pure-octave-extraction-containment
    COMMAND "${CMAKE_COMMAND}" -P
      "${CMAKE_CURRENT_SOURCE_DIR}/cmake/ContainmentRegression.cmake")

  add_test(NAME pure-octave-embed-probe
    COMMAND "${CMAKE_COMMAND}"
      "-DMKOCTFILE=${OCTAVE_MKOCTFILE}"
      "-DPROBE_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}/probes/embed_probe.cc"
      "-DPROBE_BINARY=${CMAKE_CURRENT_BINARY_DIR}/embed_probe.exe"
      "-DOCTAVE_RUNTIME_DIR=${OCTAVE_RUNTIME_DIR}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunEmbedProbe.cmake")

  add_test(NAME pure-octave-basic
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_PREFIX}/bin/pure.exe"
      "-DPURE_PREFIX=${PURE_PREFIX}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DBRIDGE_DIR=${PURE_OCTAVE_LIBRARY_DIR}"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/basic.pure"
      "-DOCTAVE_ROOT=${OCTAVE_ROOT_NORMALIZED}"
      "-DEXPECTED_OUTPUT=PURE_OCTAVE_BASIC_OK"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake")

  add_test(NAME pure-octave-conversions
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_PREFIX}/bin/pure.exe"
      "-DPURE_PREFIX=${PURE_PREFIX}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DBRIDGE_DIR=${PURE_OCTAVE_LIBRARY_DIR}"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/conversions.pure"
      "-DOCTAVE_ROOT=${OCTAVE_ROOT_NORMALIZED}"
      "-DEXPECTED_OUTPUT=PURE_OCTAVE_CONVERSIONS_OK"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake")

  add_test(NAME pure-octave-function-values
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_PREFIX}/bin/pure.exe"
      "-DPURE_PREFIX=${PURE_PREFIX}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DBRIDGE_DIR=${PURE_OCTAVE_LIBRARY_DIR}"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/function-values.pure"
      "-DOCTAVE_ROOT=${OCTAVE_ROOT_NORMALIZED}"
      "-DEXPECTED_OUTPUT=PURE_OCTAVE_FUNCTION_VALUES_OK"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake")

  add_test(NAME pure-octave-poison-init
    COMMAND "${CMAKE_COMMAND}"
      "-DCMAKE_COMMAND=${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_PREFIX}/bin/pure.exe"
      "-DPURE_PREFIX=${PURE_PREFIX}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DBRIDGE_DIR=${PURE_OCTAVE_LIBRARY_DIR}"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/poison_init.pure"
      "-DOCTAVE_ROOT=${OCTAVE_ROOT_NORMALIZED}"
      "-DRUN_PURE_TEST=${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake"
      "-DWORK_ROOT=${CMAKE_CURRENT_BINARY_DIR}/poison-init-test"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPoisonInitTest.cmake")

  add_test(NAME pure-octave-absolute-preload
    COMMAND "${CMAKE_COMMAND}"
      "-DHELPER=$<TARGET_FILE:pure_octave_absolute_preload>"
      "-DLOADER=$<TARGET_FILE:octave_embed>"
      "-DPURE_RUNTIME_STUB=$<TARGET_FILE:pure_octave_runtime_stub>"
      "-DTEST_BINARY_DIR=${PURE_OCTAVE_TEST_BINARY_DIR}"
      "-DOBJDUMP=${OCTAVE_RUNTIME_DIR}/objdump.exe"
      "-DPOISON_DLL=$<TARGET_FILE:pure_octave_poison>"
      "-DSOURCE_RUNTIME_DIR=${OCTAVE_RUNTIME_DIR}"
      "-DSOURCE_MODULE_DIR=${OCTAVE_MODULE_DIR}"
      "-DSOURCE_FINGERPRINT=${OCTAVE_ROOT_NORMALIZED}/pure-octave.fingerprint"
      "-DWORK_ROOT=${CMAKE_CURRENT_BINARY_DIR}/absolute-preload-test"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunAbsolutePreloadTest.cmake")
  set_tests_properties(
    pure-octave-basic pure-octave-conversions pure-octave-function-values
    pure-octave-poison-init pure-octave-absolute-preload
    PROPERTIES RESOURCE_LOCK pure_octave_interpreter)

  set(loader_audit_test
    "${CMAKE_CURRENT_BINARY_DIR}/pure-octave-loader-audit.cmake")
  file(CONFIGURE OUTPUT "${loader_audit_test}" CONTENT [=[
execute_process(
  COMMAND "@OCTAVE_RUNTIME_DIR@/objdump.exe" -p
    "@PURE_OCTAVE_LIBRARY_DIR@/octave_embed.dll"
  RESULT_VARIABLE audit_result
  OUTPUT_VARIABLE audit_output
  ERROR_VARIABLE audit_stderr)
if (NOT audit_result EQUAL 0)
  message(FATAL_ERROR "Could not inspect octave_embed.dll:\n${audit_stderr}")
endif ()
if (audit_output MATCHES "DLL Name:[^\r\n]*[Oo]ctave")
  message(FATAL_ERROR "Stable loader has a static Octave import:\n${audit_output}")
endif ()
foreach (required_export octave_init octave_fini octave_eval octave_last_error
    octave_get octave_set octave_call octave_func octave_valuep octave_free
    octave_converters)
  if (NOT audit_output MATCHES "[ \t]${required_export}(\r?\n|$)")
    message(FATAL_ERROR "Stable loader omitted export ${required_export}.")
  endif ()
endforeach ()
]=] @ONLY)
  add_test(NAME pure-octave-loader
    COMMAND "${CMAKE_COMMAND}" -P "${loader_audit_test}")

  set(dependency_audit_test
    "${CMAKE_CURRENT_BINARY_DIR}/pure-octave-dependency-audit.cmake")
  file(CONFIGURE OUTPUT "${dependency_audit_test}" CONTENT [=[
execute_process(
  COMMAND "@OCTAVE_RUNTIME_DIR@/objdump.exe" -p
    "@PURE_OCTAVE_IMPL@"
  RESULT_VARIABLE audit_result
  OUTPUT_VARIABLE audit_output
  ERROR_VARIABLE audit_stderr)
if (NOT audit_result EQUAL 0)
  message(FATAL_ERROR
    "Could not inspect octave_bridge_impl.dll:\n${audit_stderr}")
endif ()
foreach (required_import liboctave liboctinterp)
  if (NOT audit_output MATCHES "DLL Name: ${required_import}-[0-9]+\\.dll")
    message(FATAL_ERROR
      "Implementation omitted ${required_import} import:\n${audit_output}")
  endif ()
endforeach ()
string(REGEX MATCHALL
  "DLL Name: (liboctave|liboctinterp)-[0-9]+\\.dll"
  octave_import_lines "${audit_output}")
foreach (import_line IN LISTS octave_import_lines)
  string(REGEX REPLACE "^DLL Name: " "" import_name "${import_line}")
  if (NOT EXISTS "@OCTAVE_RUNTIME_DIR@/${import_name}")
    message(FATAL_ERROR
      "Octave import is absent from the explicit root: ${import_name}")
  endif ()
endforeach ()
]=] @ONLY)
  add_test(NAME pure-octave-dependencies
    COMMAND "${CMAKE_COMMAND}" -P "${dependency_audit_test}")
endif ()
