cmake_minimum_required(VERSION 3.25)

foreach(_required IN ITEMS BUILD_DIR STAGE_PREFIX)
  if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
    message(FATAL_ERROR "${_required} is required")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH BUILD_DIR NORMALIZE OUTPUT_VARIABLE _build_dir)
cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE _stage)
cmake_path(IS_PREFIX _build_dir "${_stage}" NORMALIZE _stage_is_owned)
if(NOT _stage_is_owned OR _stage STREQUAL _build_dir)
  message(FATAL_ERROR
    "package oracle generation stage must be a child of BUILD_DIR: ${_stage}")
endif()

file(REMOVE_RECURSE "${_stage}")
execute_process(
  COMMAND "${CMAKE_COMMAND}" --install "${_build_dir}"
    --prefix "${_stage}" --component PureReduce
  RESULT_VARIABLE _install_result
  OUTPUT_VARIABLE _install_output
  ERROR_VARIABLE _install_error
  ENCODING UTF-8)
file(REMOVE_RECURSE "${_stage}")
if(NOT _install_result EQUAL 0)
  message(FATAL_ERROR
    "package oracle generation install failed (${_install_result})\n"
    "stdout:\n${_install_output}\nstderr:\n${_install_error}")
endif()
message("${_install_output}")
