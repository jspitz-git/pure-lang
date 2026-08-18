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
target_compile_definitions(pure-bonjour PRIVATE _WIN32_WINNT=0x0A00)
target_compile_options(pure-bonjour PRIVATE -Wall -Wextra -Werror)
target_link_libraries(pure-bonjour PRIVATE PkgConfig::PURE dnsapi ws2_32)

include(CTest)
if(BUILD_TESTING)
  add_executable(pure-bonjour-unit tests/unit.c bonjour_windows.c)
  target_compile_features(pure-bonjour-unit PRIVATE c_std_11)
  target_compile_definitions(pure-bonjour-unit PRIVATE
    _WIN32_WINNT=0x0A00 BONJOUR_WINDOWS_TESTING)
  target_compile_options(pure-bonjour-unit PRIVATE -Wall -Wextra -Werror -UNDEBUG)
  target_include_directories(pure-bonjour-unit PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
  target_link_libraries(pure-bonjour-unit PRIVATE PkgConfig::PURE dnsapi ws2_32)
  add_test(NAME pure-bonjour-unit COMMAND pure-bonjour-unit)
endif()
