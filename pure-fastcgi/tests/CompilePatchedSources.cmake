if(NOT DEFINED CMAKE_COMMAND OR "${CMAKE_COMMAND}" STREQUAL "")
  message(FATAL_ERROR "CMAKE_COMMAND is required")
endif()
if(NOT DEFINED BUILD_DIR OR "${BUILD_DIR}" STREQUAL "")
  message(FATAL_ERROR "BUILD_DIR is required")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" --build "${BUILD_DIR}" --clean-first
    --target fcgi2-static
  RESULT_VARIABLE build_result
  OUTPUT_VARIABLE build_output
  ERROR_VARIABLE build_error)
if(NOT build_result EQUAL 0)
  message(FATAL_ERROR "patched fcgi2 build failed: ${build_output}${build_error}")
endif()

set(build_log "${build_output}${build_error}")
if(build_log MATCHES
    "warning:.*(pointer-to-int-cast|int-to-pointer-cast|void-pointer-to-int-cast|int-to-void-pointer-cast|incompatible-pointer-types|incompatible-function-pointer-types)")
  message(FATAL_ERROR "patched fcgi2 has pointer-width warnings: ${build_log}")
endif()
