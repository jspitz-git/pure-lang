cmake_minimum_required(VERSION 3.25)

foreach(required_variable IN ITEMS
    PUREPAD_EXECUTABLE
    PUREPAD_SOURCE_DIR
    PUREPAD_BUILD_DIR
    PUREPAD_CMAKE_MT)
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

file(GET_RUNTIME_DEPENDENCIES
  EXECUTABLES "${PUREPAD_EXECUTABLE}"
  RESOLVED_DEPENDENCIES_VAR purepad_resolved_dependencies
  UNRESOLVED_DEPENDENCIES_VAR purepad_unresolved_dependencies)

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

foreach(purepad_forbidden_prefix IN ITEMS
    "${PUREPAD_SOURCE_DIR}"
    "${PUREPAD_BUILD_DIR}")
  file(TO_CMAKE_PATH "${purepad_forbidden_prefix}" purepad_forbidden_prefix)
  string(REGEX REPLACE "/+$" "" purepad_forbidden_prefix
    "${purepad_forbidden_prefix}")
  string(TOLOWER "${purepad_forbidden_prefix}" purepad_forbidden_prefix)

  foreach(purepad_dependency IN LISTS purepad_resolved_dependencies)
    file(TO_CMAKE_PATH "${purepad_dependency}" purepad_dependency_path)
    string(TOLOWER "${purepad_dependency_path}" purepad_dependency_path)
    string(LENGTH "${purepad_forbidden_prefix}" purepad_prefix_length)
    string(SUBSTRING "${purepad_dependency_path}" 0 ${purepad_prefix_length}
      purepad_dependency_prefix)
    if(purepad_dependency_prefix STREQUAL purepad_forbidden_prefix)
      string(SUBSTRING "${purepad_dependency_path}" ${purepad_prefix_length} 1
        purepad_prefix_separator)
      if(purepad_prefix_separator STREQUAL "/")
        message(FATAL_ERROR
          "PurePad dependency is embedded under ${purepad_forbidden_prefix}: "
          "${purepad_dependency}")
      endif()
    endif()
  endforeach()
endforeach()

set(purepad_expected_runtime_names
  mfc140u.dll
  msvcp140.dll
  vcruntime140.dll
  vcruntime140_1.dll)
foreach(purepad_expected_runtime IN LISTS purepad_expected_runtime_names)
  list(FIND purepad_dependency_names "${purepad_expected_runtime}"
    purepad_expected_runtime_index)
  if(purepad_expected_runtime_index EQUAL -1)
    message(FATAL_ERROR
      "PurePad does not declare required Microsoft runtime "
      "${purepad_expected_runtime}. Found: ${purepad_dependency_names}")
  endif()
endforeach()

set(purepad_manifest "${CMAKE_CURRENT_BINARY_DIR}/purepad-installed.manifest")
execute_process(
  COMMAND "${PUREPAD_CMAKE_MT}"
    "-inputresource:${PUREPAD_EXECUTABLE};#1"
    "-out:${purepad_manifest}"
  RESULT_VARIABLE purepad_manifest_result
  OUTPUT_VARIABLE purepad_manifest_stdout
  ERROR_VARIABLE purepad_manifest_stderr)
if(NOT purepad_manifest_result EQUAL 0)
  message(FATAL_ERROR
    "Could not extract PurePad manifest:\n"
    "${purepad_manifest_stdout}${purepad_manifest_stderr}")
endif()
file(READ "${purepad_manifest}" purepad_manifest_contents)
if(NOT purepad_manifest_contents MATCHES
    "<longPathAware[^>]*>[ \t\r\n]*true[ \t\r\n]*</longPathAware>")
  message(FATAL_ERROR "PurePad manifest must declare longPathAware=true")
endif()

message(STATUS
  "PurePad runtime dependencies for TODO-49: ${purepad_dependency_names}")
