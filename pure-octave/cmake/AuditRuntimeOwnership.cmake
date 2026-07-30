foreach (required_variable
    OBJDUMP LOADER IMPLEMENTATION PURE_LIBRARY PURE_RUNTIME_DIR
    OCTAVE_RUNTIME_DIR)
  if (NOT DEFINED ${required_variable} OR "${${required_variable}}" STREQUAL "")
    message(FATAL_ERROR
      "${required_variable} is required for the runtime ownership audit.")
  endif ()
endforeach ()

function (read_pe_imports binary owner output_variable)
  if (NOT EXISTS "${binary}")
    message(FATAL_ERROR "${owner} binary is missing: ${binary}")
  endif ()
  execute_process(
    COMMAND "${OBJDUMP}" -p "${binary}"
    RESULT_VARIABLE objdump_result
    OUTPUT_VARIABLE objdump_output
    ERROR_VARIABLE objdump_stderr)
  if (NOT objdump_result EQUAL 0)
    message(FATAL_ERROR
      "Could not inspect ${owner} binary ${binary}:\n${objdump_stderr}")
  endif ()

  string(REGEX MATCHALL "DLL Name:[ \t]*[^\r\n]+" import_lines
    "${objdump_output}")
  set(imports)
  foreach (import_line IN LISTS import_lines)
    string(REGEX REPLACE "^DLL Name:[ \t]*" "" import_name "${import_line}")
    string(STRIP "${import_name}" import_name)
    string(TOLOWER "${import_name}" import_name)
    list(APPEND imports "${import_name}")
  endforeach ()
  if (NOT imports)
    message(FATAL_ERROR "${owner} binary has no readable PE imports: ${binary}")
  endif ()
  set(${output_variable} "${imports}" PARENT_SCOPE)
endfunction ()

function (require_import imports_variable import_name owner)
  string(TOLOWER "${import_name}" import_name_lower)
  list(FIND ${imports_variable} "${import_name_lower}" import_index)
  if (import_index EQUAL -1)
    message(FATAL_ERROR "${owner} must import ${import_name}.")
  endif ()
endfunction ()

function (forbid_import imports_variable import_name owner)
  string(TOLOWER "${import_name}" import_name_lower)
  list(FIND ${imports_variable} "${import_name_lower}" import_index)
  if (NOT import_index EQUAL -1)
    message(FATAL_ERROR "${owner} must not import ${import_name}.")
  endif ()
endfunction ()

function (forbid_octave_family imports_variable owner)
  foreach (import_name IN LISTS ${imports_variable})
    if (import_name MATCHES "^liboctave(-[0-9]+)?[.]dll$" OR
        import_name MATCHES "^liboctinterp(-[0-9]+)?[.]dll$")
      message(FATAL_ERROR
        "${owner} must not import Octave runtime ${import_name}.")
    endif ()
  endforeach ()
endfunction ()

function (require_pinned_octave_family imports_variable family expected owner)
  foreach (import_name IN LISTS ${imports_variable})
    if (import_name MATCHES "^${family}(-[0-9]+)?[.]dll$" AND
        NOT import_name STREQUAL "${expected}")
      message(FATAL_ERROR
        "${owner} imported unpinned ${family} runtime ${import_name}; "
        "expected ${expected}.")
    endif ()
  endforeach ()
  require_import(${imports_variable} "${expected}" "${owner}")
endfunction ()

function (require_controlled_file path owner)
  if (NOT EXISTS "${path}")
    message(FATAL_ERROR "Controlled ${owner} DLL is missing: ${path}")
  endif ()
endfunction ()

# This audit is tied to the Task 1 Octave 11.3.0 ABI and its versioned DLLs.
set(octave_core_name "liboctave-13.dll")
set(octave_interpreter_name "liboctinterp-15.dll")

require_controlled_file("${PURE_RUNTIME_DIR}/libpure.dll" "Pure")
require_controlled_file("${PURE_RUNTIME_DIR}/libc++.dll" "Pure C++ runtime")
require_controlled_file(
  "${OCTAVE_RUNTIME_DIR}/libgcc_s_seh-1.dll" "Octave GCC runtime")
require_controlled_file(
  "${OCTAVE_RUNTIME_DIR}/libstdc++-6.dll" "Octave C++ runtime")
require_controlled_file(
  "${OCTAVE_RUNTIME_DIR}/${octave_core_name}" "Octave core")
require_controlled_file(
  "${OCTAVE_RUNTIME_DIR}/${octave_interpreter_name}" "Octave interpreter")

read_pe_imports("${LOADER}" "Stable loader" loader_imports)
foreach (forbidden_import IN ITEMS
    libpure.dll libgcc_s_seh-1.dll libstdc++-6.dll libc++.dll)
  forbid_import(loader_imports "${forbidden_import}" "Stable loader")
endforeach ()
forbid_octave_family(loader_imports "Stable loader")

read_pe_imports("${IMPLEMENTATION}" "Bridge implementation" bridge_imports)
require_import(bridge_imports "libpure.dll" "Bridge implementation")
require_import(
  bridge_imports "libgcc_s_seh-1.dll" "Bridge implementation")
require_import(bridge_imports "libstdc++-6.dll" "Bridge implementation")
require_pinned_octave_family(
  bridge_imports "liboctave" "${octave_core_name}" "Bridge implementation")
require_pinned_octave_family(
  bridge_imports "liboctinterp" "${octave_interpreter_name}"
  "Bridge implementation")
forbid_import(bridge_imports "libc++.dll" "Bridge implementation")

read_pe_imports("${PURE_LIBRARY}" "Pure runtime" pure_imports)
require_import(pure_imports "libc++.dll" "Pure runtime")
forbid_import(pure_imports "libstdc++-6.dll" "Pure runtime")
forbid_import(pure_imports "libgcc_s_seh-1.dll" "Pure runtime")

read_pe_imports(
  "${OCTAVE_RUNTIME_DIR}/${octave_core_name}" "Octave core" octave_core_imports)
require_import(octave_core_imports "libstdc++-6.dll" "Octave core")
forbid_import(octave_core_imports "libc++.dll" "Octave core")

read_pe_imports(
  "${OCTAVE_RUNTIME_DIR}/${octave_interpreter_name}"
  "Octave interpreter" octave_interpreter_imports)
require_import(
  octave_interpreter_imports "libstdc++-6.dll" "Octave interpreter")
forbid_import(octave_interpreter_imports "libc++.dll" "Octave interpreter")
