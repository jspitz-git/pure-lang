#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

#include <octave/oct.h>
#include <octave/octave.h>
#include <octave/interpreter.h>

#include "octave_bridge_api.h"

namespace
{
std::unique_ptr<octave::interpreter> interpreter;
bool interpreter_was_finalized = false;
thread_local char last_error[2048] = "";

void clear_error() noexcept
{
  last_error[0] = '\0';
}

void set_error(const char *message) noexcept
{
  std::snprintf(last_error, sizeof(last_error), "%s",
                message ? message : "unknown Octave bridge error");
}

void set_exception_error(const char *operation, const char *message) noexcept
{
  std::snprintf(last_error, sizeof(last_error), "%s: %s", operation,
                message ? message : "unknown exception");
}

void recover_after_exception() noexcept
{
  if (!interpreter)
    return;

  try
    {
      interpreter->recover_from_exception();
    }
  catch (...)
    {
    }
}

int exit_result(const octave::exit_exception& exception) noexcept
{
  int status = exception.exit_status();
  return status == 0 ? -1 : status;
}

std::string
controlled_load_path()
{
  const char *octave_home = std::getenv("OCTAVE_HOME");
  if (!octave_home || !*octave_home)
    throw std::runtime_error("OCTAVE_HOME is not set by the stable loader");

  const std::filesystem::path m_root =
    std::filesystem::u8path(octave_home) / "share" / "octave" / "11.3.0" / "m";
  if (!std::filesystem::is_directory(m_root))
    throw std::runtime_error("The selected Octave root has no public m-file path");

  std::vector<std::string> directories;
  directories.push_back(m_root.generic_u8string());
  for (std::filesystem::recursive_directory_iterator it(m_root), end;
       it != end; ++it)
    {
      const std::filesystem::path entry_path = it->path();
      const std::string name = entry_path.filename().generic_u8string();
      if (name == "private" || (!name.empty() &&
          (name[0] == '@' || name[0] == '+')))
        {
          it.disable_recursion_pending();
          continue;
        }
      if (it->is_directory())
        directories.push_back(entry_path.generic_u8string());
    }
  std::sort(directories.begin(), directories.end());

  std::string path;
  for (const std::string& directory : directories)
    {
      if (!path.empty())
        path += ';';
      path += directory;
    }
  return path;
}
}

extern "C" PURE_OCTAVE_IMPL_API int
pure_octave_impl_init(int argc, char **argv)
{
  try
    {
      clear_error();
      (void) argc;
      (void) argv;

      if (interpreter)
        return 0;

      if (interpreter_was_finalized)
        {
          set_error("Octave interpreter restart is not supported");
          return -1;
        }

      const std::string load_path = controlled_load_path();
      interpreter = std::make_unique<octave::interpreter>();
      interpreter->initialize_load_path(false);
      interpreter->get_load_path().set(load_path, false, true);
      interpreter->initialize();
      int status = interpreter->execute();
      if (status != 0)
        {
          set_error("Octave interpreter initialization failed");
          interpreter.reset();
          return status;
        }

      return 0;
    }
  catch (const octave::exit_exception& exception)
    {
      set_exception_error("Octave interpreter exited during initialization",
                          exception.what());
      interpreter.reset();
      return exit_result(exception);
    }
  catch (const octave::execution_exception& exception)
    {
      set_exception_error("Octave initialization failed", exception.what());
      recover_after_exception();
      interpreter.reset();
      return -1;
    }
  catch (const std::exception& exception)
    {
      set_exception_error("Octave initialization failed", exception.what());
      interpreter.reset();
      return -1;
    }
  catch (...)
    {
      set_error("Octave initialization failed: unknown exception");
      interpreter.reset();
      return -1;
    }
}

extern "C" PURE_OCTAVE_IMPL_API void
pure_octave_impl_fini(void)
{
  try
    {
      clear_error();
      if (interpreter)
        {
          interpreter.reset();
          interpreter_was_finalized = true;
        }
    }
  catch (const octave::exit_exception& exception)
    {
      set_exception_error("Octave shutdown failed", exception.what());
    }
  catch (const octave::execution_exception& exception)
    {
      set_exception_error("Octave shutdown failed", exception.what());
    }
  catch (const std::exception& exception)
    {
      set_exception_error("Octave shutdown failed", exception.what());
    }
  catch (...)
    {
      set_error("Octave shutdown failed: unknown exception");
    }
}

extern "C" PURE_OCTAVE_IMPL_API int
pure_octave_impl_eval(const char *command)
{
  try
    {
      clear_error();
      if (!interpreter)
        {
          set_error("Octave interpreter is not initialized");
          return -1;
        }
      if (!command)
        {
          set_error("Octave command is null");
          return -1;
        }

      const std::string command_string(command);
      int parse_status = 0;
      octave_value_list out =
        interpreter->eval_string(command_string, false, parse_status, 0);
      (void) out;
      if (parse_status != 0)
        {
          set_error("Octave command could not be parsed");
          return -1;
        }

      return 0;
    }
  catch (const octave::exit_exception& exception)
    {
      set_exception_error("Octave evaluation exited", exception.what());
      recover_after_exception();
      return exit_result(exception);
    }
  catch (const octave::execution_exception& exception)
    {
      set_exception_error("Octave evaluation failed", exception.what());
      recover_after_exception();
      return -1;
    }
  catch (const std::exception& exception)
    {
      set_exception_error("Octave evaluation failed", exception.what());
      recover_after_exception();
      return -1;
    }
  catch (...)
    {
      set_error("Octave evaluation failed: unknown exception");
      recover_after_exception();
      return -1;
    }
}

extern "C" PURE_OCTAVE_IMPL_API const char *
pure_octave_impl_last_error(void)
{
  try
    {
      return last_error;
    }
  catch (const octave::exit_exception&)
    {
      return "Octave diagnostic failed: exit exception";
    }
  catch (const octave::execution_exception&)
    {
      return "Octave diagnostic failed: execution exception";
    }
  catch (const std::exception&)
    {
      return "Octave diagnostic failed: standard exception";
    }
  catch (...)
    {
      return "Octave diagnostic failed: unknown exception";
    }
}

extern "C" PURE_OCTAVE_IMPL_API const char *
pure_octave_impl_abi(void)
{
  try
    {
      return PURE_OCTAVE_BRIDGE_ABI;
    }
  catch (const octave::exit_exception&)
    {
      return "";
    }
  catch (const octave::execution_exception&)
    {
      return "";
    }
  catch (const std::exception&)
    {
      return "";
    }
  catch (...)
    {
      return "";
    }
}
