foreach(required IN ITEMS
    INPUT_PATH OUTPUT_PATH FAUST_EXECUTABLE PURE_ARCHITECTURE
    CLANG_EXECUTABLE OPT_EXECUTABLE)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

foreach(required_file IN ITEMS
    "${INPUT_PATH}" "${FAUST_EXECUTABLE}" "${PURE_ARCHITECTURE}"
    "${CLANG_EXECUTABLE}" "${OPT_EXECUTABLE}")
  if(NOT EXISTS "${required_file}" OR IS_DIRECTORY "${required_file}")
    message(FATAL_ERROR "Required Faust helper file is missing: ${required_file}")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH INPUT_PATH NORMALIZE OUTPUT_VARIABLE input_path)
cmake_path(ABSOLUTE_PATH OUTPUT_PATH NORMALIZE OUTPUT_VARIABLE output_path)
if(input_path STREQUAL output_path)
  message(FATAL_ERROR "InputPath and OutputPath must not name the same file")
endif()
if(IS_DIRECTORY "${output_path}")
  message(FATAL_ERROR "OutputPath must name a file, not a directory: ${output_path}")
endif()
cmake_path(GET output_path PARENT_PATH output_directory)
if(NOT IS_DIRECTORY "${output_directory}")
  message(FATAL_ERROR "Output directory does not exist: ${output_directory}")
endif()

string(RANDOM LENGTH 16 ALPHABET 0123456789abcdef work_suffix)
set(work_directory "${output_directory}/.faust2pure-${work_suffix}")
while(EXISTS "${work_directory}")
  string(RANDOM LENGTH 16 ALPHABET 0123456789abcdef work_suffix)
  set(work_directory "${output_directory}/.faust2pure-${work_suffix}")
endwhile()
file(MAKE_DIRECTORY "${work_directory}")

function(run_stage stage)
  execute_process(
    COMMAND ${ARGN}
    RESULT_VARIABLE stage_result
    OUTPUT_VARIABLE stage_output
    ERROR_VARIABLE stage_error
    ENCODING UTF-8)
  if(NOT stage_result EQUAL 0)
    file(REMOVE_RECURSE "${work_directory}")
    message(FATAL_ERROR
      "${stage} stage failed (${stage_result})\n"
      "stdout:\n${stage_output}\nstderr:\n${stage_error}")
  endif()
endfunction()

set(reference_c "${work_directory}/reference.c")
set(reference_bc "${work_directory}/reference.bc")
set(new_output "${output_path}.new")

run_stage(faust
  "${FAUST_EXECUTABLE}" -lang c -a "${PURE_ARCHITECTURE}" "${input_path}"
  -o "${reference_c}")
run_stage(clang
  "${CLANG_EXECUTABLE}" -emit-llvm -O3 -c "${reference_c}" -o "${reference_bc}")
run_stage(verify
  "${OPT_EXECUTABLE}" "-passes=verify" -disable-output "${reference_bc}")
file(REMOVE "${new_output}")
run_stage(publish
  "${CMAKE_COMMAND}" -E copy_if_different "${reference_bc}" "${new_output}")
run_stage(publish
  "${CMAKE_COMMAND}" -E rename "${new_output}" "${output_path}")

file(REMOVE_RECURSE "${work_directory}")
