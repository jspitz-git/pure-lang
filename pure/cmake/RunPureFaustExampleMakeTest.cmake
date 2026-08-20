foreach(required
    PURE_MAKE_EXECUTABLE
    PURE_SH_EXECUTABLE
    PURE_MAKEFILE
    PURE_DSP_SOURCE
    PURE_FAUST_EXECUTABLE
    PURE_C_COMPILER
    PURE_LLVM_DIS_EXECUTABLE
    PURE_PATH_LIST_MODULE
    PURE_WORK_ROOT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "Missing Faust example Makefile argument ${required}")
  endif()
endforeach()

include("${PURE_PATH_LIST_MODULE}")
pure_prepend_path(posix_contract
  "/opt/Faust Tools/bin" "/usr/local/bin:/usr/bin:/bin" FALSE)
if(NOT posix_contract STREQUAL
    "/opt/Faust Tools/bin:/usr/local/bin:/usr/bin:/bin")
  message(FATAL_ERROR
    "POSIX Faust PATH construction used the wrong separator: "
    "[${posix_contract}]")
endif()

string(RANDOM LENGTH 12 ALPHABET 0123456789abcdef nonce)
set(work_dir "${PURE_WORK_ROOT}/Faust Make path ${nonce}")
set(makefile "${work_dir}/Makefile")
set(dsp "${work_dir}/reference.dsp")
set(bitcode "${work_dir}/reference.bc")
set(assembler "${work_dir}/reference.ll")
set(c_intermediate "${work_dir}/reference.faust.c")
file(MAKE_DIRECTORY "${work_dir}")
file(COPY_FILE "${PURE_MAKEFILE}" "${makefile}")
file(COPY_FILE "${PURE_DSP_SOURCE}" "${dsp}")

get_filename_component(faust_dir "${PURE_FAUST_EXECUTABLE}" DIRECTORY)
get_filename_component(faust_name "${PURE_FAUST_EXECUTABLE}" NAME)
pure_prepend_path(faust_search_path "${faust_dir}" "$ENV{PATH}" "${WIN32}")
execute_process(
  COMMAND
    "${CMAKE_COMMAND}" -E env
    "PATH=${faust_search_path}"
    "${PURE_MAKE_EXECUTABLE}" -f "${makefile}"
    "SHELL=${PURE_SH_EXECUTABLE}"
    "FAUST=${faust_name}" "CLANG=${PURE_C_COMPILER}" reference.bc
  WORKING_DIRECTORY "${work_dir}"
  RESULT_VARIABLE make_result
  OUTPUT_VARIABLE make_output
  ERROR_VARIABLE make_error
)

if(NOT make_result EQUAL 0)
  file(REMOVE_RECURSE "${work_dir}")
  message(FATAL_ERROR
    "Faust example Makefile failed with status ${make_result}\n"
    "stdout:\n${make_output}\nstderr:\n${make_error}")
endif()
if(NOT EXISTS "${bitcode}")
  file(REMOVE_RECURSE "${work_dir}")
  message(FATAL_ERROR
    "Faust example Makefile did not create reference.bc\n"
    "stdout:\n${make_output}\nstderr:\n${make_error}")
endif()

execute_process(
  COMMAND
    "${PURE_LLVM_DIS_EXECUTABLE}" "${bitcode}"
    -o "${work_dir}/reference.dis.ll"
  RESULT_VARIABLE dis_result
  OUTPUT_VARIABLE dis_output
  ERROR_VARIABLE dis_error
)
set(intermediate_exists FALSE)
if(EXISTS "${c_intermediate}")
  set(intermediate_exists TRUE)
endif()

# Run the same rule with the configured Faust executable supplied as a Make
# variable. Its installation path intentionally contains spaces on Windows.
file(REMOVE "${bitcode}")
execute_process(
  COMMAND
    "${PURE_MAKE_EXECUTABLE}" -f "${makefile}"
    "SHELL=${PURE_SH_EXECUTABLE}"
    "FAUST=${PURE_FAUST_EXECUTABLE}" "CLANG=${PURE_C_COMPILER}" reference.bc
  WORKING_DIRECTORY "${work_dir}"
  RESULT_VARIABLE configured_result
  OUTPUT_VARIABLE configured_output
  ERROR_VARIABLE configured_error
)
set(configured_bitcode_exists FALSE)
if(EXISTS "${bitcode}")
  set(configured_bitcode_exists TRUE)
endif()
set(configured_intermediate_exists FALSE)
if(EXISTS "${c_intermediate}")
  set(configured_intermediate_exists TRUE)
endif()
execute_process(
  COMMAND
    "${PURE_LLVM_DIS_EXECUTABLE}" "${bitcode}"
    -o "${work_dir}/reference.dis.ll"
  RESULT_VARIABLE configured_dis_result
  OUTPUT_VARIABLE configured_dis_output
  ERROR_VARIABLE configured_dis_error
)
execute_process(
  COMMAND
    "${PURE_MAKE_EXECUTABLE}" -f "${makefile}"
    "SHELL=${PURE_SH_EXECUTABLE}"
    "FAUST=${PURE_FAUST_EXECUTABLE}" "CLANG=${PURE_C_COMPILER}" reference.ll
  WORKING_DIRECTORY "${work_dir}"
  RESULT_VARIABLE assembler_result
  OUTPUT_VARIABLE assembler_output
  ERROR_VARIABLE assembler_error
)
set(assembler_exists FALSE)
if(EXISTS "${assembler}")
  set(assembler_exists TRUE)
endif()
set(assembler_intermediate_exists FALSE)
if(EXISTS "${c_intermediate}")
  set(assembler_intermediate_exists TRUE)
endif()
file(REMOVE_RECURSE "${work_dir}")

if(NOT dis_result EQUAL 0)
  message(FATAL_ERROR
    "Faust example rule did not produce configured-LLVM bitcode:\n${dis_error}")
endif()
if(intermediate_exists)
  message(FATAL_ERROR "Faust example rule left reference.faust.c")
endif()
if(NOT configured_result EQUAL 0 OR NOT configured_bitcode_exists)
  message(FATAL_ERROR
    "Faust example rule rejected configured path containing spaces\n"
    "stdout:\n${configured_output}\nstderr:\n${configured_error}")
endif()
if(configured_intermediate_exists)
  message(FATAL_ERROR
    "Configured-path Faust example rule left reference.faust.c")
endif()
if(NOT configured_dis_result EQUAL 0)
  message(FATAL_ERROR
    "Configured-path Faust example rule produced invalid bitcode:\n"
    "${configured_dis_error}")
endif()
if(NOT assembler_result EQUAL 0 OR NOT assembler_exists)
  message(FATAL_ERROR
    "Faust example Makefile did not preserve the reference.ll target\n"
    "stdout:\n${assembler_output}\nstderr:\n${assembler_error}")
endif()
if(assembler_intermediate_exists)
  message(FATAL_ERROR "Faust reference.ll rule left reference.faust.c")
endif()
