cmake_minimum_required(VERSION 3.25)

if(NOT DEFINED WORKFLOW OR NOT EXISTS "${WORKFLOW}")
  message(FATAL_ERROR "CI_CONTRACT_INPUT: WORKFLOW must name an existing file")
endif()

file(READ "${WORKFLOW}" workflow)
foreach(required IN ITEMS
    "pure-fastcgi/**"
    "windows-pure-fastcgi:"
    "FastCGI-Archives/fcgi2/archive/refs/tags/2.4.7.tar.gz"
    "47f2c03b7771f0ef61d887734ef91e6fa747f837"
    "263969"
    "e41ddc3a473b555bdc0cbd80703dcb1f4610c1a7700d3b9d3d0c14a416e1074b"
    "FetchFcgi2.cmake"
    "pure_fastcgi_fetch_fcgi2"
    "-G Ninja"
    "C:/msys64/clang64/bin/clang.exe"
    "ctest.exe --test-dir"
    "-L fastcgi"
    "--component PureFastCGI"
    "VerifyInstalledPackage.cmake"
    "Collections.Generic.Queue[string]"
    "DLLName:\\s*"
    "recursive PE import closure is empty"
    "RUN_RUNTIME_TESTS=ON"
    "2000-01-01T00:00:00+00:00"
    "windows-pure-fastcgi.zip"
    "actions/upload-artifact@v4")
  string(FIND "${workflow}" "${required}" position)
  if(position EQUAL -1)
    message(FATAL_ERROR
      "CI_CONTRACT_MISSING: workflow is missing PureFastCGI contract: ${required}")
  endif()
endforeach()

# The deterministic archive must be generated twice and compared before upload.
foreach(required IN ITEMS
    "windows-pure-fastcgi-first.zip"
    "windows-pure-fastcgi-second.zip"
    "deterministic ZIP hashes differ")
  string(FIND "${workflow}" "${required}" position)
  if(position EQUAL -1)
    message(FATAL_ERROR
      "CI_CONTRACT_MISSING: workflow is missing reproducibility check: ${required}")
  endif()
endforeach()
