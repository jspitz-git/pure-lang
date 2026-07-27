foreach(required IN ITEMS
    LLVM_READOBJ
    STLBASE_DLL
    STLVEC_DLL
    STLALGORITHM_DLL
    STLMAP_DLL
    STLMMAP_DLL
    STLHMAP_DLL)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

set(modules
  "${STLBASE_DLL}"
  "${STLVEC_DLL}"
  "${STLALGORITHM_DLL}"
  "${STLMAP_DLL}"
  "${STLMMAP_DLL}"
  "${STLHMAP_DLL}"
)

function(read_imports module output_var)
  execute_process(
    COMMAND "${LLVM_READOBJ}" --coff-imports "${module}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8
  )
  if(NOT result EQUAL 0)
    message(FATAL_ERROR
      "Unable to inspect ${module} (${result})\nstdout:\n${output}\nstderr:\n${error}")
  endif()
  set(${output_var} "${output}" PARENT_SCOPE)
endfunction()

function(require_import module import_name)
  read_imports("${module}" imports)
  if(NOT imports MATCHES "Name: ${import_name}([\r\n]|$)")
    message(FATAL_ERROR "${module} does not import ${import_name}")
  endif()
endfunction()

foreach(module IN LISTS modules)
  if(NOT EXISTS "${module}")
    message(FATAL_ERROR "Module does not exist: ${module}")
  endif()
  read_imports("${module}" imports)
  if(NOT imports MATCHES "Name: libc\\+\\+\\.dll([\r\n]|$)")
    message(FATAL_ERROR "${module} does not use the shared libc++.dll runtime")
  endif()
  if(imports MATCHES "Name: (libstdc\\+\\+|libgcc[^.]*)\\.dll")
    message(FATAL_ERROR "${module} mixes a GNU C++ runtime into the CLANG64 package")
  endif()
  if(NOT imports MATCHES "Name: libpure\\.dll([\r\n]|$)")
    message(FATAL_ERROR "${module} does not import libpure.dll")
  endif()
endforeach()

require_import("${STLVEC_DLL}" "stlbase\\.dll")
require_import("${STLALGORITHM_DLL}" "stlbase\\.dll")
require_import("${STLALGORITHM_DLL}" "stlvec\\.dll")
require_import("${STLMAP_DLL}" "stlbase\\.dll")
require_import("${STLMMAP_DLL}" "stlbase\\.dll")
require_import("${STLHMAP_DLL}" "stlbase\\.dll")

message(STATUS
  "Verified pure-stllib PE dependencies: one libc++ runtime and expected module links")
