foreach(required IN ITEMS
    BUILD_ROOT TEST_ROOT PURE_EXECUTABLE PURE_PREFIX MODULE_DIR MODULE_DLL_DIR TEST_SCRIPT
    GNUPLOT_EXECUTABLE)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH BUILD_ROOT NORMALIZE OUTPUT_VARIABLE build_root)
cmake_path(ABSOLUTE_PATH TEST_ROOT NORMALIZE OUTPUT_VARIABLE test_root)
cmake_path(IS_PREFIX build_root "${test_root}" NORMALIZE test_is_in_build)
if(NOT test_is_in_build OR test_root STREQUAL build_root)
  message(FATAL_ERROR "TEST_ROOT must be a child of BUILD_ROOT")
endif()
if(NOT EXISTS "${GNUPLOT_EXECUTABLE}")
  message(FATAL_ERROR
    "Controlled gnuplot executable is missing: ${GNUPLOT_EXECUTABLE}")
endif()

file(REMOVE_RECURSE "${test_root}")
file(MAKE_DIRECTORY "${test_root}")
set(output_file "${test_root}/known plot.png")
unset(ENV{PURELIB})
set(ENV{GPLOT_EXE} "${GNUPLOT_EXECUTABLE}")
set(ENV{PATH} "${MODULE_DLL_DIR};${PURE_PREFIX}/bin;C:/Windows/System32;C:/Windows")

execute_process(
  COMMAND "${PURE_EXECUTABLE}" --norc -q
    -I "${MODULE_DIR}"
    -L "${MODULE_DLL_DIR}"
    -x "${TEST_SCRIPT}"
    "${output_file}"
  WORKING_DIRECTORY "${test_root}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
  TIMEOUT 20
  ENCODING UTF-8)
if(NOT "${result}" STREQUAL "0")
  message(FATAL_ERROR
    "pure-gplot render test failed (${result})\n"
    "stdout:\n${output}\nstderr:\n${error}")
endif()
if(NOT output MATCHES "(^|\r?\n)PURE_GPLOT_RENDER_OK(\r?\n|$)")
  message(FATAL_ERROR
    "pure-gplot render test did not emit its success marker\n"
    "stdout:\n${output}\nstderr:\n${error}")
endif()
if(NOT EXISTS "${output_file}")
  message(FATAL_ERROR "gnuplot did not create ${output_file}")
endif()
file(SIZE "${output_file}" output_size)
if(output_size LESS 1024)
  message(FATAL_ERROR "PNG payload is too small: ${output_size} bytes")
endif()
file(READ "${output_file}" png_hex HEX LIMIT 24)
string(TOLOWER "${png_hex}" png_hex)
string(SUBSTRING "${png_hex}" 0 16 signature)
string(SUBSTRING "${png_hex}" 32 8 width)
string(SUBSTRING "${png_hex}" 40 8 height)
if(NOT signature STREQUAL "89504e470d0a1a0a")
  message(FATAL_ERROR "Invalid PNG signature: ${signature}")
endif()
if(NOT width STREQUAL "00000140" OR NOT height STREQUAL "000000c8")
  message(FATAL_ERROR
    "Unexpected PNG dimensions: width=${width}, height=${height}")
endif()

file(REMOVE_RECURSE "${test_root}")
