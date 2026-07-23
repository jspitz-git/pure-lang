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
