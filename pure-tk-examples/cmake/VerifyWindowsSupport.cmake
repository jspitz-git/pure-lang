foreach(required IN ITEMS STAGE_PREFIX SOURCE_DIR)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH STAGE_PREFIX NORMALIZE OUTPUT_VARIABLE stage)
cmake_path(ABSOLUTE_PATH SOURCE_DIR NORMALIZE OUTPUT_VARIABLE source)
set(module_dir "${stage}/lib/pure")
set(work_dir "${stage}/Pure Tk Examples Verification")

set(required_stage_files
  "${stage}/bin/pure.exe"
  "${stage}/bin/tcl86.dll"
  "${stage}/bin/tk86.dll"
  "${module_dir}/tk.dll"
  "${module_dir}/tk.pure")
foreach(required_file IN LISTS required_stage_files)
  if(NOT EXISTS "${required_file}")
    message(FATAL_ERROR "Missing staged pure-tk file: ${required_file}")
  endif()
endforeach()

set(required_source_files
  "${source}/WINDOWS.md"
  "${source}/tests/windows-dependency-probe.pure"
  "${source}/graphedit/graphedit.pure"
  "${source}/graphedit/graphedit.tcl"
  "${source}/graphedit/examples/sample1.graph"
  "${source}/pong/pong.pure"
  "${source}/pong/pong.tcl"
  "${source}/pong/pong.png"
  "${source}/scale/scale.pure"
  "${source}/scale/scale.tcl"
  "${source}/scale/scale.m"
  "${source}/scale/intnam.par"
  "${source}/scale/scl/12tone.scl")
foreach(required_file IN LISTS required_source_files)
  if(NOT EXISTS "${required_file}")
    message(FATAL_ERROR
      "Incomplete pure-tk-examples source inventory: ${required_file}")
  endif()
endforeach()

if(EXISTS "${module_dir}/octave.pure" OR EXISTS "${module_dir}/octave.dll")
  message(FATAL_ERROR
    "Pure Octave is now staged; revisit the deferred scale classification")
endif()

file(REMOVE_RECURSE "${work_dir}")
file(MAKE_DIRECTORY "${work_dir}")
unset(ENV{PURELIB})
unset(ENV{TCL_LIBRARY})
unset(ENV{TK_LIBRARY})
unset(ENV{TCLLIBPATH})
set(ENV{PATH} "${stage}/bin;C:/Windows/System32;C:/Windows")

execute_process(
  COMMAND "${stage}/bin/pure.exe" --norc -q
    -I "${module_dir}"
    -L "${module_dir}"
    -x "${source}/tests/windows-dependency-probe.pure"
  WORKING_DIRECTORY "${work_dir}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
  TIMEOUT 30
  ENCODING UTF-8)
file(REMOVE_RECURSE "${work_dir}")

if(NOT result EQUAL 0)
  message(FATAL_ERROR
    "pure-tk-examples dependency probe failed (${result})\n"
    "stdout:\n${output}\nstderr:\n${error}")
endif()
if(NOT error STREQUAL "")
  message(FATAL_ERROR
    "pure-tk-examples dependency probe emitted stderr\n"
    "stdout:\n${output}\nstderr:\n${error}")
endif()
if(NOT output MATCHES
    "(^|\r?\n)PURE_TK_EXAMPLES_DEFERRED_OK(\r?\n|$)")
  message(FATAL_ERROR
    "pure-tk-examples dependency probe did not confirm deferred support\n"
    "stdout:\n${output}")
endif()

message(STATUS
  "Verified pure-tk-examples Windows classification: 0 shippable "
  "applications; Gnocl, GnoclCanvas, vtk, and vtkinteraction Tcl packages "
  "are unavailable in the staged runtime")
