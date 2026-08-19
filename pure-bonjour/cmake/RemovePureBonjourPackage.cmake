cmake_minimum_required(VERSION 3.25)

include("${CMAKE_CURRENT_LIST_DIR}/PureBonjourPackageSafety.cmake")
foreach(required IN ITEMS PREFIX BUILD_PREFIX)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "" OR
      NOT IS_ABSOLUTE "${${required}}")
    pure_bonjour_safety_fail(PACKAGE_INVENTORY
      "${required} must be an absolute path")
  endif()
endforeach()
if(NOT EXISTS "${PREFIX}" OR NOT IS_DIRECTORY "${PREFIX}")
  pure_bonjour_safety_fail(PACKAGE_PATH
    "installed prefix does not exist: ${PREFIX}")
endif()
pure_bonjour_fs_action(inspect-dir "${PREFIX}" "" PACKAGE_PATH)
file(REAL_PATH "${PREFIX}" prefix)
set(oracle_input "${BUILD_PREFIX}/PureBonjourExpected.sha256")
pure_bonjour_parse_external_oracle("${oracle_input}" "${prefix}"
  oracle owned_paths owned_identities owned_hashes)

# Complete preflight: no deletion occurs until every owned file and both
# package-specific directories have passed a fresh no-follow containment walk.
foreach(relative IN LISTS owned_paths)
  pure_bonjour_fs_action(inspect-file "${prefix}/${relative}"
    "${prefix}" PACKAGE_PATH)
endforeach()
foreach(relative IN ITEMS
    share/doc/pure-bonjour/examples
    share/doc/pure-bonjour)
  pure_bonjour_fs_action(inspect-dir "${prefix}/${relative}"
    "${prefix}" PACKAGE_PATH)
endforeach()

# Deterministic adversarial seam for the script test only.  Normal package
# removal never defines these variables; the hook does not replace or weaken
# the fresh no-follow checks performed by each deletion below.
if(DEFINED PACKAGE_TEST_POST_PREFLIGHT_SCRIPT AND
    NOT PACKAGE_TEST_POST_PREFLIGHT_SCRIPT STREQUAL "")
  if(NOT DEFINED PACKAGE_ENABLE_TEST_HOOKS OR
      NOT PACKAGE_ENABLE_TEST_HOOKS STREQUAL "ON")
    pure_bonjour_safety_fail(PACKAGE_TEST_HOOK
      "post-preflight hook requires explicit PACKAGE_ENABLE_TEST_HOOKS=ON")
  endif()
  pure_bonjour_fs_action(inspect-file
    "${PACKAGE_TEST_POST_PREFLIGHT_SCRIPT}" "" PACKAGE_TEST_HOOK)
  set(package_powershell
    "$ENV{SystemRoot}/System32/WindowsPowerShell/v1.0/powershell.exe")
  execute_process(
    COMMAND "${package_powershell}" -NoLogo -NoProfile -NonInteractive
      -File "${PACKAGE_TEST_POST_PREFLIGHT_SCRIPT}"
      -Prefix "${prefix}" -Target "${PACKAGE_TEST_POST_PREFLIGHT_TARGET}"
    RESULT_VARIABLE hook_result
    OUTPUT_VARIABLE hook_output
    ERROR_VARIABLE hook_error
    ENCODING UTF-8)
  if(NOT hook_result EQUAL 0)
    pure_bonjour_safety_fail(PACKAGE_TEST_HOOK
      "post-preflight test hook failed: ${hook_output}${hook_error}")
  endif()
endif()

foreach(relative IN LISTS owned_paths)
  pure_bonjour_fs_action(remove-file "${prefix}/${relative}"
    "${prefix}" PACKAGE_PATH)
endforeach()
foreach(relative IN ITEMS
    share/doc/pure-bonjour/examples
    share/doc/pure-bonjour)
  pure_bonjour_fs_action(remove-empty-dir "${prefix}/${relative}"
    "${prefix}" PACKAGE_PATH)
endforeach()
message(STATUS "PureBonjour exact oracle-bounded removal completed")
