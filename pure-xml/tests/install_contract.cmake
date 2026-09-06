cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS SOURCE_DIR BINARY_DIR TEST_ROOT PURE_EXECUTABLE
    LLVM_READOBJ_EXECUTABLE LIBXML2_RUNTIME_DLL LIBXSLT_RUNTIME_DLL
    LIBICONV_RUNTIME_DLL ZLIB_RUNTIME_DLL)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH BINARY_DIR NORMALIZE OUTPUT_VARIABLE binary_root)
cmake_path(ABSOLUTE_PATH TEST_ROOT NORMALIZE OUTPUT_VARIABLE test_root)
cmake_path(IS_PREFIX binary_root "${test_root}" NORMALIZE inside_build)
if(NOT inside_build OR test_root STREQUAL binary_root)
  message(FATAL_ERROR "TEST_ROOT must be a proper child of BINARY_DIR")
endif()

set(package_stage "${test_root}/package stage")
set(runtime_stage "${test_root}/portable runtime")
file(REMOVE_RECURSE "${test_root}")
file(MAKE_DIRECTORY "${test_root}")
execute_process(
  COMMAND "${CMAKE_COMMAND}" --install "${BINARY_DIR}" --prefix "${package_stage}"
  RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Package install failed:\n${output}${error}")
endif()

set(expected
  bin/libxml2-16.dll
  bin/libxslt-1.dll
  lib/pure/xml.dll
  lib/pure/xml.pure
  share/doc/pure-xml/COPYING
  share/doc/pure-xml/COPYING.LESSER
  share/doc/pure-xml/README
  share/doc/pure-xml/WINDOWS.md
  share/doc/pure-xml/libxml2-COPYING
  share/doc/pure-xml/libxslt-Copyright
  share/doc/pure-xml/examples/catalog.pure
  share/doc/pure-xml/examples/catalog.xsl
  share/doc/pure-xml/examples/recipes.pure
  share/doc/pure-xml/examples/recipes.xml
  share/doc/pure-xml/examples/recipes.xsl
  share/doc/pure-xml/examples/sample.xml
  share/doc/pure-xml/examples/xml_example.pure)
file(GLOB_RECURSE installed RELATIVE "${package_stage}" "${package_stage}/*")
list(SORT expected)
list(SORT installed)
if(NOT installed STREQUAL expected)
  message(FATAL_ERROR
    "Installed manifest differs. Expected '${expected}', got '${installed}'")
endif()

foreach(pair IN ITEMS
    "bin/libxml2-16.dll|${LIBXML2_RUNTIME_DLL}"
    "bin/libxslt-1.dll|${LIBXSLT_RUNTIME_DLL}")
  string(REPLACE "|" ";" fields "${pair}")
  list(GET fields 0 relative)
  list(GET fields 1 source)
  file(SHA256 "${package_stage}/${relative}" installed_hash)
  file(SHA256 "${source}" source_hash)
  if(NOT installed_hash STREQUAL source_hash)
    message(FATAL_ERROR "Installed ${relative} differs from configured input")
  endif()
endforeach()

execute_process(COMMAND "${CMAKE_COMMAND}"
  "-DLLVM_READOBJ=${LLVM_READOBJ_EXECUTABLE}"
  "-DXML_DLL=${package_stage}/lib/pure/xml.dll"
  "-DLIBXML2_DLL=${package_stage}/bin/libxml2-16.dll"
  "-DLIBXSLT_DLL=${package_stage}/bin/libxslt-1.dll"
  "-DLIBICONV_DLL=${LIBICONV_RUNTIME_DLL}"
  "-DZLIB_DLL=${ZLIB_RUNTIME_DLL}"
  -P "${SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
  RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Installed PE verification failed:\n${output}${error}")
endif()

get_filename_component(pure_bin "${PURE_EXECUTABLE}" DIRECTORY)
get_filename_component(pure_prefix "${pure_bin}" DIRECTORY)
if(NOT EXISTS "${pure_prefix}/lib/pure/math.pure")
  message(FATAL_ERROR "PURE_EXECUTABLE is not in an installed runtime")
endif()
file(COPY "${pure_prefix}/" DESTINATION "${runtime_stage}")
execute_process(COMMAND "${CMAKE_COMMAND}" --install "${BINARY_DIR}"
  --prefix "${runtime_stage}" RESULT_VARIABLE result
  OUTPUT_VARIABLE output ERROR_VARIABLE error)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Runtime overlay install failed:\n${output}${error}")
endif()
file(COPY "${LIBICONV_RUNTIME_DLL}" "${ZLIB_RUNTIME_DLL}"
  DESTINATION "${runtime_stage}/bin")

set(poison "${test_root}/poison")
file(MAKE_DIRECTORY "${poison}")
file(WRITE "${poison}/xml.pure" "error \"ambient PURELIB was used\";\n")
set(ENV{PURELIB} "${poison}")
set(ENV{PATH} "C:/msys64/clang64/bin;C:/msys64/usr/bin;$ENV{PATH}")
execute_process(COMMAND "${CMAKE_COMMAND}"
  "-DPURE_EXECUTABLE=${runtime_stage}/bin/pure.exe"
  "-DPACKAGE_DIR=${runtime_stage}/lib/pure"
  "-DMODULE_DIR=${runtime_stage}/lib/pure"
  "-DRUNTIME_BIN_DIR=${runtime_stage}/bin"
  "-DTEST_SCRIPT=${SOURCE_DIR}/tests/smoke.pure"
  "-DTEST_DATA_DIR=${SOURCE_DIR}/tests"
  "-DRUN_WORKING_DIRECTORY=$ENV{SystemRoot}"
  -P "${SOURCE_DIR}/cmake/RunSmokeTest.cmake"
  RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Installed runtime smoke failed:\n${output}${error}")
endif()

message(STATUS "Verified exact 17-file install and standalone runtime smoke")
