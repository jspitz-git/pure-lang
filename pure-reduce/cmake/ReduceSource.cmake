include_guard(GLOBAL)

# This is deliberately a normal variable, not a cache entry: command-line
# overrides must not change the immutable source identity used by this build.
set(PURE_REDUCE_UPSTREAM_COMMIT
  "7efba90661139ae9c73c99fddd55f3fb2fabf69a")

function(pure_reduce_verify_source ROOT OUT_COMMIT OUT_TREE_SHA256)
  set(_pure_reduce_required_commit
    "7efba90661139ae9c73c99fddd55f3fb2fabf69a")

  if(NOT IS_DIRECTORY "${ROOT}")
    message(FATAL_ERROR "REDUCE source directory does not exist: ${ROOT}")
  endif()

  get_filename_component(_pure_reduce_root "${ROOT}" ABSOLUTE)

  execute_process(
    COMMAND git -C "${_pure_reduce_root}" rev-parse --show-toplevel
    RESULT_VARIABLE _pure_reduce_checkout_result
    OUTPUT_VARIABLE _pure_reduce_checkout_root
    ERROR_VARIABLE _pure_reduce_checkout_error
    OUTPUT_STRIP_TRAILING_WHITESPACE)
  if(NOT _pure_reduce_checkout_result EQUAL 0)
    message(FATAL_ERROR
      "REDUCE source directory is not a Git checkout: ${_pure_reduce_root}\n"
      "${_pure_reduce_checkout_error}")
  endif()
  file(REAL_PATH "${_pure_reduce_root}" _pure_reduce_real_root)
  file(REAL_PATH "${_pure_reduce_checkout_root}" _pure_reduce_real_checkout_root)
  if(NOT _pure_reduce_real_root STREQUAL _pure_reduce_real_checkout_root)
    message(FATAL_ERROR
      "REDUCE source directory is not a Git checkout: ${_pure_reduce_root}")
  endif()

  execute_process(
    COMMAND git -C "${_pure_reduce_root}" rev-parse HEAD
    RESULT_VARIABLE _pure_reduce_revision_result
    OUTPUT_VARIABLE _pure_reduce_revision
    ERROR_VARIABLE _pure_reduce_revision_error
    OUTPUT_STRIP_TRAILING_WHITESPACE)
  if(NOT _pure_reduce_revision_result EQUAL 0)
    message(FATAL_ERROR
      "could not determine REDUCE source commit: ${_pure_reduce_root}\n"
      "${_pure_reduce_revision_error}")
  endif()

  execute_process(
    COMMAND git -C "${_pure_reduce_root}" status --porcelain --untracked-files=no
    RESULT_VARIABLE _pure_reduce_status_result
    OUTPUT_VARIABLE _pure_reduce_status
    ERROR_VARIABLE _pure_reduce_status_error)
  if(NOT _pure_reduce_status_result EQUAL 0)
    message(FATAL_ERROR
      "could not inspect REDUCE source tree: ${_pure_reduce_root}\n"
      "${_pure_reduce_status_error}")
  endif()
  if(NOT _pure_reduce_status STREQUAL "")
    message(FATAL_ERROR "REDUCE source tree is dirty: ${_pure_reduce_root}")
  endif()

  if(NOT _pure_reduce_revision STREQUAL _pure_reduce_required_commit)
    message(FATAL_ERROR
      "REDUCE source commit does not match the required pin: ${_pure_reduce_revision}\n"
      "required: ${_pure_reduce_required_commit}")
  endif()

  # git ls-files is emitted in Git's pathname order. Hashing the complete
  # record stream preserves modes, object IDs and paths without a network step.
  execute_process(
    COMMAND git -C "${_pure_reduce_root}" ls-files -s
    RESULT_VARIABLE _pure_reduce_files_result
    OUTPUT_VARIABLE _pure_reduce_file_records
    ERROR_VARIABLE _pure_reduce_files_error)
  if(NOT _pure_reduce_files_result EQUAL 0)
    message(FATAL_ERROR
      "could not list REDUCE source files: ${_pure_reduce_root}\n"
      "${_pure_reduce_files_error}")
  endif()
  string(SHA256 _pure_reduce_tree_sha256 "${_pure_reduce_file_records}")

  set(${OUT_COMMIT} "${_pure_reduce_revision}" PARENT_SCOPE)
  set(${OUT_TREE_SHA256} "${_pure_reduce_tree_sha256}" PARENT_SCOPE)
endfunction()
