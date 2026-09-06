foreach(required IN ITEMS PURE_EXECUTABLE PACKAGE_DIR MODULE_DIR RUNTIME_BIN_DIR
    TEST_SCRIPT TEST_DATA_DIR)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

set(test_root "${MODULE_DIR}/pure xml smoke with spaces")
file(REMOVE_RECURSE "${test_root}")
file(MAKE_DIRECTORY "${test_root}")
file(COPY_FILE
  "${TEST_DATA_DIR}/input-utf8.xml"
  "${test_root}/vstup s mezerou.xml"
)
file(COPY_FILE
  "${TEST_DATA_DIR}/transform.xsl"
  "${test_root}/styl s mezerou.xsl"
)

get_filename_component(pure_bin_dir "${PURE_EXECUTABLE}" DIRECTORY)
get_filename_component(pure_runtime_prefix "${pure_bin_dir}" DIRECTORY)
if(NOT EXISTS "${pure_runtime_prefix}/lib/pure/math.pure")
  message(FATAL_ERROR
    "PURE_EXECUTABLE must belong to an installed Pure runtime prefix")
endif()
foreach(runtime IN ITEMS
    libxml2-16.dll libxslt-1.dll libiconv-2.dll zlib1.dll)
  if(NOT EXISTS "${RUNTIME_BIN_DIR}/${runtime}")
    message(FATAL_ERROR "Missing runtime dependency: ${RUNTIME_BIN_DIR}/${runtime}")
  endif()
endforeach()
unset(ENV{PURELIB})
if(WIN32)
  string(CONCAT smoke_path
    "${MODULE_DIR};${RUNTIME_BIN_DIR};${pure_bin_dir};"
    "$ENV{SystemRoot}/System32;$ENV{SystemRoot}")
  set(ENV{PATH} "${smoke_path}")
else()
  set(ENV{PATH} "${MODULE_DIR}:${RUNTIME_BIN_DIR}:${pure_bin_dir}:$ENV{PATH}")
endif()
set(ENV{http_proxy} "http://127.0.0.1:9")
set(ENV{https_proxy} "http://127.0.0.1:9")
set(ENV{no_proxy} "")
set(ENV{XML_CATALOG_FILES} "")

if(NOT DEFINED RUN_WORKING_DIRECTORY OR RUN_WORKING_DIRECTORY STREQUAL "")
  set(RUN_WORKING_DIRECTORY "${test_root}")
endif()
if(NOT IS_DIRECTORY "${RUN_WORKING_DIRECTORY}")
  message(FATAL_ERROR
    "RUN_WORKING_DIRECTORY must name an existing directory")
endif()

execute_process(
  COMMAND "${PURE_EXECUTABLE}" --norc
    -I "${PACKAGE_DIR}"
    -L "${MODULE_DIR}"
    -x "${TEST_SCRIPT}" "${test_root}"
  WORKING_DIRECTORY "${RUN_WORKING_DIRECTORY}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
  ENCODING UTF-8
)

if(NOT result EQUAL 0)
  message(FATAL_ERROR
    "pure-xml smoke test failed (${result})\nstdout:\n${output}\nstderr:\n${error}")
endif()
if(NOT error STREQUAL "")
  message(FATAL_ERROR
    "pure-xml smoke emitted stderr\nstdout:\n${output}\nstderr:\n${error}")
endif()
if(NOT output MATCHES "(^|\r?\n)PURE_XML_SMOKE_OK(\r?\n|$)")
  message(FATAL_ERROR
    "pure-xml smoke marker missing\nstdout:\n${output}\nstderr:\n${error}")
endif()
message(STATUS "${output}")
