cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS MODE PURE_PREFIX TOOLCHAIN_BIN LLVM_READOBJ)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "SDK_RUNTIME_INPUT: ${required} is required")
  endif()
endforeach()
if(NOT MODE STREQUAL "STAGE" AND NOT MODE STREQUAL "VERIFY")
  message(FATAL_ERROR "SDK_RUNTIME_INPUT: MODE must be STAGE or VERIFY")
endif()

if(NOT DEFINED RUNTIME_MANIFEST OR "${RUNTIME_MANIFEST}" STREQUAL "")
  message(FATAL_ERROR "SDK_RUNTIME_INPUT: RUNTIME_MANIFEST is required")
endif()
set(runtime_manifest "${RUNTIME_MANIFEST}")
if(NOT EXISTS "${runtime_manifest}" OR IS_DIRECTORY "${runtime_manifest}")
  message(FATAL_ERROR "SDK_RUNTIME_INPUT: runtime manifest is missing")
endif()
include("${runtime_manifest}")
if(NOT DEFINED pure_windows_runtime_dlls OR
    NOT DEFINED pure_windows_system_dlls)
  message(FATAL_ERROR "SDK_RUNTIME_INPUT: runtime manifest is incomplete")
endif()
if(NOT EXISTS "${LLVM_READOBJ}" OR IS_DIRECTORY "${LLVM_READOBJ}")
  message(FATAL_ERROR "SDK_RUNTIME_INPUT: llvm-readobj is missing")
endif()

file(REAL_PATH "${TOOLCHAIN_BIN}" toolchain_bin)
if(NOT IS_DIRECTORY "${toolchain_bin}")
  message(FATAL_ERROR
    "SDK_RUNTIME_SOURCE: TOOLCHAIN_BIN is not a directory: ${toolchain_bin}")
endif()
file(REAL_PATH "${PURE_PREFIX}" pure_prefix)
set(destination_bin "${pure_prefix}/bin")
if(NOT IS_DIRECTORY "${destination_bin}")
  message(FATAL_ERROR
    "SDK_RUNTIME_DESTINATION: Pure bin directory is missing: ${destination_bin}")
endif()

file(REAL_PATH "${destination_bin}" canonical_destination_bin)
cmake_path(IS_PREFIX pure_prefix "${canonical_destination_bin}" NORMALIZE
  destination_inside_prefix)
if(NOT destination_inside_prefix)
  message(FATAL_ERROR
    "SDK_RUNTIME_ESCAPE: Pure bin directory resolves outside PURE_PREFIX")
endif()

set(expected_names)
foreach(dll IN LISTS pure_windows_runtime_dlls)
  string(TOLOWER "${dll}" dll_lower)
  if(dll_lower IN_LIST expected_names)
    message(FATAL_ERROR "SDK_RUNTIME_DUPLICATE: duplicate allowlist name ${dll}")
  endif()
  list(APPEND expected_names "${dll_lower}")
endforeach()
list(SORT expected_names)

# Derive the recursive non-system closure from both installed Pure SDK roots.
# Resolution is deliberately limited to the installed Pure bin and the
# selected CLANG64 bin; system imports are admitted only by the manifest.
set(queue "${destination_bin}/pure.exe" "${destination_bin}/libpure.dll")
set(visited)
set(reached_names)
while(queue)
  list(POP_FRONT queue owner)
  file(REAL_PATH "${owner}" canonical_owner)
  if(NOT EXISTS "${canonical_owner}" OR IS_DIRECTORY "${canonical_owner}")
    message(FATAL_ERROR "SDK_RUNTIME_ROOT: closure input is missing: ${owner}")
  endif()
  string(TOLOWER "${canonical_owner}" owner_identity)
  if(owner_identity IN_LIST visited)
    continue()
  endif()
  list(APPEND visited "${owner_identity}")

  execute_process(
    COMMAND "${LLVM_READOBJ}" --file-headers --coff-imports "${canonical_owner}"
    RESULT_VARIABLE read_result OUTPUT_VARIABLE listing ERROR_VARIABLE read_error)
  if(NOT read_result EQUAL 0 OR
      NOT listing MATCHES "Format: COFF-x86-64" OR
      NOT listing MATCHES "Arch: x86_64" OR
      NOT listing MATCHES "Machine: IMAGE_FILE_MACHINE_AMD64")
    message(FATAL_ERROR
      "SDK_RUNTIME_FORMAT: invalid x86-64 PE ${owner}: ${read_error}")
  endif()
  get_filename_component(owner_name "${canonical_owner}" NAME)
  string(TOLOWER "${owner_name}" owner_name_lower)
  if(NOT owner_name_lower STREQUAL "pure.exe" AND
      NOT listing MATCHES "IMAGE_FILE_DLL")
    message(FATAL_ERROR "SDK_RUNTIME_FORMAT: ${owner_name} is not a DLL")
  endif()

  string(REGEX MATCHALL "  Name: [A-Za-z0-9_.+-]+\\.[Dd][Ll][Ll]" import_lines
    "${listing}")
  foreach(import_line IN LISTS import_lines)
    string(REGEX REPLACE "^  Name: " "" import_name "${import_line}")
    string(TOLOWER "${import_name}" import_lower)
    if(import_lower IN_LIST pure_windows_system_dlls)
      continue()
    endif()
    if(import_lower STREQUAL "libpure.dll")
      set(import_path "${destination_bin}/libpure.dll")
    else()
      if(NOT import_lower IN_LIST expected_names)
        message(FATAL_ERROR
          "SDK_RUNTIME_CLOSURE: unmanifested import ${import_name} from ${owner_name}")
      endif()
      if(NOT import_lower IN_LIST reached_names)
        list(APPEND reached_names "${import_lower}")
      endif()
      set(import_path "${toolchain_bin}/${import_name}")
    endif()
    list(APPEND queue "${import_path}")
  endforeach()
endwhile()
list(SORT reached_names)
if(NOT reached_names STREQUAL expected_names)
  message(FATAL_ERROR
    "SDK_RUNTIME_CLOSURE: reached=[${reached_names}] expected=[${expected_names}]")
endif()

set(casefolded_names)
foreach(dll IN LISTS pure_windows_runtime_dlls)
  string(TOLOWER "${dll}" casefolded)
  if(casefolded IN_LIST casefolded_names)
    message(FATAL_ERROR "SDK_RUNTIME_DUPLICATE: duplicate allowlist name ${dll}")
  endif()
  list(APPEND casefolded_names "${casefolded}")

  set(source "${toolchain_bin}/${dll}")
  if(NOT EXISTS "${source}" OR IS_DIRECTORY "${source}")
    message(FATAL_ERROR "SDK_RUNTIME_SOURCE: required DLL is missing: ${dll}")
  endif()
  file(REAL_PATH "${source}" resolved_source)
  cmake_path(GET resolved_source PARENT_PATH resolved_parent)
  if(NOT resolved_parent STREQUAL toolchain_bin)
    message(FATAL_ERROR
      "SDK_RUNTIME_ESCAPE: ${dll} resolves outside TOOLCHAIN_BIN")
  endif()
  file(READ "${resolved_source}" pe_magic OFFSET 0 LIMIT 2 HEX)
  string(TOLOWER "${pe_magic}" pe_magic)
  if(NOT pe_magic STREQUAL "4d5a")
    message(FATAL_ERROR "SDK_RUNTIME_FORMAT: ${dll} lacks the PE MZ signature")
  endif()

  set(destination "${destination_bin}/${dll}")
  if(EXISTS "${destination}")
    file(REAL_PATH "${destination}" canonical_destination)
    cmake_path(IS_PREFIX canonical_destination_bin "${canonical_destination}"
      NORMALIZE destination_inside_bin)
    if(NOT destination_inside_bin)
      message(FATAL_ERROR
        "SDK_RUNTIME_ESCAPE: staged path resolves outside Pure bin: ${dll}")
    endif()
  endif()
  if(MODE STREQUAL "STAGE")
    execute_process(
      COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${resolved_source}" "${destination}"
      RESULT_VARIABLE copy_result ERROR_VARIABLE copy_error)
    if(NOT copy_result EQUAL 0)
      message(FATAL_ERROR
        "SDK_RUNTIME_COPY: failed to stage ${dll}: ${copy_error}")
    endif()
  endif()
  if(NOT EXISTS "${destination}" OR IS_DIRECTORY "${destination}")
    message(FATAL_ERROR "SDK_RUNTIME_MISSING: staged DLL is missing: ${dll}")
  endif()
  file(REAL_PATH "${destination}" canonical_destination)
  cmake_path(IS_PREFIX canonical_destination_bin "${canonical_destination}"
    NORMALIZE destination_inside_bin)
  if(NOT destination_inside_bin)
    message(FATAL_ERROR
      "SDK_RUNTIME_ESCAPE: staged path escaped Pure bin after copy: ${dll}")
  endif()
  file(SHA256 "${resolved_source}" source_hash)
  file(SHA256 "${destination}" destination_hash)
  if(NOT destination_hash STREQUAL source_hash)
    message(FATAL_ERROR "SDK_RUNTIME_HASH: staged DLL differs: ${dll}")
  endif()
endforeach()

list(LENGTH pure_windows_runtime_dlls runtime_dll_count)
message(STATUS
  "Pure Windows SDK runtime closure ${MODE}: ${runtime_dll_count} exact DLLs")
