#include "reduce_bridge.h"

#include <cstring>
#include <iostream>

namespace {

int failures = 0;

void expect(bool condition, const char *message)
{
    if (!condition)
    {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

} // namespace

int main()
{
    expect(pure_reduce_state() == PURE_REDUCE_UNINITIALIZED,
           "bridge starts uninitialized");
    expect(pure_reduce_finish() == 0,
           "finish succeeds before initialization");
    expect(pure_reduce_finish() == 0,
           "finish remains idempotent before initialization");
    expect(pure_reduce_state() == PURE_REDUCE_UNINITIALIZED,
           "pre-start finish preserves the uninitialized state");

    expect(pure_reduce_start(nullptr) != 0,
           "null image path is rejected");
    expect(pure_reduce_state() == PURE_REDUCE_FAILED,
           "null image rejection records failure state");
    expect(std::strcmp(pure_reduce_last_error(), "image path is required") == 0,
           "null image rejection has stable diagnostics");

    expect(pure_reduce_start("") != 0,
           "empty image path is rejected");
    expect(pure_reduce_state() == PURE_REDUCE_FAILED,
           "empty image rejection records failure state");
    expect(std::strcmp(pure_reduce_last_error(), "image path is required") == 0,
           "empty image rejection has the same stable diagnostics");

    return failures == 0 ? 0 : 1;
}
