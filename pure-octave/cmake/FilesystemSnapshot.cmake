function(pure_octave_filesystem_snapshot root allowed_root output)
  if (NOT IS_DIRECTORY "${root}")
    message(FATAL_ERROR "Write audit root is not a directory: ${root}")
  endif ()
  file(REAL_PATH "${root}" normalized_root EXPAND_TILDE)

  set(normalized_allowed "")
  if (NOT "${allowed_root}" STREQUAL "")
    if (EXISTS "${allowed_root}")
      file(REAL_PATH "${allowed_root}" normalized_allowed EXPAND_TILDE)
    else ()
      cmake_path(ABSOLUTE_PATH allowed_root
        BASE_DIRECTORY "${normalized_root}" NORMALIZE
        OUTPUT_VARIABLE normalized_allowed)
    endif ()
    set(root_path "${normalized_root}")
    cmake_path(IS_PREFIX root_path "${normalized_allowed}" NORMALIZE
      allowed_below_root)
    if (NOT allowed_below_root)
      message(FATAL_ERROR
        "Allowed write root is outside the audited filesystem: "
        "${normalized_allowed}")
    endif ()
  endif ()

  file(GLOB_RECURSE audit_entries
    LIST_DIRECTORIES TRUE RELATIVE "${normalized_root}"
    "${normalized_root}/*")
  list(SORT audit_entries)
  set(snapshot_records)
  foreach (relative_entry IN LISTS audit_entries)
    if (relative_entry MATCHES "[;\r\n]")
      message(FATAL_ERROR
        "Write audit cannot serialize path: ${relative_entry}")
    endif ()
    set(absolute_entry "${normalized_root}/${relative_entry}")
    if (NOT "${normalized_allowed}" STREQUAL "")
      set(allowed_path "${normalized_allowed}")
      cmake_path(IS_PREFIX allowed_path "${absolute_entry}" NORMALIZE
        entry_is_allowed)
      if (entry_is_allowed)
        continue ()
      endif ()
    endif ()
    if (IS_SYMLINK "${absolute_entry}")
      message(FATAL_ERROR
        "Write audit rejects reparse/symbolic entry: ${absolute_entry}")
    endif ()
    if (IS_DIRECTORY "${absolute_entry}")
      list(APPEND snapshot_records "D  ${relative_entry}")
    elseif (EXISTS "${absolute_entry}")
      file(SHA256 "${absolute_entry}" entry_hash)
      list(APPEND snapshot_records "F  ${entry_hash}  ${relative_entry}")
    else ()
      message(FATAL_ERROR
        "Write audit entry disappeared during snapshot: ${absolute_entry}")
    endif ()
  endforeach ()

  if (snapshot_records)
    string(JOIN "\n" snapshot_text ${snapshot_records})
  else ()
    set(snapshot_text "")
  endif ()
  set(${output} "${snapshot_text}" PARENT_SCOPE)
endfunction ()
