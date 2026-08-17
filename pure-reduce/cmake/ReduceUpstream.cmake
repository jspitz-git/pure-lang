include_guard(GLOBAL)

include("${CMAKE_CURRENT_LIST_DIR}/ReduceSource.cmake")

function(_pure_reduce_checkout_pinned_files SOURCE_ROOT DESTINATION)
  file(MAKE_DIRECTORY "${DESTINATION}")
  # The private build must use the exact bytes in the pinned Git objects.
  # Explicitly disable host core.autocrlf so materialization is invariant
  # across Windows Git installations.
  execute_process(
    COMMAND git -c core.autocrlf=false -C "${SOURCE_ROOT}" checkout-index
      --force "--prefix=${DESTINATION}/" ${ARGN}
    RESULT_VARIABLE _checkout_result
    ERROR_VARIABLE _checkout_error)
  if(NOT _checkout_result EQUAL 0)
    message(FATAL_ERROR
      "could not materialize canonical pinned files: ${_checkout_error}")
  endif()
endfunction()

function(_pure_reduce_apply_private_source_patch
    PRIVATE_ROOT PATCH_FILE SOURCE_TREE_SHA256 TRANSCRIPT OUT_JSON)
  set(_expected_tree_sha256
    "134a68fdb10403d3a4c69051eb4e133803ff2659784f2d38ac4d94c7ee9f86d8")
  get_filename_component(_patch_name "${PATCH_FILE}" NAME)
  if(_patch_name STREQUAL "0001-csl-winsupport-define-nil.patch")
    set(_expected_patch_sha256
      "2d88d6d4a842ccb4574b60b0bd7e3af91896cea76708551a6e54489792e91d08")
    set(_target "csl/cslbase/winsupport.cpp")
    set(_expected_preimage
      "8e51f7c1fe17e960626f714c5e91e158ec73427ebcb7b886c8a0ffb6e2e633d2")
    set(_expected_postimage
      "8721a10c8ba5d9a82b5b0f5d2d83a46a4b98d87bb5519f92ce37940d15f936e0")
  else()
    message(FATAL_ERROR "source patch is not in the approved registry: ${PATCH_FILE}")
  endif()
  if(NOT SOURCE_TREE_SHA256 STREQUAL _expected_tree_sha256)
    message(FATAL_ERROR
      "private source patch is not approved for tree ${SOURCE_TREE_SHA256}")
  endif()
  if(NOT EXISTS "${PATCH_FILE}")
    message(FATAL_ERROR "approved private source patch is missing: ${PATCH_FILE}")
  endif()
  file(SHA256 "${PATCH_FILE}" _patch_sha256)
  if(NOT _patch_sha256 STREQUAL _expected_patch_sha256)
    message(FATAL_ERROR
      "approved source patch SHA-256 mismatch for ${_patch_name}: "
      "${_patch_sha256}; expected ${_expected_patch_sha256}")
  endif()
  set(_target_path "${PRIVATE_ROOT}/${_target}")
  file(SHA256 "${_target_path}" _preimage)
  if(NOT _preimage STREQUAL _expected_preimage)
    message(FATAL_ERROR
      "private source patch preimage mismatch for ${_target}: ${_preimage}")
  endif()
  execute_process(
    COMMAND git -C "${PRIVATE_ROOT}" rev-parse --show-toplevel
    RESULT_VARIABLE _top_result
    OUTPUT_VARIABLE _worktree_root
    ERROR_VARIABLE _top_error
    OUTPUT_STRIP_TRAILING_WHITESPACE)
  if(NOT _top_result EQUAL 0)
    message(FATAL_ERROR
      "private source patch root is not below the project worktree: ${_top_error}")
  endif()
  cmake_path(RELATIVE_PATH PRIVATE_ROOT
    BASE_DIRECTORY "${_worktree_root}" OUTPUT_VARIABLE _private_relative)
  execute_process(
    COMMAND git -C "${_worktree_root}" apply --check --whitespace=nowarn
      "--directory=${_private_relative}" "${PATCH_FILE}"
    RESULT_VARIABLE _check_result
    ERROR_VARIABLE _check_error)
  if(NOT _check_result EQUAL 0)
    message(FATAL_ERROR "approved source patch check failed: ${_check_error}")
  endif()
  execute_process(
    COMMAND git -C "${_worktree_root}" apply --whitespace=nowarn
      "--directory=${_private_relative}" "${PATCH_FILE}"
    RESULT_VARIABLE _apply_result
    ERROR_VARIABLE _apply_error)
  if(NOT _apply_result EQUAL 0)
    message(FATAL_ERROR "approved source patch failed: ${_apply_error}")
  endif()
  file(SHA256 "${_target_path}" _postimage)
  if(NOT _postimage STREQUAL _expected_postimage)
    message(FATAL_ERROR
      "private source patch postimage mismatch for ${_target}: ${_postimage}")
  endif()
  file(APPEND "${TRANSCRIPT}"
    "patch=${_patch_name}\n"
    "patch_sha256=${_patch_sha256}\n"
    "source_tree_sha256=${SOURCE_TREE_SHA256}\n"
    "target=${_target}\n"
    "preimage_sha256=${_preimage}\n"
    "postimage_sha256=${_postimage}\n\n")
  set(${OUT_JSON}
    "{\"patch\":\"${_patch_name}\",\"patch_sha256\":\"${_patch_sha256}\",\"target\":\"${_target}\",\"preimage_sha256\":\"${_preimage}\",\"postimage_sha256\":\"${_postimage}\"}"
    PARENT_SCOPE)
endfunction()

function(_pure_reduce_csl_link_interface
    CSL_ARCHIVE CRLIBM_ARCHIVE FFI_ARCHIVE OUT_INTERFACE)
  # This order is the successfully probed CLANG64 static link interface.
  # Consumers must not reorder it or substitute host library search paths.
  set(${OUT_INTERFACE}
    "${CSL_ARCHIVE}"
    "${CRLIBM_ARCHIVE}"
    "${FFI_ARCHIVE}"
    -Wl,-Bstatic
    -lz
    -lncurses
    -lstdc++
    -lpthread
    -static-libgcc
    -lcomctl32
    -lgdi32
    -lws2_32
    -lwsock32
    -lwinspool
    -lmpr
    -Wl,--subsystem,console
    PARENT_SCOPE)
endfunction()

function(_pure_reduce_write_directory_manifest DIRECTORY MANIFEST)
  if(NOT IS_DIRECTORY "${DIRECTORY}")
    message(FATAL_ERROR "CSL runtime directory is missing: ${DIRECTORY}")
  endif()
  file(GLOB_RECURSE _files LIST_DIRECTORIES FALSE "${DIRECTORY}/*")
  list(SORT _files)
  if(NOT _files)
    message(FATAL_ERROR "CSL runtime directory is empty: ${DIRECTORY}")
  endif()
  file(WRITE "${MANIFEST}" "")
  foreach(_file IN LISTS _files)
    file(SHA256 "${_file}" _sha256)
    file(SIZE "${_file}" _bytes)
    cmake_path(RELATIVE_PATH _file BASE_DIRECTORY "${DIRECTORY}"
      OUTPUT_VARIABLE _relative)
    file(APPEND "${MANIFEST}" "${_sha256} ${_bytes} ${_relative}\n")
  endforeach()
endfunction()

function(_pure_reduce_run_source_verification)
  foreach(_required IN ITEMS PURE_REDUCE_SOURCE_DIR
      PURE_REDUCE_VERIFIED_COMMIT PURE_REDUCE_SOURCE_TREE_SHA256)
    if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
      message(FATAL_ERROR "${_required} is required by source revalidation")
    endif()
  endforeach()
  pure_reduce_verify_source(
    "${PURE_REDUCE_SOURCE_DIR}" _actual_commit _actual_tree_sha256)
  if(NOT _actual_commit STREQUAL PURE_REDUCE_VERIFIED_COMMIT OR
      NOT _actual_tree_sha256 STREQUAL PURE_REDUCE_SOURCE_TREE_SHA256)
    message(FATAL_ERROR
      "verified REDUCE source identity changed after configuration")
  endif()
  message(STATUS
    "verified REDUCE source remains ${_actual_commit} (${_actual_tree_sha256})")
endfunction()

function(_pure_reduce_run_runtime_artifact_refresh)
  if(NOT DEFINED PURE_REDUCE_UPSTREAM_BINARY_DIR OR
      PURE_REDUCE_UPSTREAM_BINARY_DIR STREQUAL "")
    message(FATAL_ERROR
      "PURE_REDUCE_UPSTREAM_BINARY_DIR is required by runtime refresh")
  endif()
  get_filename_component(_root "${PURE_REDUCE_UPSTREAM_BINARY_DIR}" ABSOLUTE)
  _pure_reduce_select_windows_configuration("${_root}/source" _configuration)
  _pure_reduce_select_configuration_image("${_configuration}" _image)
  get_filename_component(_producer "${_image}" DIRECTORY)
  set(_runtime_root "${_root}/artifacts/runtime")
  set(_runtime_complete TRUE)
  foreach(_name IN ITEMS reduce.resources reduce.fonts)
    if(NOT IS_DIRECTORY "${_runtime_root}/${_name}" OR
       NOT EXISTS "${_runtime_root}/${_name}.manifest")
      set(_runtime_complete FALSE)
    endif()
  endforeach()
  if(_runtime_complete)
    message(STATUS "complete CSL runtime data remains staged")
    return()
  endif()
  file(MAKE_DIRECTORY "${_runtime_root}")
  foreach(_name IN ITEMS reduce.resources reduce.fonts)
    set(_source "${_producer}/${_name}")
    set(_destination "${_runtime_root}/${_name}")
    if(NOT IS_DIRECTORY "${_source}")
      message(FATAL_ERROR
        "complete CSL runtime data is missing from the image producer: ${_source}")
    endif()
    file(REMOVE_RECURSE "${_destination}")
    file(COPY "${_source}" DESTINATION "${_runtime_root}")
    _pure_reduce_write_directory_manifest(
      "${_destination}" "${_runtime_root}/${_name}.manifest")
  endforeach()
endfunction()

function(_pure_reduce_run_upstream_build_ensure)
  foreach(_required IN ITEMS PURE_REDUCE_UPSTREAM_BINARY_DIR
      PURE_REDUCE_SOURCE_DIR PURE_REDUCE_MSYS2_BASH PURE_REDUCE_MAKE
      PURE_REDUCE_VERIFIED_COMMIT PURE_REDUCE_SOURCE_TREE_SHA256)
    if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
      message(FATAL_ERROR "${_required} is required by upstream build ensure")
    endif()
  endforeach()
  get_filename_component(_root "${PURE_REDUCE_UPSTREAM_BINARY_DIR}" ABSOLUTE)
  set(_required_artifacts
    "${_root}/artifacts/reduce.img"
    "${_root}/artifacts/link/libreduce-csl.a"
    "${_root}/artifacts/link/libcrlibm.a"
    "${_root}/artifacts/link/libffi.a"
    "${_root}/reduce-upstream-metrics.json"
    "${_root}/logs/artifact-contract-probe.exe"
    "${_root}/logs/artifact-contract.log")
  set(_complete TRUE)
  foreach(_artifact IN LISTS _required_artifacts)
    if(NOT EXISTS "${_artifact}" OR IS_DIRECTORY "${_artifact}")
      set(_complete FALSE)
    else()
      file(SIZE "${_artifact}" _size)
      if(_size LESS 16)
        set(_complete FALSE)
      endif()
    endif()
  endforeach()
  set(_stamp "${_root}/pure-reduce-upstream.stamp")
  if(EXISTS "${_stamp}")
    file(READ "${_stamp}" _stamp_content)
    string(REPLACE "\r" "" _stamp_content "${_stamp_content}")
    set(_expected_stamp
      "${PURE_REDUCE_VERIFIED_COMMIT}\n${PURE_REDUCE_SOURCE_TREE_SHA256}\n")
    if(NOT _stamp_content STREQUAL _expected_stamp)
      set(_complete FALSE)
    endif()
  else()
    set(_complete FALSE)
  endif()
  if(_complete)
    message(STATUS "complete pinned REDUCE/CSL artifacts remain valid")
    return()
  endif()
  _pure_reduce_run_upstream_build()
endfunction()

function(_pure_reduce_discover_current_link_closure
    CSL_CONFIGURATION BASH_EXECUTABLE MAKE_EXECUTABLE OUT_OBJECTS)
  set(_query_script [=[
set -eu
export MSYSTEM=CLANG64
export PATH=/clang64/bin:/usr/bin
configuration=$(cygpath -u "$1")
make_exe=$(cygpath -u "$2")
cd "$configuration"
"$make_exe" -np reduce.exe | sed -n 's/^reduce\.exe: //p'
]=])
  execute_process(
    COMMAND "${BASH_EXECUTABLE}" --noprofile --norc -c "${_query_script}"
      pure-reduce "${CSL_CONFIGURATION}" "${MAKE_EXECUTABLE}"
    RESULT_VARIABLE _query_result
    OUTPUT_VARIABLE _prerequisites
    ERROR_VARIABLE _query_error)
  if(NOT _query_result EQUAL 0)
    message(FATAL_ERROR
      "could not query current REDUCE object closure: ${_query_error}")
  endif()
  string(REPLACE "\r" "" _prerequisites "${_prerequisites}")
  string(REPLACE "\n" " " _prerequisites "${_prerequisites}")
  separate_arguments(_prerequisites UNIX_COMMAND "${_prerequisites}")
  set(_object_names)
  foreach(_prerequisite IN LISTS _prerequisites)
    if(NOT _prerequisite MATCHES "^[A-Za-z0-9_.+-]+\\.o$")
      continue()
    endif()
    list(APPEND _object_names "${_prerequisite}")
  endforeach()
  list(REMOVE_DUPLICATES _object_names)
  set(_objects)
  set(_startup_count 0)
  foreach(_prerequisite IN LISTS _object_names)
    if(_prerequisite STREQUAL "reduce-csl.o")
      math(EXPR _startup_count "${_startup_count} + 1")
      set(_prerequisite "reduce_web-csl.o")
    endif()
    set(_object "${CSL_CONFIGURATION}/${_prerequisite}")
    cmake_path(IS_PREFIX CSL_CONFIGURATION "${_object}"
      NORMALIZE _inside_configuration)
    if(NOT _inside_configuration)
      message(FATAL_ERROR
        "current REDUCE object escapes selected configuration: ${_object}")
    endif()
    list(APPEND _objects "${_object}")
  endforeach()
  list(REMOVE_DUPLICATES _objects)
  if(NOT _startup_count EQUAL 1)
    message(FATAL_ERROR
      "expected exactly one reduce-csl.o in current REDUCE closure; "
      "found ${_startup_count}")
  endif()
  foreach(_object IN LISTS _objects)
    if(NOT EXISTS "${_object}")
      message(FATAL_ERROR
        "current REDUCE object closure is incomplete: ${_object}")
    endif()
  endforeach()
  set(${OUT_OBJECTS} "${_objects}" PARENT_SCOPE)
endfunction()

function(_pure_reduce_tree_bytes ROOT BASH_EXECUTABLE OUT_BYTES)
  set(_size_script [=[
set -eu
export MSYSTEM=CLANG64
export PATH=/clang64/bin:/usr/bin
root=$(cygpath -u "$1")
find "$root" -type f -printf '%s\n' | awk '{total += $1} END {printf "%.0f\n", total}'
]=])
  execute_process(
    COMMAND "${BASH_EXECUTABLE}" --noprofile --norc -c "${_size_script}"
      pure-reduce "${ROOT}"
    RESULT_VARIABLE _size_result
    OUTPUT_VARIABLE _total
    ERROR_VARIABLE _size_error
    OUTPUT_STRIP_TRAILING_WHITESPACE)
  if(NOT _size_result EQUAL 0 OR NOT _total MATCHES "^[0-9]+$")
    message(FATAL_ERROR
      "could not measure tree bytes below ${ROOT}: ${_size_error}")
  endif()
  set(${OUT_BYTES} "${_total}" PARENT_SCOPE)
endfunction()

function(_pure_reduce_select_windows_configuration SOURCE_ROOT OUT_DIRECTORY)
  file(GLOB _configuration_headers LIST_DIRECTORIES FALSE
    "${SOURCE_ROOT}/cslbuild/*/csl/config.h")
  list(SORT _configuration_headers)
  set(_candidates)
  foreach(_header IN LISTS _configuration_headers)
    file(READ "${_header}" _configuration)
    get_filename_component(_csl_directory "${_header}" DIRECTORY)
    get_filename_component(_configuration_directory
      "${_csl_directory}" DIRECTORY)
    if(_configuration MATCHES
        "#define[ \t]+HOST_CPU[ \t]+\"x86_64\"" AND
       _configuration MATCHES
        "#define[ \t]+HOST_OS[ \t]+\"mingw(32|64)\"" AND
       NOT _configuration MATCHES
        "#define[ \t]+RAW_CYGWIN[ \t]+1" AND
       EXISTS "${_configuration_directory}/Makefile")
      list(APPEND _candidates "${_configuration_directory}")
    endif()
  endforeach()

  list(LENGTH _candidates _candidate_count)
  if(NOT _candidate_count EQUAL 1)
    string(JOIN "\n  " _candidate_lines ${_candidates})
    if(_candidate_lines STREQUAL "")
      set(_candidate_lines "<none>")
    endif()
    message(FATAL_ERROR
      "expected exactly one non-Cygwin x86-64 CSL build configuration "
      "below ${SOURCE_ROOT}/cslbuild; found ${_candidate_count}:\n  "
      "${_candidate_lines}")
  endif()
  list(GET _candidates 0 _selected)
  set(${OUT_DIRECTORY} "${_selected}" PARENT_SCOPE)
endfunction()

function(_pure_reduce_select_configuration_image CONFIGURATION OUT_IMAGE)
  file(GLOB _image_candidates LIST_DIRECTORIES FALSE
    "${CONFIGURATION}/csl/reduce.img")
  list(LENGTH _image_candidates _image_count)
  if(NOT _image_count EQUAL 1)
    string(JOIN "\n  " _candidate_lines ${_image_candidates})
    if(_candidate_lines STREQUAL "")
      set(_candidate_lines "<none>")
    endif()
    message(FATAL_ERROR
      "expected exactly one complete CSL image in selected configuration "
      "${CONFIGURATION}; found ${_image_count}:\n  ${_candidate_lines}")
  endif()
  list(GET _image_candidates 0 _selected)
  set(${OUT_IMAGE} "${_selected}" PARENT_SCOPE)
endfunction()

function(_pure_reduce_restore_top_level_generated_files
    PINNED_ROOT PRIVATE_ROOT TRANSCRIPT OUT_JSON)
  # Upstream autogen is needed to populate generated support in nested CSL
  # projects. Its regenerated top-level configure is incompatible with the
  # pinned source, so restore only the top-level files that are tracked by the
  # verified commit. The fixed list makes this transformation fail closed.
  set(_restored_files
    Makefile.in
    aclocal.m4
    compile
    config.guess
    config.sub
    configure
    depcomp
    install-sh
    ltmain.sh
    missing)
  file(WRITE "${TRANSCRIPT}" "")
  set(_json "[")
  set(_separator "")
  foreach(_name IN LISTS _restored_files)
    set(_pinned "${PINNED_ROOT}/${_name}")
    set(_private "${PRIVATE_ROOT}/${_name}")
    if(NOT EXISTS "${_pinned}")
      message(FATAL_ERROR
        "pinned top-level generated file is missing: ${_pinned}")
    endif()
    file(COPY_FILE "${_pinned}" "${_private}" ONLY_IF_DIFFERENT)
    file(SHA256 "${_pinned}" _pinned_hash)
    file(SHA256 "${_private}" _private_hash)
    if(NOT _private_hash STREQUAL _pinned_hash)
      message(FATAL_ERROR
        "restored top-level generated file differs from pin: ${_name}")
    endif()
    file(APPEND "${TRANSCRIPT}" "${_pinned_hash}  ${_name}\n")
    string(APPEND _json
      "${_separator}{\"path\":\"${_name}\",\"sha256\":\"${_pinned_hash}\"}")
    set(_separator ",")
  endforeach()
  string(APPEND _json "]")
  set(${OUT_JSON} "${_json}" PARENT_SCOPE)
endfunction()

function(_pure_reduce_json_escape VALUE OUT_VALUE)
  string(REPLACE "\\" "\\\\" _escaped "${VALUE}")
  string(REPLACE "\"" "\\\"" _escaped "${_escaped}")
  string(REPLACE "\r" "" _escaped "${_escaped}")
  string(REPLACE "\n" "\\n" _escaped "${_escaped}")
  set(${OUT_VALUE} "${_escaped}" PARENT_SCOPE)
endfunction()

function(_pure_reduce_run_logged LABEL LOG_FILE BASH_EXECUTABLE SCRIPT)
  execute_process(
    COMMAND "${BASH_EXECUTABLE}" --noprofile --norc -c "${SCRIPT}"
      pure-reduce ${ARGN}
    RESULT_VARIABLE _result
    OUTPUT_FILE "${LOG_FILE}"
    ERROR_FILE "${LOG_FILE}")
  if(NOT _result EQUAL 0)
    message(FATAL_ERROR
      "${LABEL} failed with exit code ${_result}; transcript: ${LOG_FILE}")
  endif()
endfunction()

function(_pure_reduce_run_upstream_build)
  foreach(_required IN ITEMS
      PURE_REDUCE_SOURCE_DIR
      PURE_REDUCE_UPSTREAM_BINARY_DIR
      PURE_REDUCE_MSYS2_BASH
      PURE_REDUCE_MAKE
      PURE_REDUCE_VERIFIED_COMMIT
      PURE_REDUCE_SOURCE_TREE_SHA256)
    if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
      message(FATAL_ERROR "${_required} is required by the upstream build")
    endif()
  endforeach()

  pure_reduce_verify_source(
    "${PURE_REDUCE_SOURCE_DIR}" _actual_commit _actual_tree_sha256)
  if(NOT _actual_commit STREQUAL PURE_REDUCE_VERIFIED_COMMIT OR
      NOT _actual_tree_sha256 STREQUAL PURE_REDUCE_SOURCE_TREE_SHA256)
    message(FATAL_ERROR
      "verified REDUCE source identity changed before the upstream build")
  endif()

  string(TIMESTAMP _started "%s" UTC)
  get_filename_component(_root "${PURE_REDUCE_UPSTREAM_BINARY_DIR}" ABSOLUTE)
  set(_private_source "${_root}/source")
  set(_pinned_generated "${_root}/pinned-generated")
  set(_artifacts "${_root}/artifacts")
  set(_link_artifacts "${_artifacts}/link")
  set(_runtime_artifacts "${_artifacts}/runtime")
  set(_logs "${_root}/logs")
  set(_nil_patch_file
    "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../patches/0001-csl-winsupport-define-nil.patch")
  set(_autogen_log "${_logs}/autogen.log")
  set(_patch_log "${_logs}/applied-source-patches.log")
  set(_restore_log "${_logs}/restored-top-level-files.log")
  set(_configure_log "${_logs}/configure.log")
  set(_build_log "${_logs}/build.log")
  set(_no_startup_log "${_logs}/no-startup-object.log")
  set(_archive_log "${_logs}/current-closure-archive.log")
  set(_closure_manifest "${_logs}/current-closure-objects.log")
  set(_artifact_contract_log "${_logs}/artifact-contract.log")
  set(_metrics "${_root}/reduce-upstream-metrics.json")
  set(_stamp "${_root}/pure-reduce-upstream.stamp")

  cmake_path(IS_PREFIX PURE_REDUCE_SOURCE_DIR "${_private_source}"
    NORMALIZE _private_inside_verified)
  cmake_path(IS_PREFIX _private_source "${PURE_REDUCE_SOURCE_DIR}"
    NORMALIZE _verified_inside_private)
  if(_private_inside_verified OR _verified_inside_private)
    message(FATAL_ERROR
      "private upstream materialization overlaps verified checkout: "
      "${_private_source} vs ${PURE_REDUCE_SOURCE_DIR}")
  endif()

  file(REMOVE_RECURSE
    "${_private_source}" "${_pinned_generated}" "${_artifacts}" "${_logs}")
  file(REMOVE "${_metrics}" "${_stamp}")
  file(MAKE_DIRECTORY
    "${_root}" "${_private_source}" "${_link_artifacts}"
    "${_runtime_artifacts}" "${_logs}")

  _pure_reduce_checkout_pinned_files(
    "${PURE_REDUCE_SOURCE_DIR}" "${_private_source}" --all)
  file(WRITE "${_patch_log}" "")
  _pure_reduce_apply_private_source_patch(
    "${_private_source}" "${_nil_patch_file}"
    "${PURE_REDUCE_SOURCE_TREE_SHA256}" "${_patch_log}"
    _nil_patch_json)
  _pure_reduce_tree_bytes(
    "${_private_source}" "${PURE_REDUCE_MSYS2_BASH}" _source_bytes)

  set(_autogen_script [=[
set -eu
export MSYSTEM=CLANG64
export PATH=/clang64/bin:/usr/bin
export CONFIG_SITE=/dev/null
export WANT_AUTOCONF=2.73
src=$(cygpath -u "$1")
cd "$src"
./autogen.sh --with-csl --without-gui --without-redfront
]=])
  _pure_reduce_run_logged(
    "upstream REDUCE CSL autogen" "${_autogen_log}"
    "${PURE_REDUCE_MSYS2_BASH}" "${_autogen_script}"
    "${_private_source}")
  _pure_reduce_checkout_pinned_files(
    "${PURE_REDUCE_SOURCE_DIR}" "${_pinned_generated}"
    Makefile.in aclocal.m4 compile config.guess config.sub configure depcomp
    install-sh ltmain.sh missing)
  _pure_reduce_restore_top_level_generated_files(
    "${_pinned_generated}" "${_private_source}" "${_restore_log}"
    _restored_files_json)

  set(_configure_script [=[
set -eu
export MSYSTEM=CLANG64
export PATH=/clang64/bin:/usr/bin
export CONFIG_SITE=/dev/null
export WANT_AUTOCONF=2.73
# libffi mistakes lld's GNU-driver compatibility for ELF symbol-versioning
# support on native MinGW. This documented configure variable is inherited by
# its nested configure script, while the top-level driver does not forward
# arbitrary --disable-* options.
export enable_symvers=no
src=$(cygpath -u "$1")
cd "$src"
./configure --without-autogen --with-csl --without-gui --without-redfront CC=clang CXX=clang++
]=])
  _pure_reduce_run_logged(
    "official REDUCE CSL configure" "${_configure_log}"
    "${PURE_REDUCE_MSYS2_BASH}" "${_configure_script}"
    "${_private_source}")

  _pure_reduce_select_windows_configuration(
    "${_private_source}" _build_configuration)

  set(_build_script [=[
set -eu
export MSYSTEM=CLANG64
export PATH=/clang64/bin:/usr/bin
src=$(cygpath -u "$1")
make_exe=$(cygpath -u "$2")
configuration=$(cygpath -u "$3")
cd "$src"
"$make_exe" -j1 -C "$configuration"
]=])
  _pure_reduce_run_logged(
    "official complete REDUCE CSL build" "${_build_log}"
    "${PURE_REDUCE_MSYS2_BASH}" "${_build_script}"
    "${_private_source}" "${PURE_REDUCE_MAKE}"
    "${_build_configuration}")

  _pure_reduce_select_configuration_image(
    "${_build_configuration}" _full_image)
  get_filename_component(_full_configuration "${_full_image}" DIRECTORY)

  foreach(_runtime_name IN ITEMS reduce.resources reduce.fonts)
    if(NOT IS_DIRECTORY "${_full_configuration}/${_runtime_name}")
      message(FATAL_ERROR
        "complete CSL runtime data is missing from the image producer: "
        "${_full_configuration}/${_runtime_name}")
    endif()
    file(COPY "${_full_configuration}/${_runtime_name}"
      DESTINATION "${_runtime_artifacts}")
  endforeach()

  set(_closure_script [=[
set -eu
export MSYSTEM=CLANG64
export PATH=/clang64/bin:/usr/bin
configuration=$(cygpath -u "$1")
make_exe=$(cygpath -u "$2")
cd "$configuration"
"$make_exe" -j1 reduce_web-csl.o
]=])
  _pure_reduce_run_logged(
    "current upstream no-startup CSL object build" "${_no_startup_log}"
    "${PURE_REDUCE_MSYS2_BASH}" "${_closure_script}"
    "${_full_configuration}" "${PURE_REDUCE_MAKE}")
  _pure_reduce_discover_current_link_closure(
    "${_full_configuration}" "${PURE_REDUCE_MSYS2_BASH}"
    "${PURE_REDUCE_MAKE}" _current_objects)

  file(COPY_FILE "${_full_image}"
    "${_artifacts}/reduce.img" ONLY_IF_DIFFERENT)
  set(_csl_archive "${_link_artifacts}/libreduce-csl.a")
  file(WRITE "${_closure_manifest}" "")
  foreach(_object IN LISTS _current_objects)
    file(SHA256 "${_object}" _object_sha256)
    get_filename_component(_object_name "${_object}" NAME)
    file(APPEND "${_closure_manifest}"
      "${_object_sha256}  ${_object_name}\n")
  endforeach()
  set(_archive_script [=[
set -eu
export MSYSTEM=CLANG64
export PATH=/clang64/bin:/usr/bin
archive=$(cygpath -u "$1")
shift
objects=()
for object in "$@"; do objects+=("$(cygpath -u "$object")"); done
llvm-ar rcs "$archive" "${objects[@]}"
]=])
  _pure_reduce_run_logged(
    "archive current upstream CSL object closure" "${_archive_log}"
    "${PURE_REDUCE_MSYS2_BASH}" "${_archive_script}"
    "${_csl_archive}" ${_current_objects})

  set(_selected_static_libraries)
  foreach(_library_name IN ITEMS libcrlibm.a libffi.a)
    set(_library_source "${_build_configuration}/lib/${_library_name}")
    set(_library_artifact "${_link_artifacts}/${_library_name}")
    cmake_path(IS_PREFIX _build_configuration "${_library_source}"
      NORMALIZE _selected_library)
    if(NOT _selected_library OR NOT EXISTS "${_library_source}")
      message(FATAL_ERROR
        "selected static library is unavailable: ${_library_source}")
    endif()
    file(COPY_FILE "${_library_source}" "${_library_artifact}"
      ONLY_IF_DIFFERENT)
    list(APPEND _selected_static_libraries "${_library_artifact}")
  endforeach()

  set(_probe_source "${_logs}/artifact-contract-probe.cpp")
  set(_probe_executable "${_logs}/artifact-contract-probe.exe")
  file(WRITE "${_probe_source}" [=[
extern "C" int PROC_clear_stack();
namespace CSL_LISP {
using character_writer = int(int);
void cslstart(int, const char*[], character_writer*);
}
int main() {
  void (*volatile start)(int, const char*[], CSL_LISP::character_writer*) =
      &CSL_LISP::cslstart;
  return PROC_clear_stack() + (start == nullptr);
}
]=])
  set(_probe_script [=[
set -eu
export MSYSTEM=CLANG64
export PATH=/clang64/bin:/usr/bin
source_file=$(cygpath -u "$1")
probe=$(cygpath -u "$2")
shift 2
link_args=()
for arg in "$@"; do
  case "$arg" in
    [A-Za-z]:/*) link_args+=("$(cygpath -u "$arg")") ;;
    *) link_args+=("$arg") ;;
  esac
done
clang++ -std=gnu++26 -flto -O3 "$source_file" "${link_args[@]}" -o "$probe"
llvm-nm -C --defined-only "$probe" | grep -q 'PROC_clear_stack$'
llvm-nm -C --defined-only "$probe" | grep -q 'CSL_LISP::cslstart('
imports=$(llvm-readobj --coff-imports "$probe" | sed -n 's/^  Name: //p')
if printf '%s\n' "$imports" | grep -Eiq \
    '(^|/)(msys|cygwin|zlib|libstdc\+\+|libwinpthread|ncurses)'; then
  printf 'non-system runtime import found:\n%s\n' "$imports" >&2
  exit 1
fi
printf 'PROC_clear_stack=defined\n'
printf 'CSL_LISP::cslstart=defined\n'
printf 'non_system_runtime_imports=none\n'
printf 'imports:\n%s\n' "$imports"
]=])
  list(GET _selected_static_libraries 0 _crlibm_artifact)
  list(GET _selected_static_libraries 1 _ffi_artifact)
  _pure_reduce_csl_link_interface(
    "${_csl_archive}" "${_crlibm_artifact}" "${_ffi_artifact}"
    _link_interface)
  _pure_reduce_run_logged(
    "current CSL artifact link and symbol contract" "${_artifact_contract_log}"
    "${PURE_REDUCE_MSYS2_BASH}" "${_probe_script}"
    "${_probe_source}" "${_probe_executable}" ${_link_interface})
  list(LENGTH _current_objects _current_object_count)

  set(_tool_script [=[
set -eu
export MSYSTEM=CLANG64
export PATH=/clang64/bin:/usr/bin
make_exe=$(cygpath -u "$1")
printf 'bash=%s\n' "$(bash --version | sed -n '1p')"
printf 'make=%s\n' "$("$make_exe" --version | sed -n '1p')"
printf 'clang=%s\n' "$(clang --version | sed -n '1p')"
printf 'g++_compat=%s\n' "$(g++ --version | sed -n '1p')"
printf 'autoconf=%s\n' "$(autoconf --version | sed -n '1p')"
]=])
  execute_process(
    COMMAND "${PURE_REDUCE_MSYS2_BASH}" --noprofile --norc -c
      "${_tool_script}" pure-reduce "${PURE_REDUCE_MAKE}"
    RESULT_VARIABLE _tool_result
    OUTPUT_VARIABLE _tool_versions
    ERROR_VARIABLE _tool_error
    OUTPUT_STRIP_TRAILING_WHITESPACE)
  if(NOT _tool_result EQUAL 0)
    message(FATAL_ERROR "could not record upstream tool versions: ${_tool_error}")
  endif()

  string(TIMESTAMP _finished "%s" UTC)
  math(EXPR _elapsed_seconds "${_finished} - ${_started}")
  _pure_reduce_tree_bytes(
    "${_root}" "${PURE_REDUCE_MSYS2_BASH}" _build_tree_bytes)
  _pure_reduce_json_escape("${_tool_versions}" _tool_versions_json)
  _pure_reduce_json_escape("${_patch_log}" _patch_log_json)
  _pure_reduce_json_escape("${_autogen_log}" _autogen_log_json)
  _pure_reduce_json_escape("${_restore_log}" _restore_log_json)
  _pure_reduce_json_escape("${_configure_log}" _configure_log_json)
  _pure_reduce_json_escape("${_build_log}" _build_log_json)
  _pure_reduce_json_escape("${_no_startup_log}" _no_startup_log_json)
  _pure_reduce_json_escape("${_archive_log}" _archive_log_json)
  _pure_reduce_json_escape("${_closure_manifest}" _closure_manifest_json)
  _pure_reduce_json_escape("${_artifact_contract_log}"
    _artifact_contract_log_json)
  file(WRITE "${_metrics}"
    "{\n"
    "  \"commit\": \"${PURE_REDUCE_VERIFIED_COMMIT}\",\n"
    "  \"source_tree_sha256\": \"${PURE_REDUCE_SOURCE_TREE_SHA256}\",\n"
    "  \"source_materialization\": \"git -c core.autocrlf=false checkout-index\",\n"
    "  \"source_patches\": [${_nil_patch_json}],\n"
    "  \"tool_versions\": \"${_tool_versions_json}\",\n"
    "  \"autogen_arguments\": [\"--with-csl\", \"--without-gui\", \"--without-redfront\"],\n"
    "  \"configure_arguments\": [\"--without-autogen\", \"--with-csl\", \"--without-gui\", \"--without-redfront\", \"CC=clang\", \"CXX=clang++\"],\n"
    "  \"dependency_profile\": \"text-only CSL/image runtime; upstream GUI, Redfront, FOX, X11, and libedit dependencies excluded\",\n"
    "  \"configure_environment\": {\"enable_symvers\": \"no\"},\n"
    "  \"restored_top_level_files\": ${_restored_files_json},\n"
    "  \"link_closure\": {\"source_target\": \"reduce.exe\", \"startup_object_replacement\": \"reduce-csl.o -> reduce_web-csl.o\", \"object_count\": ${_current_object_count}, \"archive\": \"${_csl_archive}\", \"selected_static_libraries\": [\"${_crlibm_artifact}\", \"${_ffi_artifact}\"]},\n"
    "  \"elapsed_seconds\": ${_elapsed_seconds},\n"
    "  \"source_bytes\": ${_source_bytes},\n"
    "  \"build_tree_bytes\": ${_build_tree_bytes},\n"
    "  \"logs\": {\"source_patches\": \"${_patch_log_json}\", \"autogen\": \"${_autogen_log_json}\", \"restored_top_level_files\": \"${_restore_log_json}\", \"configure\": \"${_configure_log_json}\", \"build\": \"${_build_log_json}\", \"no_startup_object\": \"${_no_startup_log_json}\", \"closure_archive\": \"${_archive_log_json}\", \"closure_manifest\": \"${_closure_manifest_json}\", \"artifact_contract\": \"${_artifact_contract_log_json}\"}\n"
    "}\n")
  file(WRITE "${_stamp}"
    "${PURE_REDUCE_VERIFIED_COMMIT}\n"
    "${PURE_REDUCE_SOURCE_TREE_SHA256}\n")
endfunction()

function(pure_reduce_define_upstream_build)
  foreach(_required IN ITEMS
      PURE_REDUCE_SOURCE_DIR
      PURE_REDUCE_VERIFIED_COMMIT
      PURE_REDUCE_SOURCE_TREE_SHA256)
    if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
      message(FATAL_ERROR "${_required} is required by the upstream contract")
    endif()
  endforeach()

  if(NOT DEFINED PURE_REDUCE_UPSTREAM_BINARY_DIR OR
      PURE_REDUCE_UPSTREAM_BINARY_DIR STREQUAL "")
    set(PURE_REDUCE_UPSTREAM_BINARY_DIR
      "${CMAKE_CURRENT_BINARY_DIR}/reduce-upstream")
  endif()
  get_filename_component(_root "${PURE_REDUCE_UPSTREAM_BINARY_DIR}" ABSOLUTE
    BASE_DIR "${CMAKE_CURRENT_BINARY_DIR}")
  file(TO_CMAKE_PATH "${_root}" _root)

  set(_image "${_root}/artifacts/reduce.img")
  set(_link_artifacts
    "${_root}/artifacts/link/libreduce-csl.a"
    "${_root}/artifacts/link/libcrlibm.a"
    "${_root}/artifacts/link/libffi.a")
  list(GET _link_artifacts 0 _csl_archive)
  list(GET _link_artifacts 1 _crlibm_archive)
  list(GET _link_artifacts 2 _ffi_archive)
  _pure_reduce_csl_link_interface(
    "${_csl_archive}" "${_crlibm_archive}" "${_ffi_archive}"
    _link_interface)
  set(_runtime_data
    "${_root}/artifacts/runtime/reduce.resources"
    "${_root}/artifacts/runtime/reduce.fonts")
  set(_runtime_manifests
    "${_root}/artifacts/runtime/reduce.resources.manifest"
    "${_root}/artifacts/runtime/reduce.fonts.manifest")
  set(_metrics "${_root}/reduce-upstream-metrics.json")
  set(_stamp "${_root}/pure-reduce-upstream.stamp")

  set(PURE_REDUCE_UPSTREAM_BINARY_DIR "${_root}" PARENT_SCOPE)
  set(PURE_REDUCE_CSL_IMAGE "${_image}" PARENT_SCOPE)
  # LINK_ARTIFACTS are verified files. LINK_INTERFACE (and its compatibility
  # alias LINK_INPUTS) is the complete ordered sequence for target_link_libraries.
  set(PURE_REDUCE_CSL_LINK_ARTIFACTS "${_link_artifacts}" PARENT_SCOPE)
  set(PURE_REDUCE_CSL_LINK_INTERFACE "${_link_interface}" PARENT_SCOPE)
  set(PURE_REDUCE_CSL_LINK_INPUTS "${_link_interface}" PARENT_SCOPE)
  set(PURE_REDUCE_RUNTIME_DATA "${_runtime_data}" PARENT_SCOPE)
  set(PURE_REDUCE_RUNTIME_MANIFESTS "${_runtime_manifests}" PARENT_SCOPE)
  set(PURE_REDUCE_UPSTREAM_METRICS "${_metrics}" PARENT_SCOPE)

  if(CMAKE_SCRIPT_MODE_FILE)
    return()
  endif()
  foreach(_tool IN ITEMS PURE_REDUCE_MSYS2_BASH PURE_REDUCE_MAKE)
    if(NOT IS_ABSOLUTE "${${_tool}}" OR NOT EXISTS "${${_tool}}")
      message(FATAL_ERROR
        "${_tool} must be an existing absolute build-tool path: ${${_tool}}")
    endif()
  endforeach()
  if(TARGET pure-reduce-upstream)
    return()
  endif()

  add_custom_target(pure-reduce-upstream-source-verify
    COMMAND "${CMAKE_COMMAND}"
      -DPURE_REDUCE_RUN_SOURCE_VERIFICATION=ON
      "-DPURE_REDUCE_SOURCE_DIR=${PURE_REDUCE_SOURCE_DIR}"
      "-DPURE_REDUCE_VERIFIED_COMMIT=${PURE_REDUCE_VERIFIED_COMMIT}"
      "-DPURE_REDUCE_SOURCE_TREE_SHA256=${PURE_REDUCE_SOURCE_TREE_SHA256}"
      -P "${CMAKE_CURRENT_FUNCTION_LIST_FILE}"
    COMMENT "Revalidating pinned REDUCE source"
    VERBATIM)
  add_custom_target(pure-reduce-upstream-build-ensure
    COMMAND "${CMAKE_COMMAND}"
      -DPURE_REDUCE_RUN_UPSTREAM_BUILD_ENSURE=ON
      "-DPURE_REDUCE_SOURCE_DIR=${PURE_REDUCE_SOURCE_DIR}"
      "-DPURE_REDUCE_UPSTREAM_BINARY_DIR=${_root}"
      "-DPURE_REDUCE_MSYS2_BASH=${PURE_REDUCE_MSYS2_BASH}"
      "-DPURE_REDUCE_MAKE=${PURE_REDUCE_MAKE}"
      "-DPURE_REDUCE_VERIFIED_COMMIT=${PURE_REDUCE_VERIFIED_COMMIT}"
      "-DPURE_REDUCE_SOURCE_TREE_SHA256=${PURE_REDUCE_SOURCE_TREE_SHA256}"
      -P "${CMAKE_CURRENT_FUNCTION_LIST_FILE}"
    BYPRODUCTS "${_stamp}" "${_image}" ${_link_artifacts} "${_metrics}"
      "${_root}/logs/artifact-contract-probe.exe"
      "${_root}/logs/artifact-contract.log"
    COMMENT "Ensuring complete pinned REDUCE/CSL artifacts"
    USES_TERMINAL
    VERBATIM)
  add_dependencies(
    pure-reduce-upstream-build-ensure pure-reduce-upstream-source-verify)
  add_custom_target(pure-reduce-upstream-runtime-ensure
    COMMAND "${CMAKE_COMMAND}"
      -DPURE_REDUCE_RUN_RUNTIME_ARTIFACT_REFRESH=ON
      "-DPURE_REDUCE_UPSTREAM_BINARY_DIR=${_root}"
      -P "${CMAKE_CURRENT_FUNCTION_LIST_FILE}"
    BYPRODUCTS ${_runtime_manifests} ${_runtime_data}
    COMMENT "Ensuring complete CSL runtime data"
    VERBATIM)
  add_dependencies(
    pure-reduce-upstream-runtime-ensure pure-reduce-upstream-build-ensure)
  add_custom_target(pure-reduce-upstream)
  add_dependencies(pure-reduce-upstream pure-reduce-upstream-runtime-ensure)
endfunction()

if(PURE_REDUCE_RUN_UPSTREAM_BUILD)
  _pure_reduce_run_upstream_build()
elseif(PURE_REDUCE_RUN_SOURCE_VERIFICATION)
  _pure_reduce_run_source_verification()
elseif(PURE_REDUCE_RUN_RUNTIME_ARTIFACT_REFRESH)
  _pure_reduce_run_runtime_artifact_refresh()
elseif(PURE_REDUCE_RUN_UPSTREAM_BUILD_ENSURE)
  _pure_reduce_run_upstream_build_ensure()
endif()
