foreach(required IN ITEMS
    LLVM_READOBJ GLPK_MODULE GLPK_DLL COLAMD_DLL AMD_DLL
    SUITESPARSECONFIG_DLL OMP_DLL GMP_DLL ZLIB_DLL)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

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

foreach(module IN ITEMS
    "${GLPK_MODULE}" "${GLPK_DLL}" "${COLAMD_DLL}" "${AMD_DLL}"
    "${SUITESPARSECONFIG_DLL}" "${OMP_DLL}" "${GMP_DLL}" "${ZLIB_DLL}")
  if(NOT EXISTS "${module}")
    message(FATAL_ERROR "Dependency does not exist: ${module}")
  endif()
  read_imports("${module}" imports)
  if(imports MATCHES
      "Name: (msys-2\\.0|libgcc[^.]*|libstdc\\+\\+[^.]*)\\.dll")
    message(FATAL_ERROR "${module} imports an incompatible MSYS/GNU runtime")
  endif()
endforeach()

require_import("${GLPK_MODULE}" "libpure\\.dll")
require_import("${GLPK_MODULE}" "libglpk-40\\.dll")
require_import("${GLPK_MODULE}" "libgmp-10\\.dll")
require_import("${GLPK_DLL}" "libcolamd\\.dll")
require_import("${GLPK_DLL}" "libamd\\.dll")
require_import("${GLPK_DLL}" "zlib1\\.dll")
require_import("${GLPK_DLL}" "libgmp-10\\.dll")
require_import("${COLAMD_DLL}" "libsuitesparseconfig\\.dll")
require_import("${AMD_DLL}" "libsuitesparseconfig\\.dll")
require_import("${SUITESPARSECONFIG_DLL}" "libomp\\.dll")

message(STATUS
  "Verified pure-glpk PE closure: GLPK, AMD/COLAMD, SuiteSparseConfig, "
  "OpenMP, GMP, zlib, and UCRT")
