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

add_pure_midi_module(pmlib pmdev.c midi_bounds.c)
target_link_libraries(pmlib PRIVATE PkgConfig::PORTMIDI)

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
	set(MIDI_BOUNDARY_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/midi-boundary")
	set(MIDI_BOUNDARY_FAKE_DIRECTORY "${MIDI_BOUNDARY_DIRECTORY}/fake")
	file(MAKE_DIRECTORY "${MIDI_BOUNDARY_DIRECTORY}" "${MIDI_BOUNDARY_FAKE_DIRECTORY}")
	string(RANDOM LENGTH 24 ALPHABET 0123456789abcdef MIDI_BOUNDS_TOKEN)

	add_library(pure-midi-boundary-fake MODULE tests/midi_boundary_harness.c midi_bounds.c)
	target_compile_features(pure-midi-boundary-fake PRIVATE c_std_11)
	target_compile_definitions(pure-midi-boundary-fake PRIVATE PURE_MIDI_BOUNDARY_FAKE=1)
	target_link_libraries(pure-midi-boundary-fake PRIVATE PkgConfig::PURE)
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

  find_program(PURE_EXECUTABLE
    NAMES pure
    HINTS "${PURE_PREFIX}/bin"
    NO_DEFAULT_PATH
    REQUIRED)
  add_test(
    NAME pure-midi-bounds
    COMMAND "${CMAKE_COMMAND}" -E env
      --modify "PATH=path_list_prepend:$<TARGET_FILE_DIR:pure-midi-boundary-fake>"
      --modify "PATH=path_list_prepend:$<TARGET_FILE_DIR:midifile>"
      "PURE_MIDI_BOUNDS_TOKEN=${MIDI_BOUNDS_TOKEN}"
      "PURE_MIDI_BOUNDS_FIXTURE=${CMAKE_CURRENT_SOURCE_DIR}/examples/prelude3.mid"
      "${PURE_EXECUTABLE}" --norc
        -I "${CMAKE_CURRENT_SOURCE_DIR}"
        -I "${CMAKE_CURRENT_SOURCE_DIR}/midifile"
        -L "$<TARGET_FILE_DIR:pure-midi-boundary-fake>"
        -L "$<TARGET_FILE_DIR:midifile>"
        -x "${CMAKE_CURRENT_SOURCE_DIR}/tests/bounds.pure")
  set_tests_properties(pure-midi-bounds PROPERTIES
    LABELS "midi;boundary;pure;no-hardware"
    ENVIRONMENT_MODIFICATION
      "PATH=path_list_prepend:${PURE_PREFIX}/bin;PATH=path_list_prepend:$ENV{MSYSTEM_PREFIX}/bin"
    PASS_REGULAR_EXPRESSION "${MIDI_BOUNDS_TOKEN}"
    REQUIRED_FILES
      "$<TARGET_FILE:pure-midi-boundary-fake>;$<TARGET_FILE:midifile>;${CMAKE_CURRENT_SOURCE_DIR}/tests/bounds.pure"
    WORKING_DIRECTORY "${MIDI_BOUNDARY_DIRECTORY}"
    TIMEOUT 45)
  add_test(
    NAME pure-midi-device-timing
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DMODULE_DIR=$<TARGET_FILE_DIR:pmlib>"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/device-timing.pure"
      "-DTEST_DIRECTORY=${CMAKE_CURRENT_BINARY_DIR}/device-timing-test"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake")
  set_tests_properties(pure-midi-device-timing PROPERTIES
    LABELS "midi;device-enumeration;timing;no-hardware"
    REQUIRED_FILES "$<TARGET_FILE:pmlib>;${CMAKE_CURRENT_SOURCE_DIR}/midi.pure"
    TIMEOUT 45)
  add_test(
    NAME pure-midi-smoke
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DMODULE_DIR=$<TARGET_FILE_DIR:pmlib>"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
      "-DTEST_DIRECTORY=${CMAKE_CURRENT_BINARY_DIR}/smoke-test"
      "-DFIXTURE=${CMAKE_CURRENT_SOURCE_DIR}/examples/prelude3.mid"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake")
  set_tests_properties(pure-midi-smoke PROPERTIES
    LABELS "midi;encoding;midifile;cleanup;no-hardware"
    REQUIRED_FILES
      "$<TARGET_FILE:pmlib>;$<TARGET_FILE:midifile>;${CMAKE_CURRENT_SOURCE_DIR}/examples/prelude3.mid"
    TIMEOUT 45)
  add_custom_target(check-midi-output
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DMODULE_DIR=$<TARGET_FILE_DIR:pmlib>"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunHardwareTest.cmake"
    DEPENDS pmlib
    COMMENT "Running bounded pure-midi output validation"
    VERBATIM)
endif()

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/Install.cmake")
