cmake_minimum_required(VERSION 3.25)

foreach(required_variable IN ITEMS
    PUREPAD_CMAKE_COMMAND
    PUREPAD_BUILD_DIR
    PUREPAD_SOURCE_DIR
    PUREPAD_CONFIGURATION
    PUREPAD_CMAKE_MT)
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
    -P "${PUREPAD_SOURCE_DIR}/cmake/VerifyInstalledPurePad.cmake"
  RESULT_VARIABLE purepad_verify_result
  OUTPUT_VARIABLE purepad_verify_stdout
  ERROR_VARIABLE purepad_verify_stderr)
if(NOT purepad_verify_result EQUAL 0)
  message(FATAL_ERROR
    "PurePad installed executable verification failed:\n"
    "${purepad_verify_stdout}${purepad_verify_stderr}")
endif()
