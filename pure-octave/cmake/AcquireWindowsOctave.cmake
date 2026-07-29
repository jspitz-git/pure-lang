include_guard(GLOBAL)
include("${CMAKE_CURRENT_LIST_DIR}/ExtractionContainment.cmake")

function(_pure_octave_download_and_verify archive_url signature_url archive_path signature_path
    gpg_executable gnupg_home signing_key fingerprint_output)
  if (EXISTS "${archive_path}.complete")
    set(archive_status 0 "reusing completed download")
  else ()
    file(DOWNLOAD "${archive_url}" "${archive_path}" STATUS archive_status SHOW_PROGRESS INACTIVITY_TIMEOUT 120)
  endif ()
  list(GET archive_status 0 archive_status_code)
  list(GET archive_status 1 archive_status_message)
  if (NOT archive_status_code EQUAL 0)
    message(FATAL_ERROR "Failed to download ${archive_url}: ${archive_status_message}")
  endif ()
  if (NOT EXISTS "${archive_path}.complete")
    file(WRITE "${archive_path}.complete" "${archive_url}\n")
  endif ()
  if (EXISTS "${signature_path}.complete")
    set(signature_status 0 "reusing completed download")
  else ()
    file(DOWNLOAD "${signature_url}" "${signature_path}" STATUS signature_status SHOW_PROGRESS INACTIVITY_TIMEOUT 120)
  endif ()
  list(GET signature_status 0 signature_status_code)
  list(GET signature_status 1 signature_status_message)
  if (NOT signature_status_code EQUAL 0)
    message(FATAL_ERROR "Failed to download ${signature_url}: ${signature_status_message}")
  endif ()
  if (NOT EXISTS "${signature_path}.complete")
    file(WRITE "${signature_path}.complete" "${signature_url}\n")
  endif ()

  set(gpg_home_arg "${gnupg_home}")
  set(archive_arg "${archive_path}")
  set(signature_arg "${signature_path}")
  if (gpg_executable MATCHES "[/\\\\]msys64[/\\\\]")
    get_filename_component(gpg_directory "${gpg_executable}" DIRECTORY)
    set(cygpath_executable "${gpg_directory}/cygpath.exe")
    if (NOT EXISTS "${cygpath_executable}")
      message(FATAL_ERROR "MSYS GnuPG requires cygpath beside ${gpg_executable}.")
    endif ()
    foreach (path_variable gpg_home_arg archive_arg signature_arg)
      execute_process(COMMAND "${cygpath_executable}" -u "${${path_variable}}"
        RESULT_VARIABLE cygpath_result OUTPUT_VARIABLE cygpath_output)
      if (NOT cygpath_result EQUAL 0)
        message(FATAL_ERROR "Could not convert ${${path_variable}} for MSYS GnuPG.")
      endif ()
      string(STRIP "${cygpath_output}" ${path_variable})
    endforeach ()
  endif ()

  execute_process(
    COMMAND "${gpg_executable}" --batch --homedir "${gpg_home_arg}"
      --keyserver hkps://keyserver.ubuntu.com --recv-keys "${signing_key}"
    TIMEOUT 60
    RESULT_VARIABLE key_result
    OUTPUT_VARIABLE key_stdout
    ERROR_VARIABLE key_stderr)
  if (NOT key_result EQUAL 0)
    message(FATAL_ERROR "Failed to import signing key ${signing_key} into ${gnupg_home}:\n${key_stdout}${key_stderr}")
  endif ()
  execute_process(
    COMMAND "${gpg_executable}" --batch --homedir "${gpg_home_arg}" --with-colons --list-keys "${signing_key}"
    RESULT_VARIABLE listed_key_result
    OUTPUT_VARIABLE listed_keys
    ERROR_VARIABLE listed_keys_stderr)
  if (NOT listed_key_result EQUAL 0 OR NOT listed_keys MATCHES "fpr:::::::::([0-9A-F]*${signing_key}):")
    message(FATAL_ERROR "The imported keyring does not contain primary fingerprint ending in ${signing_key}:\n${listed_keys}${listed_keys_stderr}")
  endif ()


  execute_process(
    COMMAND "${gpg_executable}" --batch --homedir "${gpg_home_arg}" --status-fd 1
      --verify "${signature_arg}" "${archive_arg}"
    RESULT_VARIABLE verify_result
    OUTPUT_VARIABLE verify_status
    ERROR_VARIABLE verify_stderr)
  if (NOT verify_result EQUAL 0)
    message(FATAL_ERROR "Detached signature verification failed for ${archive_path}:\n${verify_status}${verify_stderr}")
  endif ()
  string(REPLACE "\r\n" "\n" gpg_status_lines "${verify_status}")
  string(REPLACE "\n" ";" gpg_status_lines "${gpg_status_lines}")
  set(validsig_line "")
  foreach (status_line IN LISTS gpg_status_lines)
    if (status_line MATCHES "^\\[GNUPG:\\] VALIDSIG ")
      set(validsig_line "${status_line}")
      break ()
    endif ()
  endforeach ()
  if (NOT validsig_line)
    message(FATAL_ERROR "GnuPG did not report VALIDSIG for ${archive_path}:\n${verify_status}${verify_stderr}")
  endif ()
  string(REGEX REPLACE "^\\[GNUPG:\\] VALIDSIG " "" validsig_fields "${validsig_line}")
  string(STRIP "${validsig_fields}" validsig_fields)
  string(REPLACE " " ";" validsig_fields "${validsig_fields}")
  list(LENGTH validsig_fields validsig_field_count)
  if (validsig_field_count LESS 10)
    message(FATAL_ERROR "GnuPG VALIDSIG did not report a primary-key fingerprint: ${validsig_line}")
  endif ()
  list(GET validsig_fields 9 primary_fingerprint)
  if (NOT primary_fingerprint MATCHES "${signing_key}$")
    message(FATAL_ERROR "Signature primary-key fingerprint ${primary_fingerprint} does not end in ${signing_key}.")
  endif ()
  set(${fingerprint_output} "${primary_fingerprint}" PARENT_SCOPE)
endfunction ()

function(_pure_octave_validate_archive_paths archive_path work_root)
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar tf "${archive_path}"
    RESULT_VARIABLE list_result
    OUTPUT_VARIABLE archive_paths
    ERROR_VARIABLE list_stderr)
  if (NOT list_result EQUAL 0)
    set(PURE_OCTAVE_ARCHIVE_LIST_FAILED TRUE PARENT_SCOPE)
    return ()
  endif ()
  string(REPLACE "\n" ";" archive_paths "${archive_paths}")
  foreach (archive_path_entry IN LISTS archive_paths)
    if (archive_path_entry MATCHES "^/" OR archive_path_entry MATCHES "^[A-Za-z]:" OR
        archive_path_entry MATCHES "(^|/)\\.\\.(/|$)")
      message(FATAL_ERROR "Signed archive contains an unsafe extraction path: ${archive_path_entry}")
    endif ()
  endforeach ()
  set(PURE_OCTAVE_ARCHIVE_LIST_FAILED FALSE PARENT_SCOPE)
endfunction ()

function(acquire_windows_octave output_root)
  set(options)
  set(one_value_args WORK_ROOT GPG_EXECUTABLE)
  cmake_parse_arguments(ARG "${options}" "${one_value_args}" "" ${ARGN})

  set(octave_version "11.3.0")
  set(archive_name "octave-11.3.0-w64.7z")
  set(archive_url
    "https://ftpmirror.gnu.org/octave/windows/${archive_name}")
  set(signature_url "${archive_url}.sig")
  set(signing_key "B05F05B75D36644B")

  if (NOT ARG_WORK_ROOT)
    message(FATAL_ERROR "WORK_ROOT is required for signed Octave acquisition.")
  endif ()
  cmake_path(ABSOLUTE_PATH ARG_WORK_ROOT BASE_DIRECTORY "${CMAKE_BINARY_DIR}" NORMALIZE OUTPUT_VARIABLE work_root)
  file(MAKE_DIRECTORY "${work_root}/downloads" "${work_root}/gnupg" "${work_root}/octave-${octave_version}")
  if (NOT ARG_GPG_EXECUTABLE)
    find_program(ARG_GPG_EXECUTABLE NAMES gpg gpg.exe REQUIRED)
  endif ()

  set(archive_path "${work_root}/downloads/${archive_name}")
  set(signature_path "${archive_path}.sig")
  _pure_octave_download_and_verify("${archive_url}" "${signature_url}" "${archive_path}" "${signature_path}"
    "${ARG_GPG_EXECUTABLE}" "${work_root}/gnupg" "${signing_key}" signing_fingerprint)
  _pure_octave_validate_archive_paths("${archive_path}" "${work_root}")

  set(extract_root "${work_root}/octave-${octave_version}")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar xf "${archive_path}"
    WORKING_DIRECTORY "${extract_root}"
    RESULT_VARIABLE extract_result
    OUTPUT_VARIABLE extract_stdout
    ERROR_VARIABLE extract_stderr)
  if (NOT extract_result EQUAL 0 OR PURE_OCTAVE_ARCHIVE_LIST_FAILED)
    set(archive_name "octave-11.3.0-w64.zip")
    set(archive_url "https://ftpmirror.gnu.org/octave/windows/${archive_name}")
    set(signature_url "${archive_url}.sig")
    set(archive_path "${work_root}/downloads/${archive_name}")
    set(signature_path "${archive_path}.sig")
    _pure_octave_download_and_verify("${archive_url}" "${signature_url}" "${archive_path}" "${signature_path}"
      "${ARG_GPG_EXECUTABLE}" "${work_root}/gnupg" "${signing_key}" signing_fingerprint)
    _pure_octave_validate_archive_paths("${archive_path}" "${work_root}")
    execute_process(
      COMMAND "${CMAKE_COMMAND}" -E tar xf "${archive_path}"
      WORKING_DIRECTORY "${extract_root}"
      RESULT_VARIABLE extract_result
      OUTPUT_VARIABLE extract_stdout
      ERROR_VARIABLE extract_stderr)
    set(OCTAVE_ARCHIVE_FORMAT "zip" CACHE STRING "Verified Octave archive format" FORCE)
  else ()
    set(OCTAVE_ARCHIVE_FORMAT "7z" CACHE STRING "Verified Octave archive format" FORCE)
  endif ()
  if (NOT extract_result EQUAL 0)
    message(FATAL_ERROR "Failed to extract signed Octave archive: ${extract_stdout}${extract_stderr}")
  endif ()
  _pure_octave_validate_extraction_containment("${extract_root}" "${work_root}")

  # _pure_octave_validate_archive_paths rejects absolute and traversal paths before extraction.
  file(GLOB extracted_roots LIST_DIRECTORIES TRUE "${extract_root}/*")
  list(LENGTH extracted_roots extracted_root_count)
  if (extracted_root_count EQUAL 1)
    list(GET extracted_roots 0 discovered_root)
  else ()
    set(discovered_root "${extract_root}")
  endif ()
  set(OCTAVE_SIGNING_FINGERPRINT "${signing_fingerprint}" CACHE STRING
    "Primary fingerprint used to verify the Octave archive" FORCE)
  set(${output_root} "${discovered_root}" PARENT_SCOPE)
endfunction ()
