include_guard(GLOBAL)

include(CTest)

find_program(PURE_DIFF_EXECUTABLE NAMES diff REQUIRED)

set(DIFF "${PURE_DIFF_EXECUTABLE}")
set(ECHO_N "-n")
set(ECHO_C "")
set(ECHO_T "")
set(srcdir "${CMAKE_CURRENT_SOURCE_DIR}")

if(WIN32)
  set(LD_LIB_PATH "PATH")
elseif(APPLE)
  set(LD_LIB_PATH "DYLD_LIBRARY_PATH")
else()
  set(LD_LIB_PATH "LD_LIBRARY_PATH")
endif()

configure_file(
  "${CMAKE_CURRENT_SOURCE_DIR}/run-test.in"
  "${CMAKE_CURRENT_BINARY_DIR}/run-test"
  @ONLY
)
configure_file(
  "${CMAKE_CURRENT_SOURCE_DIR}/run-tests.in"
  "${CMAKE_CURRENT_BINARY_DIR}/run-tests"
  @ONLY
)
file(
  CHMOD
    "${CMAKE_CURRENT_BINARY_DIR}/run-test"
    "${CMAKE_CURRENT_BINARY_DIR}/run-tests"
  PERMISSIONS
    OWNER_READ OWNER_WRITE OWNER_EXECUTE
    GROUP_READ GROUP_EXECUTE
    WORLD_READ WORLD_EXECUTE
)

if(BUILD_TESTING)
  find_program(PURE_SH_EXECUTABLE NAMES sh REQUIRED)
  find_program(
    PURE_LLVM_AS_EXECUTABLE
    NAMES llvm-as-22 llvm-as
    HINTS "${LLVM_TOOLS_BINARY_DIR}"
    REQUIRED
  )
  find_program(
    PURE_LLVM_DIS_EXECUTABLE
    NAMES llvm-dis-22 llvm-dis
    HINTS "${LLVM_TOOLS_BINARY_DIR}"
    REQUIRED
  )
  find_program(
    PURE_OPT_EXECUTABLE
    NAMES opt-22 opt
    HINTS "${LLVM_TOOLS_BINARY_DIR}"
    REQUIRED
  )

  set(PURE_BITCODE_FIXTURE_OUTPUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/test/bitcode")
  set(PURE_BITCODE_FIXTURE_OUTPUTS)
  foreach(fixture basic duplicate-a duplicate-b unresolved)
    set(source "${CMAKE_CURRENT_SOURCE_DIR}/test/bitcode/${fixture}.c")
    set(output "${PURE_BITCODE_FIXTURE_OUTPUT_DIR}/${fixture}.bc")
    set(disassembly "${PURE_BITCODE_FIXTURE_OUTPUT_DIR}/${fixture}.ll")
    add_custom_command(
      OUTPUT "${output}"
      BYPRODUCTS "${disassembly}"
      COMMAND
        "${CMAKE_COMMAND}" -E make_directory
        "${PURE_BITCODE_FIXTURE_OUTPUT_DIR}"
      COMMAND
        "${CMAKE_C_COMPILER}" -O0 -emit-llvm -c "${source}" -o "${output}"
      COMMAND
        "${PURE_LLVM_DIS_EXECUTABLE}" "${output}" -o "${disassembly}"
      COMMAND
        "${PURE_OPT_EXECUTABLE}" -passes=verify -disable-output "${output}"
      DEPENDS "${source}"
      COMMENT "Generating LLVM bitcode fixture ${fixture}.bc"
      VERBATIM
    )
    list(APPEND PURE_BITCODE_FIXTURE_OUTPUTS "${output}")
  endforeach()

  foreach(fixture
      pointer-valid pointer-missing metadata-malformed metadata-mismatch
      metadata-duplicate pointer-duplicate-a pointer-duplicate-b)
    set(source "${CMAKE_CURRENT_SOURCE_DIR}/test/bitcode/${fixture}.ll")
    set(output "${PURE_BITCODE_FIXTURE_OUTPUT_DIR}/${fixture}.bc")
    set(disassembly "${PURE_BITCODE_FIXTURE_OUTPUT_DIR}/${fixture}.ll")
    add_custom_command(
      OUTPUT "${output}"
      BYPRODUCTS "${disassembly}"
      COMMAND
        "${CMAKE_COMMAND}" -E make_directory
        "${PURE_BITCODE_FIXTURE_OUTPUT_DIR}"
      COMMAND
        "${PURE_LLVM_AS_EXECUTABLE}" "${source}" -o "${output}"
      COMMAND
        "${PURE_LLVM_DIS_EXECUTABLE}" "${output}" -o "${disassembly}"
      COMMAND
        "${PURE_OPT_EXECUTABLE}" -passes=verify -disable-output "${output}"
      DEPENDS "${source}"
      COMMENT "Generating LLVM ABI metadata fixture ${fixture}.bc"
      VERBATIM
    )
    list(APPEND PURE_BITCODE_FIXTURE_OUTPUTS "${output}")
  endforeach()

  set(malformed_output "${PURE_BITCODE_FIXTURE_OUTPUT_DIR}/malformed.bc")
  add_custom_command(
    OUTPUT "${malformed_output}"
    COMMAND
      "${CMAKE_COMMAND}" -E make_directory
      "${PURE_BITCODE_FIXTURE_OUTPUT_DIR}"
    COMMAND
      "${CMAKE_COMMAND}" -E copy_if_different
      "${CMAKE_CURRENT_SOURCE_DIR}/test/bitcode/malformed.txt"
      "${malformed_output}"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/test/bitcode/malformed.txt"
    COMMENT "Generating malformed bitcode fixture"
    VERBATIM
  )
  list(APPEND PURE_BITCODE_FIXTURE_OUTPUTS "${malformed_output}")

  if(PURE_HOST_TRIPLE MATCHES "^(aarch64|arm64)")
    set(PURE_MISMATCH_TRIPLE "x86_64-unknown-linux-gnu")
  else()
    set(PURE_MISMATCH_TRIPLE "aarch64-unknown-linux-gnu")
  endif()
  set(abi_mismatch_output
      "${PURE_BITCODE_FIXTURE_OUTPUT_DIR}/abi-mismatch.bc")
  set(abi_mismatch_disassembly
      "${PURE_BITCODE_FIXTURE_OUTPUT_DIR}/abi-mismatch.ll")
  add_custom_command(
    OUTPUT "${abi_mismatch_output}"
    BYPRODUCTS "${abi_mismatch_disassembly}"
    COMMAND
      "${CMAKE_COMMAND}" -E make_directory
      "${PURE_BITCODE_FIXTURE_OUTPUT_DIR}"
    COMMAND
      "${CMAKE_C_COMPILER}" --target=${PURE_MISMATCH_TRIPLE}
      -O0 -emit-llvm -c
      "${CMAKE_CURRENT_SOURCE_DIR}/test/bitcode/basic.c"
      -o "${abi_mismatch_output}"
    COMMAND
      "${PURE_LLVM_DIS_EXECUTABLE}" "${abi_mismatch_output}"
      -o "${abi_mismatch_disassembly}"
    COMMAND
      "${PURE_OPT_EXECUTABLE}" -passes=verify -disable-output
      "${abi_mismatch_output}"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/test/bitcode/basic.c"
    COMMENT "Generating incompatible ABI bitcode fixture"
    VERBATIM
  )
  list(APPEND PURE_BITCODE_FIXTURE_OUTPUTS "${abi_mismatch_output}")

  add_custom_target(
    pure-bitcode-fixtures ALL
    DEPENDS ${PURE_BITCODE_FIXTURE_OUTPUTS}
  )

  if(PURE_FAUST_EXECUTABLE)
    set(PURE_FAUST_FIXTURE_OUTPUT_DIR
        "${CMAKE_CURRENT_BINARY_DIR}/test/faust")
    set(PURE_FAUST_FIXTURE_OUTPUTS)

    set(reference_c "${PURE_FAUST_FIXTURE_OUTPUT_DIR}/reference.c")
    set(reference_bc "${PURE_FAUST_FIXTURE_OUTPUT_DIR}/reference.bc")
    set(reference_ll "${PURE_FAUST_FIXTURE_OUTPUT_DIR}/reference.ll")
    add_custom_command(
      OUTPUT "${reference_bc}"
      BYPRODUCTS "${reference_c}" "${reference_ll}"
      COMMAND
        "${CMAKE_COMMAND}" -E make_directory
        "${PURE_FAUST_FIXTURE_OUTPUT_DIR}"
      COMMAND
        "${PURE_FAUST_EXECUTABLE}" -double -a pure.c -lang c
        "${CMAKE_CURRENT_SOURCE_DIR}/test/faust/reference.dsp"
        -o "${reference_c}"
      COMMAND
        "${CMAKE_C_COMPILER}" -O0 -emit-llvm -c
        "${reference_c}" -o "${reference_bc}"
      COMMAND
        "${PURE_LLVM_DIS_EXECUTABLE}" "${reference_bc}"
        -o "${reference_ll}"
      COMMAND
        "${PURE_OPT_EXECUTABLE}" -passes=verify -disable-output
        "${reference_bc}"
      DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/test/faust/reference.dsp"
      COMMENT "Generating reference Faust LLVM bitcode fixture"
      VERBATIM
    )
    list(APPEND PURE_FAUST_FIXTURE_OUTPUTS "${reference_bc}")

    foreach(fixture reload-a reload-b)
      if(fixture STREQUAL "reload-a")
        set(version 11)
      else()
        set(version 22)
      endif()
      set(output "${PURE_FAUST_FIXTURE_OUTPUT_DIR}/${fixture}.bc")
      set(disassembly "${PURE_FAUST_FIXTURE_OUTPUT_DIR}/${fixture}.ll")
      add_custom_command(
        OUTPUT "${output}"
        BYPRODUCTS "${disassembly}"
        COMMAND
          "${CMAKE_COMMAND}" -E make_directory
          "${PURE_FAUST_FIXTURE_OUTPUT_DIR}"
        COMMAND
          "${CMAKE_C_COMPILER}" -O0 -emit-llvm -c
          -DFAUST_TEST_VERSION=${version}
          "${CMAKE_CURRENT_SOURCE_DIR}/test/faust/reload.c"
          -o "${output}"
        COMMAND
          "${PURE_LLVM_DIS_EXECUTABLE}" "${output}" -o "${disassembly}"
        COMMAND
          "${PURE_OPT_EXECUTABLE}" -passes=verify -disable-output "${output}"
        DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/test/faust/reload.c"
        COMMENT "Generating Faust reload fixture ${fixture}.bc"
        VERBATIM
      )
      list(APPEND PURE_FAUST_FIXTURE_OUTPUTS "${output}")
    endforeach()

    foreach(fixture reload-float reload-unresolved)
      set(source "${CMAKE_CURRENT_SOURCE_DIR}/test/faust/${fixture}.c")
      set(output "${PURE_FAUST_FIXTURE_OUTPUT_DIR}/${fixture}.bc")
      set(disassembly "${PURE_FAUST_FIXTURE_OUTPUT_DIR}/${fixture}.ll")
      add_custom_command(
        OUTPUT "${output}"
        BYPRODUCTS "${disassembly}"
        COMMAND
          "${CMAKE_COMMAND}" -E make_directory
          "${PURE_FAUST_FIXTURE_OUTPUT_DIR}"
        COMMAND
          "${CMAKE_C_COMPILER}" -O0 -emit-llvm -c
          "${source}" -o "${output}"
        COMMAND
          "${PURE_LLVM_DIS_EXECUTABLE}" "${output}" -o "${disassembly}"
        COMMAND
          "${PURE_OPT_EXECUTABLE}" -passes=verify -disable-output "${output}"
        DEPENDS "${source}"
        COMMENT "Generating Faust reload fixture ${fixture}.bc"
        VERBATIM
      )
      list(APPEND PURE_FAUST_FIXTURE_OUTPUTS "${output}")
    endforeach()

    add_custom_target(
      pure-faust-fixtures ALL
      DEPENDS ${PURE_FAUST_FIXTURE_OUTPUTS}
    )

    configure_file(
      "${CMAKE_CURRENT_SOURCE_DIR}/test/faust/lifecycle.pure.in"
      "${PURE_FAUST_FIXTURE_OUTPUT_DIR}/lifecycle.pure"
      @ONLY
    )
    configure_file(
      "${CMAKE_CURRENT_SOURCE_DIR}/test/faust/batch.pure.in"
      "${PURE_FAUST_FIXTURE_OUTPUT_DIR}/batch.pure"
      @ONLY
    )
  endif()

  add_executable(
    pure-jit-smoke
    "${CMAKE_CURRENT_SOURCE_DIR}/pure_jit.cc"
    "${CMAKE_CURRENT_SOURCE_DIR}/test/pure-jit-smoke.cc"
  )
  target_include_directories(
    pure-jit-smoke
    PRIVATE
      "${CMAKE_CURRENT_SOURCE_DIR}"
      ${LLVM_INCLUDE_DIRS}
  )
  # Clang's UBSan function check expects compiler-emitted type metadata before
  # an indirect-call target. ORC-generated functions do not carry that marker.
  target_compile_options(
    pure-jit-smoke
    PRIVATE
      $<$<COMPILE_LANG_AND_ID:CXX,Clang>:-fno-sanitize=function>
  )
  target_compile_definitions(
    pure-jit-smoke
    PRIVATE
      $<$<AND:$<CONFIG:Debug>,$<PLATFORM_ID:Linux>>:PURE_JIT_ELF_DEBUG_OBJECTS>
  )
  target_link_libraries(
    pure-jit-smoke
    PRIVATE
      ${PURE_LLVM_LIBRARIES}
      Threads::Threads
      ${CMAKE_DL_LIBS}
  )
  add_test(NAME pure-jit-smoke COMMAND pure-jit-smoke)
  set_tests_properties(pure-jit-smoke PROPERTIES LABELS "jit;smoke")
  add_test(
    NAME pure-jit-ir-dump
    COMMAND
      "${CMAKE_COMMAND}" -E env PURE_JIT_DUMP=ir
      "$<TARGET_FILE:pure-jit-smoke>"
  )
  set_tests_properties(
    pure-jit-ir-dump
    PROPERTIES
      LABELS "jit;smoke"
      PASS_REGULAR_EXPRESSION
        "\\[pure-jit IR\\] module='pure-jit-smoke'"
  )
  add_test(
    NAME pure-jit-object-dump
    COMMAND
      "${CMAKE_COMMAND}" -E env PURE_JIT_DUMP=objects
      "$<TARGET_FILE:pure-jit-smoke>"
  )
  set_tests_properties(
    pure-jit-object-dump
    PROPERTIES
      LABELS "jit;smoke"
      PASS_REGULAR_EXPRESSION
        "\\[pure-jit object\\].*format='[^']+'.*symbols="
  )
  add_test(
    NAME pure-jit-lifetime-stress
    COMMAND
      "${CMAKE_COMMAND}"
      -DPURE_EXECUTABLE=$<TARGET_FILE:pure>
      -DPURE_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/test/jit-lifetime-stress.pure
      -DPURE_EXPECTED=${CMAKE_CURRENT_SOURCE_DIR}/test/jit-lifetime-stress.log
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureLifetimeStress.cmake"
  )
  set_tests_properties(
    pure-jit-lifetime-stress
    PROPERTIES
      LABELS "jit;stress"
      REQUIRED_FILES
        "${CMAKE_CURRENT_SOURCE_DIR}/test/jit-lifetime-stress.pure;${CMAKE_CURRENT_SOURCE_DIR}/test/jit-lifetime-stress.log"
      TIMEOUT 60
      FAIL_REGULAR_EXPRESSION
        "failed to remove ORC compilation unit;AddressSanitizer;LeakSanitizer;runtime error:"
  )
  add_test(
    NAME pure-jit-deferred-generation
    COMMAND
      "${CMAKE_COMMAND}"
      -DPURE_EXECUTABLE=$<TARGET_FILE:pure>
      -DPURE_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/test/jit-deferred-generation.pure
      -DPURE_EXPECTED=${CMAKE_CURRENT_SOURCE_DIR}/test/jit-deferred-generation.log
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureLifetimeStress.cmake"
  )
  set_tests_properties(
    pure-jit-deferred-generation
    PROPERTIES
      LABELS "jit;stress"
      REQUIRED_FILES
        "${CMAKE_CURRENT_SOURCE_DIR}/test/jit-deferred-generation.pure;${CMAKE_CURRENT_SOURCE_DIR}/test/jit-deferred-generation.log"
      TIMEOUT 60
      FAIL_REGULAR_EXPRESSION
        "failed to remove ORC compilation unit;AddressSanitizer;LeakSanitizer;runtime error:"
  )
  add_test(
    NAME pure-jit-eager
    COMMAND
      "${CMAKE_COMMAND}"
      -DPURE_EXECUTABLE=$<TARGET_FILE:pure>
      -DPURE_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/test/jit-eager.pure
      -DPURE_EXPECTED=${CMAKE_CURRENT_SOURCE_DIR}/test/jit-eager.log
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureLifetimeStress.cmake"
  )
  set_tests_properties(
    pure-jit-eager
    PROPERTIES
      LABELS "jit;smoke"
      REQUIRED_FILES
        "${CMAKE_CURRENT_SOURCE_DIR}/test/jit-eager.pure;${CMAKE_CURRENT_SOURCE_DIR}/test/jit-eager.log"
      TIMEOUT 60
      FAIL_REGULAR_EXPRESSION
        "failed to;AddressSanitizer;LeakSanitizer;runtime error:"
  )

  function(add_pure_bitcode_test name script fixture)
    if(PURE_SANITIZERS)
      set(test_timeout 300)
    else()
      set(test_timeout 60)
    endif()
    add_test(
      NAME "pure-bitcode-${name}"
      COMMAND
        "${CMAKE_COMMAND}"
        -DPURE_SH_EXECUTABLE=${PURE_SH_EXECUTABLE}
        -DPURE_RUN_TEST=${CMAKE_CURRENT_BINARY_DIR}/run-test
        -DPURE_FIXTURE_DIR=${PURE_BITCODE_FIXTURE_OUTPUT_DIR}
        -DPURE_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/test/bitcode/${script}
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureBitcodeTest.cmake"
    )
    set_tests_properties(
      "pure-bitcode-${name}"
      PROPERTIES
        LABELS "bitcode;integration"
        REQUIRED_FILES
          "${PURE_BITCODE_FIXTURE_OUTPUT_DIR}/${fixture};${CMAKE_CURRENT_SOURCE_DIR}/test/bitcode/${script}"
        TIMEOUT ${test_timeout}
        FAIL_REGULAR_EXPRESSION
          "AddressSanitizer;LeakSanitizer;runtime error:"
    )
  endfunction()

  add_pure_bitcode_test(duplicate-symbols duplicate-symbols.pure duplicate-a.bc)
  set_tests_properties(
    pure-bitcode-duplicate-symbols
    PROPERTIES PASS_REGULAR_EXPRESSION "11(.|\n)*101"
  )

  add_pure_bitcode_test(malformed-input malformed-input.pure malformed.bc)
  set_tests_properties(
    pure-bitcode-malformed-input
    PROPERTIES
      PASS_REGULAR_EXPRESSION
        "(Invalid bitcode signature|file doesn't start with bitcode header)(.|\n)*42"
  )

  add_pure_bitcode_test(abi-mismatch abi-mismatch.pure abi-mismatch.bc)
  set_tests_properties(
    pure-bitcode-abi-mismatch
    PROPERTIES
      PASS_REGULAR_EXPRESSION
        "Incompatible target triple \\(architecture\\)(.|\n)*42"
  )

  add_pure_bitcode_test(
    unresolved-dependency unresolved-dependency.pure unresolved.bc
  )
  set_tests_properties(
    pure-bitcode-unresolved-dependency
    PROPERTIES
      PASS_REGULAR_EXPRESSION
        "Failed to materialize bitcode export 'bc_unresolved'(.|\n)*bc_missing_dependency(.|\n)*42"
  )

  add_pure_bitcode_test(unload unload.pure basic.bc)
  set_tests_properties(
    pure-bitcode-unload
    PROPERTIES
      PASS_REGULAR_EXPRESSION "42"
      FAIL_REGULAR_EXPRESSION
        "failed to remove ORC compilation unit;AddressSanitizer;LeakSanitizer;runtime error:"
  )

  add_pure_bitcode_test(pointer-valid pointer-valid.pure pointer-valid.bc)
  set_tests_properties(
    pure-bitcode-pointer-valid
    PROPERTIES
      PASS_REGULAR_EXPRESSION "\"first cache\"(.|\n)*\"second cache\""
      FAIL_REGULAR_EXPRESSION
        "failed to remove ORC compilation unit;AddressSanitizer;LeakSanitizer;runtime error:"
  )

  add_pure_bitcode_test(pointer-missing pointer-missing.pure pointer-missing.bc)
  set_tests_properties(
    pure-bitcode-pointer-missing
    PROPERTIES
      PASS_REGULAR_EXPRESSION "unsupported prototype(.|\n)*42"
  )

  add_pure_bitcode_test(
    metadata-malformed metadata-malformed.pure metadata-malformed.bc
  )
  set_tests_properties(
    pure-bitcode-metadata-malformed
    PROPERTIES
      PASS_REGULAR_EXPRESSION "Unsupported pure.abi metadata version 2(.|\n)*42"
  )

  add_pure_bitcode_test(
    metadata-mismatch metadata-mismatch.pure metadata-mismatch.bc
  )
  set_tests_properties(
    pure-bitcode-metadata-mismatch
    PROPERTIES
      PASS_REGULAR_EXPRESSION
        "Invalid pure.abi metadata for function 'bc_metadata_mismatch' result:(.|\n)*42"
  )

  add_pure_bitcode_test(
    metadata-duplicate metadata-duplicate.pure metadata-duplicate.bc
  )
  set_tests_properties(
    pure-bitcode-metadata-duplicate
    PROPERTIES
      PASS_REGULAR_EXPRESSION
        "duplicate function record 'bc_metadata_duplicate'(.|\n)*42"
  )

  add_pure_bitcode_test(
    pointer-duplicate-exports pointer-duplicate-exports.pure pointer-duplicate-a.bc
  )
  set_tests_properties(
    pure-bitcode-pointer-duplicate-exports
    PROPERTIES PASS_REGULAR_EXPRESSION "11(.|\n)*101"
  )

  if(PURE_FAUST_EXECUTABLE)
    add_test(
      NAME pure-faust-lifecycle
      COMMAND
        "${CMAKE_COMMAND}"
        -DPURE_SH_EXECUTABLE=${PURE_SH_EXECUTABLE}
        -DPURE_RUN_TEST=${CMAKE_CURRENT_BINARY_DIR}/run-test
        -DPURE_FIXTURE_DIR=${PURE_FAUST_FIXTURE_OUTPUT_DIR}
        -DPURE_SCRIPT=${PURE_FAUST_FIXTURE_OUTPUT_DIR}/lifecycle.pure
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureFaustTest.cmake"
    )
    if(PURE_SANITIZERS)
      set(faust_test_timeout 300)
    else()
      set(faust_test_timeout 180)
    endif()
    set_tests_properties(
      pure-faust-lifecycle
      PROPERTIES
        LABELS "faust;bitcode;integration"
        REQUIRED_FILES
          "${reference_bc};${PURE_FAUST_FIXTURE_OUTPUT_DIR}/reload-a.bc;${PURE_FAUST_FIXTURE_OUTPUT_DIR}/reload-b.bc;${PURE_FAUST_FIXTURE_OUTPUT_DIR}/reload-float.bc;${PURE_FAUST_FIXTURE_OUTPUT_DIR}/reload-unresolved.bc;${PURE_FAUST_FIXTURE_OUTPUT_DIR}/lifecycle.pure"
        TIMEOUT ${faust_test_timeout}
        PASS_REGULAR_EXPRESSION
          "Cannot reload Faust module while DSP instances are live(.|\n)*11(.|\n)*22(.|\n)*Module was previously loaded with the double sample ABI(.|\n)*22(.|\n)*faust_missing_test_dependency(.|\n)*22(.|\n)*42"
        FAIL_REGULAR_EXPRESSION
          "failed to remove ORC compilation unit;AddressSanitizer;LeakSanitizer;runtime error:"
    )
  endif()

  if(PURE_SANITIZERS)
    set(formatted_io_test_timeout 300)
  else()
    set(formatted_io_test_timeout 120)
  endif()
  add_test(
    NAME pure-formatted-io
    COMMAND
      "${PURE_SH_EXECUTABLE}"
      "${CMAKE_CURRENT_BINARY_DIR}/run-test"
      "${CMAKE_CURRENT_SOURCE_DIR}/test/formatted-io-smoke.pure"
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
  )
  set_tests_properties(
    pure-formatted-io
    PROPERTIES
      LABELS "runtime;integration"
      REQUIRED_FILES "${CMAKE_CURRENT_SOURCE_DIR}/test/formatted-io-smoke.pure"
      TIMEOUT ${formatted_io_test_timeout}
      PASS_REGULAR_EXPRESSION "formatted:ok:42"
      FAIL_REGULAR_EXPRESSION
        "unhandled exception;AddressSanitizer;LeakSanitizer;runtime error:"
  )
  if(PURE_SANITIZERS)
    set_tests_properties(
      pure-formatted-io PROPERTIES ENVIRONMENT "PURE_STACK=0"
    )
  endif()

  add_test(
    NAME pure-batch-object
    COMMAND
      "${CMAKE_COMMAND}"
      -DPURE_EXECUTABLE=$<TARGET_FILE:pure>
      -DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}
      -DPURE_BUILD_DIR=${CMAKE_CURRENT_BINARY_DIR}
      -DPURE_LD_LIB_PATH=${LD_LIB_PATH}
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureBatchTest.cmake"
  )
  if(PURE_SANITIZERS)
    set(batch_test_timeout 300)
  else()
    set(batch_test_timeout 120)
  endif()
  set_tests_properties(
    pure-batch-object
    PROPERTIES
      LABELS "batch;integration"
      REQUIRED_FILES "${CMAKE_CURRENT_SOURCE_DIR}/test/batch-smoke.pure"
      TIMEOUT ${batch_test_timeout}
      FAIL_REGULAR_EXPRESSION
        "AddressSanitizer;LeakSanitizer;runtime error:"
  )
  if(WIN32)
    set(PURE_EXPECTED_BATCH_CXX "clang++")
  else()
    set(PURE_EXPECTED_BATCH_CXX "${LLVM_TOOLS_BINARY_DIR}/clang++")
  endif()
  add_test(
    NAME pure-batch-executable
    COMMAND
      "${CMAKE_COMMAND}"
      -DPURE_EXECUTABLE=$<TARGET_FILE:pure>
      -DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}
      -DPURE_BUILD_DIR=${CMAKE_CURRENT_BINARY_DIR}
      -DPURE_LD_LIB_PATH=${LD_LIB_PATH}
      -DPURE_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/test/batch-smoke.pure
      -DPURE_OUTPUT_NAME=pure-batch-program.o
      -DPURE_RUN_EXECUTABLE=ON
      -DPURE_EXPECTED_CXX_COMPILER=${PURE_EXPECTED_BATCH_CXX}
      -DPURE_MAIN_OBJECT=$<TARGET_OBJECTS:pure-main-object>
      -DPURE_EXECUTABLE_SUFFIX=${CMAKE_EXECUTABLE_SUFFIX}
      -DPURE_SANITIZERS=${PURE_SANITIZERS}
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureBatchTest.cmake"
  )
  set_tests_properties(
    pure-batch-executable
    PROPERTIES
      LABELS "batch;integration"
      REQUIRED_FILES "${CMAKE_CURRENT_SOURCE_DIR}/test/batch-smoke.pure"
      TIMEOUT ${batch_test_timeout}
      FAIL_REGULAR_EXPRESSION
        "failed;AddressSanitizer;LeakSanitizer;runtime error:"
  )
  if(PURE_FAUST_EXECUTABLE)
    add_test(
      NAME pure-batch-faust
      COMMAND
        "${CMAKE_COMMAND}"
        -DPURE_EXECUTABLE=$<TARGET_FILE:pure>
        -DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}
        -DPURE_BUILD_DIR=${CMAKE_CURRENT_BINARY_DIR}
        -DPURE_LD_LIB_PATH=${LD_LIB_PATH}
        -DPURE_SCRIPT=${PURE_FAUST_FIXTURE_OUTPUT_DIR}/batch.pure
        -DPURE_OUTPUT_NAME=pure-batch-faust.o
        -DPURE_FIXTURE_SOURCE=${PURE_FAUST_FIXTURE_OUTPUT_DIR}/reload-a.bc
        -DPURE_FIXTURE_DESTINATION=${PURE_FAUST_FIXTURE_OUTPUT_DIR}/batch_reload.bc
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureBatchTest.cmake"
    )
    set_tests_properties(
      pure-batch-faust
      PROPERTIES
        LABELS "batch;faust;integration"
        REQUIRED_FILES
          "${reference_bc};${PURE_FAUST_FIXTURE_OUTPUT_DIR}/reload-a.bc;${PURE_FAUST_FIXTURE_OUTPUT_DIR}/reload-b.bc;${PURE_FAUST_FIXTURE_OUTPUT_DIR}/batch.pure"
        TIMEOUT ${batch_test_timeout}
        FAIL_REGULAR_EXPRESSION
          "failed to;AddressSanitizer;LeakSanitizer;runtime error:"
    )
  endif()

  add_test(
    NAME pure-regression
    COMMAND
      "${PURE_SH_EXECUTABLE}" "${CMAKE_CURRENT_BINARY_DIR}/run-tests" -v
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
  )
  set(regression_timeout 600)
  set(regression_environment "TEST_JOBS=4")
  if(PURE_SANITIZERS)
    set(regression_timeout 1800)
    list(APPEND regression_environment "PURE_STACK=0")
  elseif(CMAKE_BUILD_TYPE STREQUAL "Debug")
    set(regression_timeout 900)
  endif()
  set_tests_properties(
    pure-regression
    PROPERTIES
      ENVIRONMENT "${regression_environment}"
      LABELS "regression"
      TIMEOUT ${regression_timeout}
  )
endif()

set(PURE_INSTALL_INCLUDE_DIR "${CMAKE_INSTALL_INCLUDEDIR}/pure")
set(PURE_INSTALL_LIBRARY_DIR "${CMAKE_INSTALL_LIBDIR}/${PURE_LIBRARY_DIRECTORY}")

set(LLVM_EXE_LIBS "")
set(LIBS "")
if(WIN32)
  set(prefix "\${pcfiledir}/../..")
  set(exec_prefix "\${prefix}")
  set(bindir "\${prefix}/${CMAKE_INSTALL_BINDIR}")
  set(libdir "\${prefix}/${CMAKE_INSTALL_LIBDIR}")
  set(includedir "\${prefix}/${CMAKE_INSTALL_INCLUDEDIR}")
  set(PC_TOOL_PREFIX "\${prefix}/tools/bin/")
  set(LLVM_LDFLAGS "")
else()
  set(prefix "${CMAKE_INSTALL_PREFIX}")
  set(exec_prefix "${CMAKE_INSTALL_PREFIX}")
  set(bindir "${CMAKE_INSTALL_FULL_BINDIR}")
  set(libdir "${CMAKE_INSTALL_FULL_LIBDIR}")
  set(includedir "${CMAKE_INSTALL_FULL_INCLUDEDIR}")
  set(PC_TOOL_PREFIX "${TOOL_PREFIX}")
  set(LLVM_LDFLAGS "-L${LLVM_LIBRARY_DIRS}")
endif()
if(APPLE)
  set(shared "-dynamiclib")
  set(PIC "-fPIC")
elseif(WIN32)
  set(shared "-shared")
  set(PIC "")
else()
  set(shared "-shared")
  set(PIC "-fPIC")
endif()
set(PACKAGE_VERSION "${PROJECT_VERSION}")
configure_file(
  "${CMAKE_CURRENT_SOURCE_DIR}/pure.pc.in"
  "${CMAKE_CURRENT_BINARY_DIR}/pure.pc"
  @ONLY
)

option(
  PURE_INSTALL_WINDOWS_RUNTIME_DEPENDENCIES
  "Install non-system runtime DLL dependencies with Pure on Windows"
  ON
)
if(WIN32 AND PURE_INSTALL_WINDOWS_RUNTIME_DEPENDENCIES)
  install(
    TARGETS pure pure-runtime
    RUNTIME_DEPENDENCIES
      DIRECTORIES "${LLVM_TOOLS_BINARY_DIR}"
      PRE_EXCLUDE_REGEXES "^api-ms-win-.*" "^ext-ms-win-.*"
      POST_EXCLUDE_REGEXES
        "^[A-Za-z]:[/\\\\][Ww][Ii][Nn][Dd][Oo][Ww][Ss][/\\\\]([Ss][Yy][Ss][Tt][Ee][Mm]32|[Ss][Yy][Ss][Ww][Oo][Ww]64)[/\\\\].*"
    RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}"
    LIBRARY DESTINATION "${CMAKE_INSTALL_LIBDIR}"
    ARCHIVE DESTINATION "${CMAKE_INSTALL_LIBDIR}"
  )
else()
  install(
    TARGETS pure pure-runtime
    RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}"
    LIBRARY DESTINATION "${CMAKE_INSTALL_LIBDIR}"
    ARCHIVE DESTINATION "${CMAKE_INSTALL_LIBDIR}"
  )
endif()
install(
  FILES runtime.h
  DESTINATION "${PURE_INSTALL_INCLUDE_DIR}"
)
if(WIN32)
  install(
    FILES compat/libglob/glob.h compat/libglob/fnmatch.h
    DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}"
  )
endif()
install(
  FILES pure_main.c
  DESTINATION "${PURE_INSTALL_LIBRARY_DIR}"
)
install(
  FILES "$<TARGET_OBJECTS:pure-main-object>"
  DESTINATION "${PURE_INSTALL_LIBRARY_DIR}"
  RENAME pure_main.o
)
install(
  DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/lib/"
  DESTINATION "${PURE_INSTALL_LIBRARY_DIR}"
  FILES_MATCHING PATTERN "*.pure"
)
install(
  FILES "${CMAKE_CURRENT_BINARY_DIR}/pure.pc"
  DESTINATION "${CMAKE_INSTALL_LIBDIR}/pkgconfig"
)
install(
  FILES pure.1
  DESTINATION "${CMAKE_INSTALL_MANDIR}/man1"
)

option(
  PURE_INSTALL_EMACS_MODE
  "Install the Pure Emacs and Flycheck modes"
  OFF
)
set(
  PURE_EMACS_SITE_LISP_DIR
  "${CMAKE_INSTALL_DATADIR}/emacs/site-lisp"
  CACHE STRING
  "Installation directory for Pure Emacs Lisp files"
)
if(PURE_INSTALL_EMACS_MODE)
  configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/etc/pure-mode.el.in"
    "${CMAKE_CURRENT_BINARY_DIR}/etc/pure-mode.el"
    @ONLY
  )
  install(
    FILES
      "${CMAKE_CURRENT_BINARY_DIR}/etc/pure-mode.el"
      "${CMAKE_CURRENT_SOURCE_DIR}/etc/flycheck-pure.el"
    DESTINATION "${PURE_EMACS_SITE_LISP_DIR}"
  )
endif()

option(
  PURE_INSTALL_TEXMACS_PLUGIN
  "Install the Pure TeXmacs plugin"
  OFF
)
set(
  PURE_TEXMACS_DIR
  "${CMAKE_INSTALL_DATADIR}/TeXmacs"
  CACHE STRING
  "Installation root for Pure TeXmacs files"
)
if(PURE_INSTALL_TEXMACS_PLUGIN)
  install(
    DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/texmacs/"
    DESTINATION "${PURE_TEXMACS_DIR}"
  )
endif()

configure_file(
  "${CMAKE_CURRENT_SOURCE_DIR}/cmake/Uninstall.cmake.in"
  "${CMAKE_CURRENT_BINARY_DIR}/cmake_uninstall.cmake"
  @ONLY
)
add_custom_target(
  uninstall
  COMMAND "${CMAKE_COMMAND}" -P "${CMAKE_CURRENT_BINARY_DIR}/cmake_uninstall.cmake"
  COMMENT "Removing installed Pure files"
)
