foreach(required IN ITEMS
    LLVM_READOBJ PURE_TK_MODULE TCL_DLL TK_DLL ZLIB_DLL)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

function(read_imports binary output_var)
  if(NOT EXISTS "${binary}")
    message(FATAL_ERROR "Missing binary: ${binary}")
  endif()
  execute_process(
    COMMAND "${LLVM_READOBJ}" --file-headers --coff-imports "${binary}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8
  )
  if(NOT result EQUAL 0)
    message(FATAL_ERROR
      "Unable to inspect ${binary} (${result})\n${output}\n${error}")
  endif()
  if(NOT output MATCHES "Format: COFF-x86-64")
    message(FATAL_ERROR "${binary} is not a 64-bit PE/COFF binary")
  endif()
  if(output MATCHES
      "Name: (msys-2\\.0|libgcc[^.]*|libstdc\\+\\+[^.]*|libc\\+\\+)\\.dll")
    message(FATAL_ERROR "${binary} imports an incompatible POSIX/C++ runtime")
  endif()
  set(${output_var} "${output}" PARENT_SCOPE)
endfunction()

function(require_import imports_var import_name description)
  if(NOT "${${imports_var}}" MATCHES "Name: ${import_name}")
    message(FATAL_ERROR "${description} does not import ${import_name}")
  endif()
endfunction()

read_imports("${PURE_TK_MODULE}" module_imports)
require_import(module_imports "tcl86\\.dll" "pure-tk module")
require_import(module_imports "tk86\\.dll" "pure-tk module")
require_import(module_imports "libpure\\.dll" "pure-tk module")

read_imports("${TCL_DLL}" tcl_imports)
require_import(tcl_imports "zlib1\\.dll" "Tcl runtime")
require_import(tcl_imports "WS2_32\\.dll" "Tcl runtime")
require_import(tcl_imports "USERENV\\.dll" "Tcl runtime")

read_imports("${TK_DLL}" tk_imports)
require_import(tk_imports "USER32\\.dll" "Tk runtime")
require_import(tk_imports "GDI32\\.dll" "Tk runtime")
require_import(tk_imports "COMCTL32\\.dll" "Tk runtime")

read_imports("${ZLIB_DLL}" zlib_imports)

message(STATUS
  "Verified pure-tk PE closure: tk.dll, Tcl/Tk/zlib runtimes, reused "
  "libpure, native Windows GUI/network APIs, and UCRT")
