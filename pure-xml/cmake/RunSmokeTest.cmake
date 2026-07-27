foreach(required IN ITEMS PURE_EXECUTABLE PURE_SOURCE_DIR MODULE_DIR TEST_SCRIPT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

set(test_root "${MODULE_DIR}/pure xml smoke with spaces")
file(REMOVE_RECURSE "${test_root}")
file(MAKE_DIRECTORY "${test_root}")
file(COPY_FILE
  "${PURE_SOURCE_DIR}/tests/input-utf8.xml"
  "${test_root}/vstup s mezerou.xml"
)
file(COPY_FILE
  "${PURE_SOURCE_DIR}/tests/transform.xsl"
  "${test_root}/styl s mezerou.xsl"
)

set(ENV{PATH} "${MODULE_DIR};$ENV{PATH}")
set(ENV{http_proxy} "http://127.0.0.1:9")
set(ENV{https_proxy} "http://127.0.0.1:9")
set(ENV{no_proxy} "")
set(ENV{XML_CATALOG_FILES} "")

execute_process(
  COMMAND "${PURE_EXECUTABLE}" --norc
    -I "${PURE_SOURCE_DIR}"
    -L "${MODULE_DIR}"
    -x "${TEST_SCRIPT}" "${test_root}"
  WORKING_DIRECTORY "${test_root}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
  ENCODING UTF-8
)

if(NOT result EQUAL 0)
  message(FATAL_ERROR
    "pure-xml smoke test failed (${result})\nstdout:\n${output}\nstderr:\n${error}")
endif()
if(NOT output MATCHES "PURE_XML_SMOKE_OK")
  message(FATAL_ERROR
    "pure-xml smoke marker missing\nstdout:\n${output}\nstderr:\n${error}")
endif()
message(STATUS "${output}")
