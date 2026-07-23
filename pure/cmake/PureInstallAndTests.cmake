include_guard(GLOBAL)

include(CTest)

find_program(PURE_DIFF_EXECUTABLE NAMES diff REQUIRED)

set(DIFF "${PURE_DIFF_EXECUTABLE}")
set(ECHO_N "-n")
set(ECHO_C "")
set(ECHO_T "")
set(srcdir "${CMAKE_CURRENT_SOURCE_DIR}")

if(APPLE)
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
  target_link_libraries(
    pure-jit-smoke
    PRIVATE
      ${PURE_LLVM_LIBRARIES}
      Threads::Threads
      ${CMAKE_DL_LIBS}
  )
  add_test(NAME pure-jit-smoke COMMAND pure-jit-smoke)
  set_tests_properties(pure-jit-smoke PROPERTIES LABELS "jit;smoke")

  function(add_pure_bitcode_test name script fixture)
    add_test(
      NAME "pure-bitcode-${name}"
      COMMAND
        "${CMAKE_COMMAND}"
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
        TIMEOUT 60
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
    PROPERTIES PASS_REGULAR_EXPRESSION "Invalid bitcode signature(.|\n)*42"
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

  add_test(
    NAME pure-regression
    COMMAND "${CMAKE_CURRENT_BINARY_DIR}/run-tests"
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
  )
  set_tests_properties(pure-regression PROPERTIES LABELS "regression")
endif()

set(PURE_INSTALL_INCLUDE_DIR "${CMAKE_INSTALL_INCLUDEDIR}/pure")
set(PURE_INSTALL_LIBRARY_DIR "${CMAKE_INSTALL_LIBDIR}/${PURE_LIBRARY_DIRECTORY}")

set(prefix "${CMAKE_INSTALL_PREFIX}")
set(exec_prefix "${CMAKE_INSTALL_PREFIX}")
set(libdir "${CMAKE_INSTALL_FULL_LIBDIR}")
set(includedir "${CMAKE_INSTALL_FULL_INCLUDEDIR}")
set(LLVM_EXE_LIBS "")
set(LLVM_LDFLAGS "-L${LLVM_LIBRARY_DIRS}")
set(LIBS "")
set(shared "-shared")
set(PIC "-fPIC")
set(PACKAGE_VERSION "${PROJECT_VERSION}")
configure_file(
  "${CMAKE_CURRENT_SOURCE_DIR}/pure.pc.in"
  "${CMAKE_CURRENT_BINARY_DIR}/pure.pc"
  @ONLY
)

install(
  TARGETS pure pure-runtime
  RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}"
  LIBRARY DESTINATION "${CMAKE_INSTALL_LIBDIR}"
  ARCHIVE DESTINATION "${CMAKE_INSTALL_LIBDIR}"
)
install(
  FILES runtime.h
  DESTINATION "${PURE_INSTALL_INCLUDE_DIR}"
)
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
