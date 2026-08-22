cmake_minimum_required(VERSION 3.25)

foreach(required_variable IN ITEMS
    PUREPAD_CMAKE_COMMAND
    PUREPAD_BUILD_DIR
    PUREPAD_SOURCE_DIR
    PUREPAD_CONFIGURATION
    PUREPAD_CMAKE_MT
    PUREPAD_PE_FIXTURE_MUTATOR)
  if(NOT DEFINED ${required_variable} OR "${${required_variable}}" STREQUAL "")
    message(FATAL_ERROR "${required_variable} is required")
  endif()
endforeach()

string(RANDOM LENGTH 12 ALPHABET 0123456789abcdef purepad_install_suffix)
set(purepad_install_prefix
  "${CMAKE_CURRENT_BINARY_DIR}/purepad-install-contract-${purepad_install_suffix}")

execute_process(
  COMMAND "${PUREPAD_CMAKE_COMMAND}" --install "${PUREPAD_BUILD_DIR}"
    --config "${PUREPAD_CONFIGURATION}"
    --component PurePad
    --prefix "${purepad_install_prefix}"
  RESULT_VARIABLE purepad_install_result
  OUTPUT_VARIABLE purepad_install_stdout
  ERROR_VARIABLE purepad_install_stderr)
if(NOT purepad_install_result EQUAL 0)
  message(FATAL_ERROR
    "PurePad component install failed:\n${purepad_install_stdout}${purepad_install_stderr}")
endif()

set(purepad_executable "${purepad_install_prefix}/bin/purepad.exe")
set(purepad_documentation "${purepad_install_prefix}/share/doc/purepad/WINDOWS.md")
set(purepad_manifest "${purepad_install_prefix}/purepad.manifest")
if(NOT EXISTS "${purepad_executable}")
  message(FATAL_ERROR "PurePad component did not install ${purepad_executable}")
endif()
if(NOT EXISTS "${purepad_documentation}")
  message(FATAL_ERROR "PurePad component did not install ${purepad_documentation}")
endif()

execute_process(
  COMMAND "${PUREPAD_CMAKE_COMMAND}"
    "-DPUREPAD_EXECUTABLE=${purepad_executable}"
    "-DPUREPAD_SOURCE_DIR=${PUREPAD_SOURCE_DIR}"
    "-DPUREPAD_BUILD_DIR=${PUREPAD_BUILD_DIR}"
    "-DPUREPAD_CMAKE_MT=${PUREPAD_CMAKE_MT}"
    "-DPUREPAD_MANIFEST=${purepad_manifest}"
    -P "${PUREPAD_SOURCE_DIR}/cmake/VerifyInstalledPurePad.cmake"
  RESULT_VARIABLE purepad_verify_result
  OUTPUT_VARIABLE purepad_verify_stdout
  ERROR_VARIABLE purepad_verify_stderr)
if(NOT purepad_verify_result EQUAL 0)
  message(FATAL_ERROR
    "PurePad installed executable verification failed:\n"
    "${purepad_verify_stdout}${purepad_verify_stderr}")
endif()

message(STATUS "PurePad verifier output:\n${purepad_verify_stdout}")
set(purepad_expected_runtime_report
  "PurePad Microsoft runtime dependencies for TODO-49: mfc140u.dll;msvcp140.dll;vcruntime140.dll;vcruntime140_1.dll")
string(FIND "${purepad_verify_stdout}" "${purepad_expected_runtime_report}"
  purepad_runtime_report_index)
if(purepad_runtime_report_index EQUAL -1)
  message(FATAL_ERROR
    "PurePad verifier did not report the normalized Microsoft runtime "
    "contract: ${purepad_expected_runtime_report}")
endif()

set(purepad_fixture_runtime_dependencies
  "C:/Windows/System32/mfc140u.dll"
  "C:/Windows/System32/msvcp140.dll"
  "C:/Windows/System32/vcruntime140.dll"
  "C:/Windows/System32/vcruntime140_1.dll")

function(purepad_expect_pe_rejection executable expected_message label)
  execute_process(
    COMMAND "${PUREPAD_CMAKE_COMMAND}"
      "-DPUREPAD_EXECUTABLE=${executable}"
      "-DPUREPAD_SOURCE_DIR=${PUREPAD_SOURCE_DIR}"
      "-DPUREPAD_BUILD_DIR=${PUREPAD_BUILD_DIR}"
      "-DPUREPAD_CMAKE_MT=${PUREPAD_CMAKE_MT}"
      "-DPUREPAD_MANIFEST=${purepad_manifest}"
      "-DPUREPAD_TEST_RESOLVED_DEPENDENCIES=${purepad_fixture_runtime_dependencies}"
      "-DPUREPAD_TEST_UNRESOLVED_DEPENDENCIES="
      -P "${PUREPAD_SOURCE_DIR}/cmake/VerifyInstalledPurePad.cmake"
    RESULT_VARIABLE verify_result
    OUTPUT_VARIABLE verify_stdout
    ERROR_VARIABLE verify_stderr)
  set(verify_output "${verify_stdout}${verify_stderr}")
  if(verify_result EQUAL 0)
    message(FATAL_ERROR
      "PurePad verifier accepted ${label}")
  endif()
  if(NOT verify_output MATCHES "${expected_message}")
    message(FATAL_ERROR
      "PurePad verifier rejected ${label} for the wrong reason:\n"
      "${verify_output}")
  endif()
endfunction()

set(purepad_wrong_machine "${purepad_install_prefix}/wrong-machine.exe")
execute_process(
  COMMAND "${PUREPAD_PE_FIXTURE_MUTATOR}" "${purepad_executable}"
    "${purepad_wrong_machine}" --machine-i386
  RESULT_VARIABLE purepad_machine_mutation_result)
if(NOT purepad_machine_mutation_result EQUAL 0)
  message(FATAL_ERROR "Could not create wrong-machine PurePad fixture")
endif()
purepad_expect_pe_rejection("${purepad_wrong_machine}" "machine AMD64"
  "an I386 executable")

set(purepad_wrong_subsystem "${purepad_install_prefix}/wrong-subsystem.exe")
execute_process(
  COMMAND "${PUREPAD_PE_FIXTURE_MUTATOR}" "${purepad_executable}"
    "${purepad_wrong_subsystem}" --subsystem-console
  RESULT_VARIABLE purepad_subsystem_mutation_result)
if(NOT purepad_subsystem_mutation_result EQUAL 0)
  message(FATAL_ERROR "Could not create wrong-subsystem PurePad fixture")
endif()
purepad_expect_pe_rejection("${purepad_wrong_subsystem}"
  "Windows GUI subsystem" "a Console-subsystem executable")

set(purepad_unresolved_source_leak
  "${PUREPAD_SOURCE_DIR}/fixtures/../unresolved-leak.dll")
execute_process(
  COMMAND "${PUREPAD_CMAKE_COMMAND}"
    "-DPUREPAD_EXECUTABLE=${purepad_executable}"
    "-DPUREPAD_SOURCE_DIR=${PUREPAD_SOURCE_DIR}"
    "-DPUREPAD_BUILD_DIR=${PUREPAD_BUILD_DIR}"
    "-DPUREPAD_CMAKE_MT=${PUREPAD_CMAKE_MT}"
    "-DPUREPAD_MANIFEST=${purepad_manifest}"
    "-DPUREPAD_TEST_UNRESOLVED_DEPENDENCIES=${purepad_unresolved_source_leak}"
    -P "${PUREPAD_SOURCE_DIR}/cmake/VerifyInstalledPurePad.cmake"
  RESULT_VARIABLE purepad_leak_result
  OUTPUT_VARIABLE purepad_leak_stdout
  ERROR_VARIABLE purepad_leak_stderr)
if(purepad_leak_result EQUAL 0)
  message(FATAL_ERROR
    "PurePad verifier accepted an unresolved dependency under the source tree")
endif()
set(purepad_leak_output "${purepad_leak_stdout}${purepad_leak_stderr}")
if(NOT purepad_leak_output MATCHES "embedded under")
  message(FATAL_ERROR
    "PurePad verifier failed for the wrong reason:\n${purepad_leak_output}")
endif()

file(REMOVE_RECURSE "${purepad_install_prefix}")
if(EXISTS "${purepad_install_prefix}")
  message(FATAL_ERROR
    "PurePad install-contract cleanup left ${purepad_install_prefix}")
endif()
