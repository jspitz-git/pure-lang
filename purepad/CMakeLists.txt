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
  ProcessSession.cpp
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

if(CMAKE_MT MATCHES "-NOTFOUND$")
  find_program(CMAKE_MT NAMES mt mt.exe
    HINTS
      "[HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows Kits\\Installed Roots;KitsRoot10]/bin/${CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION}/x64"
      "$ENV{WindowsSdkDir}/bin/${CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION}/x64")
endif()
if(NOT CMAKE_MT OR CMAKE_MT MATCHES "-NOTFOUND$")
  message(FATAL_ERROR "The Windows SDK manifest tool (mt.exe) is required.")
endif()

install(TARGETS purepad RUNTIME DESTINATION bin COMPONENT PurePad)
install(FILES WINDOWS.md DESTINATION share/doc/purepad COMPONENT PurePad)

include(CTest)
if(BUILD_TESTING)
  add_executable(purepad-process-child tests/process_child.cpp)
  add_executable(purepad-process-session-tests
    tests/process_session_tests.cpp Buffer.cpp ProcessSession.cpp)
  target_compile_features(purepad-process-child PRIVATE cxx_std_17)
  target_compile_features(purepad-process-session-tests PRIVATE cxx_std_17)
  target_compile_definitions(purepad-process-session-tests PRIVATE
    _AFXDLL
    UNICODE
    _UNICODE
    WINVER=0x0A00
    _WIN32_WINNT=0x0A00
  )
  target_include_directories(purepad-process-session-tests PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}")
  add_test(NAME purepad-process-session
    COMMAND purepad-process-session-tests
      "$<TARGET_FILE:purepad-process-child>")
  add_test(NAME purepad-install-contract
    COMMAND "${CMAKE_COMMAND}"
      "-DPUREPAD_CMAKE_COMMAND=${CMAKE_COMMAND}"
      "-DPUREPAD_BUILD_DIR=${CMAKE_BINARY_DIR}"
      "-DPUREPAD_SOURCE_DIR=${CMAKE_SOURCE_DIR}"
      "-DPUREPAD_CONFIGURATION=$<CONFIG>"
      "-DPUREPAD_CMAKE_MT=${CMAKE_MT}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/install_contract.cmake")
endif()
