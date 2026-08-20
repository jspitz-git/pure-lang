if(NOT DEFINED PURE_REPOSITORY_ROOT)
  message(FATAL_ERROR "Missing Pure repository root")
endif()

file(REAL_PATH "${PURE_REPOSITORY_ROOT}" repository_root)
file(REAL_PATH "${CMAKE_CURRENT_LIST_FILE}" contract_file)
file(TO_CMAKE_PATH "${contract_file}" contract_file)
execute_process(
  COMMAND git -C "${repository_root}" ls-files --cached
  RESULT_VARIABLE git_result
  OUTPUT_VARIABLE tracked_output
  ERROR_VARIABLE git_error
)
if(NOT git_result EQUAL 0)
  string(STRIP "${git_error}" git_error)
  message(FATAL_ERROR
    "Unable to enumerate tracked repository files with git ls-files: ${git_error}")
endif()
string(REPLACE "\r\n" "\n" tracked_output "${tracked_output}")
string(REPLACE ";" "\\;" tracked_output "${tracked_output}")
string(REPLACE "\n" ";" tracked_files "${tracked_output}")
set(violations)
foreach(relative IN LISTS tracked_files)
  if(relative STREQUAL "")
    continue()
  endif()
  set(candidate "${repository_root}/${relative}")
  file(REAL_PATH "${candidate}" normalized)
  file(TO_CMAKE_PATH "${normalized}" normalized)
  if(normalized MATCHES "/(build|\\.git|\\.superpowers)/" OR
     normalized STREQUAL "${contract_file}")
    continue()
  endif()
  get_filename_component(name "${candidate}" NAME)
  get_filename_component(extension "${candidate}" EXT)
  if(NOT name MATCHES "^Makefile" AND
     NOT extension MATCHES "^\\.(mk|cmake|sh|bash|ps1|bat)$" AND
     NOT name STREQUAL "faust2pure")
    continue()
  endif()
  file(READ "${candidate}" content)
  string(REPLACE "\r\n" "\n" content "${content}")
  string(TOLOWER "${content}" lower)
  if(lower MATCHES "(^|\n)[ \t]*[^#\n]*faust[^\n]*-lang[ \t]+llvm" OR
     lower MATCHES "(^|\n)[ \t]*[^#\n]*faust2llvm")
    list(APPEND violations
      "${normalized}: invokes Faust's unsupported direct LLVM backend")
  endif()
  if(content MATCHES "%\\.bc:[ \t]*%\\.dsp")
    if(NOT lower MATCHES "pure\\.c" OR NOT lower MATCHES "clang" OR
       NOT lower MATCHES "trap" OR NOT content MATCHES "\\.faust\\.\\$\\$\\$\\$\\.c")
      list(APPEND violations
        "${normalized}: Faust bitcode rule lacks pure.c, matching Clang, or unique trapped temporary C ownership")
    endif()
  endif()
  string(FIND "${content}" "cfile='$@.faust.$$$$.c'"
    single_quoted_pid_position)
  if(NOT single_quoted_pid_position EQUAL -1)
    list(APPEND violations
      "${normalized}: single quotes prevent the shell from expanding the per-invocation PID in the Faust temporary C name")
  endif()
endforeach()

if(violations)
  list(JOIN violations "\n  " detail)
  message(FATAL_ERROR "Direct Faust LLVM pipeline contract failed:\n  ${detail}")
endif()
message("Repository-wide Faust pipeline contract passed")
