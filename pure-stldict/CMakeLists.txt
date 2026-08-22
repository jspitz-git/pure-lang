cmake_minimum_required(VERSION 3.25)

project(pure-stldict VERSION 0.8 LANGUAGES CXX)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")

foreach(module IN ITEMS hashdict orddict)
  add_library(${module} MODULE "${module}.cc")
  target_compile_features(${module} PRIVATE cxx_std_17)
  target_link_libraries(${module} PRIVATE PkgConfig::PURE)
  set_target_properties(
    ${module}
    PROPERTIES
      PREFIX ""
  )
  if(WIN32)
    target_compile_options(${module} PRIVATE -fno-exceptions)
    file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/${module}.pure"
      extern_declarations REGEX "^extern .+\\);")
    set(module_def "${CMAKE_CURRENT_BINARY_DIR}/${module}.def")
    file(WRITE "${module_def}" "EXPORTS\n")
    set(module_exports)
    foreach(declaration IN LISTS extern_declarations)
      string(REGEX MATCH "([A-Za-z_][A-Za-z0-9_]*)\\(" match "${declaration}")
      list(APPEND module_exports "${CMAKE_MATCH_1}")
    endforeach()
    list(REMOVE_DUPLICATES module_exports)
    list(SORT module_exports)
    foreach(symbol IN LISTS module_exports)
      file(APPEND "${module_def}" "  ${symbol}\n")
    endforeach()
    target_sources(${module} PRIVATE "${module_def}")
  endif()
endforeach()

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/Install.cmake")

include(CTest)
if(BUILD_TESTING)
  pkg_get_variable(PURE_PREFIX pure prefix)
  if(WIN32)
    set(PURE_EXECUTABLE "" CACHE FILEPATH "Installed Pure interpreter for tests")
    set(LLVM_READOBJ_EXECUTABLE "" CACHE FILEPATH "llvm-readobj for PE tests")
    if(NOT PURE_EXECUTABLE OR NOT EXISTS "${PURE_EXECUTABLE}")
      message(FATAL_ERROR "BUILD_TESTING requires an existing PURE_EXECUTABLE")
    endif()
    if(NOT LLVM_READOBJ_EXECUTABLE OR
        NOT EXISTS "${LLVM_READOBJ_EXECUTABLE}")
      message(FATAL_ERROR
        "BUILD_TESTING requires an existing LLVM_READOBJ_EXECUTABLE")
    endif()
  else()
    find_program(PURE_EXECUTABLE NAMES pure HINTS "${PURE_PREFIX}/bin" REQUIRED)
  endif()
  get_filename_component(pure_bin_dir "${PURE_EXECUTABLE}" DIRECTORY)
  get_filename_component(pure_runtime_prefix "${pure_bin_dir}" DIRECTORY)
  if(NOT EXISTS "${pure_runtime_prefix}/lib/pure/math.pure")
    message(FATAL_ERROR
      "PURE_EXECUTABLE must belong to an installed Pure runtime prefix")
  endif()
  add_test(
    NAME pure-stldict-smoke
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DMODULE_DIR=$<TARGET_FILE_DIR:hashdict>"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunSmokeTest.cmake"
  )
  set_tests_properties(
    pure-stldict-smoke
    PROPERTIES
      LABELS "stldict;hashdict;orddict;lifetime"
      REQUIRED_FILES
        "$<TARGET_FILE:hashdict>;$<TARGET_FILE:orddict>;${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
      TIMEOUT 60
  )
  if(WIN32)
    set(contract_root "${CMAKE_CURRENT_BINARY_DIR}/pure-stldict contract")
    add_test(NAME pure-stldict-configure-contract COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DTEST_ROOT=${contract_root}/configure"
      "-DGENERATOR=${CMAKE_GENERATOR}"
      "-DMAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}"
      "-DCXX_COMPILER=${CMAKE_CXX_COMPILER}"
      "-DPKG_CONFIG_EXECUTABLE=${PKG_CONFIG_EXECUTABLE}"
      "-DPURE_PKG_CONFIG_PATH=${pure_runtime_prefix}/lib/pkgconfig"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/configure_contract.cmake")
    foreach(module IN ITEMS hashdict orddict)
      add_test(NAME pure-stldict-${module}-pe-contract COMMAND "${CMAKE_COMMAND}"
        "-DMODULE_DLL=$<TARGET_FILE:${module}>"
        "-DMODULE_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}/${module}.pure"
        "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/verify_pe_contract.cmake")
    endforeach()
    add_test(NAME pure-stldict-install-contract COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DHASHDICT_TARGET_FILE=$<TARGET_FILE:hashdict>"
      "-DORDDICT_TARGET_FILE=$<TARGET_FILE:orddict>"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}"
      "-DTEST_ROOT=${contract_root}/install"
      "-DSMOKE_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/install_contract.cmake")
    set_tests_properties(pure-stldict-configure-contract
      pure-stldict-hashdict-pe-contract pure-stldict-orddict-pe-contract
      pure-stldict-install-contract
      PROPERTIES LABELS "stldict;contract;pe" TIMEOUT 60)
  endif()
endif()
