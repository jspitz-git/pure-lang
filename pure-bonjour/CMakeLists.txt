cmake_minimum_required(VERSION 3.25)
project(pure_bonjour VERSION 0.2 LANGUAGES C)

if(NOT WIN32)
  message(FATAL_ERROR "pure-bonjour Windows backend requires Windows")
endif()

if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
  message(FATAL_ERROR "PureBonjour supports only 64-bit Windows")
endif()

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")

add_library(pure-bonjour MODULE bonjour_windows.c)
set_target_properties(pure-bonjour PROPERTIES OUTPUT_NAME bonjour PREFIX ""
  WINDOWS_EXPORT_ALL_SYMBOLS ON)
target_compile_features(pure-bonjour PRIVATE c_std_11)
target_compile_definitions(pure-bonjour PRIVATE
  _WIN32_WINNT=0x0A00 UNICODE _UNICODE)
target_compile_options(pure-bonjour PRIVATE -Wall -Wextra -Werror)
target_link_libraries(pure-bonjour PRIVATE PkgConfig::PURE dnsapi ws2_32)

include(CTest)
if(BUILD_TESTING)
  add_library(pure-bonjour-test-backend OBJECT bonjour_windows.c)
  target_compile_features(pure-bonjour-test-backend PRIVATE c_std_11)
  target_compile_definitions(pure-bonjour-test-backend PRIVATE
    _WIN32_WINNT=0x0A00 UNICODE _UNICODE BONJOUR_WINDOWS_TESTING)
  target_compile_options(pure-bonjour-test-backend PRIVATE -Wall -Wextra -Werror)
  target_include_directories(pure-bonjour-test-backend PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR})
  target_link_libraries(pure-bonjour-test-backend PRIVATE PkgConfig::PURE)

  add_executable(pure-bonjour-unit tests/unit.c
    $<TARGET_OBJECTS:pure-bonjour-test-backend>)
  target_compile_features(pure-bonjour-unit PRIVATE c_std_11)
  target_compile_definitions(pure-bonjour-unit PRIVATE
    _WIN32_WINNT=0x0A00 UNICODE _UNICODE BONJOUR_WINDOWS_TESTING)
  target_compile_options(pure-bonjour-unit PRIVATE -Wall -Wextra -Werror -UNDEBUG)
  target_include_directories(pure-bonjour-unit PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
  target_link_libraries(pure-bonjour-unit PRIVATE PkgConfig::PURE dnsapi ws2_32)
  add_test(NAME pure-bonjour-unit COMMAND pure-bonjour-unit)
  set_tests_properties(pure-bonjour-unit PROPERTIES LABELS "bonjour;unit"
    TIMEOUT 10 ENVIRONMENT_MODIFICATION
    "PATH=path_list_prepend:${PURE_PREFIX}/bin")

  add_executable(pure-bonjour-lifecycle tests/lifecycle.c
    $<TARGET_OBJECTS:pure-bonjour-test-backend>)
  target_compile_features(pure-bonjour-lifecycle PRIVATE c_std_11)
  target_compile_definitions(pure-bonjour-lifecycle PRIVATE
    _WIN32_WINNT=0x0A00 UNICODE _UNICODE BONJOUR_WINDOWS_TESTING)
  target_compile_options(pure-bonjour-lifecycle PRIVATE
    -Wall -Wextra -Werror -UNDEBUG)
  target_include_directories(pure-bonjour-lifecycle PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR})
  target_link_libraries(pure-bonjour-lifecycle PRIVATE
    PkgConfig::PURE dnsapi ws2_32)
  add_test(NAME pure-bonjour-lifecycle COMMAND pure-bonjour-lifecycle)
  set_tests_properties(pure-bonjour-lifecycle PROPERTIES
    LABELS "bonjour;lifecycle" TIMEOUT 10 ENVIRONMENT_MODIFICATION
    "PATH=path_list_prepend:${PURE_PREFIX}/bin")

  set(PURE_BONJOUR_LOOPBACK_TIMEOUT_SECONDS 30)
  add_test(NAME pure-bonjour-smoke-budget-contract
    COMMAND "${CMAKE_COMMAND}"
      "-DRUNNER=${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunSmokeTest.cmake"
      "-DSMOKE_OUTER_TIMEOUT_SECONDS=${PURE_BONJOUR_LOOPBACK_TIMEOUT_SECONDS}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/TestSmokeBudgets.cmake")
  set_tests_properties(pure-bonjour-smoke-budget-contract PROPERTIES
    LABELS "bonjour;unit" TIMEOUT 5)

  set(PURE_EXECUTABLE "${PURE_PREFIX}/bin/pure.exe")
  if(EXISTS "${PURE_EXECUTABLE}")
    add_test(NAME pure-bonjour-loopback
      COMMAND "${CMAKE_COMMAND}"
        "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
        "-DMODULE_PATH=$<TARGET_FILE:pure-bonjour>"
        "-DWRAPPER_PATH=${CMAKE_CURRENT_SOURCE_DIR}/bonjour.pure"
        "-DSMOKE_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
        "-DSMOKE_ROOT=${CMAKE_CURRENT_BINARY_DIR}"
        "-DSMOKE_OUTER_TIMEOUT_SECONDS=${PURE_BONJOUR_LOOPBACK_TIMEOUT_SECONDS}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunSmokeTest.cmake")
    set_tests_properties(pure-bonjour-loopback PROPERTIES
      LABELS "bonjour;dnssd;integration"
      TIMEOUT ${PURE_BONJOUR_LOOPBACK_TIMEOUT_SECONDS})
  endif()
endif()
