include_guard(GLOBAL)

set(_PURE_REDUCE_WINDOWS_SYSTEM_DLLS
  advapi32.dll
  api-ms-win-crt-convert-l1-1-0.dll
  api-ms-win-crt-environment-l1-1-0.dll
  api-ms-win-crt-filesystem-l1-1-0.dll
  api-ms-win-crt-heap-l1-1-0.dll
  api-ms-win-crt-locale-l1-1-0.dll
  api-ms-win-crt-math-l1-1-0.dll
  api-ms-win-crt-multibyte-l1-1-0.dll
  api-ms-win-crt-private-l1-1-0.dll
  api-ms-win-crt-runtime-l1-1-0.dll
  api-ms-win-crt-stdio-l1-1-0.dll
  api-ms-win-crt-string-l1-1-0.dll
  api-ms-win-crt-time-l1-1-0.dll
  api-ms-win-crt-utility-l1-1-0.dll
  bcrypt.dll
  comctl32.dll
  comdlg32.dll
  crypt32.dll
  gdi32.dll
  imm32.dll
  kernel32.dll
  mpr.dll
  msvcrt.dll
  ntdll.dll
  ole32.dll
  oleaut32.dll
  rpcrt4.dll
  secur32.dll
  setupapi.dll
  shell32.dll
  shlwapi.dll
  ucrtbase.dll
  user32.dll
  uuid.dll
  version.dll
  winmm.dll
  winspool.drv
  ws2_32.dll
  wsock32.dll)

function(_pure_reduce_audit_canonical_file INPUT OUTPUT)
  if(NOT IS_ABSOLUTE "${INPUT}" OR NOT EXISTS "${INPUT}" OR
      IS_DIRECTORY "${INPUT}")
    message(FATAL_ERROR
      "PE audit input must be an existing absolute file: ${INPUT}")
  endif()
  file(REAL_PATH "${INPUT}" _canonical)
  cmake_path(GET _canonical FILENAME _basename)
  string(TOLOWER "${_basename}" _basename_lower)
  if(_basename_lower MATCHES
      "^(bash|sh|dash|zsh|fish|cmd|powershell|pwsh|make|ninja|pacman)(\\.exe)?$" OR
      _basename_lower MATCHES "\\.(a|lib|o|obj|exe)$" OR
      NOT _basename_lower MATCHES "\\.dll$")
    message(FATAL_ERROR "forbidden PE audit payload: ${_canonical}")
  endif()
  set(${OUTPUT} "${_canonical}" PARENT_SCOPE)
endfunction()

function(_pure_reduce_audit_imports MODULE OUTPUT)
  if(NOT DEFINED PURE_REDUCE_LLVM_READOBJ OR
      "${PURE_REDUCE_LLVM_READOBJ}" STREQUAL "" OR
      NOT IS_ABSOLUTE "${PURE_REDUCE_LLVM_READOBJ}" OR
      NOT EXISTS "${PURE_REDUCE_LLVM_READOBJ}")
    message(FATAL_ERROR
      "PURE_REDUCE_LLVM_READOBJ must be an existing absolute executable")
  endif()
  execute_process(
    COMMAND "${PURE_REDUCE_LLVM_READOBJ}" --coff-imports "${MODULE}"
    RESULT_VARIABLE _result
    OUTPUT_VARIABLE _output
    ERROR_VARIABLE _error
    ENCODING UTF-8)
  if(NOT _result EQUAL 0)
    message(FATAL_ERROR
      "unable to inspect PE imports for ${MODULE} (${_result})\n"
      "stdout:\n${_output}\nstderr:\n${_error}")
  endif()
  string(REGEX MATCHALL "Name: [^\r\n]+" _name_lines "${_output}")
  set(_imports)
  foreach(_line IN LISTS _name_lines)
    string(REGEX REPLACE "^Name: " "" _name "${_line}")
    string(STRIP "${_name}" _name)
    string(TOLOWER "${_name}" _name_lower)
    list(APPEND _imports "${_name_lower}")
  endforeach()
  list(REMOVE_DUPLICATES _imports)
  list(SORT _imports COMPARE NATURAL CASE INSENSITIVE)
  set(${OUTPUT} "${_imports}" PARENT_SCOPE)
endfunction()

function(pure_reduce_audit_pe ROOT_FILES SEARCH_DIRS OUT_FILES)
  if("${ROOT_FILES}" STREQUAL "")
    message(FATAL_ERROR "PE audit requires at least one root file")
  endif()

  set(_search_candidates)
  foreach(_search_dir IN LISTS SEARCH_DIRS)
    if(NOT IS_ABSOLUTE "${_search_dir}" OR NOT IS_DIRECTORY "${_search_dir}")
      message(FATAL_ERROR
        "PE audit search directory must be existing and absolute: ${_search_dir}")
    endif()
    file(REAL_PATH "${_search_dir}" _canonical_search_dir)
    file(GLOB_RECURSE _directory_candidates LIST_DIRECTORIES FALSE
      "${_canonical_search_dir}/*.dll")
    list(APPEND _search_candidates ${_directory_candidates})
  endforeach()

  set(_candidate_records)
  foreach(_candidate IN LISTS _search_candidates)
    _pure_reduce_audit_canonical_file("${_candidate}" _canonical_candidate)
    cmake_path(GET _canonical_candidate FILENAME _candidate_name)
    string(TOLOWER "${_candidate_name}" _candidate_name_lower)
    list(APPEND _candidate_records
      "${_candidate_name_lower}|${_canonical_candidate}")
  endforeach()
  list(REMOVE_DUPLICATES _candidate_records)

  set(_queue)
  set(_parents)
  foreach(_root IN LISTS ROOT_FILES)
    _pure_reduce_audit_canonical_file("${_root}" _canonical_root)
    list(APPEND _queue "${_canonical_root}")
    list(APPEND _parents "${_canonical_root}|<ROOT>")
  endforeach()

  set(_closure)
  set(_seen_lower)
  while(_queue)
    list(POP_FRONT _queue _module)
    string(TOLOWER "${_module}" _module_lower)
    if(_module_lower IN_LIST _seen_lower)
      continue()
    endif()
    list(APPEND _seen_lower "${_module_lower}")
    list(APPEND _closure "${_module}")
    _pure_reduce_audit_imports("${_module}" _imports)
    foreach(_import IN LISTS _imports)
      if(_import STREQUAL "msys-2.0.dll" OR
          _import STREQUAL "cygwin1.dll")
        message(FATAL_ERROR
          "forbidden MSYS/Cygwin PE import ${_import} in ${_module}")
      endif()
      if(_import IN_LIST _PURE_REDUCE_WINDOWS_SYSTEM_DLLS)
        continue()
      endif()
      if(_import MATCHES "[/\\\\]" OR NOT _import MATCHES "\\.dll$")
        message(FATAL_ERROR
          "forbidden non-DLL PE import ${_import} in ${_module}")
      endif()

      set(_matches)
      foreach(_record IN LISTS _candidate_records)
        string(FIND "${_record}" "|" _separator)
        string(SUBSTRING "${_record}" 0 ${_separator} _record_name)
        if(_record_name STREQUAL _import)
          math(EXPR _path_start "${_separator} + 1")
          string(SUBSTRING "${_record}" ${_path_start} -1 _match)
          list(APPEND _matches "${_match}")
        endif()
      endforeach()
      list(REMOVE_DUPLICATES _matches)
      list(LENGTH _matches _match_count)
      if(_match_count EQUAL 0)
        message(FATAL_ERROR
          "unresolved PE import ${_import} in ${_module}; searched only: "
          "${SEARCH_DIRS}")
      elseif(_match_count GREATER 1)
        message(FATAL_ERROR
          "ambiguous PE import ${_import} in ${_module}: ${_matches}")
      endif()
      list(GET _matches 0 _resolved)
      list(APPEND _queue "${_resolved}")
      list(APPEND _parents "${_resolved}|${_module}")
    endforeach()
  endwhile()

  list(REMOVE_DUPLICATES _closure)
  list(SORT _closure COMPARE NATURAL CASE INSENSITIVE)
  list(REMOVE_DUPLICATES _parents)
  list(SORT _parents COMPARE NATURAL CASE INSENSITIVE)
  set(${OUT_FILES} "${_closure}" PARENT_SCOPE)
  set(PURE_REDUCE_AUDIT_PARENT_RECORDS "${_parents}" PARENT_SCOPE)
endfunction()
