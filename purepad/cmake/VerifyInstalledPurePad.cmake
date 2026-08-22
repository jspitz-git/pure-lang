cmake_minimum_required(VERSION 3.25)

foreach(required_variable IN ITEMS
    PUREPAD_EXECUTABLE
    PUREPAD_SOURCE_DIR
    PUREPAD_BUILD_DIR
    PUREPAD_CMAKE_MT
    PUREPAD_MANIFEST)
  if(NOT DEFINED ${required_variable} OR "${${required_variable}}" STREQUAL "")
    message(FATAL_ERROR "${required_variable} is required")
  endif()
endforeach()

if(NOT EXISTS "${PUREPAD_EXECUTABLE}")
  message(FATAL_ERROR "PurePad executable does not exist: ${PUREPAD_EXECUTABLE}")
endif()
if(NOT EXISTS "${PUREPAD_CMAKE_MT}")
  message(FATAL_ERROR "CMAKE_MT does not exist: ${PUREPAD_CMAKE_MT}")
endif()

if(DEFINED PUREPAD_TEST_UNRESOLVED_DEPENDENCIES)
  set(purepad_resolved_dependencies "${PUREPAD_TEST_RESOLVED_DEPENDENCIES}")
  set(purepad_unresolved_dependencies "${PUREPAD_TEST_UNRESOLVED_DEPENDENCIES}")
else()
  file(GET_RUNTIME_DEPENDENCIES
    EXECUTABLES "${PUREPAD_EXECUTABLE}"
    RESOLVED_DEPENDENCIES_VAR purepad_resolved_dependencies
    UNRESOLVED_DEPENDENCIES_VAR purepad_unresolved_dependencies)
endif()

function(purepad_normalize_path input output)
  file(TO_CMAKE_PATH "${input}" normalized_path)
  string(REGEX REPLACE "^//[?]/" "" normalized_path "${normalized_path}")
  cmake_path(NORMAL_PATH normalized_path OUTPUT_VARIABLE normalized_path)
  string(TOLOWER "${normalized_path}" normalized_path)
  set(${output} "${normalized_path}" PARENT_SCOPE)
endfunction()

foreach(purepad_forbidden_prefix IN ITEMS
    "${PUREPAD_SOURCE_DIR}"
    "${PUREPAD_BUILD_DIR}")
  purepad_normalize_path("${purepad_forbidden_prefix}"
    purepad_normalized_forbidden_prefix)

  foreach(purepad_dependency IN LISTS
      purepad_resolved_dependencies
      purepad_unresolved_dependencies)
    purepad_normalize_path("${purepad_dependency}" purepad_normalized_dependency)
    cmake_path(IS_PREFIX purepad_normalized_forbidden_prefix
      "${purepad_normalized_dependency}" NORMALIZE purepad_dependency_embedded)
    if(purepad_dependency_embedded)
      message(FATAL_ERROR
        "PurePad dependency is embedded under ${purepad_normalized_forbidden_prefix}: "
        "${purepad_dependency}")
    endif()
  endforeach()
endforeach()

set(purepad_dependency_names)
foreach(purepad_dependency IN LISTS
    purepad_resolved_dependencies
    purepad_unresolved_dependencies)
  get_filename_component(purepad_dependency_name
    "${purepad_dependency}" NAME)
  string(TOLOWER "${purepad_dependency_name}" purepad_dependency_name)
  list(APPEND purepad_dependency_names "${purepad_dependency_name}")

  if(purepad_dependency_name STREQUAL "msys-2.0.dll")
    message(FATAL_ERROR "PurePad must not depend on msys-2.0.dll")
  endif()
endforeach()
list(REMOVE_DUPLICATES purepad_dependency_names)
list(SORT purepad_dependency_names)

set(purepad_expected_runtime_names
  mfc140u.dll
  msvcp140.dll
  vcruntime140.dll
  vcruntime140_1.dll)
set(purepad_declared_runtime_names)
foreach(purepad_expected_runtime IN LISTS purepad_expected_runtime_names)
  list(FIND purepad_dependency_names "${purepad_expected_runtime}"
    purepad_expected_runtime_index)
  if(purepad_expected_runtime_index EQUAL -1)
    message(FATAL_ERROR
      "PurePad does not declare required Microsoft runtime "
      "${purepad_expected_runtime}. Found: ${purepad_dependency_names}")
  endif()
  list(APPEND purepad_declared_runtime_names "${purepad_expected_runtime}")
endforeach()

execute_process(
  COMMAND "${PUREPAD_CMAKE_MT}"
    "-inputresource:${PUREPAD_EXECUTABLE};#1"
    "-out:${PUREPAD_MANIFEST}"
  RESULT_VARIABLE purepad_manifest_result
  OUTPUT_VARIABLE purepad_manifest_stdout
  ERROR_VARIABLE purepad_manifest_stderr)
if(NOT purepad_manifest_result EQUAL 0)
  message(FATAL_ERROR
    "Could not extract PurePad manifest:\n"
    "${purepad_manifest_stdout}${purepad_manifest_stderr}")
endif()
file(READ "${PUREPAD_MANIFEST}" purepad_manifest_contents)
if(NOT purepad_manifest_contents MATCHES
    "<longPathAware[^>]*>[ \t\r\n]*true[ \t\r\n]*</longPathAware>")
  message(FATAL_ERROR "PurePad manifest must declare longPathAware=true")
endif()

message(STATUS
  "PurePad Microsoft runtime dependencies for TODO-49: "
  "${purepad_declared_runtime_names}")
