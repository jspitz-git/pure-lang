foreach(required IN ITEMS
    LLVM_READOBJ RUNTIME_DIR AUDIO_MODULE FFTW_MODULE SRCPROCESS_MODULE
    SFINFO_MODULE REALTIME_MODULE)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

set(runtime_names
  libportaudio.dll
  libfftw3-3.dll
  libsamplerate-0.dll
  libsndfile-1.dll
  libogg-0.dll
  libvorbisenc-2.dll
  libFLAC.dll
  libopus-0.dll
  libmpg123-0.dll
  libmp3lame-0.dll
  libvorbis-0.dll
  libwinpthread-1.dll
  libc++.dll
)
set(modules
  "${AUDIO_MODULE}"
  "${FFTW_MODULE}"
  "${SRCPROCESS_MODULE}"
  "${SFINFO_MODULE}"
  "${REALTIME_MODULE}"
)
foreach(runtime IN LISTS runtime_names)
  list(APPEND modules "${RUNTIME_DIR}/${runtime}")
endforeach()

function(read_imports module output_var)
  if(NOT EXISTS "${module}")
    message(FATAL_ERROR "Dependency does not exist: ${module}")
  endif()
  execute_process(
    COMMAND "${LLVM_READOBJ}" --coff-imports "${module}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    ENCODING UTF-8
  )
  if(NOT result EQUAL 0)
    message(FATAL_ERROR
      "Unable to inspect ${module} (${result})\n${output}\n${error}")
  endif()
  set(${output_var} "${output}" PARENT_SCOPE)
endfunction()

function(require_import module import_name)
  read_imports("${module}" imports)
  if(NOT imports MATCHES "Name: ${import_name}")
    message(FATAL_ERROR "${module} does not import ${import_name}")
  endif()
endfunction()

foreach(module IN LISTS modules)
  read_imports("${module}" imports)
  if(imports MATCHES
      "Name: (msys-2\\.0|libgcc[^.]*|libstdc\\+\\+[^.]*)\\.dll")
    message(FATAL_ERROR "${module} imports an incompatible MSYS/GNU runtime")
  endif()
endforeach()

require_import("${AUDIO_MODULE}" "libpure\\.dll")
require_import("${AUDIO_MODULE}" "libportaudio\\.dll")
require_import("${AUDIO_MODULE}" "libwinpthread-1\\.dll")
require_import("${FFTW_MODULE}" "libfftw3-3\\.dll")
require_import("${SRCPROCESS_MODULE}" "libpure\\.dll")
require_import("${SRCPROCESS_MODULE}" "libsamplerate-0\\.dll")
require_import("${SFINFO_MODULE}" "libpure\\.dll")
require_import("${SFINFO_MODULE}" "libsndfile-1\\.dll")
require_import("${REALTIME_MODULE}" "libpure\\.dll")
require_import("${REALTIME_MODULE}" "libwinpthread-1\\.dll")

require_import("${RUNTIME_DIR}/libportaudio.dll" "WINMM\\.dll")
require_import("${RUNTIME_DIR}/libportaudio.dll" "ole32\\.dll")
require_import("${RUNTIME_DIR}/libportaudio.dll" "libc\\+\\+\\.dll")
foreach(codec IN ITEMS
    libogg-0.dll libvorbisenc-2.dll libFLAC.dll libopus-0.dll
    libmpg123-0.dll libmp3lame-0.dll libvorbis-0.dll)
  require_import("${RUNTIME_DIR}/libsndfile-1.dll" "${codec}")
endforeach()
require_import("${RUNTIME_DIR}/libvorbisenc-2.dll" "libvorbis-0\\.dll")
require_import("${RUNTIME_DIR}/libvorbis-0.dll" "libogg-0\\.dll")
require_import("${RUNTIME_DIR}/libFLAC.dll" "libogg-0\\.dll")
require_import("${RUNTIME_DIR}/libFLAC.dll" "libwinpthread-1\\.dll")

message(STATUS
  "Verified pure-audio PE closure: 5 modules, 11 audio/codec DLLs, "
  "reused libc++/winpthreads, native Windows audio APIs, and UCRT")
