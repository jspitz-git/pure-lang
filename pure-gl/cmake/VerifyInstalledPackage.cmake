foreach(required IN ITEMS
    STAGE_PREFIX SOURCE_RUNTIME_DIR LLVM_READOBJ LLVM_STRINGS)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE stage)
cmake_path(ABSOLUTE_PATH SOURCE_RUNTIME_DIR NORMALIZE OUTPUT_VARIABLE source_bin)
set(module_dir "${stage}/lib/pure")
set(doc_dir "${stage}/share/doc/pure-gl")

set(expected_files
  "${module_dir}/pure-gl.dll"
  "${module_dir}/GL.pure"
  "${module_dir}/GL_ARB.pure"
  "${module_dir}/GL_EXT.pure"
  "${module_dir}/GL_NV.pure"
  "${module_dir}/GL_ATI.pure"
  "${module_dir}/GLU.pure"
  "${module_dir}/GLUT.pure"
  "${stage}/bin/libfreeglut.dll"
  "${doc_dir}/README"
  "${doc_dir}/COPYING"
  "${doc_dir}/WINDOWS.md"
  "${doc_dir}/THIRD_PARTY.md"
  "${doc_dir}/licenses/FreeGLUT.txt"
  "${doc_dir}/examples/simple_glut_example.pure"
  "${doc_dir}/examples/teapot.pure"
  "${doc_dir}/examples/texture.pure"
  "${doc_dir}/examples/Imlib2.pure"
  "${doc_dir}/examples/fractal.jpg"
  "${doc_dir}/examples/flexi-line/vector_math.pure"
  "${doc_dir}/examples/flexi-line/glamour.pure"
  "${doc_dir}/examples/flexi-line/flexi-line.pure"
  "${doc_dir}/examples/flexi-line/flexi-line-auto.pure"
  "${doc_dir}/tests/load.pure"
  "${doc_dir}/tests/hidden-render.pure"
  "${doc_dir}/tests/interactive.pure")
foreach(expected IN LISTS expected_files)
  if(NOT EXISTS "${expected}")
    message(FATAL_ERROR "Missing installed pure-gl file: ${expected}")
  endif()
endforeach()

foreach(system_dll IN ITEMS
    opengl32.dll glu32.dll gdi32.dll user32.dll winmm.dll)
  if(EXISTS "${stage}/bin/${system_dll}")
    message(FATAL_ERROR "Windows system DLL must not be bundled: ${system_dll}")
  endif()
endforeach()

file(SHA256 "${stage}/bin/libfreeglut.dll" staged_hash)
file(SHA256 "${source_bin}/libfreeglut.dll" source_hash)
if(NOT staged_hash STREQUAL source_hash)
  message(FATAL_ERROR "Staged FreeGLUT runtime hash mismatch")
endif()

set(ENV{PATH} "${stage}/bin;C:/Windows/System32;C:/Windows")
set(ENV{PURELIB} "")
foreach(test_name IN ITEMS load hidden-render)
  execute_process(
    COMMAND "${stage}/bin/pure.exe" --norc
      -I "${module_dir}" -L "${module_dir}"
      -x "${doc_dir}/tests/${test_name}.pure"
    WORKING_DIRECTORY "${stage}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    TIMEOUT 60
    ENCODING UTF-8)
  if(NOT result EQUAL 0 OR NOT error STREQUAL "")
    message(FATAL_ERROR
      "Installed pure-gl ${test_name} test failed (${result})\n"
      "stdout:\n${output}\nstderr:\n${error}")
  endif()
endforeach()

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    "-DLLVM_STRINGS=${LLVM_STRINGS}"
    "-DPURE_GL_MODULE=${module_dir}/pure-gl.dll"
    "-DFREEGLUT_DLL=${stage}/bin/libfreeglut.dll"
    -P "${CMAKE_CURRENT_LIST_DIR}/VerifyWindowsDependencies.cmake"
  RESULT_VARIABLE audit_result
  OUTPUT_VARIABLE audit_output
  ERROR_VARIABLE audit_error
  ENCODING UTF-8)
if(NOT audit_result EQUAL 0)
  message(FATAL_ERROR
    "Installed pure-gl PE audit failed (${audit_result})\n"
    "stdout:\n${audit_output}\nstderr:\n${audit_error}")
endif()

list(LENGTH expected_files expected_count)
message(STATUS
  "Verified installed pure-gl: ${expected_count} package files, "
  "hash-matched FreeGLUT runtime, 2 sanitized tests, and staged PE closure")
