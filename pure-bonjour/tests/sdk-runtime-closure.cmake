cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS STAGER TEST_ROOT LLVM_READOBJ TOOLCHAIN_BIN
    PURE_RUNTIME_BIN PRODUCTION_MANIFEST)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "SDK_RUNTIME_FIXTURE: ${required} is required")
  endif()
endforeach()

set(runtime_dlls
  libc++.dll
  libgmp-10.dll
  libiconv-2.dll
  libmpfr-6.dll
  libpcre-1.dll
  libpcreposix-0.dll
  libreadline8.dll
  libtermcap-0.dll
  libwinpthread-1.dll
  libzstd.dll
  zlib1.dll)

set(source "${TEST_ROOT}/toolchain/bin")
set(prefix "${TEST_ROOT}/Pure SDK prefix")
set(manifest "${TEST_ROOT}/PureWindowsRuntimeClosure.cmake")
file(REMOVE_RECURSE "${TEST_ROOT}")
file(MAKE_DIRECTORY "${source}" "${prefix}/bin")
file(COPY_FILE "${PURE_RUNTIME_BIN}/pure.exe" "${prefix}/bin/pure.exe")
file(COPY_FILE "${PURE_RUNTIME_BIN}/libpure.dll" "${prefix}/bin/libpure.dll")
foreach(dll IN LISTS runtime_dlls)
  file(COPY_FILE "${TOOLCHAIN_BIN}/${dll}" "${source}/${dll}")
endforeach()
file(COPY_FILE "${TOOLCHAIN_BIN}/libffi-8.dll" "${source}/libffi-8.dll")
include("${PRODUCTION_MANIFEST}")
set(system_dlls "${pure_windows_system_dlls}")
file(WRITE "${manifest}" "set(pure_windows_runtime_dlls\n")
foreach(dll IN LISTS runtime_dlls)
  file(APPEND "${manifest}" "  ${dll}\n")
endforeach()
file(APPEND "${manifest}" ")\n")
file(APPEND "${manifest}" "set(pure_windows_system_dlls\n")
foreach(dll IN LISTS system_dlls)
  file(APPEND "${manifest}" "  ${dll}\n")
endforeach()
file(APPEND "${manifest}" ")\n")

function(run_stager mode expected_result expected_category)
  execute_process(
    COMMAND "${CMAKE_COMMAND}"
      "-DMODE=${mode}"
      "-DPURE_PREFIX=${prefix}"
      "-DTOOLCHAIN_BIN=${source}"
      "-DLLVM_READOBJ=${LLVM_READOBJ}"
      "-DRUNTIME_MANIFEST=${manifest}"
      -P "${STAGER}"
    RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
  if(expected_result STREQUAL "pass")
    if(NOT result EQUAL 0)
      message(FATAL_ERROR
        "SDK_RUNTIME_FIXTURE: ${mode} should pass: ${output}${error}")
    endif()
  elseif(result EQUAL 0 OR NOT "${output}${error}" MATCHES
      "SDK_RUNTIME_${expected_category}")
    message(FATAL_ERROR
      "SDK_RUNTIME_FIXTURE: ${mode} should fail as ${expected_category}: "
      "exit=${result} output=[${output}${error}]")
  endif()
endfunction()

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    -DMODE=STAGE
    "-DPURE_PREFIX=${prefix}"
    "-DTOOLCHAIN_BIN=${source}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    -DRUNTIME_MANIFEST=relative-manifest.cmake
    -P "${STAGER}"
  RESULT_VARIABLE relative_result OUTPUT_VARIABLE relative_output
  ERROR_VARIABLE relative_error)
if(relative_result EQUAL 0 OR NOT "${relative_output}${relative_error}" MATCHES
    "SDK_RUNTIME_INPUT: RUNTIME_MANIFEST must be absolute")
  message(FATAL_ERROR
    "SDK_RUNTIME_FIXTURE: relative manifest was not rejected explicitly")
endif()

run_stager(STAGE pass "")

file(GLOB staged RELATIVE "${prefix}/bin" "${prefix}/bin/*.dll")
list(REMOVE_ITEM staged libpure.dll)
list(SORT staged)
set(expected "${runtime_dlls}")
list(SORT expected)
if(NOT staged STREQUAL expected)
  message(FATAL_ERROR
    "SDK_RUNTIME_FIXTURE: staged DLL set differs: [${staged}]")
endif()

file(APPEND "${manifest}"
  "list(APPEND pure_windows_runtime_dlls libffi-8.dll)\n")
run_stager(STAGE fail CLOSURE)
file(WRITE "${manifest}" "set(pure_windows_runtime_dlls\n")
foreach(dll IN LISTS runtime_dlls)
  file(APPEND "${manifest}" "  ${dll}\n")
endforeach()
file(APPEND "${manifest}" ")\n")
file(APPEND "${manifest}" "set(pure_windows_system_dlls\n")
foreach(dll IN LISTS system_dlls)
  file(APPEND "${manifest}" "  ${dll}\n")
endforeach()
file(APPEND "${manifest}" ")\n")

file(REMOVE "${prefix}/bin/libmpfr-6.dll")
run_stager(VERIFY fail MISSING)

run_stager(STAGE pass "")
file(APPEND "${prefix}/bin/libmpfr-6.dll" "corruption")
run_stager(VERIFY fail HASH)

set(ordinary_prefix "${prefix}")
set(outside_bin "${TEST_ROOT}/outside-bin")
set(junction_prefix "${TEST_ROOT}/Junction SDK prefix")
file(MAKE_DIRECTORY "${outside_bin}" "${junction_prefix}")
file(WRITE "${outside_bin}/sentinel.txt" "outside sentinel\n")
file(SHA256 "${outside_bin}/sentinel.txt" sentinel_before)
cmake_path(NATIVE_PATH outside_bin NORMALIZE outside_native)
set(junction_bin "${junction_prefix}/bin")
cmake_path(NATIVE_PATH junction_bin NORMALIZE junction_native)
execute_process(COMMAND "$ENV{COMSPEC}" /d /c mklink /J
  "${junction_native}" "${outside_native}" RESULT_VARIABLE junction_result)
if(NOT junction_result EQUAL 0)
  message(FATAL_ERROR "SDK_RUNTIME_FIXTURE: could not create bin junction")
endif()
set(prefix "${junction_prefix}")
run_stager(STAGE fail ESCAPE)
file(SHA256 "${outside_bin}/sentinel.txt" sentinel_after)
file(GLOB outside_dlls "${outside_bin}/*.dll")
execute_process(COMMAND "$ENV{COMSPEC}" /d /c rmdir "${junction_native}"
  RESULT_VARIABLE unlink_result)
if(NOT unlink_result EQUAL 0 OR NOT sentinel_after STREQUAL sentinel_before OR
    outside_dlls)
  message(FATAL_ERROR
    "SDK_RUNTIME_FIXTURE: rejected bin junction changed outside state")
endif()
set(prefix "${ordinary_prefix}")
run_stager(STAGE pass "")
set(outside_file_target "${TEST_ROOT}/outside-file-target")
file(MAKE_DIRECTORY "${outside_file_target}")
file(WRITE "${outside_file_target}/sentinel.txt" "file sentinel\n")
file(SHA256 "${outside_file_target}/sentinel.txt" file_sentinel_before)
file(REMOVE "${prefix}/bin/libmpfr-6.dll")
set(file_junction "${prefix}/bin/libmpfr-6.dll")
cmake_path(NATIVE_PATH outside_file_target NORMALIZE file_target_native)
cmake_path(NATIVE_PATH file_junction NORMALIZE file_junction_native)
execute_process(COMMAND "$ENV{COMSPEC}" /d /c mklink /J
  "${file_junction_native}" "${file_target_native}"
  RESULT_VARIABLE file_junction_result)
if(NOT file_junction_result EQUAL 0)
  message(FATAL_ERROR "SDK_RUNTIME_FIXTURE: could not create file-path junction")
endif()
run_stager(STAGE fail ESCAPE)
file(SHA256 "${outside_file_target}/sentinel.txt" file_sentinel_after)
file(GLOB file_target_dlls "${outside_file_target}/*.dll")
execute_process(COMMAND "$ENV{COMSPEC}" /d /c rmdir "${file_junction_native}"
  RESULT_VARIABLE file_unlink_result)
if(NOT file_unlink_result EQUAL 0 OR
    NOT file_sentinel_after STREQUAL file_sentinel_before OR file_target_dlls)
  message(FATAL_ERROR
    "SDK_RUNTIME_FIXTURE: rejected file-path junction changed outside state")
endif()
file(WRITE "${source}/libmpfr-6.dll" "MZnot-a-valid-pe\n")
run_stager(STAGE fail FORMAT)

message(STATUS "Pure Windows SDK runtime closure contract passed")
