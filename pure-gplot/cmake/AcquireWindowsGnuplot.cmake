foreach(required IN ITEMS WORK_ROOT INSTALL_ROOT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH WORK_ROOT NORMALIZE OUTPUT_VARIABLE work_root)
cmake_path(ABSOLUTE_PATH INSTALL_ROOT NORMALIZE OUTPUT_VARIABLE install_root)
cmake_path(IS_PREFIX work_root "${install_root}" NORMALIZE install_is_in_work)
if(NOT install_is_in_work OR install_root STREQUAL work_root)
  message(FATAL_ERROR "INSTALL_ROOT must be a child of WORK_ROOT")
endif()

set(version "6.0.4")
set(installer_name "gp604-win64-clang.exe")
set(installer_url
  "https://master.dl.sourceforge.net/project/gnuplot/gnuplot/6.0.4/${installer_name}?viasf=1")
set(installer_sha256
  "2c31e3fc91b21c450f4b015f1cd1f2f84f7a8cfc63afc037f9ba5efb47cc0c23")
set(download_dir "${work_root}/downloads")
set(installer "${download_dir}/${installer_name}")
file(MAKE_DIRECTORY "${download_dir}")

if(EXISTS "${installer}")
  file(SHA256 "${installer}" actual_sha256)
  if(NOT actual_sha256 STREQUAL installer_sha256)
    file(REMOVE "${installer}")
  endif()
endif()
if(NOT EXISTS "${installer}")
  file(DOWNLOAD
    "${installer_url}" "${installer}"
    EXPECTED_HASH "SHA256=${installer_sha256}"
    TLS_VERIFY ON
    SHOW_PROGRESS
    STATUS download_status)
  list(GET download_status 0 download_result)
  list(GET download_status 1 download_message)
  if(NOT download_result EQUAL 0)
    message(FATAL_ERROR
      "Unable to download ${installer_name}: ${download_message}")
  endif()
endif()

if(EXISTS "${install_root}")
  file(REMOVE_RECURSE "${install_root}")
endif()
execute_process(
  COMMAND "${installer}"
    /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /CURRENTUSER
    "/DIR=${install_root}"
  RESULT_VARIABLE install_result
  TIMEOUT 120)
if(NOT "${install_result}" STREQUAL "0")
  message(FATAL_ERROR
    "gnuplot ${version} installer failed (${install_result})")
endif()

set(gnuplot_executable "${install_root}/bin/gnuplot.exe")
execute_process(
  COMMAND "${gnuplot_executable}" --version
  RESULT_VARIABLE version_result
  OUTPUT_VARIABLE version_output
  ERROR_VARIABLE version_error
  OUTPUT_STRIP_TRAILING_WHITESPACE
  ENCODING UTF-8)
if(NOT "${version_result}" STREQUAL "0" OR
    NOT version_output STREQUAL "gnuplot 6.0 patchlevel 4")
  message(FATAL_ERROR
    "Unexpected controlled gnuplot version\n"
    "stdout: ${version_output}\nstderr: ${version_error}")
endif()

message(STATUS
  "Acquired official gnuplot ${version} at ${install_root}; "
  "SHA256=${installer_sha256}")
