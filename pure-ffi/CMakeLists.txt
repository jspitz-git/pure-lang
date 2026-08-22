cmake_minimum_required(VERSION 3.25)

project(pure-ffi VERSION 0.16 LANGUAGES C)

include(CTest)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(LIBFFI REQUIRED IMPORTED_TARGET "libffi>=3.4")
pkg_check_modules(GMP REQUIRED IMPORTED_TARGET gmp)

set(
  PURE_LIBRARY_INSTALL_DIR "lib/pure"
  CACHE STRING "Relative install directory for Pure modules"
)
set(
  PURE_RUNTIME_INSTALL_DIR "bin"
  CACHE STRING "Relative install directory for bundled runtime DLLs"
)
set(
  PURE_DOCUMENTATION_INSTALL_DIR "share/doc/${PROJECT_NAME}"
  CACHE STRING "Relative install directory for package documentation"
)
set(
  PURE_EXAMPLES_INSTALL_DIR "${PURE_DOCUMENTATION_INSTALL_DIR}/examples"
  CACHE STRING "Relative install directory for package examples"
)
foreach(destination_var IN ITEMS
    PURE_LIBRARY_INSTALL_DIR
    PURE_RUNTIME_INSTALL_DIR
    PURE_DOCUMENTATION_INSTALL_DIR
    PURE_EXAMPLES_INSTALL_DIR)
  set(destination "${${destination_var}}")
  if(IS_ABSOLUTE "${destination}" OR
      destination MATCHES "(^|[/\\\\])\\.\\.([/\\\\]|$)")
    message(FATAL_ERROR
      "${destination_var} must remain within the installation prefix: ${destination}")
  endif()
endforeach()

set(version "${PROJECT_VERSION}")
string(TIMESTAMP today "%B %d, %Y")
configure_file(
  README
  "${CMAKE_CURRENT_BINARY_DIR}/README"
  @ONLY
  NEWLINE_STYLE UNIX
)
file(READ "${CMAKE_CURRENT_BINARY_DIR}/README" readme)
string(REPLACE "|today|" "${today}" readme "${readme}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/README" "${readme}")

add_library(ffi MODULE ffi.c)
target_link_libraries(
  ffi
  PRIVATE
    PkgConfig::PURE
    PkgConfig::LIBFFI
    PkgConfig::GMP
)
if(MINGW)
  target_link_options(ffi PRIVATE LINKER:--enable-auto-import)
endif()
set_target_properties(
  ffi
  PROPERTIES
    PREFIX ""
    WINDOWS_EXPORT_ALL_SYMBOLS ON
)

install(
  TARGETS ffi
  RUNTIME DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  LIBRARY DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime
)
install(
  FILES ffi.pure
  DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime
)
install(
  FILES
    "${CMAKE_CURRENT_BINARY_DIR}/README"
    COPYING
    COPYING.LESSER
  DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}"
  COMPONENT documentation
)
install(
  DIRECTORY examples/
  DESTINATION "${PURE_EXAMPLES_INSTALL_DIR}"
  COMPONENT documentation
  FILES_MATCHING PATTERN "*.pure"
)

set(
  PURE_FFI_RUNTIME_DLL ""
  CACHE FILEPATH "libffi runtime DLL bundled with the Windows package"
)
set(
  PURE_FFI_RUNTIME_LICENSE ""
  CACHE FILEPATH "License for the bundled libffi runtime DLL"
)
if(WIN32)
  pkg_get_variable(LIBFFI_PREFIX libffi prefix)
  if(NOT PURE_FFI_RUNTIME_DLL)
    find_file(
      detected_pure_ffi_runtime_dll
      NAMES libffi-8.dll
      HINTS "${LIBFFI_PREFIX}/bin"
      NO_DEFAULT_PATH
    )
    if(detected_pure_ffi_runtime_dll)
      set(
        PURE_FFI_RUNTIME_DLL "${detected_pure_ffi_runtime_dll}"
        CACHE FILEPATH "libffi runtime DLL bundled with the Windows package"
        FORCE
      )
    endif()
  endif()
  if(NOT PURE_FFI_RUNTIME_LICENSE)
    find_file(
      detected_pure_ffi_runtime_license
      NAMES LICENSE
      HINTS "${LIBFFI_PREFIX}/share/licenses/libffi"
      NO_DEFAULT_PATH
    )
    if(detected_pure_ffi_runtime_license)
      set(
        PURE_FFI_RUNTIME_LICENSE "${detected_pure_ffi_runtime_license}"
        CACHE FILEPATH "License for the bundled libffi runtime DLL"
        FORCE
      )
    endif()
  endif()
  if(NOT EXISTS "${PURE_FFI_RUNTIME_DLL}")
    message(FATAL_ERROR
      "PURE_FFI_RUNTIME_DLL does not exist: ${PURE_FFI_RUNTIME_DLL}")
  endif()
  if(NOT EXISTS "${PURE_FFI_RUNTIME_LICENSE}")
    message(FATAL_ERROR
      "PURE_FFI_RUNTIME_LICENSE does not exist: ${PURE_FFI_RUNTIME_LICENSE}")
  endif()
  install(
    FILES "${PURE_FFI_RUNTIME_DLL}"
    DESTINATION "${PURE_RUNTIME_INSTALL_DIR}"
    COMPONENT runtime
  )
  install(
    FILES "${PURE_FFI_RUNTIME_LICENSE}"
    DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}"
    RENAME libffi-LICENSE
    COMPONENT documentation
  )
endif()

set(
  PURE_EXECUTABLE ""
  CACHE FILEPATH "Pure interpreter used for package smoke tests"
)
set(
  LLVM_READOBJ_EXECUTABLE ""
  CACHE FILEPATH "llvm-readobj used for the Windows package contract"
)
if(BUILD_TESTING)
  if(NOT PURE_EXECUTABLE OR NOT EXISTS "${PURE_EXECUTABLE}")
    message(FATAL_ERROR
      "BUILD_TESTING requires an existing PURE_EXECUTABLE: ${PURE_EXECUTABLE}")
  endif()
  if(WIN32 AND NOT EXISTS "${LLVM_READOBJ_EXECUTABLE}")
    message(FATAL_ERROR
      "Windows BUILD_TESTING requires an existing LLVM_READOBJ_EXECUTABLE: "
      "${LLVM_READOBJ_EXECUTABLE}")
  endif()
    add_library(ffi-smoke-native SHARED tests/smoke-native.c)
    target_link_libraries(ffi-smoke-native PRIVATE PkgConfig::LIBFFI)
    add_custom_command(TARGET ffi POST_BUILD
      COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${PURE_FFI_RUNTIME_DLL}" "$<TARGET_FILE_DIR:ffi>/libffi-8.dll")
    set_target_properties(
      ffi-smoke-native
      PROPERTIES
        PREFIX ""
        C_STANDARD 99
        C_STANDARD_REQUIRED ON
    )
    add_test(
      NAME pure-ffi-configure-contract
      COMMAND "${CMAKE_COMMAND}"
        "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
        "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
        "-DTEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/pure-ffi contract/configure"
        "-DGENERATOR=${CMAKE_GENERATOR}"
        "-DMAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}"
        "-DC_COMPILER=${CMAKE_C_COMPILER}"
        "-DPKG_CONFIG_EXECUTABLE=${PKG_CONFIG_EXECUTABLE}"
        "-DPKG_CONFIG_PATH=$ENV{PKG_CONFIG_PATH}"
        "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/configure_contract.cmake"
    )
    add_test(
      NAME pure-ffi-smoke
      COMMAND "${CMAKE_COMMAND}"
        "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
        "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
        "-DPURE_MODULE_DIR=$<TARGET_FILE_DIR:ffi>"
        "-DNATIVE_MODULE_DIR=$<TARGET_FILE_DIR:ffi-smoke-native>"
        "-DRUNTIME_DLL_DIRECTORY=$<TARGET_FILE_DIR:ffi>"
        "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunSmokeTest.cmake"
    )
    set(ffi_tests pure-ffi-configure-contract pure-ffi-smoke)
    if(WIN32)
      add_test(
        NAME pure-ffi-install-contract
        COMMAND "${CMAKE_COMMAND}"
          "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
          "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
          "-DFFI_TARGET_FILE=$<TARGET_FILE:ffi>"
          "-DFFI_SMOKE_NATIVE_FILE=$<TARGET_FILE:ffi-smoke-native>"
          "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
          "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}"
          "-DTEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/pure-ffi contract/install"
          "-DSMOKE_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
          "-DRUNTIME_DLL=${PURE_FFI_RUNTIME_DLL}"
          "-DRUNTIME_LICENSE=${PURE_FFI_RUNTIME_LICENSE}"
          -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/install_contract.cmake"
      )
      list(APPEND ffi_tests pure-ffi-install-contract)
    endif()
    set_tests_properties(
      ${ffi_tests}
      PROPERTIES
        LABELS "pure-ffi"
    )
endif()
