#include "reduce_bridge.h"

#include <cstdint>
#include <cstring>
#include <iostream>

#include "proc.h"

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

int basic_contract()
{
    expect(pure_reduce_state() == PURE_REDUCE_UNINITIALIZED,
           "bridge starts uninitialized");
    expect(pure_reduce_finish() == 0,
           "finish succeeds before initialization");
    expect(pure_reduce_finish() == 0,
           "finish remains idempotent before initialization");
    expect(pure_reduce_state() == PURE_REDUCE_UNINITIALIZED,
           "pre-start finish preserves the uninitialized state");

    expect(PROC_capture_output(1) != 0,
           "output callback setup is rejected before CSL start");
    expect(pure_reduce_state() == PURE_REDUCE_UNINITIALIZED,
           "rejected pre-start capture preserves uninitialized state");
    expect(std::strcmp(pure_reduce_last_error(), "REDUCE is not running") == 0,
           "rejected pre-start capture has stable diagnostics");
    expect(PROC_feed_input("pre-start input") != 0,
           "input callback setup is rejected before CSL start");
    expect(pure_reduce_state() == PURE_REDUCE_UNINITIALIZED,
           "rejected pre-start feed preserves uninitialized state");
    expect(std::strcmp(pure_reduce_last_error(), "REDUCE is not running") == 0,
           "rejected pre-start feed has stable diagnostics");

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

bool start_real_image(const char *image)
{
    expect(image != nullptr && image[0] != '\0',
           "live contract receives the Task 2 image path");
    if (image == nullptr || image[0] == '\0') return false;
    expect(pure_reduce_start(image) == 0,
           "real Task 2 image starts in process");
    expect(pure_reduce_state() == PURE_REDUCE_RUNNING,
           "successful real-image start enters running state");
    if (pure_reduce_state() != PURE_REDUCE_RUNNING)
    {
        std::cerr << "startup diagnostic: " << pure_reduce_last_error() << '\n';
        return false;
    }
    return true;
}

int live_redundant_start_contract(const char *image)
{
    if (!start_real_image(image)) return 1;

    expect(pure_reduce_start(image) != 0,
           "redundant real-image start is rejected");
    expect(pure_reduce_state() == PURE_REDUCE_RUNNING,
           "redundant real-image start preserves running state");
    expect(std::strcmp(pure_reduce_last_error(), "REDUCE is already running") == 0,
           "redundant real-image start has stable diagnostics");

    expect(pure_reduce_start(nullptr) != 0,
           "invalid start is rejected while REDUCE is running");
    expect(pure_reduce_state() == PURE_REDUCE_RUNNING,
           "invalid start preserves a live running state");
    expect(std::strcmp(pure_reduce_last_error(), "REDUCE is already running") == 0,
           "invalid running start uses the redundant-start diagnostic");

    expect(pure_reduce_finish() == 0,
           "finish remains available after rejected running starts");
    expect(pure_reduce_state() == PURE_REDUCE_FINISHED,
           "finish after rejected running starts reaches finished state");
    expect(std::strcmp(pure_reduce_last_error(), "") == 0,
           "successful finish releases rejected-start diagnostics");
    expect(pure_reduce_finish() == 0,
           "finish is idempotent after live shutdown");
    expect(pure_reduce_state() == PURE_REDUCE_FINISHED,
           "idempotent finish preserves finished state");
    return failures == 0 ? 0 : 1;
}

int live_cleanup_contract(const char *image)
{
    if (!start_real_image(image)) return 1;

    expect(PROC_capture_output(1) == 0,
           "capture callback can be installed while running");
    expect(PROC_feed_input("unused deterministic input\n") == 0,
           "input callback and owned input buffer can be installed while running");
    expect(CSL_LISP::PROC_prepare_for_top_level_loop() == 0,
           "live CSL prepares its statement processor");
    expect(CSL_LISP::PROC_process_one_reduce_statement(
               "write \"bridge-output\";") == 0,
           "live CSL emits deterministic captured output");
    expect(std::strstr(PROC_get_output(), "bridge-output") != nullptr,
           "capture callback stores deterministic CSL output");

    expect(pure_reduce_finish() == 0,
           "running CSL shuts down after callbacks were installed");
    expect(pure_reduce_state() == PURE_REDUCE_FINISHED,
           "callback-bearing shutdown reaches finished state");
    expect(std::strcmp(PROC_get_output(), "") == 0,
           "shutdown releases captured output storage");
    expect(std::strcmp(pure_reduce_last_error(), "") == 0,
           "successful shutdown releases diagnostic storage");
    expect(pure_reduce_finish() == 0,
           "callback-bearing shutdown remains idempotent");
    expect(pure_reduce_state() == PURE_REDUCE_FINISHED,
           "idempotent callback-bearing shutdown preserves finished state");
    return failures == 0 ? 0 : 1;
}

int live_cons_slot_contract(const char *image)
{
    if (!start_real_image(image)) return 1;

    expect(CSL_LISP::PROC_clear_stack() == 0,
           "live cons contract starts with an empty procedural stack");
    expect(CSL_LISP::PROC_push_small_integer(42) == 0,
           "public save-slot sentinel can be pushed");
    expect(CSL_LISP::PROC_save(99) == 0,
           "public save slot 99 accepts the sentinel");
    expect(CSL_LISP::PROC_push_small_integer(1) == 0,
           "raw cons first operand can be pushed");
    expect(CSL_LISP::PROC_push_small_integer(2) == 0,
           "raw cons second operand can be pushed");
    expect(PROC_make_cons() == 0,
           "bridge constructs a raw cons without evaluating its operands");

    CSL_LISP::PROC_handle pair = CSL_LISP::PROC_get_raw_value();
    expect(pair != nullptr && CSL_LISP::PROC_atom(pair) == 0,
           "raw cons result is a pair");
    if (pair != nullptr && CSL_LISP::PROC_atom(pair) == 0)
    {
        CSL_LISP::PROC_handle first = CSL_LISP::PROC_first(pair);
        CSL_LISP::PROC_handle rest = CSL_LISP::PROC_rest(pair);
        expect(CSL_LISP::PROC_fixnum(first) != 0 &&
                   CSL_LISP::PROC_integer_value(first) == 1,
               "raw cons preserves its first operand");
        expect(CSL_LISP::PROC_fixnum(rest) != 0 &&
                   CSL_LISP::PROC_integer_value(rest) == 2,
               "raw cons preserves its second operand");
    }

    expect(CSL_LISP::PROC_load(99) == 0,
           "public save slot 99 remains loadable after raw cons");
    CSL_LISP::PROC_handle sentinel = CSL_LISP::PROC_get_raw_value();
    expect(sentinel != nullptr && CSL_LISP::PROC_fixnum(sentinel) != 0 &&
               CSL_LISP::PROC_integer_value(sentinel) == 42,
           "raw cons preserves the public save-slot 99 value");
    expect(pure_reduce_finish() == 0,
           "live cons contract shuts REDUCE down cleanly");
    return failures == 0 ? 0 : 1;
}

int main(int argc, char **argv)
{
    if (argc == 1) return basic_contract();
    if (argc == 3 && std::strcmp(argv[1], "--live-redundant") == 0)
        return live_redundant_start_contract(argv[2]);
    if (argc == 3 && std::strcmp(argv[1], "--live-cleanup") == 0)
        return live_cleanup_contract(argv[2]);
    if (argc == 3 && std::strcmp(argv[1], "--live-cons-slot") == 0)
        return live_cons_slot_contract(argv[2]);
    std::cerr << "usage: bridge-contract "
                 "[--live-redundant|--live-cleanup|--live-cons-slot image]\n";
    return 2;
}
