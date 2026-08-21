#include "ProcessSession.h"
#include <chrono>
#include <iostream>
#include <mutex>
#include <string>
#include <vector>

using namespace std::chrono_literals;

static int failures = 0;
#define CHECK(condition) do { if (!(condition)) { \
  std::cerr << __FILE__ << ':' << __LINE__ << ": " #condition "\n"; \
  ++failures; } } while (false)

int wmain(int argc, wchar_t** argv) {
  CHECK(argc == 2);
  std::mutex output_mutex;
  std::string output;
  purepad::ProcessSession session;
  purepad::ProcessCallbacks callbacks;
  callbacks.output = [&](std::string_view bytes) {
    std::lock_guard<std::mutex> lock(output_mutex);
    output.append(bytes);
  };
  purepad::ProcessLaunch launch;
  launch.application = argv[1];
  launch.arguments = {L"--echo"};
  auto started = session.Start(launch, std::move(callbacks));
  CHECK(started.ok());
  CHECK(session.Write("hello\n"));
  CHECK(session.WaitForExit(5s));
  session.Stop();
  CHECK(!session.IsRunning());
  {
    std::lock_guard<std::mutex> lock(output_mutex);
    CHECK(output == "READY\r\nhello\r\nDONE\r\n");
  }
  return failures == 0 ? 0 : 1;
}
