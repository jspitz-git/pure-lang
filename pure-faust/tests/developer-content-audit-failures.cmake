foreach(required IN ITEMS SOURCE_DIR TEST_ROOT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

set(mutations
  "source=C:/repo/source"
  "build=C:/repo/build"
  "faust=C:/Program Files/Faust"
  "compiler=C:/msys64/clang64")
foreach(mutation IN LISTS mutations)
  file(REMOVE_RECURSE "${TEST_ROOT}")
  file(MAKE_DIRECTORY "${TEST_ROOT}")
  file(WRITE "${TEST_ROOT}/mutated.txt" "${mutation}\n")
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DSTAGE=${TEST_ROOT}"
      -P "${SOURCE_DIR}/tests/run-content-audit.cmake"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8)
  if(result EQUAL 0 OR NOT error MATCHES "Embedded absolute Windows path")
    message(FATAL_ERROR
      "Absolute-path mutation was not rejected: ${mutation}\n"
      "stdout:\n${output}\nstderr:\n${error}")
  endif()
endforeach()
message(STATUS "Source/build/Faust/compiler path mutations were rejected")
