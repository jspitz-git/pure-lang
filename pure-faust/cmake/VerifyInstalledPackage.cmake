foreach(required IN ITEMS STAGE_PREFIX EXPECT_DEVELOPER)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

if(NOT EXPECT_DEVELOPER STREQUAL "ON" AND NOT EXPECT_DEVELOPER STREQUAL "OFF")
  message(FATAL_ERROR "EXPECT_DEVELOPER must be ON or OFF")
endif()

cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE stage)

if(DEFINED BUILD_DIR AND NOT "${BUILD_DIR}" STREQUAL "")
  cmake_path(ABSOLUTE_PATH BUILD_DIR NORMALIZE OUTPUT_VARIABLE build_dir)
  file(REMOVE_RECURSE "${stage}")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" --install "${build_dir}"
      --prefix "${stage}" --component Runtime
    RESULT_VARIABLE install_result
    OUTPUT_VARIABLE install_output
    ERROR_VARIABLE install_error
    ENCODING UTF-8)
  if(NOT install_result EQUAL 0)
    message(FATAL_ERROR
      "Runtime install failed (${install_result})\\n"
      "stdout:\\n${install_output}\\nstderr:\\n${install_error}")
  endif()
endif()

set(expected_relative_files
  "lib/pure/faust2.pure"
  "share/doc/pure-faust/COPYING"
  "share/doc/pure-faust/COPYING.LESSER"
  "share/doc/pure-faust/WINDOWS.md"
  "share/doc/pure-faust/tests/reference.bc")
foreach(relative_file IN LISTS expected_relative_files)
  if(NOT EXISTS "${stage}/${relative_file}")
    message(FATAL_ERROR
      "Missing installed pure-faust file: ${stage}/${relative_file}")
  endif()
endforeach()

file(GLOB_RECURSE installed_files LIST_DIRECTORIES FALSE "${stage}/*")
set(installed_relative_files)
foreach(installed_file IN LISTS installed_files)
  file(RELATIVE_PATH relative_file "${stage}" "${installed_file}")
  list(APPEND installed_relative_files "${relative_file}")
endforeach()
list(SORT expected_relative_files)
list(SORT installed_relative_files)

set(forbidden_basenames
  faust.dll
  faust.pure
  pure.cpp
  faust.exe
  clang.exe
  opt.exe
  msys-2.0.dll)
foreach(installed_file IN LISTS installed_files)
  cmake_path(GET installed_file FILENAME basename)
  string(TOLOWER "${basename}" basename_lower)
  if(basename_lower IN_LIST forbidden_basenames)
    message(FATAL_ERROR
      "Forbidden pure-faust runtime file: ${installed_file}")
  endif()
endforeach()

if(NOT installed_relative_files STREQUAL expected_relative_files)
  message(FATAL_ERROR
    "Unexpected pure-faust runtime inventory: ${installed_relative_files}")
endif()

message(STATUS
  "Verified installed pure-faust runtime: ${stage} "
  "(${EXPECT_DEVELOPER} developer component expected)")
