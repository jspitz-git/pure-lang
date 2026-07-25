cmake_minimum_required(VERSION 3.25)

if(POLICY CMP0207)
  cmake_policy(SET CMP0207 NEW)
endif()

if(NOT DEFINED PURE_PREFIX OR PURE_PREFIX STREQUAL "")
  message(FATAL_ERROR "Set PURE_PREFIX to the staged Windows installation")
endif()

cmake_path(ABSOLUTE_PATH PURE_PREFIX NORMALIZE OUTPUT_VARIABLE prefix)
set(bin_dir "${prefix}/bin")
set(pure_executable "${bin_dir}/pure.exe")
set(pure_runtime "${bin_dir}/libpure.dll")
foreach(required_file IN ITEMS "${pure_executable}" "${pure_runtime}")
  if(NOT EXISTS "${required_file}")
    message(FATAL_ERROR "Missing staged runtime file: ${required_file}")
  endif()
endforeach()

file(GLOB staged_dlls LIST_DIRECTORIES FALSE "${bin_dir}/*.dll")
file(
  GET_RUNTIME_DEPENDENCIES
  EXECUTABLES "${pure_executable}"
  LIBRARIES ${staged_dlls}
  DIRECTORIES "${bin_dir}"
  RESOLVED_DEPENDENCIES_VAR resolved_dependencies
  UNRESOLVED_DEPENDENCIES_VAR unresolved_dependencies
  CONFLICTING_DEPENDENCIES_PREFIX conflicting_dependencies
  PRE_EXCLUDE_REGEXES "^api-ms-win-.*" "^ext-ms-win-.*"
  POST_EXCLUDE_REGEXES
    "^[A-Za-z]:[/\\\\][Ww][Ii][Nn][Dd][Oo][Ww][Ss][/\\\\]([Ss][Yy][Ss][Tt][Ee][Mm]32|[Ss][Yy][Ss][Ww][Oo][Ww]64)[/\\\\].*"
)

if(unresolved_dependencies)
  list(JOIN unresolved_dependencies ", " unresolved_text)
  message(FATAL_ERROR "Unresolved staged runtime dependencies: ${unresolved_text}")
endif()
if(conflicting_dependencies_FILENAMES)
  list(JOIN conflicting_dependencies_FILENAMES ", " conflicts_text)
  message(FATAL_ERROR "Conflicting staged runtime dependencies: ${conflicts_text}")
endif()

list(SORT resolved_dependencies)
foreach(dependency IN LISTS resolved_dependencies)
  cmake_path(GET dependency FILENAME dependency_name)
  string(TOLOWER "${dependency_name}" dependency_name_lower)
  if(dependency_name_lower STREQUAL "msys-2.0.dll")
    message(FATAL_ERROR "Forbidden MSYS runtime dependency: ${dependency}")
  endif()
  cmake_path(IS_PREFIX prefix "${dependency}" NORMALIZE dependency_is_staged)
  if(NOT dependency_is_staged)
    message(FATAL_ERROR "Non-system dependency resolved outside the stage: ${dependency}")
  endif()
endforeach()

find_program(
  strings_executable
  NAMES llvm-strings strings
  HINTS "${PURE_TOOL_DIR}"
  REQUIRED
)
set(forbidden_paths "C:/msys64" "C:\\msys64")
if(DEFINED PURE_FORBIDDEN_PATHS)
  list(APPEND forbidden_paths ${PURE_FORBIDDEN_PATHS})
endif()

file(GLOB_RECURSE staged_files LIST_DIRECTORIES FALSE "${prefix}/*")
foreach(staged_file IN LISTS staged_files)
  execute_process(
    COMMAND "${strings_executable}" "${staged_file}"
    RESULT_VARIABLE strings_status
    OUTPUT_VARIABLE printable_strings
    ERROR_VARIABLE strings_error
  )
  if(NOT strings_status EQUAL 0)
    message(FATAL_ERROR "String scan failed for ${staged_file}: ${strings_error}")
  endif()
  foreach(forbidden_path IN LISTS forbidden_paths)
    if(NOT forbidden_path STREQUAL "")
      string(FIND "${printable_strings}" "${forbidden_path}" forbidden_position)
      if(NOT forbidden_position EQUAL -1)
        message(FATAL_ERROR "Forbidden path '${forbidden_path}' in ${staged_file}")
      endif()
    endif()
  endforeach()
endforeach()

list(LENGTH staged_dlls staged_dll_count)
list(LENGTH resolved_dependencies resolved_dependency_count)
list(LENGTH staged_files staged_file_count)
message(
  STATUS
  "Portable Windows audit passed: ${staged_dll_count} DLLs, "
  "${resolved_dependency_count} non-system dependency paths, "
  "${staged_file_count} staged files"
)
