cmake_minimum_required(VERSION 3.25)

project(pure-odbc VERSION 0.10 LANGUAGES C)

option(PURE_ODBC_BUILD_FAULT_TESTS "Build native ODBC fault-injection tests" OFF)
option(PURE_ODBC_STRICT_WINDOWS_AUDIT
  "Require the audited Windows CLANG64 toolchain and package contracts" OFF)

if(PURE_ODBC_STRICT_WINDOWS_AUDIT AND NOT WIN32)
  message(FATAL_ERROR
    "PURE_ODBC_STRICT_WINDOWS_AUDIT is supported only by Windows builds")
endif()

if(WIN32)
  set(PURE_ODBC_CLANG64_PREFIX "" CACHE PATH
    "Exact MSYS2 CLANG64 prefix for the strict Windows audit")
  set(PURE_ODBC_PKG_CONFIG_PATH "" CACHE PATH
    "Exact staged Pure pkg-config directory for the strict Windows audit")
  set(LLVM_READOBJ_EXECUTABLE "" CACHE FILEPATH
    "Exact llvm-readobj executable for Windows PE validation")
  set(PURE_ODBC_MAKE_EXECUTABLE "" CACHE FILEPATH
    "Exact MSYS make executable for contract tests")
  set(PURE_EXECUTABLE "" CACHE FILEPATH
    "Exact staged Pure interpreter")
  set(PURE_RUNTIME_DLL "" CACHE FILEPATH
    "Exact staged libpure.dll")
  set(GMP_RUNTIME_DLL "" CACHE FILEPATH
    "Exact CLANG64 libgmp-10.dll")
  set(ODBC_HEADER "" CACHE FILEPATH
    "Exact CLANG64 sql.h")
  set(ODBC_IMPORT_LIBRARY "" CACHE FILEPATH
    "Exact CLANG64 native ODBC import library")
  set(SYSTEM_ODBC_DLL "" CACHE FILEPATH
    "Exact native 64-bit System32 ODBC manager")

  if(PURE_ODBC_STRICT_WINDOWS_AUDIT)
    foreach(required IN ITEMS
        PURE_ODBC_CLANG64_PREFIX PURE_ODBC_PKG_CONFIG_PATH
        PKG_CONFIG_EXECUTABLE LLVM_READOBJ_EXECUTABLE
        PURE_ODBC_MAKE_EXECUTABLE PURE_EXECUTABLE PURE_RUNTIME_DLL
        GMP_RUNTIME_DLL ODBC_HEADER ODBC_IMPORT_LIBRARY SYSTEM_ODBC_DLL)
      if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
        message(FATAL_ERROR
          "Strict Windows audit requires explicit ${required}")
      endif()
    endforeach()
    foreach(required IN ITEMS
        PURE_ODBC_CLANG64_PREFIX PURE_ODBC_PKG_CONFIG_PATH)
      if(NOT IS_DIRECTORY "${${required}}")
        message(FATAL_ERROR
          "${required} must be an existing directory: ${${required}}")
      endif()
    endforeach()
    foreach(required IN ITEMS
        CMAKE_C_COMPILER CMAKE_MAKE_PROGRAM PKG_CONFIG_EXECUTABLE
        LLVM_READOBJ_EXECUTABLE PURE_ODBC_MAKE_EXECUTABLE PURE_EXECUTABLE
        PURE_RUNTIME_DLL GMP_RUNTIME_DLL ODBC_HEADER ODBC_IMPORT_LIBRARY
        SYSTEM_ODBC_DLL)
      if(NOT EXISTS "${${required}}" OR IS_DIRECTORY "${${required}}" OR
          IS_SYMLINK "${${required}}")
        message(FATAL_ERROR
          "${required} must be an existing regular file: ${${required}}")
      endif()
    endforeach()
    set(ENV{PKG_CONFIG_PATH} "${PURE_ODBC_PKG_CONFIG_PATH}")

    cmake_path(ABSOLUTE_PATH PURE_ODBC_CLANG64_PREFIX NORMALIZE
      OUTPUT_VARIABLE strict_clang64_prefix)
    cmake_path(GET strict_clang64_prefix PARENT_PATH strict_msys_root)
    function(pure_odbc_require_lexical_path label actual expected)
      cmake_path(ABSOLUTE_PATH actual NORMALIZE OUTPUT_VARIABLE actual)
      cmake_path(ABSOLUTE_PATH expected NORMALIZE OUTPUT_VARIABLE expected)
      string(TOLOWER "${actual}" folded_actual)
      string(TOLOWER "${expected}" folded_expected)
      if(NOT folded_actual STREQUAL folded_expected)
        message(FATAL_ERROR
          "${label} must use the audited origin\n"
          "expected: ${expected}\nactual: ${actual}")
      endif()
    endfunction()
    pure_odbc_require_lexical_path("CMAKE_C_COMPILER in CLANG64"
      "${CMAKE_C_COMPILER}" "${strict_clang64_prefix}/bin/clang.exe")
    pure_odbc_require_lexical_path("PKG_CONFIG_EXECUTABLE in CLANG64"
      "${PKG_CONFIG_EXECUTABLE}"
      "${strict_clang64_prefix}/bin/pkgconf.exe")
    pure_odbc_require_lexical_path("LLVM_READOBJ_EXECUTABLE in CLANG64"
      "${LLVM_READOBJ_EXECUTABLE}"
      "${strict_clang64_prefix}/bin/llvm-readobj.exe")
    pure_odbc_require_lexical_path("GMP_RUNTIME_DLL in CLANG64"
      "${GMP_RUNTIME_DLL}"
      "${strict_clang64_prefix}/bin/libgmp-10.dll")
    pure_odbc_require_lexical_path("ODBC_HEADER in CLANG64"
      "${ODBC_HEADER}" "${strict_clang64_prefix}/include/sql.h")
    pure_odbc_require_lexical_path("ODBC_IMPORT_LIBRARY in CLANG64"
      "${ODBC_IMPORT_LIBRARY}"
      "${strict_clang64_prefix}/lib/libodbc32.a")
    pure_odbc_require_lexical_path("PURE_ODBC_MAKE_EXECUTABLE in MSYS"
      "${PURE_ODBC_MAKE_EXECUTABLE}"
      "${strict_msys_root}/usr/bin/make.exe")
  endif()
endif()

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(GMP REQUIRED IMPORTED_TARGET gmp)
pkg_get_variable(PURE_PREFIX pure prefix)

if(PURE_ODBC_STRICT_WINDOWS_AUDIT)
  if(NOT CMAKE_GENERATOR STREQUAL "Ninja")
    message(FATAL_ERROR "Strict Windows audit requires the Ninja generator")
  endif()
  if(NOT CMAKE_BUILD_TYPE STREQUAL "Release")
    message(FATAL_ERROR "Strict Windows audit requires a Release build")
  endif()
  if(NOT CMAKE_C_COMPILER_ID STREQUAL "Clang")
    message(FATAL_ERROR
      "Strict Windows audit requires compiler ID Clang; actual: "
      "${CMAKE_C_COMPILER_ID}")
  endif()
  if(NOT CMAKE_C_COMPILER_VERSION MATCHES "^22\\.")
    message(FATAL_ERROR
      "Strict Windows audit requires Clang 22; actual: "
      "${CMAKE_C_COMPILER_VERSION}")
  endif()
  if(NOT CMAKE_C_COMPILER_TARGET MATCHES
      "^x86_64-[A-Za-z0-9_.-]*windows-gnu$" OR
      NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR
      "Strict Windows audit requires an x86-64 Windows target; actual: "
      "${CMAKE_C_COMPILER_TARGET}, pointer size ${CMAKE_SIZEOF_VOID_P}")
  endif()
endif()

add_library(odbc MODULE odbc.c)
target_compile_features(odbc PRIVATE c_std_11)
target_link_libraries(odbc PRIVATE PkgConfig::PURE PkgConfig::GMP)
if(WIN32)
  if(PURE_ODBC_STRICT_WINDOWS_AUDIT)
    cmake_path(GET ODBC_HEADER PARENT_PATH odbc_include_directory)
    target_include_directories(odbc PRIVATE "${odbc_include_directory}")
    target_link_libraries(odbc PRIVATE "${ODBC_IMPORT_LIBRARY}")
  else()
    target_link_libraries(odbc PRIVATE odbc32)
  endif()
endif()
if(MINGW)
  target_compile_options(odbc PRIVATE -Wall -Wextra -Werror)
  target_link_options(odbc PRIVATE "LINKER:--enable-auto-import")
endif()
set_target_properties(odbc PROPERTIES PREFIX "" WINDOWS_EXPORT_ALL_SYMBOLS ON)

if(WIN32)
  if(NOT PURE_ODBC_STRICT_WINDOWS_AUDIT)
    find_file(
      GMP_RUNTIME_DLL
      NAMES libgmp-10.dll
      HINTS "$ENV{MSYSTEM_PREFIX}/bin"
      NO_DEFAULT_PATH
      REQUIRED
    )
    find_program(LLVM_READOBJ_EXECUTABLE NAMES llvm-readobj REQUIRED)
    find_file(PURE_RUNTIME_DLL NAMES libpure.dll
      HINTS "${PURE_PREFIX}/bin" NO_DEFAULT_PATH REQUIRED)
  endif()
endif()

include(CTest)
if(PURE_ODBC_STRICT_WINDOWS_AUDIT AND NOT BUILD_TESTING)
  message(FATAL_ERROR
    "PURE_ODBC_STRICT_WINDOWS_AUDIT requires BUILD_TESTING=ON")
endif()
if(BUILD_TESTING)
  if(WIN32)
    add_executable(pure-odbc-run-pure-test tests/run_pure_test.c)
    target_compile_features(pure-odbc-run-pure-test PRIVATE c_std_11)
    set_target_properties(
      pure-odbc-run-pure-test PROPERTIES OUTPUT_NAME run_pure_test)
    if(MINGW)
      target_compile_options(
        pure-odbc-run-pure-test PRIVATE -Wall -Wextra -Werror)
      target_link_options(pure-odbc-run-pure-test PRIVATE -municode)
      set(pure_odbc_try_run_link_options LINK_OPTIONS -municode)
    endif()
    add_executable(
      pure-odbc-run-pure-test-alternate tests/run_pure_test.c)
    target_compile_features(
      pure-odbc-run-pure-test-alternate PRIVATE c_std_11)
    target_compile_definitions(
      pure-odbc-run-pure-test-alternate PRIVATE PURE_ODBC_TEST_SEAM)
    set_target_properties(
      pure-odbc-run-pure-test-alternate
      PROPERTIES OUTPUT_NAME run_pure_test_alternate)
    if(MINGW)
      target_compile_options(
        pure-odbc-run-pure-test-alternate PRIVATE -Wall -Wextra -Werror)
      target_link_options(
        pure-odbc-run-pure-test-alternate PRIVATE -municode)
    endif()
    try_run(
      windows_directory_result windows_directory_compiled
      SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/tests/run_pure_test.c"
      ${pure_odbc_try_run_link_options}
      RUN_OUTPUT_VARIABLE windows_directory_output
      ARGS --print-windows-directory
    )
    string(STRIP "${windows_directory_output}"
      PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY)
    if(NOT windows_directory_compiled OR
        NOT "${windows_directory_result}" STREQUAL "0" OR
        NOT IS_DIRECTORY "${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}")
      message(FATAL_ERROR
        "Unable to obtain the OS Windows directory from run_pure_test.c\n"
        "compile: ${windows_directory_compiled}\n"
        "result: ${windows_directory_result}\n"
        "output: ${windows_directory_output}")
    endif()
    cmake_path(ABSOLUTE_PATH PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY
      NORMALIZE OUTPUT_VARIABLE PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY)
    include("${CMAKE_CURRENT_SOURCE_DIR}/tests/ContractTestRoot.cmake")

    if(PURE_ODBC_STRICT_WINDOWS_AUDIT)
      foreach(directory_input IN ITEMS
          PURE_ODBC_CLANG64_PREFIX PURE_ODBC_PKG_CONFIG_PATH)
        cmake_path(ABSOLUTE_PATH ${directory_input} NORMALIZE
          OUTPUT_VARIABLE normalized)
        _pure_odbc_require_no_reparse(
          "${normalized}" "${directory_input}" FALSE)
        file(REAL_PATH "${normalized}" canonical)
        set(${directory_input} "${canonical}")
      endforeach()
      foreach(file_input IN ITEMS
          CMAKE_C_COMPILER CMAKE_MAKE_PROGRAM PKG_CONFIG_EXECUTABLE
          LLVM_READOBJ_EXECUTABLE PURE_ODBC_MAKE_EXECUTABLE PURE_EXECUTABLE
          PURE_RUNTIME_DLL GMP_RUNTIME_DLL ODBC_HEADER ODBC_IMPORT_LIBRARY
          SYSTEM_ODBC_DLL)
        cmake_path(ABSOLUTE_PATH ${file_input} NORMALIZE
          OUTPUT_VARIABLE normalized)
        _pure_odbc_require_no_reparse("${normalized}" "${file_input}" FALSE)
        file(REAL_PATH "${normalized}" canonical)
        set(${file_input} "${canonical}")
      endforeach()

      function(pure_odbc_require_exact_strict_path label actual expected)
        cmake_path(ABSOLUTE_PATH expected NORMALIZE OUTPUT_VARIABLE expected)
        if(NOT EXISTS "${expected}" OR IS_DIRECTORY "${expected}")
          message(FATAL_ERROR "Expected ${label} does not exist: ${expected}")
        endif()
        file(REAL_PATH "${expected}" expected)
        _pure_odbc_fold_path("${actual}" folded_actual)
        _pure_odbc_fold_path("${expected}" folded_expected)
        if(NOT folded_actual STREQUAL folded_expected)
          message(FATAL_ERROR
            "${label} must use the audited origin\n"
            "expected: ${expected}\nactual: ${actual}")
        endif()
      endfunction()
      function(pure_odbc_require_exact_strict_directory label actual expected)
        cmake_path(ABSOLUTE_PATH expected NORMALIZE OUTPUT_VARIABLE expected)
        if(NOT IS_DIRECTORY "${expected}")
          message(FATAL_ERROR "Expected ${label} does not exist: ${expected}")
        endif()
        file(REAL_PATH "${expected}" expected)
        _pure_odbc_fold_path("${actual}" folded_actual)
        _pure_odbc_fold_path("${expected}" folded_expected)
        if(NOT folded_actual STREQUAL folded_expected)
          message(FATAL_ERROR
            "${label} must use the audited origin\n"
            "expected: ${expected}\nactual: ${actual}")
        endif()
      endfunction()

      cmake_path(GET PURE_ODBC_CLANG64_PREFIX PARENT_PATH msys_root)
      cmake_path(ABSOLUTE_PATH GMP_PREFIX NORMALIZE OUTPUT_VARIABLE GMP_PREFIX)
      file(REAL_PATH "${GMP_PREFIX}" GMP_PREFIX)
      pure_odbc_require_exact_strict_directory("GMP pkg-config prefix"
        "${GMP_PREFIX}" "${PURE_ODBC_CLANG64_PREFIX}")
      pure_odbc_require_exact_strict_path("CMAKE_C_COMPILER in CLANG64"
        "${CMAKE_C_COMPILER}"
        "${PURE_ODBC_CLANG64_PREFIX}/bin/clang.exe")
      pure_odbc_require_exact_strict_path("PKG_CONFIG_EXECUTABLE in CLANG64"
        "${PKG_CONFIG_EXECUTABLE}"
        "${PURE_ODBC_CLANG64_PREFIX}/bin/pkgconf.exe")
      pure_odbc_require_exact_strict_path("LLVM_READOBJ_EXECUTABLE in CLANG64"
        "${LLVM_READOBJ_EXECUTABLE}"
        "${PURE_ODBC_CLANG64_PREFIX}/bin/llvm-readobj.exe")
      pure_odbc_require_exact_strict_path("GMP_RUNTIME_DLL in CLANG64"
        "${GMP_RUNTIME_DLL}"
        "${PURE_ODBC_CLANG64_PREFIX}/bin/libgmp-10.dll")
      pure_odbc_require_exact_strict_path("ODBC_HEADER in CLANG64"
        "${ODBC_HEADER}"
        "${PURE_ODBC_CLANG64_PREFIX}/include/sql.h")
      pure_odbc_require_exact_strict_path("ODBC_IMPORT_LIBRARY in CLANG64"
        "${ODBC_IMPORT_LIBRARY}"
        "${PURE_ODBC_CLANG64_PREFIX}/lib/libodbc32.a")
      pure_odbc_require_exact_strict_path("PURE_ODBC_MAKE_EXECUTABLE in MSYS"
        "${PURE_ODBC_MAKE_EXECUTABLE}" "${msys_root}/usr/bin/make.exe")

      cmake_path(ABSOLUTE_PATH PURE_PREFIX NORMALIZE OUTPUT_VARIABLE PURE_PREFIX)
      file(REAL_PATH "${PURE_PREFIX}" PURE_PREFIX)
      pure_odbc_require_exact_strict_directory("PURE_ODBC_PKG_CONFIG_PATH"
        "${PURE_ODBC_PKG_CONFIG_PATH}" "${PURE_PREFIX}/lib/pkgconfig")
      pure_odbc_require_exact_strict_path("PURE_EXECUTABLE in staged Pure SDK"
        "${PURE_EXECUTABLE}" "${PURE_PREFIX}/bin/pure.exe")
      pure_odbc_require_exact_strict_path("PURE_RUNTIME_DLL in staged Pure SDK"
        "${PURE_RUNTIME_DLL}" "${PURE_PREFIX}/bin/libpure.dll")
      pure_odbc_require_exact_strict_path("SYSTEM_ODBC_DLL in native System32"
        "${SYSTEM_ODBC_DLL}"
        "${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}/System32/odbc32.dll")

      set(sqlext_header "${PURE_ODBC_CLANG64_PREFIX}/include/sqlext.h")
      if(NOT EXISTS "${sqlext_header}" OR IS_DIRECTORY "${sqlext_header}" OR
          IS_SYMLINK "${sqlext_header}")
        message(FATAL_ERROR
          "Strict Windows audit requires CLANG64 sqlext.h: ${sqlext_header}")
      endif()
      _pure_odbc_require_no_reparse("${sqlext_header}" "CLANG64 sqlext.h" FALSE)

      execute_process(
        COMMAND "${CMAKE_C_COMPILER}" -dumpmachine
        RESULT_VARIABLE target_result
        OUTPUT_VARIABLE compiler_target
        ERROR_VARIABLE target_error
        ENCODING UTF-8)
      string(STRIP "${compiler_target}" compiler_target)
      if(NOT target_result EQUAL 0 OR NOT target_error STREQUAL "" OR
          NOT compiler_target STREQUAL "${CMAKE_C_COMPILER_TARGET}")
        message(FATAL_ERROR
          "Strict compiler target probe mismatch\n"
          "expected: ${CMAKE_C_COMPILER_TARGET}\nactual: ${compiler_target}\n"
          "stderr: ${target_error}")
      endif()

      cmake_path(GET CMAKE_MAKE_PROGRAM FILENAME ninja_name)
      string(TOLOWER "${ninja_name}" ninja_name)
      execute_process(
        COMMAND "${CMAKE_MAKE_PROGRAM}" --version
        RESULT_VARIABLE ninja_result
        OUTPUT_VARIABLE ninja_version
        ERROR_VARIABLE ninja_error
        ENCODING UTF-8)
      string(STRIP "${ninja_version}" ninja_version)
      if(NOT ninja_name STREQUAL "ninja.exe" OR
          NOT ninja_result EQUAL 0 OR NOT ninja_error STREQUAL "" OR
          NOT ninja_version MATCHES "^[0-9]+\\.[0-9]+")
        message(FATAL_ERROR
          "CMAKE_MAKE_PROGRAM must be an explicit working Ninja executable\n"
          "path: ${CMAKE_MAKE_PROGRAM}\nversion: ${ninja_version}\n"
          "stderr: ${ninja_error}")
      endif()

      set(staged_gmp "${PURE_PREFIX}/bin/libgmp-10.dll")
      if(NOT EXISTS "${staged_gmp}" OR IS_DIRECTORY "${staged_gmp}")
        message(FATAL_ERROR "Staged Pure SDK is missing GMP: ${staged_gmp}")
      endif()
      file(SHA256 "${GMP_RUNTIME_DLL}" clang64_gmp_hash)
      file(SHA256 "${staged_gmp}" staged_gmp_hash)
      if(NOT staged_gmp_hash STREQUAL clang64_gmp_hash)
        message(FATAL_ERROR
          "Staged Pure GMP differs from explicit CLANG64 GMP\n"
          "CLANG64: ${clang64_gmp_hash}\nstaged: ${staged_gmp_hash}")
      endif()
    else()
      if(NOT SYSTEM_ODBC_DLL)
        set(SYSTEM_ODBC_DLL
          "${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}/System32/odbc32.dll")
      endif()
    endif()
  endif()

  if(NOT PURE_ODBC_STRICT_WINDOWS_AUDIT)
    find_program(
      PURE_EXECUTABLE
      NAMES pure
      HINTS "${PURE_PREFIX}/bin"
      NO_DEFAULT_PATH
      REQUIRED
    )
  endif()
  include("${CMAKE_CURRENT_SOURCE_DIR}/tests/ContractTestRoot.cmake")
  pure_odbc_prepare_contract_test_root(
    "access"
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_BINARY_DIR}"
    access_work_directory
  )
  configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/data/people.csv"
    "${access_work_directory}/people.csv"
    COPYONLY
  )
  configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/data/Schema.ini"
    "${access_work_directory}/Schema.ini"
    COPYONLY
  )
  if(WIN32)
    set(manager_work_directory
      "${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}")
  else()
    set(manager_work_directory "${CMAKE_CURRENT_BINARY_DIR}")
  endif()

  add_test(
    NAME pure-odbc-manager-smoke
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DMODULE_DIR=$<TARGET_FILE_DIR:odbc>"
      "-DSCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
      "-DWORK_DIRECTORY=${manager_work_directory}"
      "-DPURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY=${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake"
  )
  set(manager_required_files
    "$<TARGET_FILE:odbc>"
    "${CMAKE_CURRENT_SOURCE_DIR}/odbc.pure"
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure")
  if(WIN32)
    list(APPEND manager_required_files
      "$<TARGET_FILE:pure-odbc-run-pure-test>")
  endif()
  set_tests_properties(
    pure-odbc-manager-smoke
    PROPERTIES
      LABELS "odbc;driver-manager;drivers;diagnostics"
      REQUIRED_FILES "${manager_required_files}"
      TIMEOUT 30
  )

  if(WIN32)
    add_test(
      NAME pure-odbc-access-text-smoke
      COMMAND "$<TARGET_FILE:pure-odbc-run-pure-test>"
        "${PURE_EXECUTABLE}"
        "${CMAKE_CURRENT_SOURCE_DIR}"
        "$<TARGET_FILE_DIR:odbc>"
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/access_smoke.pure"
        "${access_work_directory}"
    )
    set_tests_properties(
      pure-odbc-access-text-smoke
      PROPERTIES
        LABELS "odbc;access-text;parameters;results;cleanup"
        REQUIRED_FILES
          "$<TARGET_FILE:odbc>;$<TARGET_FILE:pure-odbc-run-pure-test>;${CMAKE_CURRENT_SOURCE_DIR}/odbc.pure;${CMAKE_CURRENT_SOURCE_DIR}/tests/access_smoke.pure;${access_work_directory}/people.csv;${access_work_directory}/Schema.ini"
        SKIP_RETURN_CODE 77
        TIMEOUT 60
    )

    if(NOT PURE_ODBC_STRICT_WINDOWS_AUDIT)
      cmake_path(GET PKG_CONFIG_EXECUTABLE PARENT_PATH pkg_config_bin)
      cmake_path(GET pkg_config_bin PARENT_PATH msystem_prefix)
      cmake_path(GET msystem_prefix PARENT_PATH msys_root)
      find_program(
        PURE_ODBC_MAKE_EXECUTABLE
        NAMES make
        HINTS "${msys_root}/usr/bin"
        NO_DEFAULT_PATH
        REQUIRED
      )
    endif()
    add_test(
      NAME pure-odbc-runner-contract
      COMMAND "${CMAKE_COMMAND}"
        "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
        "-DRUN_PURE_TEST_EXECUTABLE=$<TARGET_FILE:pure-odbc-run-pure-test>"
        "-DALTERNATE_RUN_PURE_TEST_EXECUTABLE=$<TARGET_FILE:pure-odbc-run-pure-test-alternate>"
        "-DACTUAL_PURE_EXECUTABLE=${PURE_EXECUTABLE}"
        "-DACTUAL_MODULE_DIR=$<TARGET_FILE_DIR:odbc>"
        "-DACCESS_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/access_smoke.pure"
        "-DACCESS_WORK_DIRECTORY=${access_work_directory}"
        "-DPURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY=${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/runner_contract.cmake"
    )
    add_test(
      NAME pure-odbc-cleanup-contract
      COMMAND "${CMAKE_COMMAND}"
        "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
        "-DMAKE_EXECUTABLE=${PURE_ODBC_MAKE_EXECUTABLE}"
        "-DPKG_CONFIG_EXECUTABLE=${PKG_CONFIG_EXECUTABLE}"
        "-DPURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY=${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/cleanup_contract.cmake"
    )
    if(PURE_ODBC_STRICT_WINDOWS_AUDIT)
      add_test(
        NAME pure-odbc-configure-contract
        COMMAND "${CMAKE_COMMAND}"
          "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
          "-DGENERATOR=${CMAKE_GENERATOR}"
          "-DMAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}"
          "-DC_COMPILER=${CMAKE_C_COMPILER}"
          "-DC_COMPILER_TARGET=${CMAKE_C_COMPILER_TARGET}"
          "-DPKG_CONFIG_EXECUTABLE=${PKG_CONFIG_EXECUTABLE}"
          "-DPKG_CONFIG_PATH=${PURE_ODBC_PKG_CONFIG_PATH}"
          "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
          "-DPURE_RUNTIME_DLL=${PURE_RUNTIME_DLL}"
          "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}"
          "-DMSYS_MAKE_EXECUTABLE=${PURE_ODBC_MAKE_EXECUTABLE}"
          "-DGMP_RUNTIME_DLL=${GMP_RUNTIME_DLL}"
          "-DODBC_HEADER=${ODBC_HEADER}"
          "-DODBC_IMPORT_LIBRARY=${ODBC_IMPORT_LIBRARY}"
          "-DSYSTEM_ODBC_DLL=${SYSTEM_ODBC_DLL}"
          "-DCLANG64_PREFIX=${PURE_ODBC_CLANG64_PREFIX}"
          "-DPURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY=${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}"
          -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/configure_contract.cmake"
      )
      add_test(
        NAME pure-odbc-runtime-verifier-contract
        COMMAND "${CMAKE_COMMAND}"
          "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
          "-DPURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY=${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}"
          -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/runtime_verifier_contract.cmake"
      )
      add_test(
        NAME pure-odbc-source-distribution-contract
        COMMAND "${CMAKE_COMMAND}"
          "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
          "-DCMAKE_EXECUTABLE=${CMAKE_COMMAND}"
          "-DMAKE_EXECUTABLE=${PURE_ODBC_MAKE_EXECUTABLE}"
          "-DNINJA_EXECUTABLE=${CMAKE_MAKE_PROGRAM}"
          "-DC_COMPILER=${CMAKE_C_COMPILER}"
          "-DPKG_CONFIG_EXECUTABLE=${PKG_CONFIG_EXECUTABLE}"
          "-DPKG_CONFIG_PATH=${PURE_ODBC_PKG_CONFIG_PATH}"
          "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
          "-DPURE_RUNTIME_DLL=${PURE_RUNTIME_DLL}"
          "-DLLVM_READOBJ=${LLVM_READOBJ_EXECUTABLE}"
          "-DGMP_RUNTIME_DLL=${GMP_RUNTIME_DLL}"
          "-DODBC_HEADER=${ODBC_HEADER}"
          "-DODBC_IMPORT_LIBRARY=${ODBC_IMPORT_LIBRARY}"
          "-DSYSTEM_ODBC_DLL=${SYSTEM_ODBC_DLL}"
          "-DCLANG64_PREFIX=${PURE_ODBC_CLANG64_PREFIX}"
          "-DPORTABLE_PURE_PREFIX=${PURE_PREFIX}"
          "-DWINDOWS_DIRECTORY=${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}"
          "-DPURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY=${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}"
          -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/source_dist_contract.cmake"
      )
    endif()
    set_tests_properties(
      pure-odbc-runner-contract pure-odbc-cleanup-contract
      PROPERTIES LABELS "odbc;contract" TIMEOUT 120
    )
    if(PURE_ODBC_STRICT_WINDOWS_AUDIT)
      set_tests_properties(
        pure-odbc-cleanup-contract pure-odbc-configure-contract
        pure-odbc-runtime-verifier-contract
        pure-odbc-source-distribution-contract
        PROPERTIES RUN_SERIAL TRUE)
      set_tests_properties(
        pure-odbc-configure-contract
        PROPERTIES LABELS "odbc;contract;configure" TIMEOUT 900)
      set_tests_properties(
        pure-odbc-runtime-verifier-contract
        PROPERTIES LABELS "odbc;contract;pe" TIMEOUT 300)
      set_tests_properties(
        pure-odbc-source-distribution-contract
        PROPERTIES LABELS "odbc;contract;source-distribution" TIMEOUT 1800)
    endif()
  endif()

  if(PURE_ODBC_BUILD_FAULT_TESTS)
    add_executable(pure-odbc-fault-tests tests/odbc_fault_harness.c)
    target_compile_features(pure-odbc-fault-tests PRIVATE c_std_11)
    target_compile_definitions(pure-odbc-fault-tests PRIVATE PURE_ODBC_TESTING)
    target_link_libraries(
      pure-odbc-fault-tests
      PRIVATE PkgConfig::PURE PkgConfig::GMP
    )
    if(WIN32)
      if(PURE_ODBC_STRICT_WINDOWS_AUDIT)
        target_link_libraries(
          pure-odbc-fault-tests PRIVATE "${ODBC_IMPORT_LIBRARY}")
      else()
        target_link_libraries(pure-odbc-fault-tests PRIVATE odbc32)
      endif()
    endif()
    if(MINGW)
      target_compile_options(
        pure-odbc-fault-tests
        PRIVATE -Wall -Wextra -Werror -fsanitize=address -fno-omit-frame-pointer
      )
      target_link_options(pure-odbc-fault-tests PRIVATE -fsanitize=address)
    endif()
    add_test(NAME pure-odbc-fault COMMAND pure-odbc-fault-tests)
    set_tests_properties(
      pure-odbc-fault
      PROPERTIES LABELS "odbc;fault;asan" TIMEOUT 30
    )
  endif()
endif()

if(WIN32 AND PURE_ODBC_STRICT_WINDOWS_AUDIT)
  add_custom_target(
    verify-windows-dependencies
    COMMAND "${CMAKE_COMMAND}"
      "-DLLVM_READOBJ=${LLVM_READOBJ_EXECUTABLE}"
      "-DSTAGE_PREFIX=${PURE_PREFIX}"
      "-DODBC_MODULE=$<TARGET_FILE:odbc>"
      "-DGMP_DLL=${PURE_PREFIX}/bin/libgmp-10.dll"
      "-DPURE_RUNTIME_DLL=${PURE_RUNTIME_DLL}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DWINDOWS_DIRECTORY=${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}"
      "-DSYSTEM_ODBC_DLL=${SYSTEM_ODBC_DLL}"
      "-DPURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY=${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
    DEPENDS odbc
    COMMENT "Verifying the exact pure-odbc Windows dependency closure"
    VERBATIM
  )
endif()

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/Install.cmake")

if(BUILD_TESTING AND WIN32 AND PURE_ODBC_STRICT_WINDOWS_AUDIT)
  add_test(
    NAME pure-odbc-install-contract
    COMMAND "${CMAKE_COMMAND}"
      "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DPORTABLE_PURE_PREFIX=${PURE_PREFIX}"
      "-DLLVM_READOBJ=${LLVM_READOBJ_EXECUTABLE}"
      "-DODBC_MODULE_SOURCE=$<TARGET_FILE:odbc>"
      "-DODBC_INTERFACE_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}/odbc.pure"
      "-DREADME_SOURCE=${CMAKE_CURRENT_BINARY_DIR}/README"
      "-DCOPYING_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}/COPYING"
      "-DCOPYING_LESSER_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}/COPYING.LESSER"
      "-DWINDOWS_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}/WINDOWS.md"
      "-DEXAMPLE_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}/examples/menagerie.pure"
      "-DSMOKE_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
      "-DPEOPLE_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}/tests/data/people.csv"
      "-DSCHEMA_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}/tests/data/Schema.ini"
      "-DGMP_DLL_SOURCE=${GMP_RUNTIME_DLL}"
      "-DPURE_RUNTIME_DLL_SOURCE=${PURE_RUNTIME_DLL}"
      "-DRUN_PURE_TEST_EXECUTABLE=$<TARGET_FILE:pure-odbc-run-pure-test>"
      "-DWINDOWS_DEPENDENCY_VERIFIER=${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
      "-DWINDOWS_DIRECTORY=${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}"
      "-DSYSTEM_ODBC_DLL=${SYSTEM_ODBC_DLL}"
      "-DPURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY=${PURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/install_contract.cmake"
  )
  set_tests_properties(
    pure-odbc-install-contract
    PROPERTIES
      LABELS "odbc;contract;install"
      REQUIRED_FILES
        "$<TARGET_FILE:odbc>;$<TARGET_FILE:pure-odbc-run-pure-test>"
      RUN_SERIAL TRUE
      TIMEOUT 600)
endif()
