foreach (required_variable
    CMAKE_COMMAND SOURCE_DIR BINARY_DIR GENERATOR C_COMPILER MAKE_PROGRAM
    PURE_PREFIX SIGNING_FINGERPRINT)
  if (NOT DEFINED ${required_variable} OR "${${required_variable}}" STREQUAL "")
    message(FATAL_ERROR
      "${required_variable} is required for the root identity regression.")
  endif ()
endforeach ()

set(work_root "${BINARY_DIR}/root-identity-regression")
set(foreign_root "${work_root}/foreign-octave")
set(foreign_build "${work_root}/foreign-build")
file(REMOVE_RECURSE "${work_root}")
file(MAKE_DIRECTORY
  "${foreign_root}/mingw64/bin"
  "${foreign_root}/mingw64/include/octave-11.3.0/octave"
  "${foreign_root}/mingw64/lib/octave/11.3.0"
  "${foreign_root}/mingw64/share/octave/11.3.0")

foreach (foreign_file
    "mingw64/bin/octave-cli.exe"
    "mingw64/bin/mkoctfile.exe"
    "mingw64/bin/liboctinterp-15.dll"
    "mingw64/include/octave-11.3.0/octave/oct.h"
    "mingw64/include/octave-11.3.0/octave/octave.h"
    "mingw64/include/octave-11.3.0/octave/interpreter.h"
    "mingw64/lib/liboctinterp.dll.a"
    "mingw64/lib/liboctave.dll.a")
  file(WRITE "${foreign_root}/${foreign_file}" "foreign root fixture\n")
endforeach ()

execute_process(
  COMMAND "${CMAKE_COMMAND}" -S "${SOURCE_DIR}" -B "${foreign_build}"
    -G "${GENERATOR}"
    "-DCMAKE_C_COMPILER=${C_COMPILER}"
    "-DCMAKE_MAKE_PROGRAM=${MAKE_PROGRAM}"
    -DBUILD_TESTING=OFF
    "-DPURE_PREFIX=${PURE_PREFIX}"
    "-DOCTAVE_ROOT=${foreign_root}"
    "-DOCTAVE_SIGNING_FINGERPRINT=${SIGNING_FINGERPRINT}"
  RESULT_VARIABLE configure_result
  OUTPUT_VARIABLE configure_stdout
  ERROR_VARIABLE configure_stderr)
set(configure_output "${configure_stdout}${configure_stderr}")
set(marker_path "${foreign_root}/pure-octave.fingerprint")

if (configure_result EQUAL 0)
  if (EXISTS "${marker_path}")
    set(marker_detail " and created its trust marker")
  else ()
    set(marker_detail "")
  endif ()
  file(REMOVE_RECURSE "${work_root}")
  message(FATAL_ERROR
    "A shape-valid foreign Octave root with only a declared signing "
    "fingerprint configured successfully${marker_detail}.")
endif ()

if (EXISTS "${marker_path}")
  file(REMOVE_RECURSE "${work_root}")
  message(FATAL_ERROR
    "Rejected foreign root still received a trust marker:\n${configure_output}")
endif ()
if (NOT configure_output MATCHES "Octave root content identity mismatch")
  file(REMOVE_RECURSE "${work_root}")
  message(FATAL_ERROR
    "Foreign-root rejection omitted the content identity diagnostic:\n"
    "${configure_output}")
endif ()

file(REMOVE_RECURSE "${work_root}")
