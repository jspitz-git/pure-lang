cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS SOURCE_DIR BINARY_DIR PURE_GL_RUNNER PURE_EXECUTABLE
    PURE_GL_MODULE FREEGLUT_RUNTIME_DLL PURE_GL_PURE_PREFIX
    PURE_GL_CLANG64_PREFIX PURE_GL_WINDOWS_SYSTEM_DIRECTORY)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

include("${SOURCE_DIR}/tests/AuditHelpers.cmake")
gl_audit_open(render-contract test_root)

function(record_contract_failure failure)
  set_property(GLOBAL APPEND PROPERTY pure_gl_render_failures "${failure}")
endfunction()

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

function(make_mutation name mutation statement replacement script_var contents_var)
  file(READ "${SOURCE_DIR}/tests/${name}.pure" contents)
  string(FIND "${contents}" "${statement}" position)
  if(position EQUAL -1)
    message(FATAL_ERROR
      "Cannot construct ${name}/${mutation}: statement is absent: ${statement}")
  endif()
  string(REPLACE "${statement}" "${replacement}" mutated "${contents}")
  if(mutated STREQUAL contents)
    message(FATAL_ERROR "Cannot construct unchanged ${name}/${mutation} mutation")
  endif()
  set(script "${test_root}/${name}-${mutation}.pure")
  file(WRITE "${script}" "${mutated}")
  set(${script_var} "${script}" PARENT_SCOPE)
  set(${contents_var} "${mutated}" PARENT_SCOPE)
endfunction()

function(require_failure name mutation statement replacement marker diagnostic
    cleanup_marker)
  make_mutation("${name}" "${mutation}" "${statement}" "${replacement}"
    script mutated)
  if(NOT mutated MATCHES "${marker}")
    message(FATAL_ERROR
      "${name}/${mutation} mutation removed semantic marker ${marker}")
  endif()
  run_script("${script}" result output error)
  # The adapter nests captured stdout in an indented CMake fatal diagnostic.
  set(transcript "${output}${error}")
  string(REGEX REPLACE "[ \t\r\n]+" " " diagnostic_text "${transcript}")
  string(FIND "${diagnostic_text}" "${diagnostic}" diagnostic_position)
  set(case_failed FALSE)
  if(result EQUAL 0)
    record_contract_failure(
      "${name}/${mutation} did not fail through the supervisor (${diagnostic})")
    set(case_failed TRUE)
  elseif(diagnostic_position EQUAL -1 OR
      NOT transcript MATCHES "pure-gl runner:")
    record_contract_failure(
      "${name}/${mutation} failed for an unrelated reason; expected ${diagnostic}\n${transcript}")
    set(case_failed TRUE)
  endif()
  if(NOT cleanup_marker STREQUAL "NONE" AND
      NOT transcript MATCHES
        "(^|[\r\n])[ \t]*(-- )?${cleanup_marker}[ \t]*([\r\n]|$)")
    record_contract_failure(
      "${name}/${mutation} bypassed failure cleanup ${cleanup_marker}\n${transcript}")
    set(case_failed TRUE)
  endif()
  if(transcript MATCHES
      "(^|[\r\n])[ \t]*(-- )?${marker}[ \t]*([\r\n]|$)")
    record_contract_failure(
      "${name}/${mutation} emitted success marker despite failed invariant ${marker}")
    set(case_failed TRUE)
  endif()
  if(NOT case_failed)
    message(STATUS
      "Rejected ${name}/${mutation}: invariant failed with marker source preserved")
  endif()
endfunction()

function(require_completion_failure name)
  make_mutation("${name}" completion "complete token;" "" script mutated)
  run_script("${script}" result output error)
  if(result EQUAL 0 OR
      NOT "${output}${error}" MATCHES "completion protocol rejected")
    message(FATAL_ERROR
      "${name}/completion did not fail naming the missing completion record\n${output}${error}")
  endif()
  message(STATUS "Rejected ${name}/completion: missing completion record")
endfunction()

require_pristine(load "PURE_GL_ALL_FAMILIES_OK")
require_pristine(hidden-render
  "PURE_GL_CONTEXT_STRINGS_OK;PURE_GL_PIXEL_OK;PURE_GL_ERRORS_OK;PURE_GL_WINDOW_DESTROYED_OK")
require_pristine(interactive
  "PURE_GL_DISPLAY_EVENT_OK;PURE_GL_ERRORS_OK;PURE_GL_WINDOW_DESTROYED_OK")

require_failure(load all-family "GL::VERSION_1_1 == 1 &&"
  "GL::VERSION_1_1 == -1 &&" PURE_GL_ALL_FAMILIES_OK
  "pure-gl module coverage failed" NONE)
require_completion_failure(load)

require_failure(hidden-render context-strings
  "verify_context_strings vendor renderer version;"
  "verify_context_strings \"\" renderer version;" PURE_GL_CONTEXT_STRINGS_OK
  "OpenGL context information is unavailable" PURE_GL_FAILURE_CLEANUP_OK)
require_failure(hidden-render pixel "verify_pixel rgba;"
  "verify_pixel [0,0,0,0];" PURE_GL_PIXEL_OK "Unexpected rendered pixel"
  PURE_GL_FAILURE_CLEANUP_OK)
require_failure(hidden-render gl-errors "verify_errors gl_errors;"
  "verify_errors [GL::INVALID_OPERATION];" PURE_GL_ERRORS_OK
  "OpenGL error in hidden render" PURE_GL_FAILURE_CLEANUP_OK)
require_failure(hidden-render window-destruction
  "destroy_window window = GLUT::DestroyWindow window $$"
  "destroy_window window = () $$" PURE_GL_WINDOW_DESTROYED_OK
  "success window remains current after destruction"
  PURE_GL_FAILURE_CLEANUP_OK)
require_failure(hidden-render failure-window-destruction
  "GLUT::DestroyWindow window $$" "() $$" PURE_GL_WINDOW_DESTROYED_OK
  "failure window remains current after destruction" NONE)
require_failure(hidden-render injected-failure
  "puts (\"pure-gl hidden render: \"+vendor+\"; \"+renderer+\"; OpenGL \"+version);"
  "throw \"INJECTED_HIDDEN_FAILURE\";" PURE_GL_WINDOW_DESTROYED_OK
  INJECTED_HIDDEN_FAILURE PURE_GL_FAILURE_CLEANUP_OK)
require_failure(hidden-render allocated-failure
  "GL::ReadPixels 16 16 1 1 GL::RGBA GL::UNSIGNED_BYTE pixel;"
  "throw \"INJECTED_ALLOCATED_FAILURE\";" PURE_GL_PIXEL_OK
  INJECTED_ALLOCATED_FAILURE PURE_GL_FAILURE_CLEANUP_OK)
require_failure(hidden-render allocation-failure "pixel = calloc 4 1;"
  "pixel = NULL;" PURE_GL_PIXEL_OK malloc_error PURE_GL_FAILURE_CLEANUP_OK)
require_failure(hidden-render clear-color
  "GL::ClearColor 0.25 0.5 0.75 1.0;"
  "GL::ClearColor 0.0 0.0 0.0 1.0;" PURE_GL_PIXEL_OK
  "Unexpected rendered pixel" PURE_GL_FAILURE_CLEANUP_OK)
require_completion_failure(hidden-render)

require_failure(interactive gl-errors "verify_errors gl_errors;"
  "verify_errors [GL::INVALID_OPERATION];" PURE_GL_ERRORS_OK
  "OpenGL error in the interactive example" PURE_GL_FAILURE_CLEANUP_OK)
require_failure(interactive display-event "GLUT::MainLoopEvent $$" "() $$"
  PURE_GL_DISPLAY_EVENT_OK "Display callback marker was not incremented"
  PURE_GL_FAILURE_CLEANUP_OK)
require_failure(interactive window-destruction
  "destroy_window window = GLUT::DestroyWindow window $$"
  "destroy_window window = () $$" PURE_GL_WINDOW_DESTROYED_OK
  "success window remains current after destruction"
  PURE_GL_FAILURE_CLEANUP_OK)
require_failure(interactive failure-window-destruction
  "GLUT::DestroyWindow window $$" "() $$" PURE_GL_WINDOW_DESTROYED_OK
  "failure window remains current after destruction" NONE)
require_failure(interactive injected-failure
  "puts \"pure-gl interactive desktop example displayed successfully\";"
  "throw \"INJECTED_INTERACTIVE_FAILURE\";" PURE_GL_WINDOW_DESTROYED_OK
  INJECTED_INTERACTIVE_FAILURE PURE_GL_FAILURE_CLEANUP_OK)
require_completion_failure(interactive)

get_property(contract_failures GLOBAL PROPERTY pure_gl_render_failures)
if(contract_failures)
  message(FATAL_ERROR
    "Semantic mutations escaped or bypassed cleanup: ${contract_failures}")
endif()
message(STATUS "PURE_GL_RENDER_CONTRACT_OK pristine=3 mutations=18")
gl_audit_clean(render-contract)
