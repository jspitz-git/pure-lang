cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS
    BUILD_DIR STAGE_PREFIX SOURCE_DIR PURE_RUNTIME_ROOT LLVM_READOBJ VERIFIER)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

foreach(directory IN ITEMS BUILD_DIR SOURCE_DIR PURE_RUNTIME_ROOT)
  cmake_path(ABSOLUTE_PATH ${directory} NORMALIZE
    OUTPUT_VARIABLE normalized_${directory})
endforeach()
set(build_dir "${normalized_BUILD_DIR}")
set(source_dir "${normalized_SOURCE_DIR}")
set(runtime_root "${normalized_PURE_RUNTIME_ROOT}")
cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE stage)

execute_process(
  COMMAND "${CMAKE_COMMAND}" --build "${build_dir}"
    --target pure-fastcgi-package-oracles pure-fastcgi-protocol-harness
  RESULT_VARIABLE build_result
  OUTPUT_VARIABLE build_output
  ERROR_VARIABLE build_error
  ENCODING UTF-8)
if(NOT build_result EQUAL 0)
  message(FATAL_ERROR
    "PureFastCGI package inputs failed to build (${build_result})\n"
    "stdout:\n${build_output}\nstderr:\n${build_error}")
endif()

file(REMOVE_RECURSE "${stage}")
execute_process(
  COMMAND "${CMAKE_COMMAND}" --install "${build_dir}"
    --prefix "${stage}" --component PureFastCGI
  RESULT_VARIABLE install_result
  OUTPUT_VARIABLE install_output
  ERROR_VARIABLE install_error
  ENCODING UTF-8)
if(NOT install_result EQUAL 0)
  message(FATAL_ERROR
    "PureFastCGI component install failed (${install_result})\n"
    "stdout:\n${install_output}\nstderr:\n${install_error}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DBUILD_DIR=${build_dir}"
    "-DSTAGE_PREFIX=${stage}"
    "-DPURE_RUNTIME_ROOT=${runtime_root}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    "-DSOURCE_PREFIX=${source_dir}"
    "-DORIGINAL_BUILD_PREFIX=${build_dir}"
    "-DORIGINAL_STAGE_PREFIX=${stage}"
    -DRUN_RUNTIME_TESTS=ON
    "-DPROTOCOL_HARNESS=${build_dir}/pure-fastcgi-protocol-harness.exe"
    "-DPROTOCOL_WORKER=${source_dir}/tests/protocol_worker.pure"
    -P "${VERIFIER}"
  RESULT_VARIABLE verify_result
  OUTPUT_VARIABLE verify_output
  ERROR_VARIABLE verify_error
  ENCODING UTF-8)
if(NOT verify_result EQUAL 0)
  message(FATAL_ERROR
    "valid PureFastCGI package was rejected (${verify_result})\n"
    "stdout:\n${verify_output}\nstderr:\n${verify_error}")
endif()

function(clone_case case_name out_build out_stage)
  set(case_build "${stage}-oracles-${case_name}")
  set(case_stage "${stage}-mutation-${case_name}")
  file(REMOVE_RECURSE "${case_build}" "${case_stage}")
  file(MAKE_DIRECTORY "${case_build}" "${case_stage}")
  file(COPY "${stage}/" DESTINATION "${case_stage}")
  file(COPY
    "${build_dir}/PureFastCGIExpected.sha256"
    "${build_dir}/PureFastCGIInventory.tsv"
    DESTINATION "${case_build}")
  set(${out_build} "${case_build}" PARENT_SCOPE)
  set(${out_stage} "${case_stage}" PARENT_SCOPE)
endfunction()

function(run_rejected_case case_name case_build case_stage expected_category)
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DBUILD_DIR=${case_build}"
      "-DSTAGE_PREFIX=${case_stage}"
      "-DPURE_RUNTIME_ROOT=${runtime_root}"
      "-DLLVM_READOBJ=${LLVM_READOBJ}"
      "-DSOURCE_PREFIX=${source_dir}"
      "-DORIGINAL_BUILD_PREFIX=${build_dir}"
      "-DORIGINAL_STAGE_PREFIX=${stage}"
      -DRUN_RUNTIME_TESTS=OFF
      -P "${VERIFIER}"
    RESULT_VARIABLE case_result
    OUTPUT_VARIABLE case_output
    ERROR_VARIABLE case_error
    ENCODING UTF-8)
  set(case_log "${case_output}${case_error}")
  if(case_result EQUAL 0)
    message(FATAL_ERROR
      "mutation ${case_name} was accepted; expected ${expected_category}")
  endif()
  if(NOT case_log MATCHES "${expected_category}")
    message(FATAL_ERROR
      "mutation ${case_name} failed without ${expected_category}\n${case_log}")
  endif()
endfunction()

function(rewrite_inventory mutation case_build case_stage)
  set(oracle_inventory "${case_build}/PureFastCGIInventory.tsv")
  file(STRINGS "${oracle_inventory}" lines ENCODING UTF-8)
  list(POP_FRONT lines header)
  string(ASCII 9 local_tab)
  set(rewritten "${header}\n")
  set(first_payload_row "")
  foreach(line IN LISTS lines)
    if(first_payload_row STREQUAL "")
      set(first_payload_row "${line}")
    endif()
    if(mutation STREQUAL "forged-hash" AND
        line MATCHES "^lib/pure/fastcgi\\.dll${local_tab}")
      string(REPLACE "${local_tab}" ";" fields "${line}")
      list(REMOVE_AT fields 4)
      list(INSERT fields 4
        "0000000000000000000000000000000000000000000000000000000000000000")
      string(JOIN "${local_tab}" line ${fields})
    endif()
    string(APPEND rewritten "${line}\n")
  endforeach()
  if(mutation STREQUAL "case-collision")
    string(REPLACE "${local_tab}" ";" collision_fields "${first_payload_row}")
    list(REMOVE_AT collision_fields 0)
    list(INSERT collision_fields 0 "LIB/pure/fastcgi.dll")
    string(JOIN "${local_tab}" collision_row ${collision_fields})
    string(APPEND rewritten "${collision_row}\n")
  endif()

  file(WRITE "${oracle_inventory}" "${rewritten}")
  file(WRITE
    "${case_stage}/share/doc/pure-fastcgi/PureFastCGIInventory.tsv"
    "${rewritten}")
  file(SHA256 "${oracle_inventory}" inventory_sha)
  string(TOLOWER "${inventory_sha}" inventory_sha)
  file(STRINGS "${case_build}/PureFastCGIExpected.sha256" manifest_lines)
  file(WRITE "${case_build}/PureFastCGIExpected.sha256" "")
  foreach(line IN LISTS manifest_lines)
    if(line MATCHES "  share/doc/pure-fastcgi/PureFastCGIInventory\\.tsv$")
      file(APPEND "${case_build}/PureFastCGIExpected.sha256"
        "${inventory_sha}  share/doc/pure-fastcgi/PureFastCGIInventory.tsv\n")
    else()
      file(APPEND "${case_build}/PureFastCGIExpected.sha256" "${line}\n")
    endif()
  endforeach()
endfunction()

clone_case("changed-module" case_build case_stage)
file(APPEND "${case_stage}/lib/pure/fastcgi.dll" "changed")
run_rejected_case(
  "changed-module" "${case_build}" "${case_stage}" "PACKAGE_HASH_MISMATCH")

clone_case("undeclared-file" case_build case_stage)
file(WRITE "${case_stage}/share/doc/pure-fastcgi/undeclared.txt" "undeclared\n")
run_rejected_case(
  "undeclared-file" "${case_build}" "${case_stage}"
  "PACKAGE_FILE_SET_MISMATCH")

clone_case("deleted-license" case_build case_stage)
file(REMOVE "${case_stage}/share/doc/pure-fastcgi/LICENSE.fcgi2")
run_rejected_case(
  "deleted-license" "${case_build}" "${case_stage}"
  "PACKAGE_FILE_SET_MISMATCH")

clone_case("forged-inventory-hash" case_build case_stage)
rewrite_inventory("forged-hash" "${case_build}" "${case_stage}")
run_rejected_case(
  "forged-inventory-hash" "${case_build}" "${case_stage}"
  "INVENTORY_METADATA_MISMATCH")

clone_case("case-colliding-path" case_build case_stage)
rewrite_inventory("case-collision" "${case_build}" "${case_stage}")
run_rejected_case(
  "case-colliding-path" "${case_build}" "${case_stage}"
  "INVENTORY_CASE_COLLISION")

clone_case("synthetic-libfcgi" case_build case_stage)
file(COPY_FILE
  "${case_stage}/lib/pure/fastcgi.dll"
  "${case_stage}/lib/pure/libfcgi.dll")
run_rejected_case(
  "synthetic-libfcgi" "${case_build}" "${case_stage}"
  "FORBIDDEN_FASTCGI_DLL")

file(REMOVE_RECURSE
  "${stage}-oracles-changed-module"
  "${stage}-mutation-changed-module"
  "${stage}-oracles-undeclared-file"
  "${stage}-mutation-undeclared-file"
  "${stage}-oracles-deleted-license"
  "${stage}-mutation-deleted-license"
  "${stage}-oracles-forged-inventory-hash"
  "${stage}-mutation-forged-inventory-hash"
  "${stage}-oracles-case-colliding-path"
  "${stage}-mutation-case-colliding-path"
  "${stage}-oracles-synthetic-libfcgi"
  "${stage}-mutation-synthetic-libfcgi")
