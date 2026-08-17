cmake_minimum_required(VERSION 3.25)

foreach(_required IN ITEMS
    REDUCE_UPSTREAM_MODULE MSYS2_BASH CXX_COMPILER)
  if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
    message(FATAL_ERROR "${_required} is required")
  endif()
endforeach()

include("${REDUCE_UPSTREAM_MODULE}")
string(SHA256 _root_key "${CMAKE_CURRENT_BINARY_DIR}")
file(TO_CMAKE_PATH
  "$ENV{TEMP}/pure reduce prefix map response-${_root_key}" _root)
_pure_reduce_private_source_path(
  "${MSYS2_BASH}" "${_root}/build root with spaces" _private_source)
if(_private_source MATCHES "[ \t\r\n]" OR
   NOT _private_source MATCHES "/tmp/pure-reduce-source-[0-9a-f]+$")
  message(FATAL_ERROR
    "private REDUCE source path is not isolated in no-space scratch: "
    "${_private_source}")
endif()
set(_source "${_root}/source with spaces")
file(REMOVE_RECURSE "${_root}")
file(MAKE_DIRECTORY "${_source}")
file(WRITE "${_source}/probe.cpp"
  "const char *pure_reduce_source_probe = __FILE__;\n"
  "int main() { return pure_reduce_source_probe[0] == 0; }\n")

_pure_reduce_write_prefix_map_response(
  "${_source}" "${MSYS2_BASH}" _response_file _response_argument)
if(_response_file MATCHES "[ \t\r\n]" OR
    NOT _response_argument STREQUAL "@${_response_file}")
  message(FATAL_ERROR
    "compiler response argument is not one no-space token: "
    "${_response_argument}")
endif()
set(_compile_script [=[
if [ "$#" -ne 4 ]; then
  printf 'expected 4 arguments, got %s\n' "$#" >&2
  exit 31
fi
compiler=$1
response=$2
source=$3
output=$4
"$compiler" "@$response" -c "$source/probe.cpp" -o "$output"
]=])
execute_process(
  COMMAND "${MSYS2_BASH}" --noprofile --norc -c "${_compile_script}"
    pure-reduce "${CXX_COMPILER}" "${_response_file}"
    "${_source}" "${_root}/probe.obj"
  RESULT_VARIABLE _compile_result
  OUTPUT_VARIABLE _compile_output
  ERROR_VARIABLE _compile_error
  ENCODING UTF-8)
file(REMOVE "${_response_file}")
if(NOT _compile_result EQUAL 0)
  file(REMOVE_RECURSE "${_root}")
  message(FATAL_ERROR
    "response-file prefix-map compile failed (${_compile_result})\n"
    "stdout:\n${_compile_output}\nstderr:\n${_compile_error}")
endif()

file(READ "${_root}/probe.obj" _object_hex HEX)
string(TOLOWER "${_object_hex}" _object_hex)
string(HEX "${_source}" _source_hex)
string(TOLOWER "${_source_hex}" _source_hex)
string(REPLACE "/" "\\" _source_backslash "${_source}")
string(HEX "${_source_backslash}" _source_backslash_hex)
string(TOLOWER "${_source_backslash_hex}" _source_backslash_hex)
string(HEX "/usr/src/pure-reduce-upstream/probe.cpp" _mapped_hex)
string(TOLOWER "${_mapped_hex}" _mapped_hex)
string(HEX "\\usr\\src\\pure-reduce-upstream\\probe.cpp"
  _mapped_backslash_hex)
string(TOLOWER "${_mapped_backslash_hex}" _mapped_backslash_hex)
string(FIND "${_object_hex}" "${_source_hex}" _source_at)
string(FIND "${_object_hex}" "${_source_backslash_hex}"
  _source_backslash_at)
string(FIND "${_object_hex}" "${_mapped_hex}" _mapped_at)
string(FIND "${_object_hex}" "${_mapped_backslash_hex}"
  _mapped_backslash_at)
if(NOT _source_at EQUAL -1 OR NOT _source_backslash_at EQUAL -1 OR
    (_mapped_at EQUAL -1 AND _mapped_backslash_at EQUAL -1))
  file(STRINGS "${_root}/probe.obj" _object_strings)
  message(FATAL_ERROR
    "response-file prefix maps did not replace the spaced source path "
    "(source_at=${_source_at}/${_source_backslash_at}, "
    "mapped_at=${_mapped_at}/${_mapped_backslash_at})\n"
    "object strings:\n${_object_strings}\nroot: ${_root}")
endif()
file(REMOVE_RECURSE "${_root}")
