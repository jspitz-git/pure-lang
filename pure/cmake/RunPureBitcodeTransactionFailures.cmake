if(NOT DEFINED PURE_TEST_DRIVER OR
   NOT DEFINED PURE_BINARY_DIR OR
   NOT DEFINED PURE_EXECUTABLE_SUFFIX)
  message(FATAL_ERROR "Missing Pure bitcode transaction failure arguments")
endif()

set(failures)
foreach(mode
    batch-bitcode-host-global
    batch-bitcode-precommit
    batch-bitcode-provider-remove)
  set(batch_object
      "${PURE_BINARY_DIR}/test/bitcode/transaction-${mode}.o")
  set(batch_executable
      "${PURE_BINARY_DIR}/test/bitcode/transaction-${mode}${PURE_EXECUTABLE_SUFFIX}")
  execute_process(
    COMMAND
      "${CMAKE_COMMAND}"
      -DPURE_SH_EXECUTABLE=${PURE_SH_EXECUTABLE}
      -DPURE_RUN_TEST=${PURE_RUN_TEST}
      -DPURE_FIXTURE_DIR=${PURE_FIXTURE_DIR}
      -DPURE_SCRIPT=${PURE_SCRIPT}
      -DPURE_C_COMPILER=${PURE_C_COMPILER}
      -DPURE_C_SOURCE=${PURE_C_SOURCE}
      -DPURE_BITCODE_OUTPUT=${PURE_BITCODE_OUTPUT}
      -DPURE_SECOND_C_SOURCE=${PURE_SECOND_C_SOURCE}
      -DPURE_SECOND_BITCODE_OUTPUT=${PURE_SECOND_BITCODE_OUTPUT}
      -DPURE_BATCH_OBJECT=${batch_object}
      -DPURE_BATCH_EXECUTABLE=${batch_executable}
      -DPURE_CXX_COMPILER=${PURE_CXX_COMPILER}
      -DPURE_MAIN_OBJECT=${PURE_MAIN_OBJECT}
      -DPURE_RUNTIME_DIR=${PURE_RUNTIME_DIR}
      -DPURE_LD_LIB_PATH=${PURE_LD_LIB_PATH}
      -DPURE_SANITIZERS=${PURE_SANITIZERS}
      -DPURE_FAILURE_MODE=${mode}
      -DPURE_EXPECTED_DIAGNOSTIC=injected.${mode}
      -P "${PURE_TEST_DRIVER}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE output
  )
  message("[${mode}]\n${output}")
  if(NOT result EQUAL 0)
    list(APPEND failures "${mode} exited with status ${result}")
  endif()
endforeach()

if(failures)
  list(JOIN failures "\n  " failure_text)
  message(FATAL_ERROR
    "Pure bitcode transaction failure recovery failed:\n  ${failure_text}")
endif()

message("Pure bitcode transaction failure recovery passed")
