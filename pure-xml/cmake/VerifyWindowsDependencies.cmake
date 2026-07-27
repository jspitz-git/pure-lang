foreach(required IN ITEMS
    LLVM_READOBJ
    XML_DLL
    LIBXML2_DLL
    LIBXSLT_DLL)
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

foreach(module IN ITEMS "${XML_DLL}" "${LIBXML2_DLL}" "${LIBXSLT_DLL}")
  if(NOT EXISTS "${module}")
    message(FATAL_ERROR "Dependency does not exist: ${module}")
  endif()
  read_imports("${module}" imports)
  if(imports MATCHES "Name: (msys-2\\.0|libgcc[^.]*)\\.dll")
    message(FATAL_ERROR "${module} imports an incompatible MSYS/GNU runtime")
  endif()
endforeach()

require_import("${XML_DLL}" "libpure\\.dll")
require_import("${XML_DLL}" "libxml2-16\\.dll")
require_import("${XML_DLL}" "libxslt-1\\.dll")
require_import("${LIBXSLT_DLL}" "libxml2-16\\.dll")
require_import("${LIBXML2_DLL}" "libiconv-2\\.dll")
require_import("${LIBXML2_DLL}" "zlib1\\.dll")

message(STATUS
  "Verified pure-xml PE dependencies: libxml2, libxslt, iconv, and zlib closure")
