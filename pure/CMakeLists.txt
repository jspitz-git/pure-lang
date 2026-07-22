cmake_minimum_required(VERSION 3.25)

project(
  pure
  VERSION 0.68
  DESCRIPTION "The Pure programming language interpreter and runtime"
  LANGUAGES C CXX
)

list(PREPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED YES)
set(CMAKE_CXX_EXTENSIONS NO)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

include(PureToolchain)
include(PureDependencies)
include(PureConfigure)
include(PureTargets)

message(STATUS "Pure ${PROJECT_VERSION} configured")
