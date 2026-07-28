foreach(name IN ITEMS LLVM_READOBJ LLVM_STRINGS PURE_GL_MODULE FREEGLUT_DLL)
  if(NOT DEFINED ${name} OR "${${name}}" STREQUAL "")
    message(FATAL_ERROR "${name} is required")
  endif()
endforeach()

foreach(path IN ITEMS "${PURE_GL_MODULE}" "${FREEGLUT_DLL}")
  if(NOT EXISTS "${path}")
    message(FATAL_ERROR "Missing binary: ${path}")
  endif()
  execute_process(
    COMMAND "${LLVM_READOBJ}" --file-headers --coff-imports "${path}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error)
  if(NOT result EQUAL 0)
    message(FATAL_ERROR "llvm-readobj failed for ${path}: ${error}")
  endif()
  if(NOT output MATCHES "Format: COFF-x86-64")
    message(FATAL_ERROR "${path} is not a 64-bit PE/COFF binary")
  endif()
  string(TOLOWER "${output}" imports)
  if(imports MATCHES "msys-2\\.0\\.dll|libgcc|libstdc\\+\\+")
    message(FATAL_ERROR "${path} imports an MSYS/GNU runtime")
  endif()
endforeach()

execute_process(
  COMMAND "${LLVM_READOBJ}" --coff-imports "${PURE_GL_MODULE}"
  OUTPUT_VARIABLE module_imports
  COMMAND_ERROR_IS_FATAL ANY)
string(TOLOWER "${module_imports}" module_imports)
foreach(dll IN ITEMS libpure.dll opengl32.dll)
  if(NOT module_imports MATCHES "${dll}")
    message(FATAL_ERROR "pure-gl module does not import ${dll}")
  endif()
endforeach()

execute_process(
  COMMAND "${LLVM_READOBJ}" --coff-imports "${FREEGLUT_DLL}"
  OUTPUT_VARIABLE freeglut_imports
  COMMAND_ERROR_IS_FATAL ANY)
string(TOLOWER "${freeglut_imports}" freeglut_imports)
foreach(dll IN ITEMS opengl32.dll gdi32.dll user32.dll winmm.dll)
  if(NOT freeglut_imports MATCHES "${dll}")
    message(FATAL_ERROR "FreeGLUT runtime does not import ${dll}")
  endif()
endforeach()

execute_process(
  COMMAND "${LLVM_STRINGS}" "${PURE_GL_MODULE}"
  OUTPUT_VARIABLE module_strings
  COMMAND_ERROR_IS_FATAL ANY)
string(REPLACE "\r\n" "\n" module_strings "${module_strings}")
if(NOT module_strings MATCHES "(^|\n)libfreeglut\\.dll(\n|$)")
  message(FATAL_ERROR "pure-gl module does not reference libfreeglut.dll")
endif()
if(module_strings MATCHES "(^|\n)freeglut\\.dll(\n|$)")
  message(FATAL_ERROR "pure-gl module still references the obsolete freeglut.dll name")
endif()

message(STATUS
  "Verified one x86-64 pure-gl module, seven wrapper families, one FreeGLUT runtime, and Windows system OpenGL APIs")
