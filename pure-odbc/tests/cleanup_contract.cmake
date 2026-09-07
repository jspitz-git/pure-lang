cmake_minimum_required(VERSION 3.29)

foreach(required IN ITEMS BINARY_DIR MAKE_EXECUTABLE PKG_CONFIG_EXECUTABLE)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()
foreach(tool IN ITEMS MAKE_EXECUTABLE PKG_CONFIG_EXECUTABLE)
  if(NOT EXISTS "${${tool}}" OR IS_DIRECTORY "${${tool}}")
    message(FATAL_ERROR "${tool} must be an existing file: ${${tool}}")
  endif()
endforeach()

set(contract_helper "${CMAKE_CURRENT_LIST_DIR}/ContractTestRoot.cmake")
if(NOT EXISTS "${contract_helper}")
  message(FATAL_ERROR "Contract root helper is missing: ${contract_helper}")
endif()
include("${contract_helper}")
pure_odbc_reset_contract_test_root("cleanup")

cmake_path(GET MAKE_EXECUTABLE PARENT_PATH make_bin)
cmake_path(GET PKG_CONFIG_EXECUTABLE PARENT_PATH pkg_config_bin)
set(clean_path
  "${make_bin};${pkg_config_bin};$ENV{SystemRoot}/System32;$ENV{SystemRoot}")
set(empty_pkg_config "${TEST_ROOT}/empty-pkg-config")
file(MAKE_DIRECTORY "${empty_pkg_config}")

function(write_cleanup_fixture fixture)
  file(MAKE_DIRECTORY "${fixture}")
  file(COPY "${SOURCE_DIR}/Makefile" DESTINATION "${fixture}")
  foreach(name IN ITEMS
      unrelated.dll unrelated.so unrelated.dylib unrelated.exe
      unrelated.a unrelated.o editor-backup~ wildcard-target keep.txt)
    file(WRITE "${fixture}/${name}" "unrelated sentinel: ${name}\n")
  endforeach()
endfunction()

function(run_clean fixture output_result output_stdout output_stderr)
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env
      "PATH=${clean_path}"
      "PKG_CONFIG_PATH=${empty_pkg_config}"
      "PKG_CONFIG_LIBDIR=${empty_pkg_config}"
      "PKG_CONFIG_SYSROOT_DIR="
      "${MAKE_EXECUTABLE}" -f Makefile
      "PKG_CONFIG=${PKG_CONFIG_EXECUTABLE}" ${ARGN} clean
    WORKING_DIRECTORY "${fixture}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8
  )
  set(${output_result} "${result}" PARENT_SCOPE)
  set(${output_stdout} "${output}" PARENT_SCOPE)
  set(${output_stderr} "${error}" PARENT_SCOPE)
endfunction()

function(expect_safe_rejection label)
  set(fixture "${TEST_ROOT}/reject-${label}")
  write_cleanup_fixture("${fixture}")
  run_clean("${fixture}" result output error ${ARGN})
  set(diagnostics "${output}\n${error}")
  if(result EQUAL 0)
    message(FATAL_ERROR "make clean accepted unsafe ${label} metadata")
  endif()
  if(NOT diagnostics MATCHES "refusing to clean: Pure DLL suffix")
    message(FATAL_ERROR
      "Unsafe ${label} metadata produced the wrong diagnostic\n${diagnostics}")
  endif()
  foreach(name IN ITEMS
      Makefile unrelated.dll unrelated.so unrelated.dylib unrelated.exe
      unrelated.a unrelated.o editor-backup~ wildcard-target keep.txt)
    if(NOT EXISTS "${fixture}/${name}")
      message(FATAL_ERROR
        "Unsafe ${label} cleanup removed unrelated sentinel '${name}'")
    endif()
  endforeach()
endfunction()

expect_safe_rejection("missing-pure-pc")
expect_safe_rejection("empty-suffix" "DLL=")
expect_safe_rejection("unknown-suffix" "DLL=.exe")
expect_safe_rejection("wildcard-suffix" "DLL=*")

foreach(suffix IN ITEMS .dll .so .dylib)
  string(SUBSTRING "${suffix}" 1 -1 suffix_name)
  set(fixture "${TEST_ROOT}/valid-${suffix_name}")
  write_cleanup_fixture("${fixture}")
  foreach(generated IN ITEMS "odbc${suffix}" odbc.a odbc.o)
    file(WRITE "${fixture}/${generated}" "generated fixture\n")
  endforeach()
  run_clean("${fixture}" result output error "DLL=${suffix}")
  if(NOT result EQUAL 0)
    message(FATAL_ERROR
      "make clean rejected valid ${suffix} metadata\n${output}${error}")
  endif()
  foreach(generated IN ITEMS "odbc${suffix}" odbc.a odbc.o)
    if(EXISTS "${fixture}/${generated}")
      message(FATAL_ERROR
        "make clean left generated artifact '${generated}' for ${suffix}")
    endif()
  endforeach()
  foreach(name IN ITEMS
      Makefile unrelated.dll unrelated.so unrelated.dylib unrelated.exe
      unrelated.a unrelated.o editor-backup~ wildcard-target keep.txt)
    if(NOT EXISTS "${fixture}/${name}")
      message(FATAL_ERROR
        "Valid ${suffix} cleanup removed unrelated sentinel '${name}'")
    endif()
  endforeach()
endforeach()

message(STATUS "pure-odbc Make cleanup contract passed")
