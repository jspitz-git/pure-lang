foreach(required IN ITEMS STAGE_PREFIX SOURCE_RUNTIME_DIR)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE stage)
cmake_path(ABSOLUTE_PATH SOURCE_RUNTIME_DIR NORMALIZE OUTPUT_VARIABLE source_bin)
set(module_dir "${stage}/lib/pure")
set(doc_dir "${stage}/share/doc/pure-gplot")
set(gnuplot_root "${stage}/tools/gnuplot")
set(expected_files
  "${stage}/bin/pure.exe"
  "${stage}/bin/libpure.dll"
  "${module_dir}/gplot.dll"
  "${module_dir}/gplot.pure"
  "${gnuplot_root}/bin/gnuplot.exe"
  "${gnuplot_root}/license/Copyright"
  "${doc_dir}/COPYING"
  "${doc_dir}/COPYING.LESSER"
  "${doc_dir}/WINDOWS.md"
  "${doc_dir}/licenses/gnuplot/Copyright"
  "${doc_dir}/examples/gplot_test.pure"
  "${doc_dir}/tests/render.pure"
  "${doc_dir}/tests/missing.pure")
foreach(expected IN LISTS expected_files)
  if(NOT EXISTS "${expected}")
    message(FATAL_ERROR "Missing installed pure-gplot file: ${expected}")
  endif()
endforeach()

foreach(reused IN ITEMS libpure.dll libgmp-10.dll libc++.dll libwinpthread-1.dll)
  set(staged_file "${stage}/bin/${reused}")
  set(source_file "${source_bin}/${reused}")
  if(NOT EXISTS "${staged_file}" OR NOT EXISTS "${source_file}")
    message(FATAL_ERROR "Missing reused runtime: ${reused}")
  endif()
  file(SHA256 "${staged_file}" staged_hash)
  file(SHA256 "${source_file}" source_hash)
  if(NOT staged_hash STREQUAL source_hash)
    message(FATAL_ERROR "Conflicting reused runtime: ${reused}")
  endif()
endforeach()

execute_process(
  COMMAND "${gnuplot_root}/bin/gnuplot.exe" --version
  RESULT_VARIABLE version_result
  OUTPUT_VARIABLE version_output
  ERROR_VARIABLE version_error
  OUTPUT_STRIP_TRAILING_WHITESPACE
  ENCODING UTF-8)
if(NOT "${version_result}" STREQUAL "0" OR
    NOT version_output STREQUAL "gnuplot 6.0 patchlevel 4")
  message(FATAL_ERROR
    "Unexpected staged gnuplot version\n"
    "stdout: ${version_output}\nstderr: ${version_error}")
endif()

set(work_dir "${stage}/Pure Gplot Verification")
file(REMOVE_RECURSE "${work_dir}")
file(MAKE_DIRECTORY "${work_dir}")
set(output_file "${work_dir}/known installed plot.png")
unset(ENV{PURELIB})
unset(ENV{GPLOT_EXE})
set(ENV{PATH} "${module_dir};${stage}/bin;C:/Windows/System32;C:/Windows")
execute_process(
  COMMAND "${stage}/bin/pure.exe" --norc -q
    -I "${module_dir}"
    -L "${module_dir}"
    -x "${doc_dir}/tests/render.pure"
    "${output_file}"
  WORKING_DIRECTORY "${work_dir}"
  RESULT_VARIABLE render_result
  OUTPUT_VARIABLE render_output
  ERROR_VARIABLE render_error
  TIMEOUT 20
  ENCODING UTF-8)
if(NOT "${render_result}" STREQUAL "0")
  message(FATAL_ERROR
    "Installed pure-gplot render failed (${render_result})\n"
    "stdout:\n${render_output}\nstderr:\n${render_error}")
endif()
if(NOT render_output MATCHES "(^|\r?\n)PURE_GPLOT_RENDER_OK(\r?\n|$)")
  message(FATAL_ERROR "Installed render did not emit its success marker")
endif()
if(NOT EXISTS "${output_file}")
  message(FATAL_ERROR "Installed gnuplot did not create ${output_file}")
endif()
file(SIZE "${output_file}" output_size)
file(READ "${output_file}" png_hex HEX LIMIT 24)
string(TOLOWER "${png_hex}" png_hex)
string(SUBSTRING "${png_hex}" 0 16 signature)
string(SUBSTRING "${png_hex}" 32 8 width)
string(SUBSTRING "${png_hex}" 40 8 height)
if(output_size LESS 1024 OR
    NOT signature STREQUAL "89504e470d0a1a0a" OR
    NOT width STREQUAL "00000140" OR
    NOT height STREQUAL "000000c8")
  message(FATAL_ERROR
    "Invalid installed PNG: size=${output_size}, signature=${signature}, "
    "width=${width}, height=${height}")
endif()

set(missing_prefix "${work_dir}/Missing Component Prefix")
set(missing_module_dir "${missing_prefix}/lib/pure")
file(MAKE_DIRECTORY "${missing_module_dir}")
file(COPY
  "${module_dir}/gplot.dll"
  "${module_dir}/gplot.pure"
  DESTINATION "${missing_module_dir}")
set(ENV{PATH}
  "${missing_module_dir};${stage}/bin;C:/Windows/System32;C:/Windows")
execute_process(
  COMMAND "${stage}/bin/pure.exe" --norc -q
    -I "${missing_module_dir}"
    -L "${missing_module_dir}"
    -x "${doc_dir}/tests/missing.pure"
  WORKING_DIRECTORY "${work_dir}"
  RESULT_VARIABLE missing_result
  OUTPUT_VARIABLE missing_output
  ERROR_VARIABLE missing_error
  TIMEOUT 10
  ENCODING UTF-8)
if(NOT "${missing_result}" STREQUAL "0")
  message(FATAL_ERROR
    "Missing-component check failed (${missing_result})\n"
    "stdout:\n${missing_output}\nstderr:\n${missing_error}")
endif()
if(NOT missing_output MATCHES "(^|\r?\n)PURE_GPLOT_MISSING_OK(\r?\n|$)")
  message(FATAL_ERROR "Missing-component check did not emit its marker")
endif()

file(REMOVE_RECURSE "${work_dir}")
list(LENGTH expected_files expected_count)
message(STATUS
  "Verified installed pure-gplot: ${expected_count} package files, "
  "4 hash-matched reused DLLs, bundle-relative gnuplot 6.0.4, relocated "
  "PNG rendering, and no PATH fallback when the optional component is absent")