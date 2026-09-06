cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS
    SOURCE_DIR BINARY_DIR CONTRACT_ROOT TEST_ROOT MAKE_EXECUTABLE GENERATOR
    MAKE_PROGRAM C_COMPILER PKG_CONFIG_EXECUTABLE PKG_CONFIG_PATH
    MSYSTEM_PREFIX LLVM_READOBJ_EXECUTABLE)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

foreach(path_var IN ITEMS SOURCE_DIR BINARY_DIR CONTRACT_ROOT TEST_ROOT
    MAKE_EXECUTABLE MAKE_PROGRAM C_COMPILER PKG_CONFIG_EXECUTABLE
    MSYSTEM_PREFIX LLVM_READOBJ_EXECUTABLE)
  cmake_path(ABSOLUTE_PATH ${path_var} NORMALIZE OUTPUT_VARIABLE normalized)
  set(${path_var} "${normalized}")
endforeach()
cmake_path(GET MAKE_EXECUTABLE PARENT_PATH make_bin_dir)
set(msys_bash "${make_bin_dir}/bash.exe")

function(require_safe_test_root)
  foreach(directory IN ITEMS SOURCE_DIR BINARY_DIR MSYSTEM_PREFIX)
    if(NOT IS_DIRECTORY "${${directory}}")
      message(FATAL_ERROR
        "${directory} must be an existing directory: ${${directory}}")
    endif()
  endforeach()
  foreach(tool IN ITEMS MAKE_EXECUTABLE MAKE_PROGRAM C_COMPILER
      PKG_CONFIG_EXECUTABLE LLVM_READOBJ_EXECUTABLE msys_bash)
    if(NOT EXISTS "${${tool}}" OR IS_DIRECTORY "${${tool}}")
      message(FATAL_ERROR "${tool} must be an existing file: ${${tool}}")
    endif()
  endforeach()
  cmake_path(GET CONTRACT_ROOT PARENT_PATH contract_parent)
  if(NOT "${contract_parent}" STREQUAL "${BINARY_DIR}")
    message(FATAL_ERROR
      "Unsafe CONTRACT_ROOT; expected a direct child of BINARY_DIR\n"
      "CONTRACT_ROOT: ${CONTRACT_ROOT}\nBINARY_DIR: ${BINARY_DIR}")
  endif()
  cmake_path(GET TEST_ROOT PARENT_PATH test_parent)
  if(NOT "${test_parent}" STREQUAL "${CONTRACT_ROOT}")
    message(FATAL_ERROR
      "Unsafe TEST_ROOT; expected a direct child of CONTRACT_ROOT\n"
      "TEST_ROOT: ${TEST_ROOT}\nCONTRACT_ROOT: ${CONTRACT_ROOT}")
  endif()
  foreach(protected IN ITEMS SOURCE_DIR BINARY_DIR MSYSTEM_PREFIX)
    cmake_path(IS_PREFIX TEST_ROOT "${${protected}}" NORMALIZE
      test_root_contains_protected)
    if(test_root_contains_protected)
      message(FATAL_ERROR
        "Unsafe TEST_ROOT contains protected ${protected}: ${${protected}}")
    endif()
  endforeach()
endfunction()

function(expect_unsafe_root_rejected label unsafe_root)
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${SOURCE_DIR}"
      "-DBINARY_DIR=${BINARY_DIR}"
      "-DCONTRACT_ROOT=${CONTRACT_ROOT}"
      "-DTEST_ROOT=${unsafe_root}"
      "-DMAKE_EXECUTABLE=${MAKE_EXECUTABLE}"
      "-DGENERATOR=${GENERATOR}"
      "-DMAKE_PROGRAM=${MAKE_PROGRAM}"
      "-DC_COMPILER=${C_COMPILER}"
      "-DPKG_CONFIG_EXECUTABLE=${PKG_CONFIG_EXECUTABLE}"
      "-DPKG_CONFIG_PATH=${PKG_CONFIG_PATH}"
      "-DMSYSTEM_PREFIX=${MSYSTEM_PREFIX}"
      "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}"
      -DROOT_SAFETY_PROBE=ON
      -P "${CMAKE_CURRENT_LIST_FILE}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8
  )
  if(result EQUAL 0)
    message(FATAL_ERROR
      "Cleanup guard accepted unsafe ${label} TEST_ROOT: ${unsafe_root}")
  endif()
  if(NOT "${output}\n${error}" MATCHES "Unsafe TEST_ROOT")
    message(FATAL_ERROR
      "Unsafe ${label} TEST_ROOT produced the wrong diagnostic\n"
      "${output}\n${error}")
  endif()
endfunction()

require_safe_test_root()
if(ROOT_SAFETY_PROBE)
  return()
endif()
expect_unsafe_root_rejected("source" "${SOURCE_DIR}")
expect_unsafe_root_rejected("binary" "${BINARY_DIR}")
expect_unsafe_root_rejected("MSYSTEM prefix" "${MSYSTEM_PREFIX}")

file(REMOVE_RECURSE "${TEST_ROOT}")
file(MAKE_DIRECTORY "${TEST_ROOT}")

set(distribution_driver "${TEST_ROOT}/distribution driver")
set(extract_root "${TEST_ROOT}/extracted")
file(COPY "${SOURCE_DIR}/" DESTINATION "${distribution_driver}")

cmake_path(GET PKG_CONFIG_EXECUTABLE PARENT_PATH pkg_config_bin_dir)
string(CONCAT make_command
  "export PATH=\"$(cygpath -u \"${make_bin_dir}\"):$(cygpath -u \"${pkg_config_bin_dir}\"):$PATH\" && "
  "cd \"$(cygpath -u \"${distribution_driver}\")\" && "
  "exec \"$(cygpath -u \"${MAKE_EXECUTABLE}\")\" \"PWD=$(pwd)\" dist")
execute_process(
  COMMAND "${msys_bash}" -lc "${make_command}"
  RESULT_VARIABLE dist_result
  OUTPUT_VARIABLE dist_output
  ERROR_VARIABLE dist_error
  ENCODING UTF-8
)
if(NOT dist_result EQUAL 0)
  message(FATAL_ERROR
    "The real source distribution flow failed (${dist_result})\n"
    "stdout:\n${dist_output}\nstderr:\n${dist_error}")
endif()

set(archive "${distribution_driver}/pure-glpk-0.6.tar.gz")
if(NOT EXISTS "${archive}")
  message(FATAL_ERROR "The source distribution flow did not create ${archive}")
endif()
file(MAKE_DIRECTORY "${extract_root}")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E tar xfz "${archive}"
  WORKING_DIRECTORY "${extract_root}"
  RESULT_VARIABLE extract_result
  OUTPUT_VARIABLE extract_output
  ERROR_VARIABLE extract_error
  ENCODING UTF-8
)
if(NOT extract_result EQUAL 0)
  message(FATAL_ERROR
    "Could not extract the real source archive (${extract_result})\n"
    "stdout:\n${extract_output}\nstderr:\n${extract_error}")
endif()

set(staged_source "${extract_root}/pure-glpk-0.6")
if(NOT IS_DIRECTORY "${staged_source}")
  message(FATAL_ERROR "Extracted source directory is missing: ${staged_source}")
endif()

set(required_assets CMakeLists.txt WINDOWS.md tests/load.pure tests/smoke.pure)
file(GLOB source_cmake_scripts RELATIVE "${SOURCE_DIR}"
  "${SOURCE_DIR}/cmake/*.cmake")
file(GLOB source_contract_scripts RELATIVE "${SOURCE_DIR}"
  "${SOURCE_DIR}/tests/*.cmake")
list(APPEND required_assets ${source_cmake_scripts} ${source_contract_scripts})
list(REMOVE_DUPLICATES required_assets)
list(SORT required_assets)
foreach(asset IN LISTS required_assets)
  if(NOT EXISTS "${staged_source}/${asset}" OR
      IS_DIRECTORY "${staged_source}/${asset}")
    message(FATAL_ERROR "Source archive misses required asset: ${asset}")
  endif()
endforeach()

# Prove the configure step consumes only the extracted source tree, rather
# than falling back to the copied tree that drove the legacy make target.
file(REMOVE_RECURSE "${distribution_driver}")
set(configure_build "${TEST_ROOT}/configure")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    "PKG_CONFIG_PATH=${PKG_CONFIG_PATH}"
    "MSYSTEM_PREFIX=${MSYSTEM_PREFIX}"
    "${CMAKE_COMMAND}" -S "${staged_source}" -B "${configure_build}"
      -G "${GENERATOR}"
      "-DCMAKE_MAKE_PROGRAM=${MAKE_PROGRAM}"
      "-DCMAKE_C_COMPILER=${C_COMPILER}"
      "-DPKG_CONFIG_EXECUTABLE=${PKG_CONFIG_EXECUTABLE}"
      "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}"
      -DBUILD_TESTING=OFF
  RESULT_VARIABLE configure_result
  OUTPUT_VARIABLE configure_output
  ERROR_VARIABLE configure_error
  ENCODING UTF-8
)
if(NOT configure_result EQUAL 0)
  message(FATAL_ERROR
    "Extracted source distribution did not configure (${configure_result})\n"
    "stdout:\n${configure_output}\nstderr:\n${configure_error}")
endif()

message(STATUS
  "Source distribution contract staged ${required_assets} and configured "
  "from the extracted tree")
