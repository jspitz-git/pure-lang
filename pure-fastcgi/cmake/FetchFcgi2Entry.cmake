cmake_minimum_required(VERSION 3.25)

if(NOT DEFINED OUTPUT OR "${OUTPUT}" STREQUAL "")
  message(FATAL_ERROR "OUTPUT is required")
endif()
include("${CMAKE_CURRENT_LIST_DIR}/FetchFcgi2.cmake")
pure_fastcgi_fetch_fcgi2(OUTPUT "${OUTPUT}")
