if(NOT DEFINED PURE_TEST_DRIVER OR NOT DEFINED PURE_BATCH_IR OR
   NOT DEFINED PURE_EXPECTED_ABI_TOKEN OR
   NOT DEFINED PURE_FORBIDDEN_ABI_METADATA)
  message(FATAL_ERROR "Missing pointer ABI batch test arguments")
endif()

file(REMOVE "${PURE_BATCH_IR}")
execute_process(
  COMMAND
    "${CMAKE_COMMAND}"
    -DPURE_SH_EXECUTABLE=${PURE_SH_EXECUTABLE}
    -DPURE_RUN_TEST=${PURE_RUN_TEST}
    -DPURE_FIXTURE_DIR=${PURE_FIXTURE_DIR}
    -DPURE_SCRIPT=${PURE_SCRIPT}
    -DPURE_BATCH_OBJECT=${PURE_BATCH_OBJECT}
    -DPURE_BATCH_EXECUTABLE=${PURE_BATCH_EXECUTABLE}
    -DPURE_BATCH_IR=${PURE_BATCH_IR}
    -DPURE_CXX_COMPILER=${PURE_CXX_COMPILER}
    -DPURE_MAIN_OBJECT=${PURE_MAIN_OBJECT}
    -DPURE_RUNTIME_DIR=${PURE_RUNTIME_DIR}
    -DPURE_LD_LIB_PATH=${PURE_LD_LIB_PATH}
    -DPURE_SANITIZERS=${PURE_SANITIZERS}
    -P "${PURE_TEST_DRIVER}"
  RESULT_VARIABLE driver_result
  OUTPUT_VARIABLE driver_stdout
  ERROR_VARIABLE driver_stderr
)
message("${driver_stdout}${driver_stderr}")
if(NOT driver_result EQUAL 0)
  message(FATAL_ERROR
    "Pointer ABI batch driver exited with status ${driver_result}")
endif()

if(NOT EXISTS "${PURE_BATCH_IR}")
  message(FATAL_ERROR "Pointer ABI batch compilation did not create LLVM IR")
endif()
file(READ "${PURE_BATCH_IR}" batch_ir)
string(FIND "${batch_ir}" "${PURE_EXPECTED_ABI_TOKEN}" abi_token_position)
if(abi_token_position EQUAL -1)
  message(FATAL_ERROR
    "Pointer ABI batch LLVM IR omitted ${PURE_EXPECTED_ABI_TOKEN}")
endif()
string(FIND "${batch_ir}" "${PURE_FORBIDDEN_ABI_METADATA}" metadata_position)
if(NOT metadata_position EQUAL -1)
  message(FATAL_ERROR
    "Pointer ABI batch LLVM IR retained ${PURE_FORBIDDEN_ABI_METADATA}")
endif()
