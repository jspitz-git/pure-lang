cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS BUILD_DIR STAGE_PREFIX SOURCE_DIR PURE_RUNTIME_ROOT
    LLVM_READOBJ POWERSHELL_EXECUTABLE PROTOCOL_HARNESS PROTOCOL_WORKER
    VERIFY_SCRIPT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH BUILD_DIR NORMALIZE OUTPUT_VARIABLE build_dir)
cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE test_root)
set(stage "${test_root}/stage with spaces")
set(relocated "${test_root}/relocated 日本語 PureFastCGI")
file(REMOVE_RECURSE "${test_root}")

execute_process(
  COMMAND "${CMAKE_COMMAND}" --install "${build_dir}"
    --prefix "${stage}" --component PureFastCGI
  RESULT_VARIABLE install_result
  OUTPUT_VARIABLE install_output
  ERROR_VARIABLE install_error
  ENCODING UTF-8)
if(NOT install_result EQUAL 0)
  message(FATAL_ERROR
    "initial component install failed (${install_result})\n"
    "stdout:\n${install_output}\nstderr:\n${install_error}")
endif()

# Copy a clean package so exact verification remains meaningful at the
# relocated destination. Ownership sentinels belong only to the overlay stage.
file(COPY "${stage}/" DESTINATION "${relocated}")
execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DBUILD_DIR=${build_dir}"
    "-DSTAGE_PREFIX=${relocated}"
    "-DSOURCE_PREFIX=${SOURCE_DIR}"
    "-DORIGINAL_BUILD_PREFIX=${build_dir}"
    "-DORIGINAL_STAGE_PREFIX=${stage}"
    "-DPURE_RUNTIME_ROOT=${PURE_RUNTIME_ROOT}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    "-DPOWERSHELL_EXECUTABLE=${POWERSHELL_EXECUTABLE}"
    "-DPROTOCOL_HARNESS=${PROTOCOL_HARNESS}"
    "-DPROTOCOL_WORKER=${PROTOCOL_WORKER}"
    -DRUN_RUNTIME_TESTS=ON
    -P "${VERIFY_SCRIPT}"
  RESULT_VARIABLE relocated_result
  OUTPUT_VARIABLE relocated_output
  ERROR_VARIABLE relocated_error
  ENCODING UTF-8)
if(NOT relocated_result EQUAL 0)
  message(FATAL_ERROR
    "relocated PureFastCGI verification failed (${relocated_result})\n"
    "stdout:\n${relocated_output}\nstderr:\n${relocated_error}")
endif()

file(WRITE "${stage}/unrelated-sentinel.txt" "keep\n")
file(WRITE "${stage}/lib/pure/unrelated-module.pure" "keep-module\n")
file(SHA256 "${stage}/unrelated-sentinel.txt" root_sentinel_before)
file(SHA256 "${stage}/lib/pure/unrelated-module.pure" module_sentinel_before)

# Exercise a real overlay before removal.
execute_process(
  COMMAND "${CMAKE_COMMAND}" --install "${build_dir}"
    --prefix "${stage}" --component PureFastCGI
  RESULT_VARIABLE overlay_result
  OUTPUT_VARIABLE overlay_output
  ERROR_VARIABLE overlay_error
  ENCODING UTF-8)
if(NOT overlay_result EQUAL 0)
  message(FATAL_ERROR
    "component overlay failed (${overlay_result})\n"
    "stdout:\n${overlay_output}\nstderr:\n${overlay_error}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DBUILD_DIR=${build_dir}"
    "-DSTAGE_PREFIX=${stage}"
    "-DSOURCE_PREFIX=${SOURCE_DIR}"
    "-DORIGINAL_BUILD_PREFIX=${build_dir}"
    "-DORIGINAL_STAGE_PREFIX=${stage}"
    "-DPURE_RUNTIME_ROOT=${PURE_RUNTIME_ROOT}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    "-DPOWERSHELL_EXECUTABLE=${POWERSHELL_EXECUTABLE}"
    -DREMOVE_OWNED=ON
    -P "${VERIFY_SCRIPT}"
  RESULT_VARIABLE removal_result
  OUTPUT_VARIABLE removal_output
  ERROR_VARIABLE removal_error
  ENCODING UTF-8)
if(NOT removal_result EQUAL 0)
  message(FATAL_ERROR
    "owned-file removal failed (${removal_result})\n"
    "stdout:\n${removal_output}\nstderr:\n${removal_error}")
endif()

file(SHA256 "${stage}/unrelated-sentinel.txt" root_sentinel_after)
file(SHA256 "${stage}/lib/pure/unrelated-module.pure" module_sentinel_after)
if(NOT root_sentinel_after STREQUAL root_sentinel_before OR
    NOT module_sentinel_after STREQUAL module_sentinel_before)
  message(FATAL_ERROR "ownership removal changed an unrelated sentinel")
endif()
foreach(owned IN ITEMS
    lib/pure/fastcgi.dll
    lib/pure/fastcgi.pure
    share/doc/pure-fastcgi/README
    share/doc/pure-fastcgi/THIRD_PARTY.md
    share/doc/pure-fastcgi/LICENSE.fcgi2
    share/doc/pure-fastcgi/PureFastCGIInventory.tsv)
  if(EXISTS "${stage}/${owned}")
    message(FATAL_ERROR "owned payload remains after removal: ${owned}")
  endif()
endforeach()
if(NOT IS_DIRECTORY "${stage}/lib/pure" OR
    NOT IS_DIRECTORY "${stage}/share/doc")
  message(FATAL_ERROR "shared package directories were removed")
endif()

message(STATUS "PureFastCGI relocation and ownership passed")
