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

  if(PURE_FAUST_EXECUTABLE)
    add_test(
      NAME pure-faust-lifecycle
      COMMAND
        "${CMAKE_COMMAND}"
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
