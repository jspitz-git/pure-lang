if(NOT DEFINED PURE_EXECUTABLE OR NOT DEFINED PURE_SOURCE_DIR OR
   NOT DEFINED PURE_BUILD_DIR OR NOT DEFINED PURE_LD_LIB_PATH)
  message(FATAL_ERROR "Missing Pure batch test driver arguments")
endif()
if(NOT DEFINED PURE_EXPECTED_OUTPUT OR NOT DEFINED PURE_OBJECT_INSPECTOR)
  message(FATAL_ERROR "Missing Pure batch harness assertions")
endif()

if(NOT DEFINED PURE_SCRIPT)
  set(PURE_SCRIPT "${PURE_SOURCE_DIR}/test/batch-smoke.pure")
endif()
if(NOT DEFINED PURE_OUTPUT_NAME)
  set(PURE_OUTPUT_NAME "pure-batch-smoke.o")
endif()

if(DEFINED PURE_FIXTURE_SOURCE OR DEFINED PURE_FIXTURE_DESTINATION)
  if(NOT DEFINED PURE_FIXTURE_SOURCE OR
     NOT DEFINED PURE_FIXTURE_DESTINATION)
    message(FATAL_ERROR "Incomplete Pure batch fixture copy arguments")
  endif()
  file(COPY_FILE "${PURE_FIXTURE_SOURCE}" "${PURE_FIXTURE_DESTINATION}")
endif()

function(assert_compile_output output_value)
  if(DEFINED PURE_EXPECTED_COMPILE_SENTINEL AND
     NOT "${PURE_EXPECTED_COMPILE_SENTINEL}" STREQUAL "")
    string(REPLACE "\r\n" "\n" normalized_output "${output_value}")
    string(FIND "\n${normalized_output}\n"
      "\n${PURE_EXPECTED_COMPILE_SENTINEL}\n" sentinel_position)
    if(sentinel_position EQUAL -1)
      message(FATAL_ERROR
        "Pure batch compilation omitted the exact expected sentinel"
      )
    endif()
  endif()
  if(DEFINED PURE_EXPECTED_DIAGNOSTIC AND
     NOT "${PURE_EXPECTED_DIAGNOSTIC}" STREQUAL "" AND
     NOT "${output_value}" MATCHES "${PURE_EXPECTED_DIAGNOSTIC}")
    message(FATAL_ERROR
      "Pure batch compilation omitted the expected diagnostic"
    )
  endif()
endfunction()

set(output "${PURE_BUILD_DIR}/test/${PURE_OUTPUT_NAME}")
file(REMOVE "${output}")

set(loader_path "${PURE_BUILD_DIR}")
if(DEFINED ENV{${PURE_LD_LIB_PATH}} AND
   NOT "$ENV{${PURE_LD_LIB_PATH}}" STREQUAL "")
  if(CMAKE_HOST_WIN32)
    string(APPEND loader_path ";$ENV{${PURE_LD_LIB_PATH}}")
  else()
    string(APPEND loader_path ":$ENV{${PURE_LD_LIB_PATH}}")
  endif()
endif()

execute_process(
  COMMAND
    "${CMAKE_COMMAND}" -E env
    "${PURE_LD_LIB_PATH}=${loader_path}"
    "PURELIB=${PURE_SOURCE_DIR}/lib"
    "${PURE_EXECUTABLE}" --norc --noprelude -c
    "${PURE_SCRIPT}" -o "${output}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE command_stdout
  ERROR_VARIABLE command_stderr
)
set(command_output "${command_stdout}${command_stderr}")

message("${command_output}")
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Pure batch compilation exited with status ${result}")
endif()
assert_compile_output("${command_output}")
if(NOT EXISTS "${output}")
  message(FATAL_ERROR "Pure batch compilation did not create ${output}")
endif()
file(SIZE "${output}" output_size)
if(output_size EQUAL 0)
  message(FATAL_ERROR "Pure batch compilation created an empty object")
endif()
execute_process(
  COMMAND "${PURE_OBJECT_INSPECTOR}" --file-headers "${output}"
  RESULT_VARIABLE object_result
  OUTPUT_VARIABLE object_report
  ERROR_VARIABLE object_error
)
message("${object_report}${object_error}")
if(NOT object_result EQUAL 0)
  message(FATAL_ERROR "Pure batch object inspection exited with status ${object_result}")
endif()
if("${object_report}${object_error}" STREQUAL "")
  message(FATAL_ERROR "Pure batch object inspection returned no report")
endif()
string(REGEX MATCH "Format: COFF" object_format "${object_report}${object_error}")
if(object_format STREQUAL "")
  message(FATAL_ERROR "Pure batch object is not COFF")
endif()
string(
  REGEX MATCH
  "Arch: (x86_64|x86-64)|Machine: IMAGE_FILE_MACHINE_AMD64"
  object_machine
  "${object_report}${object_error}"
)
if(object_machine STREQUAL "")
  message(FATAL_ERROR "Pure batch object is not x86-64/AMD64")
endif()

if((DEFINED PURE_EXPECTED_MODULE_FLAG_KEY AND
    NOT "${PURE_EXPECTED_MODULE_FLAG_KEY}" STREQUAL "") OR
   (DEFINED PURE_FORBIDDEN_METADATA_KEY AND
    NOT "${PURE_FORBIDDEN_METADATA_KEY}" STREQUAL "") OR
   (DEFINED PURE_FORBIDDEN_GLOBAL_FRAGMENT AND
    NOT "${PURE_FORBIDDEN_GLOBAL_FRAGMENT}" STREQUAL ""))
  set(llvm_ir "${PURE_BUILD_DIR}/test/${PURE_OUTPUT_NAME}.ll")
  file(REMOVE "${llvm_ir}")
  if(DEFINED PURE_FIXTURE_SOURCE)
    file(COPY_FILE "${PURE_FIXTURE_SOURCE}" "${PURE_FIXTURE_DESTINATION}")
  endif()
  execute_process(
    COMMAND
      "${CMAKE_COMMAND}" -E env
      "${PURE_LD_LIB_PATH}=${loader_path}"
      "PURELIB=${PURE_SOURCE_DIR}/lib"
      "${PURE_EXECUTABLE}" --norc --noprelude -c
      "${PURE_SCRIPT}" -o "${llvm_ir}"
    RESULT_VARIABLE llvm_ir_result
    OUTPUT_VARIABLE llvm_ir_stdout
    ERROR_VARIABLE llvm_ir_stderr
  )
  set(llvm_ir_output "${llvm_ir_stdout}${llvm_ir_stderr}")
  message("${llvm_ir_output}")
  if(NOT llvm_ir_result EQUAL 0 OR NOT EXISTS "${llvm_ir}")
    message(FATAL_ERROR
      "Pure batch LLVM IR emission failed with status ${llvm_ir_result}"
    )
  endif()
  assert_compile_output("${llvm_ir_output}")
  if(DEFINED PURE_IR_VERIFIER AND NOT "${PURE_IR_VERIFIER}" STREQUAL "")
    execute_process(
      COMMAND "${PURE_IR_VERIFIER}" -passes=verify -disable-output "${llvm_ir}"
      RESULT_VARIABLE llvm_ir_verify_result
      OUTPUT_VARIABLE llvm_ir_verify_stdout
      ERROR_VARIABLE llvm_ir_verify_stderr
    )
    message("${llvm_ir_verify_stdout}${llvm_ir_verify_stderr}")
    if(NOT llvm_ir_verify_result EQUAL 0)
      message(FATAL_ERROR
        "Pure batch LLVM IR verification failed with status ${llvm_ir_verify_result}"
      )
    endif()
  endif()
  file(READ "${llvm_ir}" llvm_ir_text)
  if(DEFINED PURE_EXPECTED_MODULE_FLAG_KEY AND
     NOT "${PURE_EXPECTED_MODULE_FLAG_KEY}" STREQUAL "")
    string(
      REGEX MATCH
      "!\\{i32 1, !\"${PURE_EXPECTED_MODULE_FLAG_KEY}\", ptr @\"([^\"]+)\"\\}"
      module_flag_record
      "${llvm_ir_text}"
    )
    if(module_flag_record STREQUAL "")
      message(FATAL_ERROR
        "Pure batch LLVM IR module flag does not reference a global value"
      )
    endif()
    set(module_flag_symbol "${CMAKE_MATCH_1}")
    string(FIND
      "${llvm_ir_text}" "@\"${module_flag_symbol}\" =" module_flag_definition
    )
    if(module_flag_definition EQUAL -1)
      message(FATAL_ERROR
        "Pure batch LLVM IR module flag references a missing global definition"
      )
    endif()
  endif()
  if(DEFINED PURE_FORBIDDEN_METADATA_KEY AND
     NOT "${PURE_FORBIDDEN_METADATA_KEY}" STREQUAL "")
    string(FIND
      "${llvm_ir_text}" "${PURE_FORBIDDEN_METADATA_KEY}" forbidden_metadata
    )
    if(NOT forbidden_metadata EQUAL -1)
      message(FATAL_ERROR
        "Pure batch LLVM IR retained forbidden metadata key ${PURE_FORBIDDEN_METADATA_KEY}"
      )
    endif()
  endif()
  if(DEFINED PURE_FORBIDDEN_GLOBAL_FRAGMENT AND
     NOT "${PURE_FORBIDDEN_GLOBAL_FRAGMENT}" STREQUAL "")
    string(FIND
      "${llvm_ir_text}" "${PURE_FORBIDDEN_GLOBAL_FRAGMENT}" forbidden_global
    )
    if(NOT forbidden_global EQUAL -1)
      message(FATAL_ERROR
        "Pure batch LLVM IR retained retired Faust global fragment ${PURE_FORBIDDEN_GLOBAL_FRAGMENT}"
      )
    endif()
  endif()
endif()

if(PURE_RUN_EXECUTABLE)
  if(NOT DEFINED PURE_EXECUTABLE_SUFFIX OR
     NOT DEFINED PURE_EXPECTED_CXX_COMPILER OR
     NOT DEFINED PURE_MAIN_OBJECT)
    message(FATAL_ERROR "Missing Pure batch executable arguments")
  endif()
  file(COPY_FILE "${PURE_MAIN_OBJECT}" "${PURE_BUILD_DIR}/test/pure_main.o")
  if(DEFINED PURE_FIXTURE_SOURCE)
    file(COPY_FILE "${PURE_FIXTURE_SOURCE}" "${PURE_FIXTURE_DESTINATION}")
  endif()
  if(NOT DEFINED PURE_BATCH_EXECUTABLE_NAME)
    set(PURE_BATCH_EXECUTABLE_NAME pure-batch-program)
  endif()
  set(executable
    "${PURE_BUILD_DIR}/test/${PURE_BATCH_EXECUTABLE_NAME}${PURE_EXECUTABLE_SUFFIX}"
  )
  file(REMOVE "${executable}")
  if(PURE_SANITIZERS)
    set(
      compiler_environment
      "CXX=${PURE_EXPECTED_CXX_COMPILER} -fsanitize=${PURE_SANITIZERS}"
    )
  else()
    set(compiler_environment --unset=CC --unset=CXX)
  endif()
  execute_process(
    COMMAND
      "${CMAKE_COMMAND}" -E env ${compiler_environment}
      "${PURE_LD_LIB_PATH}=${loader_path}"
      "PURELIB=${PURE_BUILD_DIR}/test"
      "${PURE_EXECUTABLE}" --norc --noprelude -v0100 -c
      "${PURE_SCRIPT}" -o "${executable}"
    RESULT_VARIABLE link_result
    OUTPUT_VARIABLE link_stdout
    ERROR_VARIABLE link_stderr
  )
  set(link_output "${link_stdout}${link_stderr}")
  message("${link_output}")
  if(NOT link_result EQUAL 0 OR NOT EXISTS "${executable}")
    message(FATAL_ERROR "Pure batch executable link failed with status ${link_result}")
  endif()
  assert_compile_output("${link_output}")
  if(NOT DEFINED PURE_VERIFY_CXX_OUTPUT OR PURE_VERIFY_CXX_OUTPUT)
    set(normalized_link_output "${link_output}")
    set(normalized_expected_cxx "${PURE_EXPECTED_CXX_COMPILER}")
    string(REPLACE "\\" "/" normalized_link_output "${normalized_link_output}")
    string(REPLACE "\\" "/" normalized_expected_cxx "${normalized_expected_cxx}")
    string(FIND "${normalized_link_output}" "${normalized_expected_cxx}" compiler_position)
    if(compiler_position EQUAL -1)
      message(FATAL_ERROR
        "Pure batch executable did not use ${PURE_EXPECTED_CXX_COMPILER}"
      )
    endif()
  endif()
  execute_process(
    COMMAND
      "${CMAKE_COMMAND}" -E env
      "${PURE_LD_LIB_PATH}=${loader_path}"
      "${executable}"
    RESULT_VARIABLE run_result
    OUTPUT_VARIABLE run_output
    ERROR_VARIABLE run_error
  )
  message("${run_output}${run_error}")
  if(NOT run_result EQUAL 0)
    message(FATAL_ERROR "Pure batch executable exited with status ${run_result}")
  endif()
  if(NOT "${run_output}" STREQUAL "${PURE_EXPECTED_OUTPUT}")
    message(FATAL_ERROR
      "Pure batch executable stdout did not match the expected literal"
    )
  endif()
endif()
