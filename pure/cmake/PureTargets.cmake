include_guard(GLOBAL)

bison_target(
  PureParser
  "${CMAKE_CURRENT_SOURCE_DIR}/parser.yy"
  "${CMAKE_CURRENT_BINARY_DIR}/parser.cc"
  DEFINES_FILE "${CMAKE_CURRENT_BINARY_DIR}/parser.hh"
  COMPILE_FLAGS "-v"
)

flex_target(
  PureLexer
  "${CMAKE_CURRENT_SOURCE_DIR}/lexer.ll"
  "${CMAKE_CURRENT_BINARY_DIR}/lexer.cc"
)

add_flex_bison_dependency(PureLexer PureParser)

add_custom_target(
  pure-generated-sources
  DEPENDS ${BISON_PureParser_OUTPUTS} ${FLEX_PureLexer_OUTPUTS}
)

set(PURE_RUNTIME_SOURCES
  expr.cc
  pure_jit.cc
  interpreter.cc
  matcher.cc
  printer.cc
  runtime.cc
  symtable.cc
  util.cc
  ${BISON_PureParser_OUTPUT_SOURCE}
  ${FLEX_PureLexer_OUTPUTS}
)

if(NOT HAVE_STRPTIME)
  list(APPEND PURE_RUNTIME_SOURCES strptime.c)
endif()

llvm_map_components_to_libnames(
  PURE_LLVM_LIBRARIES
  Core
  OrcJIT
  ExecutionEngine
  MCJIT
  native
  nativecodegen
  Passes
  BitReader
  BitWriter
  Linker
  Support
)

add_library(pure-runtime SHARED ${PURE_RUNTIME_SOURCES})
add_dependencies(pure-runtime pure-generated-sources)

set_target_properties(
  pure-runtime
  PROPERTIES
    OUTPUT_NAME pure
    VERSION 8.0.0
    SOVERSION 8
    POSITION_INDEPENDENT_CODE ON
)

target_include_directories(
  pure-runtime
  PUBLIC
    "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>"
    "$<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}>"
    "$<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>"
  PRIVATE
    ${LLVM_INCLUDE_DIRS}
)

target_link_libraries(
  pure-runtime
  PRIVATE
    ${PURE_LLVM_LIBRARIES}
    PkgConfig::GMP
    PkgConfig::MPFR
    PkgConfig::PCREPOSIX
    Threads::Threads
    Iconv::Iconv
    ${CMAKE_DL_LIBS}
    m
)

add_executable(pure pure.cc)
target_include_directories(
  pure
  PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_BINARY_DIR}"
    ${LLVM_INCLUDE_DIRS}
)
target_link_libraries(
  pure
  PRIVATE
    pure-runtime
    PkgConfig::READLINE
    PkgConfig::PCREPOSIX
    Threads::Threads
)

add_library(pure-main-object OBJECT pure_main.c)
target_include_directories(
  pure-main-object
  PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_BINARY_DIR}"
)
