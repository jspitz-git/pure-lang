cmake_minimum_required(VERSION 3.25)

project(PurePad LANGUAGES CXX RC)

if(NOT MSVC)
  message(FATAL_ERROR "PurePad requires the Microsoft Visual C++ toolchain.")
endif()

if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
  message(FATAL_ERROR "PurePad is supported only as a 64-bit build.")
endif()

set(CMAKE_MFC_FLAG 2)

add_executable(purepad WIN32
  Buffer.cpp
  evalview.cpp
  Gotodlg.cpp
  HistfileDlg.cpp
  History.cpp
  HistsizeDlg.cpp
  MainFrm.cpp
  Pipe.cpp
  PromptDlg.cpp
  qpad.cpp
  qpadDoc.cpp
  purepad.manifest
  qpadView.cpp
  QPathDlg.cpp
  StdAfx.cpp
  TabStopDlg.cpp
  qpad.rc
)

target_compile_definitions(purepad PRIVATE
  _AFXDLL
  UNICODE
  _UNICODE
  WINVER=0x0A00
  _WIN32_WINNT=0x0A00
)

target_compile_features(purepad PRIVATE cxx_std_17)

target_compile_options(purepad PRIVATE
  /W3
  /EHsc
)

target_link_libraries(purepad PRIVATE
  htmlhelp
)

set_property(TARGET purepad PROPERTY
  VS_DPI_AWARE "PerMonitor"
)

target_link_options(purepad PRIVATE
  "/MANIFESTINPUT:${CMAKE_CURRENT_SOURCE_DIR}/purepad.manifest"
)
