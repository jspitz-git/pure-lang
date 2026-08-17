foreach(_required IN ITEMS PURE_REDUCE_SOURCE_DIR PURE_REDUCE_SOURCE_TREE_SHA256)
  if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
    message(FATAL_ERROR "${_required} is required")
  endif()
endforeach()

include("${CMAKE_CURRENT_LIST_DIR}/../cmake/ReduceUpstream.cmake")

_pure_reduce_expected_upstream_stamp("commit" "tree" _stamp)
string(CONCAT _expected_stamp
  "commit\ntree\n"
  "2d88d6d4a842ccb4574b60b0bd7e3af91896cea76708551a6e54489792e91d08\n"
  "ad89f9581eefaaf4191b65af1b769a18883e865ee2740e4e6f053d1c5615d0e9\n")
if(NOT _stamp STREQUAL _expected_stamp OR _stamp MATCHES ";")
  message(FATAL_ERROR
    "upstream stamp must be four newline-delimited identity fields")
endif()

set(_fixture "${CMAKE_CURRENT_BINARY_DIR}/pure-reduce-utf8-image-patch")
file(REMOVE_RECURSE "${_fixture}")
_pure_reduce_checkout_pinned_files(
  "${PURE_REDUCE_SOURCE_DIR}" "${_fixture}"
  csl/cslbase/preserve.cpp
  csl/cslbase/winsupport.cpp
  csl/cslbase/winsupport.h)

_pure_reduce_apply_private_source_patch(
  "${_fixture}"
  "${CMAKE_CURRENT_LIST_DIR}/../patches/0001-csl-winsupport-define-nil.patch"
  "${PURE_REDUCE_SOURCE_TREE_SHA256}"
  "${_fixture}/patches.log"
  _nil_patch_json)
_pure_reduce_apply_private_source_patch(
  "${_fixture}"
  "${CMAKE_CURRENT_LIST_DIR}/../patches/0002-csl-windows-utf8-image-open.patch"
  "${PURE_REDUCE_SOURCE_TREE_SHA256}"
  "${_fixture}/patches.log"
  _utf8_patch_json)

string(JSON _target_count LENGTH "${_utf8_patch_json}" targets)
if(NOT _target_count EQUAL 3)
  message(FATAL_ERROR
    "UTF-8 image patch provenance must cover exactly three targets")
endif()
set(_actual_targets)
foreach(_index RANGE 0 2)
  string(JSON _target GET "${_utf8_patch_json}" targets ${_index} path)
  list(APPEND _actual_targets "${_target}")
endforeach()
set(_expected_targets
  csl/cslbase/preserve.cpp
  csl/cslbase/winsupport.cpp
  csl/cslbase/winsupport.h)
list(SORT _actual_targets)
list(SORT _expected_targets)
if(NOT _actual_targets STREQUAL _expected_targets)
  message(FATAL_ERROR
    "UTF-8 image patch provenance names wrong targets: ${_actual_targets}")
endif()

file(READ "${_fixture}/csl/cslbase/preserve.cpp" _preserve)
file(READ "${_fixture}/csl/cslbase/winsupport.cpp" _winsupport_cpp)
file(READ "${_fixture}/csl/cslbase/winsupport.h" _winsupport_h)
if(NOT _preserve MATCHES "windowsFopenUtf8" OR
   NOT _preserve MATCHES "windowsFileStatusUtf8" OR
   NOT _winsupport_cpp MATCHES "MultiByteToWideChar\\(CP_UTF8" OR
   NOT _winsupport_cpp MATCHES "_wfopen" OR
   NOT _winsupport_h MATCHES "windowsFopenUtf8" OR
   NOT _winsupport_h MATCHES "windowsFileStatusUtf8")
  message(FATAL_ERROR
    "UTF-8 image patch does not route the Windows image-open boundary")
endif()

file(REMOVE_RECURSE "${_fixture}")
