#include "reduce_bridge.h"

#include <cctype>
#include <cstdint>
#include <cstring>
#include <cstdio>
#include <exception>
#include <string>
#include <vector>

#include "proc.h"

namespace {

int bridge_state = PURE_REDUCE_UNINITIALIZED;
std::string bridge_error;
std::string output_buffer;
std::vector<char> input_buffer;
std::size_t input_position = 0;
bool capture_output = false;
std::string texmacs_buffer;

void release_input_storage() noexcept
{
    std::vector<char>().swap(input_buffer);
    input_position = 0;
}

void release_output_storage() noexcept
{
    std::string().swap(output_buffer);
}

void release_error_storage() noexcept
{
    std::string().swap(bridge_error);
}

void set_error(const char *message) noexcept
{
    try
    {
        bridge_error = message == nullptr ? "unknown bridge error" : message;
    }
    catch (...)
    {
        bridge_error.clear();
    }
}

void set_exception_error(const char *operation, const std::exception &error) noexcept
{
    try
    {
        bridge_error = std::string(operation) + ": " + error.what();
    }
    catch (...)
    {
        set_error("bridge operation failed");
    }
}

int bridge_writer(int character)
{
    try
    {
        if (character > 0) output_buffer.push_back(static_cast<char>(character));
        return 0;
    }
    catch (...)
    {
        set_error("could not capture CSL output");
        return 1;
    }
}

int bridge_reader()
{
    try
    {
        if (input_position < input_buffer.size())
        {
            return static_cast<unsigned char>(input_buffer[input_position++]);
        }

        input_buffer.clear();
        input_position = 0;
        CSL_LISP::PROC_set_callbacks(
            nullptr, capture_output ? bridge_writer : nullptr);
        return EOF;
    }
    catch (...)
    {
        set_error("could not read CSL input");
        return EOF;
    }
}

int update_callbacks()
{
    return CSL_LISP::PROC_set_callbacks(
        input_buffer.empty() ? nullptr : bridge_reader,
        capture_output ? bridge_writer : nullptr);
}

} // namespace

extern "C" PURE_REDUCE_API int pure_reduce_start(const char *image_utf8)
{
    try
    {
        if (bridge_state == PURE_REDUCE_RUNNING)
        {
            set_error("REDUCE is already running");
            return 1;
        }
        if (image_utf8 == nullptr || image_utf8[0] == '\0')
        {
            bridge_state = PURE_REDUCE_FAILED;
            set_error("image path is required");
            return 1;
        }

        release_error_storage();
        release_output_storage();
        release_input_storage();
        capture_output = false;
        const char *arguments[] = {"pure-reduce", "-i", image_utf8};
        CSL_LISP::cslstart(3, arguments, bridge_writer);
        bridge_state = PURE_REDUCE_RUNNING;
        return 0;
    }
    catch (const std::exception &error)
    {
        bridge_state = PURE_REDUCE_FAILED;
        set_exception_error("could not start REDUCE", error);
        return 1;
    }
    catch (...)
    {
        bridge_state = PURE_REDUCE_FAILED;
        set_error("could not start REDUCE");
        return 1;
    }
}

extern "C" PURE_REDUCE_API int pure_reduce_finish(void)
{
    try
    {
        if (bridge_state != PURE_REDUCE_RUNNING) return 0;

        const int callback_result =
            CSL_LISP::PROC_set_callbacks(nullptr, nullptr);
        capture_output = false;
        release_input_storage();
        const int result = CSL_LISP::cslfinish(bridge_writer);
        release_output_storage();
        if (result == 0 && callback_result == 0)
        {
            release_error_storage();
            bridge_state = PURE_REDUCE_FINISHED;
        }
        else
        {
            bridge_state = result == 0 ? PURE_REDUCE_FINISHED
                                       : PURE_REDUCE_FAILED;
            release_error_storage();
            try
            {
                if (result != 0)
                    bridge_error = "CSL finish failed with code " +
                                   std::to_string(result);
                else
                    bridge_error = "CSL callback cleanup failed with code " +
                                   std::to_string(callback_result);
            }
            catch (...)
            {
                set_error(result != 0 ? "CSL finish failed"
                                      : "CSL callback cleanup failed");
            }
        }
        return result != 0 ? result : callback_result;
    }
    catch (const std::exception &error)
    {
        capture_output = false;
        release_input_storage();
        release_output_storage();
        release_error_storage();
        bridge_state = PURE_REDUCE_FAILED;
        set_exception_error("could not finish REDUCE", error);
        return 1;
    }
    catch (...)
    {
        capture_output = false;
        release_input_storage();
        release_output_storage();
        release_error_storage();
        bridge_state = PURE_REDUCE_FAILED;
        set_error("could not finish REDUCE");
        return 1;
    }
}

extern "C" PURE_REDUCE_API int pure_reduce_state(void)
{
    try
    {
        return bridge_state;
    }
    catch (...)
    {
        return PURE_REDUCE_FAILED;
    }
}

extern "C" PURE_REDUCE_API const char *pure_reduce_last_error(void)
{
    try
    {
        return bridge_error.c_str();
    }
    catch (...)
    {
        return "bridge diagnostic unavailable";
    }
}

extern "C" PURE_REDUCE_API int PROC_capture_output(int flag)
{
    try
    {
        capture_output = flag != 0;
        if (capture_output) output_buffer.clear();
        return update_callbacks();
    }
    catch (const std::exception &error)
    {
        set_exception_error("could not update output callback", error);
        return 1;
    }
    catch (...)
    {
        set_error("could not update output callback");
        return 1;
    }
}

extern "C" PURE_REDUCE_API const char *PROC_get_output(void)
{
    try
    {
        return output_buffer.c_str();
    }
    catch (...)
    {
        return "";
    }
}

extern "C" PURE_REDUCE_API void PROC_clear_output(void)
{
    try
    {
        output_buffer.clear();
    }
    catch (...)
    {
        set_error("could not clear captured output");
    }
}

extern "C" PURE_REDUCE_API int PROC_feed_input(const char *input_utf8)
{
    try
    {
        input_buffer.clear();
        input_position = 0;
        if (input_utf8 != nullptr)
        {
            for (const char *cursor = input_utf8; *cursor != '\0'; ++cursor)
                input_buffer.push_back(*cursor);
        }
        return update_callbacks();
    }
    catch (const std::exception &error)
    {
        input_buffer.clear();
        input_position = 0;
        set_exception_error("could not update input callback", error);
        return 1;
    }
    catch (...)
    {
        input_buffer.clear();
        input_position = 0;
        set_error("could not update input callback");
        return 1;
    }
}

extern "C" PURE_REDUCE_API int PROC_make_cons(void)
{
    try
    {
        // The procedural API has no direct raw-cons operation. Slot 99 is a
        // bridge-private temporary: quote both existing stack operands, then
        // evaluate (cons (quote first) (quote second)). This preserves raw
        // Lisp objects without exposing LispObject or procstack in the ABI.
        if (CSL_LISP::PROC_save(99) != 0) return 1;
        if (CSL_LISP::PROC_make_function_call("quote", 1) != 0)
        {
            CSL_LISP::PROC_load(99);
            return 1;
        }
        if (CSL_LISP::PROC_load(99) != 0) return 1;
        if (CSL_LISP::PROC_make_function_call("quote", 1) != 0) return 1;
        if (CSL_LISP::PROC_make_function_call("cons", 2) != 0) return 2;
        if (CSL_LISP::PROC_lisp_eval() != 0) return 2;
        return 0;
    }
    catch (const std::exception &error)
    {
        set_exception_error("could not make CSL cons", error);
        return 2;
    }
    catch (...)
    {
        set_error("could not make CSL cons");
        return 2;
    }
}

extern "C" PURE_REDUCE_API int PROC_checksym(const char *symbol_utf8)
{
    try
    {
        if (symbol_utf8 == nullptr) return 0;
        if (CSL_LISP::PROC_push_symbol(symbol_utf8) != 0) return 0;
        if (CSL_LISP::PROC_make_function_call("quote", 1) != 0) return 0;
        if (CSL_LISP::PROC_make_function_call("getd", 1) != 0) return 0;
        if (CSL_LISP::PROC_lisp_eval() != 0) return 0;
        const CSL_LISP::PROC_handle result = CSL_LISP::PROC_get_value();
        return !CSL_LISP::PROC_null(result);
    }
    catch (const std::exception &error)
    {
        set_exception_error("could not inspect CSL symbol", error);
        return 0;
    }
    catch (...)
    {
        set_error("could not inspect CSL symbol");
        return 0;
    }
}

extern "C" PURE_REDUCE_API int texmacs_valid(const char *text_utf8)
{
    try
    {
        if (text_utf8 == nullptr) return 0;
        for (const unsigned char *cursor =
                 reinterpret_cast<const unsigned char *>(text_utf8);
             *cursor != 0; ++cursor)
        {
            if (std::isalnum(*cursor) == 0) return 0;
        }
        return 1;
    }
    catch (...)
    {
        set_error("could not validate TeXmacs identifier");
        return 0;
    }
}

extern "C" PURE_REDUCE_API const char *texmacs_post(const char *text_utf8)
{
    try
    {
        constexpr std::size_t max_length = 10000;
        texmacs_buffer.clear();
        if (text_utf8 == nullptr) return texmacs_buffer.c_str();

        const char *cursor = text_utf8;
        while (*cursor != '\0' &&
               std::isspace(static_cast<unsigned char>(*cursor)) != 0)
            ++cursor;

        bool after_equal = false;
        while (*cursor != '\0' && texmacs_buffer.size() + 1 < max_length)
        {
            if (*cursor == '=')
            {
                if (after_equal || cursor[1] == '=')
                    texmacs_buffer.push_back(*cursor++);
                else
                {
                    constexpr const char replacement[] = "{\\longequal}";
                    if (texmacs_buffer.size() + sizeof(replacement) >= max_length)
                        break;
                    texmacs_buffer.append(replacement);
                    ++cursor;
                }
                after_equal = true;
                continue;
            }
            after_equal = false;

            if (std::strncmp(cursor, "\\left\\{", 7) == 0)
            {
                if (texmacs_buffer.size() + 7 >= max_length) break;
                texmacs_buffer.append("\\left\\[");
                cursor += 7;
            }
            else if (std::strncmp(cursor, "\\right\\}", 8) == 0)
            {
                if (texmacs_buffer.size() + 8 >= max_length) break;
                texmacs_buffer.append("\\right\\]");
                cursor += 8;
            }
            else
                texmacs_buffer.push_back(*cursor++);
        }
        return texmacs_buffer.c_str();
    }
    catch (const std::exception &error)
    {
        texmacs_buffer.clear();
        set_exception_error("could not post-process TeXmacs output", error);
        return "";
    }
    catch (...)
    {
        texmacs_buffer.clear();
        set_error("could not post-process TeXmacs output");
        return "";
    }
}
