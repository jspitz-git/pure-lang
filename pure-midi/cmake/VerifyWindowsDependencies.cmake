foreach(required IN ITEMS LLVM_READOBJ PORTMIDI_DLL PMLIB_MODULE MIDIFILE_MODULE)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

set(binaries "${PMLIB_MODULE}" "${MIDIFILE_MODULE}" "${PORTMIDI_DLL}")

function(read_imports binary output_var)
  if(NOT EXISTS "${binary}")
    message(FATAL_ERROR "Dependency does not exist: ${binary}")
  endif()
  execute_process(
    COMMAND "${LLVM_READOBJ}" --file-headers --coff-imports "${binary}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8)
  if(NOT result EQUAL 0)
    message(FATAL_ERROR
      "Unable to inspect ${binary} (${result})\n${output}\n${error}")
  endif()
  if(NOT output MATCHES "Format: COFF-x86-64" OR
      NOT output MATCHES "Arch: x86_64")
    message(FATAL_ERROR "${binary} is not an x86-64 PE binary")
  endif()
  set(${output_var} "${output}" PARENT_SCOPE)
endfunction()

function(require_import binary import_name)
  read_imports("${binary}" imports)
  if(NOT imports MATCHES "Name: ${import_name}")
    message(FATAL_ERROR "${binary} does not import ${import_name}")
  endif()
endfunction()

foreach(binary IN LISTS binaries)
  read_imports("${binary}" imports)
  if(imports MATCHES
      "Name: (msys-2\\.0|libgcc[^.]*|libstdc\\+\\+[^.]*)\\.dll")
    message(FATAL_ERROR "${binary} imports an incompatible MSYS/GNU runtime")
  endif()
endforeach()

require_import("${PMLIB_MODULE}" "libpure\\.dll")
require_import("${PMLIB_MODULE}" "libportmidi\\.dll")
require_import("${MIDIFILE_MODULE}" "libpure\\.dll")
require_import("${PORTMIDI_DLL}" "WINMM\\.dll")

message(STATUS
  "Verified pure-midi PE closure: 2 x86-64 modules, one PortMidi DLL, "
  "native WinMM timing/device backend, and UCRT")
