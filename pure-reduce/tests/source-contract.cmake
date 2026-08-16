cmake_minimum_required(VERSION 3.25)

set(_pure_reduce_root "${CMAKE_CURRENT_LIST_DIR}/..")
set(_pure_reduce_module "${_pure_reduce_root}/cmake/ReduceSource.cmake")

if(PURE_REDUCE_SOURCE_CONTRACT_PROBE)
  include("${_pure_reduce_module}")
  if(DEFINED PURE_REDUCE_SOURCE_CONTRACT_PROBE_OVERRIDE)
    set(PURE_REDUCE_UPSTREAM_COMMIT
      "${PURE_REDUCE_SOURCE_CONTRACT_PROBE_OVERRIDE}")
  endif()
  pure_reduce_verify_source(
    "${PURE_REDUCE_SOURCE_CONTRACT_PROBE_ROOT}" actual tree_sha256)
  return()
endif()

# A cache override must not alter the checked-in upstream identity contract.
set(PURE_REDUCE_UPSTREAM_COMMIT "0000000000000000000000000000000000000000")
include("${_pure_reduce_module}")
set(expected "7efba90661139ae9c73c99fddd55f3fb2fabf69a")
if(NOT PURE_REDUCE_UPSTREAM_COMMIT STREQUAL expected)
  message(FATAL_ERROR "upstream commit override was accepted")
endif()

function(pure_reduce_expect_verification_failure label root expected_message)
  set(_override_argument)
  if(ARGC GREATER 3)
    set(_override_argument
      "-DPURE_REDUCE_SOURCE_CONTRACT_PROBE_OVERRIDE=${ARGV3}")
  endif()
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_REDUCE_SOURCE_CONTRACT_PROBE=ON"
      "-DPURE_REDUCE_SOURCE_CONTRACT_PROBE_ROOT=${root}"
      ${_override_argument}
      -P "${CMAKE_CURRENT_LIST_FILE}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error)
  if(result EQUAL 0)
    message(FATAL_ERROR "${label} source verification unexpectedly succeeded")
  endif()
  if(NOT "${output}${error}" MATCHES "${expected_message}")
    message(FATAL_ERROR
      "${label} source verification failed for the wrong reason:\n${output}${error}")
  endif()
endfunction()

if(DEFINED ENV{TEMP} AND NOT "$ENV{TEMP}" STREQUAL "")
  set(_fixture_root "$ENV{TEMP}/pure-reduce-source-contract")
else()
  set(_fixture_root "${CMAKE_CURRENT_BINARY_DIR}/pure-reduce-source-contract")
endif()
file(REMOVE_RECURSE "${_fixture_root}")
file(MAKE_DIRECTORY "${_fixture_root}/non-git")

pure_reduce_expect_verification_failure(
  "missing root" "${_fixture_root}/missing" "REDUCE source directory does not exist")
pure_reduce_expect_verification_failure(
  "non-Git root" "${_fixture_root}/non-git" "REDUCE source directory is not a Git checkout")

set(_override_root "${_fixture_root}/override-checkout")
file(MAKE_DIRECTORY "${_override_root}")
file(WRITE "${_override_root}/tracked.txt" "source contract fixture\n")
execute_process(
  COMMAND git init -q "${_override_root}"
  RESULT_VARIABLE _override_init_result
  ERROR_VARIABLE _override_init_error)
execute_process(
  COMMAND git -C "${_override_root}" add tracked.txt
  RESULT_VARIABLE _override_add_result
  ERROR_VARIABLE _override_add_error)
execute_process(
  COMMAND git -C "${_override_root}" -c user.name=fixture -c user.email=fixture@example.invalid
    commit -q -m source-contract-fixture
  RESULT_VARIABLE _override_commit_result
  ERROR_VARIABLE _override_commit_error)
if(NOT _override_init_result EQUAL 0 OR NOT _override_add_result EQUAL 0
    OR NOT _override_commit_result EQUAL 0)
  message(FATAL_ERROR
    "could not create override source fixture:\n${_override_init_error}${_override_add_error}${_override_commit_error}")
endif()
pure_reduce_expect_verification_failure(
  "override commit" "${_override_root}"
  "required: 7efba90661139ae9c73c99fddd55f3fb2fabf69a"
  "0000000000000000000000000000000000000000")

if(NOT DEFINED PURE_REDUCE_SOURCE_DIR OR PURE_REDUCE_SOURCE_DIR STREQUAL "")
  message(FATAL_ERROR "PURE_REDUCE_SOURCE_DIR must name a clean pinned checkout")
endif()

pure_reduce_verify_source(
  "${PURE_REDUCE_SOURCE_DIR}" actual tree_sha256)
if(NOT actual STREQUAL expected)
  message(FATAL_ERROR "unexpected verified commit: ${actual}")
endif()
if(NOT tree_sha256 MATCHES "^[0-9a-f]{64}$")
  # CMake's bundled regex engine on the supported CLANG64 installation treats
  # `{64}` literally. Retain the contract expression above and make the same
  # assertion portably as a hexadecimal match plus an explicit length check.
  string(LENGTH "${tree_sha256}" tree_sha256_length)
  if(NOT tree_sha256 MATCHES "^[0-9a-f]+$" OR NOT tree_sha256_length EQUAL 64)
    message(FATAL_ERROR "invalid source tree SHA-256: ${tree_sha256}")
  endif()
endif()

set(_dirty_checkout "${_fixture_root}/dirty-checkout")
file(TO_NATIVE_PATH "${PURE_REDUCE_SOURCE_DIR}" _dirty_source_root)
file(TO_NATIVE_PATH "${_dirty_checkout}" _dirty_checkout_root)
execute_process(
  COMMAND git clone --local --no-hardlinks "${_dirty_source_root}" "${_dirty_checkout_root}"
  RESULT_VARIABLE _dirty_clone_result
  OUTPUT_VARIABLE _dirty_clone_output
  ERROR_VARIABLE _dirty_clone_error)
set(_dirty_checkout_is_linked_worktree FALSE)
if(NOT _dirty_clone_result EQUAL 0)
  # Some Windows hosts prohibit Git for Windows from spawning its local clone
  # helper. A linked checkout has the same tracked working-tree semantics and
  # keeps the source-contract mutation test runnable without network access.
  message(STATUS "local Git clone unavailable; using a linked checkout for the dirty fixture")
  execute_process(
    COMMAND git -C "${_dirty_source_root}" worktree add --detach
      "${_dirty_checkout_root}" HEAD
    RESULT_VARIABLE _dirty_worktree_result
    OUTPUT_VARIABLE _dirty_worktree_output
    ERROR_VARIABLE _dirty_worktree_error)
  if(NOT _dirty_worktree_result EQUAL 0)
    message(FATAL_ERROR
      "could not create dirty REDUCE source fixture:\n"
      "clone:\n${_dirty_clone_output}${_dirty_clone_error}\n"
      "linked checkout:\n${_dirty_worktree_output}${_dirty_worktree_error}")
  endif()
  set(_dirty_checkout_is_linked_worktree TRUE)
endif()
execute_process(
  COMMAND git -C "${_dirty_checkout}" ls-files
  RESULT_VARIABLE _tracked_files_result
  OUTPUT_VARIABLE _tracked_files
  ERROR_VARIABLE _tracked_files_error
  OUTPUT_STRIP_TRAILING_WHITESPACE)
if(NOT _tracked_files_result EQUAL 0 OR _tracked_files STREQUAL "")
  message(FATAL_ERROR
    "could not select a tracked REDUCE file for the dirty fixture:\n${_tracked_files_error}")
endif()
string(REPLACE "\n" ";" _tracked_files_list "${_tracked_files}")
list(GET _tracked_files_list 0 _tracked_file)
file(APPEND "${_dirty_checkout}/${_tracked_file}"
  "\n# pure-reduce source-contract dirty fixture\n")
pure_reduce_expect_verification_failure(
  "dirty tree" "${_dirty_checkout}" "REDUCE source tree is dirty")

if(_dirty_checkout_is_linked_worktree)
  execute_process(
    COMMAND git -C "${_dirty_source_root}" worktree remove --force
      "${_dirty_checkout_root}"
    RESULT_VARIABLE _dirty_remove_result
    ERROR_VARIABLE _dirty_remove_error)
  if(NOT _dirty_remove_result EQUAL 0)
    message(FATAL_ERROR
      "could not remove dirty REDUCE source fixture:\n${_dirty_remove_error}")
  endif()
endif()
file(REMOVE_RECURSE "${_fixture_root}")
message(STATUS "pure-reduce source contract passed")
