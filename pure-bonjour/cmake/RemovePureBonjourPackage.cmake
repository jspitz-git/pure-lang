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
