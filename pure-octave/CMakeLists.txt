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
set(PURE_OCTAVE_TREE_SHA256
  "959C23237F0852C29E131C5034B378FF4168B84325EFE1C92A50070A8BB89607")
if (NOT OCTAVE_SIGNING_FINGERPRINT STREQUAL PURE_OCTAVE_FINGERPRINT)
  message(FATAL_ERROR
    "The configured Octave root is not the signature-validated Task 1 root.")
endif ()

set(PURE_OCTAVE_POWERSHELL
  "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe")
if (NOT EXISTS "${PURE_OCTAVE_POWERSHELL}")
  message(FATAL_ERROR
    "Windows PowerShell is required to validate the Octave root identity.")
endif ()
execute_process(
  COMMAND "${PURE_OCTAVE_POWERSHELL}" -NoLogo -NoProfile -NonInteractive
    -ExecutionPolicy Bypass
    -File "${CMAKE_CURRENT_SOURCE_DIR}/cmake/GetOctaveRootIdentity.ps1"
    -Root "${OCTAVE_ROOT_NORMALIZED}"
  RESULT_VARIABLE root_identity_result
  OUTPUT_VARIABLE root_identity
  ERROR_VARIABLE root_identity_stderr)
string(STRIP "${root_identity}" root_identity)
if (NOT root_identity_result EQUAL 0)
  message(FATAL_ERROR
    "Could not validate the Octave root content identity:\n"
    "${root_identity_stderr}")
endif ()
if (NOT root_identity STREQUAL PURE_OCTAVE_TREE_SHA256)
  message(FATAL_ERROR
    "Octave root content identity mismatch: expected "
    "${PURE_OCTAVE_TREE_SHA256}, got ${root_identity}")
endif ()
file(WRITE "${OCTAVE_ROOT_NORMALIZED}/pure-octave.fingerprint"
  "${PURE_OCTAVE_FINGERPRINT}\n${PURE_OCTAVE_TREE_SHA256}\n")

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
    RUNTIME_OUTPUT_DIRECTORY "${PURE_OCTAVE_TEST_BINARY_DIR}/runtime-stub"
    ARCHIVE_OUTPUT_DIRECTORY "${PURE_OCTAVE_TEST_BINARY_DIR}/runtime-stub")
  add_library(pure_octave_runtime_stub_missing SHARED tests/pure_runtime_stub.c)
  target_compile_definitions(pure_octave_runtime_stub_missing PRIVATE
    PURE_RUNTIME_STUB_OMIT_PURE_INT)
  set_target_properties(pure_octave_runtime_stub_missing PROPERTIES
    PREFIX ""
    OUTPUT_NAME "libpure"
    RUNTIME_OUTPUT_DIRECTORY "${PURE_OCTAVE_TEST_BINARY_DIR}/runtime-stub-missing"
    ARCHIVE_OUTPUT_DIRECTORY "${PURE_OCTAVE_TEST_BINARY_DIR}/runtime-stub-missing")
  add_library(pure_octave_runtime_stub_extra SHARED tests/pure_runtime_stub.c)
  target_compile_definitions(pure_octave_runtime_stub_extra PRIVATE
    PURE_RUNTIME_STUB_EXTRA)
  set_target_properties(pure_octave_runtime_stub_extra PROPERTIES
    PREFIX ""
    OUTPUT_NAME "libpure"
    RUNTIME_OUTPUT_DIRECTORY "${PURE_OCTAVE_TEST_BINARY_DIR}/runtime-stub-extra"
    ARCHIVE_OUTPUT_DIRECTORY "${PURE_OCTAVE_TEST_BINARY_DIR}/runtime-stub-extra")
  add_executable(pure_octave_absolute_preload tests/absolute_preload.c)
  set_target_properties(pure_octave_absolute_preload PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${PURE_OCTAVE_TEST_BINARY_DIR}")
  add_executable(pure_octave_restricted_runner tests/restricted_runner.c)
  target_link_libraries(pure_octave_restricted_runner PRIVATE advapi32)
  target_link_options(pure_octave_restricted_runner PRIVATE -municode)
  set_target_properties(pure_octave_restricted_runner PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${PURE_OCTAVE_TEST_BINARY_DIR}")

  file(TO_CMAKE_PATH "$ENV{USERPROFILE}/AppData/LocalLow"
    PURE_OCTAVE_LOW_INTEGRITY_BASE)

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
    "-DCMAKE_MAKE_PROGRAM=@CMAKE_MAKE_PROGRAM@"
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
  add_test(NAME pure-octave-root-identity
    COMMAND "${CMAKE_COMMAND}"
      "-DCMAKE_COMMAND=${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DGENERATOR=${CMAKE_GENERATOR}"
      "-DC_COMPILER=${CMAKE_C_COMPILER}"
      "-DMAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}"
      "-DPURE_PREFIX=${PURE_PREFIX}"
      "-DSIGNING_FINGERPRINT=${PURE_OCTAVE_FINGERPRINT}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RootIdentityRegression.cmake")
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

  add_test(NAME pure-octave-callbacks
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_PREFIX}/bin/pure.exe"
      "-DPURE_PREFIX=${PURE_PREFIX}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DBRIDGE_DIR=${PURE_OCTAVE_LIBRARY_DIR}"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/callbacks.pure"
      "-DOCTAVE_ROOT=${OCTAVE_ROOT_NORMALIZED}"
      "-DEXPECTED_OUTPUT=PURE_OCTAVE_CALLBACKS_OK"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake")

  add_test(NAME pure-octave-errors
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_PREFIX}/bin/pure.exe"
      "-DPURE_PREFIX=${PURE_PREFIX}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DBRIDGE_DIR=${PURE_OCTAVE_LIBRARY_DIR}"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/errors.pure"
      "-DOCTAVE_ROOT=${OCTAVE_ROOT_NORMALIZED}"
      "-DEXPECTED_OUTPUT=PURE_OCTAVE_ERRORS_OK"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake")

  string(SHA256 lifecycle_build_id "${CMAKE_CURRENT_BINARY_DIR}")
  string(SUBSTRING "${lifecycle_build_id}" 0 16 lifecycle_build_id)
  foreach (lifecycle_process RANGE 1 20)
    set(lifecycle_test_name
      "pure-octave-lifecycle-${lifecycle_process}")
    set(lifecycle_audit_dir
      "${PURE_OCTAVE_LOW_INTEGRITY_BASE}/pure-octave-${lifecycle_build_id}-lifecycle-${lifecycle_process}")
    set(lifecycle_work_dir
      "${lifecycle_audit_dir}/work")
    add_test(NAME "${lifecycle_test_name}"
      COMMAND "${CMAKE_COMMAND}"
        "-DPURE_EXECUTABLE=${PURE_PREFIX}/bin/pure.exe"
        "-DPURE_PREFIX=${PURE_PREFIX}"
        "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
        "-DBRIDGE_DIR=${PURE_OCTAVE_LIBRARY_DIR}"
        "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/lifecycle.pure"
        "-DOCTAVE_ROOT=${OCTAVE_ROOT_NORMALIZED}"
        "-DTEST_WORKING_DIRECTORY=${lifecycle_work_dir}"
        "-DTEST_HOME=${lifecycle_work_dir}"
        "-DEXPECTED_OUTPUT=PURE_OCTAVE_LIFECYCLE_OK"
        "-DWRITE_AUDIT_ROOT=${lifecycle_audit_dir}"
        "-DALLOWED_WRITE_ROOT=${lifecycle_work_dir}"
        "-DRESTRICT_WRITES=ON"
        "-DRESTRICTED_RUNNER=$<TARGET_FILE:pure_octave_restricted_runner>"
        "-DCLEAN_WRITE_AUDIT_ROOT=ON"
        "-DWRITE_AUDIT_CLEANUP_BASE=${PURE_OCTAVE_LOW_INTEGRITY_BASE}"
        "-DREQUIRE_CLEAN_OUTPUT=ON"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake")
    set_tests_properties("${lifecycle_test_name}" PROPERTIES
      ENVIRONMENT
        "TEMP=${lifecycle_work_dir};TMP=${lifecycle_work_dir}"
      RESOURCE_LOCK pure_octave_interpreter TIMEOUT 60)
  endforeach ()

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

  add_test(NAME pure-octave-write-audit-regression
    COMMAND "${CMAKE_COMMAND}"
      "-DCMAKE_COMMAND=${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_PREFIX}/bin/pure.exe"
      "-DPURE_PREFIX=${PURE_PREFIX}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DBRIDGE_DIR=${PURE_OCTAVE_LIBRARY_DIR}"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/poison_write.pure"
      "-DOCTAVE_ROOT=${OCTAVE_ROOT_NORMALIZED}"
      "-DRUN_PURE_TEST=${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake"
      "-DWORK_ROOT=${PURE_OCTAVE_TEST_BINARY_DIR}/write-audit-regression"
      "-DEXPECTED_OUTPUT=PURE_OCTAVE_POISON_WRITE_OK"
      "-DEXPECTED_DIAGNOSTIC=Pure/Octave test wrote outside its controlled work directory"
      -P
        "${CMAKE_CURRENT_SOURCE_DIR}/cmake/ExpectPureTestWriteAuditFailure.cmake")

  add_test(NAME pure-octave-write-confinement
    COMMAND "${CMAKE_COMMAND}"
      "-DCMAKE_COMMAND=${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_PREFIX}/bin/pure.exe"
      "-DPURE_PREFIX=${PURE_PREFIX}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DBRIDGE_DIR=${PURE_OCTAVE_LIBRARY_DIR}"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/poison_escape.pure"
      "-DOCTAVE_ROOT=${OCTAVE_ROOT_NORMALIZED}"
      "-DRUN_PURE_TEST=${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake"
      "-DRESTRICTED_RUNNER=$<TARGET_FILE:pure_octave_restricted_runner>"
      "-DWORK_ROOT=${PURE_OCTAVE_LOW_INTEGRITY_BASE}/pure-octave-${lifecycle_build_id}-write-confinement"
      "-DWRITE_AUDIT_CLEANUP_BASE=${PURE_OCTAVE_LOW_INTEGRITY_BASE}"
      "-DOUTSIDE_POISON=${CMAKE_CURRENT_BINARY_DIR}/pure-octave-write-escape-poison.txt"
      "-DEXPECTED_OUTPUT=PURE_OCTAVE_OUTSIDE_WRITE_DENIED_OK"
      "-DEXPECTED_RESULT=14"
      -P
        "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTestWriteConfinement.cmake")

  add_test(NAME pure-octave-absolute-preload
    COMMAND "${CMAKE_COMMAND}"
      "-DHELPER=$<TARGET_FILE:pure_octave_absolute_preload>"
      "-DLOADER=$<TARGET_FILE:octave_embed>"
      "-DIMPLEMENTATION=${PURE_OCTAVE_IMPL}"
      "-DPURE_RUNTIME_STUB=$<TARGET_FILE:pure_octave_runtime_stub>"
      "-DTEST_BINARY_DIR=${PURE_OCTAVE_TEST_BINARY_DIR}"
      "-DOBJDUMP=${OCTAVE_RUNTIME_DIR}/objdump.exe"
      "-DPOISON_DLL=$<TARGET_FILE:pure_octave_poison>"
      "-DSOURCE_RUNTIME_DIR=${OCTAVE_RUNTIME_DIR}"
      "-DSOURCE_MODULE_DIR=${OCTAVE_MODULE_DIR}"
      "-DSOURCE_FINGERPRINT=${OCTAVE_ROOT_NORMALIZED}/pure-octave.fingerprint"
      "-DWORK_ROOT=${CMAKE_CURRENT_BINARY_DIR}/absolute-preload-test"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunAbsolutePreloadTest.cmake")
  add_test(NAME pure-octave-runtime-stub-rejects-missing
    COMMAND "${CMAKE_COMMAND}"
      "-DAUDIT_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/cmake/AuditPureRuntimeStub.cmake"
      "-DOBJDUMP=${OCTAVE_RUNTIME_DIR}/objdump.exe"
      "-DIMPLEMENTATION=${PURE_OCTAVE_IMPL}"
      "-DPURE_RUNTIME_STUB=$<TARGET_FILE:pure_octave_runtime_stub_missing>"
      "-DEXPECTED_DIAGNOSTIC=Missing exports: pure_int"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/ExpectPureRuntimeStubAuditFailure.cmake")
  add_test(NAME pure-octave-runtime-stub-rejects-extra
    COMMAND "${CMAKE_COMMAND}"
      "-DAUDIT_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/cmake/AuditPureRuntimeStub.cmake"
      "-DOBJDUMP=${OCTAVE_RUNTIME_DIR}/objdump.exe"
      "-DIMPLEMENTATION=${PURE_OCTAVE_IMPL}"
      "-DPURE_RUNTIME_STUB=$<TARGET_FILE:pure_octave_runtime_stub_extra>"
      "-DEXPECTED_DIAGNOSTIC=Unexpected exports: pure_runtime_stub_extra"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/ExpectPureRuntimeStubAuditFailure.cmake")

  set_tests_properties(
    pure-octave-basic pure-octave-conversions pure-octave-function-values
    pure-octave-callbacks
    pure-octave-errors
    pure-octave-poison-init pure-octave-absolute-preload
    pure-octave-write-audit-regression
    pure-octave-write-confinement
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

  set(runtime_ownership_audit
    "${CMAKE_CURRENT_SOURCE_DIR}/cmake/AuditRuntimeOwnership.cmake")
  add_test(NAME pure-octave-runtime-ownership
    COMMAND "${CMAKE_COMMAND}"
      "-DOBJDUMP=${OCTAVE_RUNTIME_DIR}/objdump.exe"
      "-DLOADER=$<TARGET_FILE:octave_embed>"
      "-DIMPLEMENTATION=${PURE_OCTAVE_IMPL}"
      "-DPURE_LIBRARY=${PURE_PREFIX}/bin/libpure.dll"
      "-DPURE_RUNTIME_DIR=${PURE_PREFIX}/bin"
      "-DOCTAVE_RUNTIME_DIR=${OCTAVE_RUNTIME_DIR}"
      -P "${runtime_ownership_audit}")
  add_test(NAME pure-octave-runtime-ownership-rejects-foreign-pure-runtime
    COMMAND "${CMAKE_COMMAND}"
      "-DCMAKE_COMMAND=${CMAKE_COMMAND}"
      "-DAUDIT_SCRIPT=${runtime_ownership_audit}"
      "-DOBJDUMP=${OCTAVE_RUNTIME_DIR}/objdump.exe"
      "-DLOADER=$<TARGET_FILE:octave_embed>"
      "-DIMPLEMENTATION=${PURE_OCTAVE_IMPL}"
      "-DPURE_LIBRARY=${OCTAVE_RUNTIME_DIR}/libstdc++-6.dll"
      "-DPURE_RUNTIME_DIR=${PURE_PREFIX}/bin"
      "-DOCTAVE_RUNTIME_DIR=${OCTAVE_RUNTIME_DIR}"
      "-DEXPECTED_DIAGNOSTIC=Pure runtime must import libc++.dll"
      -P
        "${CMAKE_CURRENT_SOURCE_DIR}/cmake/ExpectRuntimeOwnershipAuditFailure.cmake")
endif ()
