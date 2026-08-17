foreach(_required IN ITEMS
    CMAKE_COMMAND REDUCE_DLL REDUCE_IMAGE PURE_MODULE
    PURE_EXECUTABLE PURE_LIBRARY_DIR
    PURE_SOURCE_DIR TEST_DRIVER TEST_SCRIPT STAGE_ROOT EXPECTED_MARKER)
  if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
    message(FATAL_ERROR "${_required} is required")
  endif()
endforeach()

file(READ "${PURE_MODULE}" _pure_module)
if(_pure_module MATCHES "GetShortPathNameW")
  message(FATAL_ERROR
    "production Pure module still calls forbidden GetShortPathNameW")
endif()

set(_module_dir "${STAGE_ROOT}/relocated 日本語 no aliases")
file(REMOVE_RECURSE "${_module_dir}")
file(MAKE_DIRECTORY "${_module_dir}")
file(COPY_FILE "${REDUCE_DLL}" "${_module_dir}/reduce.dll" ONLY_IF_DIFFERENT)
file(COPY_FILE "${REDUCE_IMAGE}" "${_module_dir}/reduce.img" ONLY_IF_DIFFERENT)

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
    "-DPURE_LIBRARY_DIR=${PURE_LIBRARY_DIR}"
    "-DPURE_SOURCE_DIR=${PURE_SOURCE_DIR}"
    "-DMODULE_DIR=${_module_dir}"
    "-DTEST_SCRIPT=${TEST_SCRIPT}"
    "-DEXPECTED_MARKER=${EXPECTED_MARKER}"
    -P "${TEST_DRIVER}"
  RESULT_VARIABLE _result
  OUTPUT_VARIABLE _output
  ERROR_VARIABLE _error
  ENCODING UTF-8)

if(NOT _result EQUAL 0)
  message(FATAL_ERROR
    "Unicode relocation test exited with ${_result}\n"
    "stdout:\n${_output}\nstderr:\n${_error}")
endif()
