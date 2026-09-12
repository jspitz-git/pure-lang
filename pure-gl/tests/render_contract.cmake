cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS SOURCE_DIR BINARY_DIR PURE_GL_RUNNER PURE_EXECUTABLE
    PURE_GL_MODULE FREEGLUT_RUNTIME_DLL PURE_GL_PURE_PREFIX
    PURE_GL_CLANG64_PREFIX PURE_GL_WINDOWS_SYSTEM_DIRECTORY)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

set(test_root "${BINARY_DIR}/render-contract")
file(REMOVE_RECURSE "${test_root}")
file(MAKE_DIRECTORY "${test_root}")

function(run_script script result_var output_var error_var)
  execute_process(COMMAND "${CMAKE_COMMAND}"
    "-DPURE_GL_RUNNER=${PURE_GL_RUNNER}"
    "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
    "-DPURE_GL_SOURCE_DIR=${SOURCE_DIR}"
    "-DPURE_GL_MODULE=${PURE_GL_MODULE}"
    "-DFREEGLUT_RUNTIME_DLL=${FREEGLUT_RUNTIME_DLL}"
    "-DPURE_GL_PURE_PREFIX=${PURE_GL_PURE_PREFIX}"
    "-DPURE_GL_CLANG64_PREFIX=${PURE_GL_CLANG64_PREFIX}"
    "-DPURE_GL_WINDOWS_SYSTEM_DIRECTORY=${PURE_GL_WINDOWS_SYSTEM_DIRECTORY}"
    "-DTEST_SCRIPT=${script}"
    -DTEST_WORKING_DIRECTORY=C:/Windows
    -DTIMEOUT_MS=120000
    -P "${SOURCE_DIR}/cmake/RunPureTest.cmake"
    RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error
    ENCODING UTF-8 TIMEOUT 125)
  set(${result_var} "${result}" PARENT_SCOPE)
  set(${output_var} "${output}" PARENT_SCOPE)
  set(${error_var} "${error}" PARENT_SCOPE)
endfunction()

function(require_pristine name markers)
  set(script "${SOURCE_DIR}/tests/${name}.pure")
  run_script("${script}" result output error)
  if(NOT result EQUAL 0)
    message(FATAL_ERROR
      "Pristine ${name} failed through the authenticated supervisor\n${output}${error}")
  endif()
  foreach(marker IN LISTS markers)
    if(NOT output MATCHES "(^|[\r\n])(-- )?${marker}([\r\n]|$)")
      message(FATAL_ERROR
        "Pristine ${name} omitted semantic marker ${marker}\n${output}${error}")
    endif()
  endforeach()
endfunction()

function(require_mutation_rejected name mutation statement marker)
  file(READ "${SOURCE_DIR}/tests/${name}.pure" contents)
  string(FIND "${contents}" "${statement}" position)
  if(position EQUAL -1)
    message(FATAL_ERROR
      "Cannot construct ${name}/${mutation}: statement is absent: ${statement}")
  endif()
  string(REPLACE "${statement}" "" mutated "${contents}")
  if(mutated STREQUAL contents)
    message(FATAL_ERROR "Cannot construct unchanged ${name}/${mutation} mutation")
  endif()
  set(script "${test_root}/${name}-${mutation}.pure")
  file(WRITE "${script}" "${mutated}")
  run_script("${script}" result output error)

  if(mutation STREQUAL "completion")
    if(result EQUAL 0 OR
        NOT "${output}${error}" MATCHES "completion protocol rejected")
      message(FATAL_ERROR
        "${name}/${mutation} did not fail naming the missing completion record\n${output}${error}")
    endif()
    message(STATUS
      "Rejected ${name}/${mutation}: missing completion record")
  else()
    if(NOT result EQUAL 0)
      message(FATAL_ERROR
        "${name}/${mutation} failed before semantic-marker validation\n${output}${error}")
    endif()
    if(output MATCHES "(^|[\r\n])(-- )?${marker}([\r\n]|$)")
      message(FATAL_ERROR
        "${name}/${mutation} retained forbidden semantic marker ${marker}\n${output}${error}")
    endif()
    message(STATUS
      "Rejected ${name}/${mutation}: missing semantic marker ${marker}")
  endif()
endfunction()

require_pristine(load "PURE_GL_ALL_FAMILIES_OK")
require_pristine(hidden-render
  "PURE_GL_CONTEXT_STRINGS_OK;PURE_GL_PIXEL_OK;PURE_GL_ERRORS_OK;PURE_GL_WINDOW_DESTROYED_OK")
require_pristine(interactive
  "PURE_GL_DISPLAY_EVENT_OK;PURE_GL_ERRORS_OK;PURE_GL_WINDOW_DESTROYED_OK")

require_mutation_rejected(load all-family "verify_all_families;"
  PURE_GL_ALL_FAMILIES_OK)
require_mutation_rejected(load completion "complete token;" COMPLETION)

require_mutation_rejected(hidden-render context-strings
  "verify_context_strings vendor renderer version;" PURE_GL_CONTEXT_STRINGS_OK)
require_mutation_rejected(hidden-render pixel "verify_pixel rgba;"
  PURE_GL_PIXEL_OK)
require_mutation_rejected(hidden-render gl-errors "verify_errors gl_errors;"
  PURE_GL_ERRORS_OK)
require_mutation_rejected(hidden-render window-destruction
  "destroy_window window;" PURE_GL_WINDOW_DESTROYED_OK)
require_mutation_rejected(hidden-render completion "complete token;" COMPLETION)

require_mutation_rejected(interactive gl-errors "verify_errors gl_errors;"
  PURE_GL_ERRORS_OK)
require_mutation_rejected(interactive display-event
  "process_display_event event_count;" PURE_GL_DISPLAY_EVENT_OK)
require_mutation_rejected(interactive window-destruction
  "destroy_window window;" PURE_GL_WINDOW_DESTROYED_OK)
require_mutation_rejected(interactive completion "complete token;" COMPLETION)

message(STATUS "PURE_GL_RENDER_CONTRACT_OK pristine=3 mutations=11")
