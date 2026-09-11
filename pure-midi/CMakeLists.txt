cmake_minimum_required(VERSION 3.25)

project(pure-midi VERSION 0.6 LANGUAGES C)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(PORTMIDI REQUIRED IMPORTED_TARGET portmidi)

function(add_pure_midi_module target)
  add_library(${target} MODULE ${ARGN})
  target_compile_features(${target} PRIVATE c_std_11)
  target_link_libraries(${target} PRIVATE PkgConfig::PURE)
  if(MINGW)
    target_compile_options(${target} PRIVATE -Wall -Wextra -Werror)
    target_link_options(${target} PRIVATE "LINKER:--enable-auto-import")
  endif()
  set_target_properties(${target} PROPERTIES
    PREFIX ""
    WINDOWS_EXPORT_ALL_SYMBOLS ON)
endfunction()

add_pure_midi_module(pmlib pmdev.c midi_bounds.c midi_stream.c)
target_link_libraries(pmlib PRIVATE PkgConfig::PORTMIDI)
if(NOT WIN32)
  find_package(Threads REQUIRED)
  target_link_libraries(pmlib PRIVATE Threads::Threads)
endif()

add_pure_midi_module(midifile midifile/midifile.c midifile/mf.c midi_bounds.c)

if(WIN32)
  find_file(PORTMIDI_RUNTIME_DLL
    NAMES libportmidi.dll
    HINTS "$ENV{MSYSTEM_PREFIX}/bin"
    NO_DEFAULT_PATH
    REQUIRED)
  find_program(LLVM_READOBJ NAMES llvm-readobj REQUIRED)
  add_custom_target(verify-windows-dependencies
    COMMAND "${CMAKE_COMMAND}"
      "-DLLVM_READOBJ=${LLVM_READOBJ}"
      "-DPORTMIDI_DLL=${PORTMIDI_RUNTIME_DLL}"
      "-DPMLIB_MODULE=$<TARGET_FILE:pmlib>"
      "-DMIDIFILE_MODULE=$<TARGET_FILE:midifile>"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
    DEPENDS pmlib midifile
    COMMENT "Verifying the pure-midi Windows dependency closure"
    VERBATIM)
endif()

include(CTest)
if(BUILD_TESTING)
	if(WIN32)
		foreach(variant IN ITEMS release asan)
			set(lifecycle_target "pure-midi-lifecycle-${variant}")
			add_executable(${lifecycle_target} tests/midi_lifecycle_harness.c midi_stream.c)
			target_compile_features(${lifecycle_target} PRIVATE c_std_11)
			target_compile_definitions(${lifecycle_target} PRIVATE PURE_MIDI_TEST_SEAM=1)
			target_link_libraries(${lifecycle_target} PRIVATE PkgConfig::PORTMIDI)
			target_compile_options(${lifecycle_target} PRIVATE -Wall -Wextra -Werror)
			if(variant STREQUAL "asan")
				target_compile_options(${lifecycle_target} PRIVATE -fsanitize=address -fno-omit-frame-pointer)
				target_link_options(${lifecycle_target} PRIVATE -fsanitize=address)
			endif()
			add_test(NAME ${lifecycle_target} COMMAND ${lifecycle_target})
			set_tests_properties(${lifecycle_target} PROPERTIES
				LABELS "midi;lifecycle;fault;${variant};no-hardware"
				ENVIRONMENT "ASAN_OPTIONS=detect_leaks=0:halt_on_error=1:strict_string_checks=1"
				ENVIRONMENT_MODIFICATION "PATH=path_list_prepend:$ENV{MSYSTEM_PREFIX}/bin"
				TIMEOUT 180)
		endforeach()
	endif()
	set(MIDI_BOUNDARY_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/midi-boundary")
	set(MIDI_BOUNDARY_FAKE_DIRECTORY "${MIDI_BOUNDARY_DIRECTORY}/fake")
	file(MAKE_DIRECTORY "${MIDI_BOUNDARY_DIRECTORY}" "${MIDI_BOUNDARY_FAKE_DIRECTORY}")

	add_library(pure-midi-boundary-fake MODULE tests/midi_boundary_harness.c midi_bounds.c midi_stream.c pmdev.c)
	target_compile_features(pure-midi-boundary-fake PRIVATE c_std_11)
	target_compile_definitions(pure-midi-boundary-fake PRIVATE PURE_MIDI_BOUNDARY_FAKE=1)
	target_link_libraries(pure-midi-boundary-fake PRIVATE PkgConfig::PURE)
	target_include_directories(pure-midi-boundary-fake PRIVATE ${PORTMIDI_INCLUDE_DIRS})
	if(NOT WIN32)
		target_link_libraries(pure-midi-boundary-fake PRIVATE Threads::Threads)
	endif()
	set_target_properties(pure-midi-boundary-fake PROPERTIES
		PREFIX ""
		OUTPUT_NAME "pmlib"
		LIBRARY_OUTPUT_DIRECTORY "${MIDI_BOUNDARY_FAKE_DIRECTORY}"
		RUNTIME_OUTPUT_DIRECTORY "${MIDI_BOUNDARY_FAKE_DIRECTORY}"
		WINDOWS_EXPORT_ALL_SYMBOLS ON)
	if(MINGW)
		target_compile_options(pure-midi-boundary-fake PRIVATE -Wall -Wextra -Werror)
		target_link_options(pure-midi-boundary-fake PRIVATE "LINKER:--enable-auto-import")
	endif()

	add_executable(pure-midi-boundary
		tests/midi_boundary_harness.c
		midifile/mf.c
		midi_bounds.c
		midifile/midifile.c)
	target_compile_features(pure-midi-boundary PRIVATE c_std_11)
	target_compile_definitions(pure-midi-boundary PRIVATE PURE_MIDI_TEST_SEAM=1)
	target_include_directories(pure-midi-boundary PRIVATE midifile tests)
	target_link_libraries(pure-midi-boundary PRIVATE PkgConfig::PURE)
	if(MINGW)
		target_compile_options(pure-midi-boundary PRIVATE
			-Wall -Wextra -Werror -fsanitize=address -fno-omit-frame-pointer)
		target_link_options(pure-midi-boundary PRIVATE -fsanitize=address)
	endif()
	add_test(NAME pure-midi-boundary COMMAND pure-midi-boundary)
	set_tests_properties(pure-midi-boundary PROPERTIES
		LABELS "midi;boundary;asan;no-hardware"
		ENVIRONMENT "ASAN_OPTIONS=detect_leaks=0:halt_on_error=1:strict_string_checks=1"
		ENVIRONMENT_MODIFICATION "PATH=path_list_prepend:${PURE_PREFIX}/bin;PATH=path_list_prepend:$ENV{MSYSTEM_PREFIX}/bin"
		WORKING_DIRECTORY "${MIDI_BOUNDARY_DIRECTORY}"
		TIMEOUT 30)
	add_executable(pure-midi-boundary-release
		tests/midi_boundary_harness.c midifile/mf.c midifile/midifile.c midi_bounds.c)
	target_compile_features(pure-midi-boundary-release PRIVATE c_std_11)
	target_compile_definitions(pure-midi-boundary-release PRIVATE PURE_MIDI_TEST_SEAM=1)
	target_include_directories(pure-midi-boundary-release PRIVATE midifile tests)
	target_link_libraries(pure-midi-boundary-release PRIVATE PkgConfig::PURE)
	if(MINGW)
		target_compile_options(pure-midi-boundary-release PRIVATE -Wall -Wextra -Werror)
	endif()
	add_test(NAME pure-midi-boundary-release COMMAND pure-midi-boundary-release)
	set_tests_properties(pure-midi-boundary-release PROPERTIES
		LABELS "midi;boundary;no-hardware"
		ENVIRONMENT_MODIFICATION "PATH=path_list_prepend:${PURE_PREFIX}/bin;PATH=path_list_prepend:$ENV{MSYSTEM_PREFIX}/bin"
		WORKING_DIRECTORY "${MIDI_BOUNDARY_DIRECTORY}" TIMEOUT 30)

	set(MIDIFILE_FAULT_RELEASE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/midifile-fault-release")
	set(MIDIFILE_FAULT_ASAN_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/midifile-fault-asan")
	set(MIDIFILE_FAULT_DEADLINE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/midifile-fault-deadline")
	file(MAKE_DIRECTORY
		"${MIDIFILE_FAULT_RELEASE_DIRECTORY}"
		"${MIDIFILE_FAULT_ASAN_DIRECTORY}"
		"${MIDIFILE_FAULT_DEADLINE_DIRECTORY}")

	add_executable(pure-midi-midifile-fault
		tests/midifile_fault_harness.c
		midifile/midifile.c)
	target_compile_features(pure-midi-midifile-fault PRIVATE c_std_11)
	target_compile_definitions(pure-midi-midifile-fault PRIVATE PURE_MIDI_TEST_SEAM=1)
	target_include_directories(pure-midi-midifile-fault PRIVATE midifile tests)
	if(MINGW)
		target_compile_options(pure-midi-midifile-fault PRIVATE -Wall -Wextra -Werror)
	endif()
	add_test(NAME pure-midi-midifile-fault
		COMMAND pure-midi-midifile-fault "${CMAKE_CURRENT_SOURCE_DIR}/examples/prelude3.mid")
	set_tests_properties(pure-midi-midifile-fault PROPERTIES
		LABELS "midi;midifile;fault;no-hardware"
		WORKING_DIRECTORY "${MIDIFILE_FAULT_RELEASE_DIRECTORY}"
		TIMEOUT 20)
	add_test(NAME pure-midi-midifile-deadline-contract
		COMMAND pure-midi-midifile-fault
			"${CMAKE_CURRENT_SOURCE_DIR}/examples/prelude3.mid"
			--deadline-contract)
	set_tests_properties(pure-midi-midifile-deadline-contract PROPERTIES
		LABELS "midi;midifile;fault;deadline;no-hardware"
		PASS_REGULAR_EXPRESSION "malformed fixture exceeded two-second deadline"
		WORKING_DIRECTORY "${MIDIFILE_FAULT_DEADLINE_DIRECTORY}"
		TIMEOUT 5)

	if(MINGW AND CMAKE_C_COMPILER_ID MATCHES "Clang")
		add_executable(pure-midi-midifile-fault-asan
			tests/midifile_fault_harness.c
			midifile/midifile.c)
		target_compile_features(pure-midi-midifile-fault-asan PRIVATE c_std_11)
		target_compile_definitions(pure-midi-midifile-fault-asan PRIVATE PURE_MIDI_TEST_SEAM=1)
		target_include_directories(pure-midi-midifile-fault-asan PRIVATE midifile tests)
		target_compile_options(pure-midi-midifile-fault-asan PRIVATE
			-Wall -Wextra -Werror -fsanitize=address -fno-omit-frame-pointer)
		target_link_options(pure-midi-midifile-fault-asan PRIVATE -fsanitize=address)
		add_test(NAME pure-midi-midifile-fault-asan
			COMMAND pure-midi-midifile-fault-asan "${CMAKE_CURRENT_SOURCE_DIR}/examples/prelude3.mid")
		set_tests_properties(pure-midi-midifile-fault-asan PROPERTIES
			LABELS "midi;midifile;fault;asan;no-hardware"
			ENVIRONMENT "ASAN_OPTIONS=detect_leaks=0:halt_on_error=1:strict_string_checks=1"
			WORKING_DIRECTORY "${MIDIFILE_FAULT_ASAN_DIRECTORY}"
			TIMEOUT 30)
	endif()

  if(WIN32)
    set(MIDI_CONTRACT_ROOT "${CMAKE_CURRENT_BINARY_DIR}/pure-midi-contract-root")
    file(MAKE_DIRECTORY "${MIDI_CONTRACT_ROOT}")
    get_filename_component(MIDI_RUNTIME_DIR "${PORTMIDI_RUNTIME_DLL}" DIRECTORY)
    add_executable(run_pure_test tests/run_pure_test.c)
    target_compile_features(run_pure_test PRIVATE c_std_11)
    target_compile_definitions(run_pure_test PRIVATE
      "PURE_MIDI_CONTRACT_ROOT=\"${MIDI_CONTRACT_ROOT}\"")
    target_compile_options(run_pure_test PRIVATE -Wall -Wextra -Werror)
    target_link_options(run_pure_test PRIVATE -municode)
    target_link_libraries(run_pure_test PRIVATE bcrypt)

    add_executable(pure-midi-runner-fixture tests/runner_fixture.c)
    target_compile_options(pure-midi-runner-fixture PRIVATE -Wall -Wextra -Werror)
    add_test(NAME pure-midi-native-environment-contract COMMAND pure-midi-runner-fixture --native-environment)
    set_tests_properties(pure-midi-native-environment-contract PROPERTIES
      LABELS "midi;contract;no-hardware" TIMEOUT 5)
    # Native fault harnesses also embed Pure. An inherited PURELIB can skip its
    # normal prelude initialization while their low-level assertions still run.
    # Preserve the existing harnesses/counters but give them the declared loader
    # path and remove the same parent settings as the native Pure supervisor.
    foreach(native IN ITEMS pure-midi-lifecycle-release pure-midi-lifecycle-asan
        pure-midi-boundary pure-midi-boundary-release pure-midi-midifile-fault
        pure-midi-midifile-deadline-contract pure-midi-midifile-fault-asan
        pure-midi-native-environment-contract)
      if(TEST ${native})
        set_property(TEST ${native} APPEND PROPERTY ENVIRONMENT_MODIFICATION
          "PURELIB=unset:" "PURE_INCLUDE=unset:" "PURE_LIBRARY=unset:"
          "PURE_MIDI_OUT=unset:" "PURE_MIDI_IN=unset:" "PURE_RUNNER_POISON=unset:"
          "PATH=set:${PURE_PREFIX}/bin" "PATH=path_list_append:${MIDI_RUNTIME_DIR}"
          "PATH=path_list_append:$ENV{SystemRoot}/System32" "PATH=path_list_append:$ENV{SystemRoot}")
      endif()
    endforeach()
    add_library(pure-midi-hardware-fixture MODULE
      tests/runner_hardware_fixture.c midi_bounds.c midi_stream.c pmdev.c)
    target_compile_definitions(pure-midi-hardware-fixture PRIVATE PURE_MIDI_BOUNDARY_FAKE=1)
    target_compile_options(pure-midi-hardware-fixture PRIVATE -Wall -Wextra -Werror)
    target_link_libraries(pure-midi-hardware-fixture PRIVATE PkgConfig::PURE)
    target_include_directories(pure-midi-hardware-fixture PRIVATE ${PORTMIDI_INCLUDE_DIRS})
    target_link_options(pure-midi-hardware-fixture PRIVATE "LINKER:--enable-auto-import")
    set_target_properties(pure-midi-hardware-fixture PROPERTIES PREFIX "" OUTPUT_NAME pmlib
      LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/hardware-fake"
      RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/hardware-fake"
      WINDOWS_EXPORT_ALL_SYMBOLS ON)
    find_program(PURE_EXECUTABLE NAMES pure
      HINTS "${PURE_PREFIX}/bin" NO_DEFAULT_PATH REQUIRED)
    set(MIDI_POWERSHELL "$ENV{SystemRoot}/System32/WindowsPowerShell/v1.0/powershell.exe")
    find_program(MIDI_MAKE_EXECUTABLE NAMES mingw32-make REQUIRED)
    find_program(MIDI_MAKE_SHELL NAMES sh HINTS "${MIDI_RUNTIME_DIR}/../../usr/bin" REQUIRED)
    foreach(contract IN ITEMS runner cleanup hardware-runner)
      set(contract_script "${contract}")
      set(extra)
      if(contract STREQUAL hardware-runner)
        set(contract_script runner)
        set(extra -DHARDWARE_ONLY=ON)
      endif()
      add_test(NAME pure-midi-${contract}-contract
        COMMAND "${CMAKE_COMMAND}" "-DRUNNER=$<TARGET_FILE:run_pure_test>"
          "-DFIXTURE_EXE=$<TARGET_FILE:pure-midi-runner-fixture>"
          "-DCONTRACT_ROOT=${MIDI_CONTRACT_ROOT}"
          "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
          "-DRUNTIME_DIR=${MIDI_RUNTIME_DIR}" "-DPOWERSHELL=${MIDI_POWERSHELL}"
          "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}" "-DMODULE_DIR=$<TARGET_FILE_DIR:midifile>"
          "-DHARDWARE_MODULE=$<TARGET_FILE:pure-midi-hardware-fixture>"
          "-DMAKE_EXE=${MIDI_MAKE_EXECUTABLE}" "-DMAKE_SHELL=${MIDI_MAKE_SHELL}"
          ${extra} -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/${contract_script}_contract.cmake")
      set_tests_properties(pure-midi-${contract}-contract PROPERTIES
        LABELS "midi;contract;no-hardware" TIMEOUT 90 RUN_SERIAL TRUE)
    endforeach()

    foreach(case IN ITEMS bounds device-timing smoke)
      set(test_pmlib "$<TARGET_FILE:pmlib>")
      if(case STREQUAL bounds)
        set(test_pmlib "$<TARGET_FILE:pure-midi-boundary-fake>")
      endif()
      add_test(NAME pure-midi-${case}
        COMMAND "${CMAKE_COMMAND}" "-DRUNNER=$<TARGET_FILE:run_pure_test>"
          "-DCONTRACT_ROOT=${MIDI_CONTRACT_ROOT}"
          "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
          "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
          "-DPURE_STDLIB=${PURE_PREFIX}/lib/pure"
          "-DMODULE_DIR=$<TARGET_FILE_DIR:midifile>"
          "-DPMLIB_MODULE=${test_pmlib}"
          "-DRUNTIME_DIRS=${MIDI_RUNTIME_DIR}"
          "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/${case}.pure"
          "-DFIXTURE=${CMAKE_CURRENT_SOURCE_DIR}/examples/prelude3.mid"
          -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake")
      set_tests_properties(pure-midi-${case} PROPERTIES
        LABELS "midi;pure;no-hardware" TIMEOUT 45
        REQUIRED_FILES "${test_pmlib};$<TARGET_FILE:midifile>")
    endforeach()

    add_custom_target(check-midi-output
      COMMAND "${CMAKE_COMMAND}" "-DRUNNER=$<TARGET_FILE:run_pure_test>"
        "-DCONTRACT_ROOT=${MIDI_CONTRACT_ROOT}"
        "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
        "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
        "-DPURE_STDLIB=${PURE_PREFIX}/lib/pure"
        "-DMODULE_DIR=$<TARGET_FILE_DIR:pmlib>"
        "-DRUNTIME_DIRS=${MIDI_RUNTIME_DIR}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunHardwareTest.cmake"
      DEPENDS run_pure_test pmlib midifile
      COMMENT "Running optional bounded MIDI output (PURE_MIDI_TEST_OUTPUT selects device)"
      VERBATIM)
  else()
    # Preserve the upstream non-Windows public tests. The native Windows job,
    # path and owned-cleanup contracts above make no POSIX verification claim.
    find_program(PURE_EXECUTABLE NAMES pure HINTS "${PURE_PREFIX}/bin" REQUIRED)
    string(RANDOM LENGTH 64 ALPHABET 0123456789abcdef portable_token)
    foreach(case IN ITEMS bounds device-timing smoke)
      set(test_pmlib "$<TARGET_FILE_DIR:pmlib>")
      if(case STREQUAL bounds)
        set(test_pmlib "$<TARGET_FILE_DIR:pure-midi-boundary-fake>")
      endif()
      file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/portable-${case}")
      add_test(NAME pure-midi-${case}
        COMMAND "${CMAKE_COMMAND}" -E env --unset=PURELIB --unset=PURE_INCLUDE --unset=PURE_LIBRARY
          "PURE_MIDI_TEST_TOKEN=${portable_token}"
          "PURE_MIDI_TEST_FIXTURE=${CMAKE_CURRENT_SOURCE_DIR}/examples/prelude3.mid"
          "${PURE_EXECUTABLE}" --norc -I "${CMAKE_CURRENT_SOURCE_DIR}"
          -I "${CMAKE_CURRENT_SOURCE_DIR}/midifile" -L "${test_pmlib}"
          -L "$<TARGET_FILE_DIR:midifile>" -x "${CMAKE_CURRENT_SOURCE_DIR}/tests/${case}.pure")
      set_tests_properties(pure-midi-${case} PROPERTIES LABELS "midi;pure;no-hardware"
        TIMEOUT 45 PASS_REGULAR_EXPRESSION "${portable_token}"
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/portable-${case}")
    endforeach()
  endif()
endif()

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/Install.cmake")
