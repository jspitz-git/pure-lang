#include <algorithm>
#include <complex>
#include <cstring>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <limits>
#include <memory>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <vector>

#include <octave/oct.h>
#include <octave/octave.h>
#include <octave/interpreter.h>
#include <octave/defun-dld.h>
#include <octave/symtab.h>

#include "octave_bridge_api.h"
#include <runtime.h>

#include "gsl_structs.h"

namespace
{
std::unique_ptr<octave::interpreter> interpreter;
bool interpreter_was_finalized = false;
thread_local char last_error[2048] = "";
bool converters_enabled = true;
bool converter_recursive = false;

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
class converter_scope
{
public:
  converter_scope() : saved(converter_recursive) { converter_recursive = true; }
  ~converter_scope() { converter_recursive = saved; }
private:
  bool saved;
};

static gsl_matrix *
create_double_matrix(size_t rows, size_t columns)
{
  size_t allocated_rows = rows ? rows : 1;
  size_t allocated_columns = columns ? columns : 1;
  gsl_matrix *matrix = static_cast<gsl_matrix *>(std::calloc(1, sizeof(*matrix)));
  gsl_block *block = static_cast<gsl_block *>(std::calloc(1, sizeof(*block)));
  if (!matrix || !block)
    {
      std::free(matrix);
      std::free(block);
      return nullptr;
    }
  block->size = allocated_rows * allocated_columns;
  block->data = static_cast<double *>(std::calloc(block->size, sizeof(double)));
  if (!block->data)
    {
      std::free(block);
      std::free(matrix);
      return nullptr;
    }
  matrix->data = block->data;
  matrix->size1 = rows;
  matrix->size2 = columns;
  matrix->tda = allocated_columns;
  matrix->block = block;
  matrix->owner = 1;
  return matrix;
}

static gsl_matrix_complex *
create_complex_matrix(size_t rows, size_t columns)
{
  size_t allocated_rows = rows ? rows : 1;
  size_t allocated_columns = columns ? columns : 1;
  gsl_matrix_complex *matrix =
    static_cast<gsl_matrix_complex *>(std::calloc(1, sizeof(*matrix)));
  gsl_block_complex *block =
    static_cast<gsl_block_complex *>(std::calloc(1, sizeof(*block)));
  if (!matrix || !block)
    {
      std::free(matrix);
      std::free(block);
      return nullptr;
    }
  block->size = allocated_rows * allocated_columns;
  block->data =
    static_cast<double *>(std::calloc(2 * block->size, sizeof(double)));
  if (!block->data)
    {
      std::free(block);
      std::free(matrix);
      return nullptr;
    }
  matrix->data = block->data;
  matrix->size1 = rows;
  matrix->size2 = columns;
  matrix->tda = allocated_columns;
  matrix->block = block;
  matrix->owner = 1;
  return matrix;
}

static gsl_matrix_int *
create_int_matrix(size_t rows, size_t columns)
{
  size_t allocated_rows = rows ? rows : 1;
  size_t allocated_columns = columns ? columns : 1;
  gsl_matrix_int *matrix =
    static_cast<gsl_matrix_int *>(std::calloc(1, sizeof(*matrix)));
  gsl_block_int *block =
    static_cast<gsl_block_int *>(std::calloc(1, sizeof(*block)));
  if (!matrix || !block)
    {
      std::free(matrix);
      std::free(block);
      return nullptr;
    }
  block->size = allocated_rows * allocated_columns;
  block->data = static_cast<int *>(std::calloc(block->size, sizeof(int)));
  if (!block->data)
    {
      std::free(block);
      std::free(matrix);
      return nullptr;
    }
  matrix->data = block->data;
  matrix->size1 = rows;
  matrix->size2 = columns;
  matrix->tda = allocated_columns;
  matrix->block = block;
  matrix->owner = 1;
  return matrix;
}

static gsl_matrix_symbolic *
create_symbolic_matrix(size_t rows, size_t columns)
{
  size_t allocated_rows = rows ? rows : 1;
  size_t allocated_columns = columns ? columns : 1;
  gsl_matrix_symbolic *matrix =
    static_cast<gsl_matrix_symbolic *>(std::calloc(1, sizeof(*matrix)));
  gsl_block_symbolic *block =
    static_cast<gsl_block_symbolic *>(std::calloc(1, sizeof(*block)));
  if (!matrix || !block)
    {
      std::free(matrix);
      std::free(block);
      return nullptr;
    }
  block->size = allocated_rows * allocated_columns;
  block->data = static_cast<pure_expr **>(
    std::calloc(block->size, sizeof(*block->data)));
  if (!block->data)
    {
      std::free(block);
      std::free(matrix);
      return nullptr;
    }
  matrix->data = block->data;
  matrix->size1 = rows;
  matrix->size2 = columns;
  matrix->tda = allocated_columns;
  matrix->block = block;
  matrix->owner = 1;
  return matrix;
}

static void
discard_symbolic_matrix(gsl_matrix_symbolic *matrix)
{
  if (!matrix)
    return;
  if (matrix->block)
    {
      for (size_t index = 0; index < matrix->block->size; ++index)
        if (matrix->block->data[index])
          pure_freenew(matrix->block->data[index]);
      std::free(matrix->block->data);
      std::free(matrix->block);
    }
  std::free(matrix);
}

static pure_expr *
octave_pointer(const octave_value& value)
{
  std::unique_ptr<octave_value> wrapper = std::make_unique<octave_value>(value);
  pure_expr *pointer = pure_pointer(wrapper.get());
  pure_expr *finalizer = pure_symbol(pure_sym("octave_free"));
  if (!pointer || !finalizer)
    {
      if (pointer)
        pure_freenew(pointer);
      return nullptr;
    }
  pure_expr *result = pure_sentry(finalizer, pointer);
  if (!result)
    {
      pure_freenew(pointer);
      return nullptr;
    }
  wrapper.release();
  return result;
}

static bool
is_octave_pointer(pure_expr *expression, octave_value **value)
{
  void *pointer = nullptr;
  pure_expr *finalizer = nullptr;
  if (!expression || !pure_is_pointer(expression, &pointer) ||
      !(finalizer = pure_get_sentry(expression)) || finalizer->tag <= 0 ||
      std::strcmp(pure_sym_pname(finalizer->tag), "octave_free") != 0)
    return false;
  if (value)
    *value = static_cast<octave_value *>(pointer);
  return true;
}

static pure_expr *octave_to_pure(const octave_value& value);
static std::unique_ptr<octave_value> pure_to_octave(pure_expr *expression);

static pure_expr *
try_octave_to_pure(const octave_value& value)
{
  pure_expr *pointer = octave_pointer(value);
  if (!pointer || !converters_enabled || converter_recursive)
    return pointer;

  pure_new(pointer);
  int32_t converter_tag = pure_sym("__oct2pure__");
  pure_expr *converter = pure_symbol(converter_tag);
  if (!converter)
    {
      pure_unref(pointer);
      return pointer;
    }

  pure_expr *exception = nullptr;
  pure_expr *converted;
  {
    converter_scope scope;
    converted = pure_appx(converter, pointer, &exception);
  }
  if (!converted)
    {
      if (exception)
        {
          char *message = str(exception);
          set_exception_error("Pure converter failed", message);
          std::free(message);
          pure_freenew(exception);
        }
      pure_unref(pointer);
      return pointer;
    }

  pure_expr *function = nullptr;
  pure_expr *argument = nullptr;
  if (pure_is_app(converted, &function, &argument) &&
      function->tag == converter_tag && argument == pointer)
    {
      pure_freenew(converted);
      pure_unref(pointer);
      return pointer;
    }

  pure_new(converted);
  pure_free(pointer);
  return converted;
}

template <typename Array>
static pure_expr *
integer_array_to_pure(Array array, size_t rows, size_t columns)
{
  const auto *values = array.fortran_vec();
  if (!values && rows * columns != 0)
    return nullptr;
  if (rows == 1 && columns == 1)
    return pure_int(static_cast<int32_t>(values[0]));
  gsl_matrix_int *matrix = create_int_matrix(rows, columns);
  if (!matrix)
    return nullptr;
  for (size_t row = 0; row < rows; ++row)
    for (size_t column = 0; column < columns; ++column)
      matrix->data[row * matrix->tda + column] =
        static_cast<int32_t>(values[column * rows + row]);
  return pure_int_matrix(matrix);
}

template <typename Integer>
static bool
fits_in_int32(Integer value)
{
  if constexpr (std::is_signed<Integer>::value)
    return value >= static_cast<Integer>(std::numeric_limits<int32_t>::min()) &&
           value <= static_cast<Integer>(std::numeric_limits<int32_t>::max());
  return value <= static_cast<Integer>(std::numeric_limits<int32_t>::max());
}

template <typename Integer, typename Array>
static pure_expr *
wide_integer_array_to_pure(Array array, size_t rows, size_t columns,
                           pure_expr *(*make_integer)(Integer))
{
  const auto *values = array.fortran_vec();
  const size_t count = rows * columns;
  if (!values && count != 0)
    return nullptr;

  bool all_fit = true;
  for (size_t index = 0; index < count; ++index)
    if (!fits_in_int32(static_cast<Integer>(values[index])))
      {
        all_fit = false;
        break;
      }
  if (all_fit)
    return integer_array_to_pure(array, rows, columns);
  if (rows == 1 && columns == 1)
    return make_integer(static_cast<Integer>(values[0]));

  gsl_matrix_symbolic *matrix = create_symbolic_matrix(rows, columns);
  if (!matrix)
    return nullptr;
  for (size_t row = 0; row < rows; ++row)
    for (size_t column = 0; column < columns; ++column)
      {
        const size_t target = row * matrix->tda + column;
        const size_t source = column * rows + row;
        matrix->data[target] =
          make_integer(static_cast<Integer>(values[source]));
        if (!matrix->data[target])
          {
            discard_symbolic_matrix(matrix);
            return nullptr;
          }
      }
  return pure_symbolic_matrix(matrix);
}

static pure_expr *
octave_to_pure(const octave_value& value)
{
  if (!value.is_defined())
    return nullptr;

  if (value.is_cs_list())
    {
      octave_value_list list = value.list_value();
      size_t count = static_cast<size_t>(list.length());
      std::vector<pure_expr *> elements(count, nullptr);
      for (size_t index = 0; index < count; ++index)
        {
          elements[index] = octave_to_pure(list(static_cast<octave_idx_type>(index)));
          if (!elements[index])
            {
              for (size_t prior = 0; prior < index; ++prior)
                pure_freenew(elements[prior]);
              return nullptr;
            }
        }
      return pure_tuplev(count, elements.data());
    }

  if (value.ndims() != 2)
    return try_octave_to_pure(value);

  dim_vector dimensions = value.dims();
  size_t rows = static_cast<size_t>(dimensions(0));
  size_t columns = static_cast<size_t>(dimensions(1));

  if (value.is_double_type())
    {
      if (value.is_complex_scalar() || value.is_complex_matrix())
        {
          ComplexMatrix source = value.complex_matrix_value();
          const std::complex<double> *values = source.fortran_vec();
          if (!values && rows * columns != 0)
            return nullptr;
          if (rows == 1 && columns == 1)
            {
              double complex_value[2] = {values[0].real(), values[0].imag()};
              return pure_complex(complex_value);
            }
          gsl_matrix_complex *matrix = create_complex_matrix(rows, columns);
          if (!matrix)
            return nullptr;
          for (size_t row = 0; row < rows; ++row)
            for (size_t column = 0; column < columns; ++column)
              {
                size_t target = 2 * (row * matrix->tda + column);
                const std::complex<double>& source_value =
                  values[column * rows + row];
                matrix->data[target] = source_value.real();
                matrix->data[target + 1] = source_value.imag();
              }
          return pure_complex_matrix(matrix);
        }

      Matrix source = value.matrix_value();
      const double *values = source.fortran_vec();
      if (!values && rows * columns != 0)
        return nullptr;
      if (rows == 1 && columns == 1)
        return pure_double(values[0]);
      gsl_matrix *matrix = create_double_matrix(rows, columns);
      if (!matrix)
        return nullptr;
      for (size_t row = 0; row < rows; ++row)
        for (size_t column = 0; column < columns; ++column)
          matrix->data[row * matrix->tda + column] =
            values[column * rows + row];
      return pure_double_matrix(matrix);
    }

  if (value.islogical())
    {
      boolMatrix source = value.bool_matrix_value();
      const bool *values = source.fortran_vec();
      if (!values && rows * columns != 0)
        return nullptr;
      if (rows == 1 && columns == 1)
        return pure_int(values[0] ? 1 : 0);
      gsl_matrix_int *matrix = create_int_matrix(rows, columns);
      if (!matrix)
        return nullptr;
      for (size_t row = 0; row < rows; ++row)
        for (size_t column = 0; column < columns; ++column)
          matrix->data[row * matrix->tda + column] =
            values[column * rows + row] ? 1 : 0;
      return pure_int_matrix(matrix);
    }

  if (value.isinteger())
    {
      if (value.is_int8_type())
        return integer_array_to_pure(value.int8_array_value(), rows, columns);
      if (value.is_uint8_type())
        return integer_array_to_pure(value.uint8_array_value(), rows, columns);
      if (value.is_int16_type())
        return integer_array_to_pure(value.int16_array_value(), rows, columns);
      if (value.is_uint16_type())
        return integer_array_to_pure(value.uint16_array_value(), rows, columns);
      if (value.is_int32_type())
        return integer_array_to_pure(value.int32_array_value(), rows, columns);
      if (value.is_uint32_type())
        return wide_integer_array_to_pure<uint64_t>(
          value.uint32_array_value(), rows, columns, pure_uint64);
      if (value.is_int64_type())
        return wide_integer_array_to_pure<int64_t>(
          value.int64_array_value(), rows, columns, pure_int64);
      if (value.is_uint64_type())
        return wide_integer_array_to_pure<uint64_t>(
          value.uint64_array_value(), rows, columns, pure_uint64);
      return try_octave_to_pure(value);
    }

  if (value.is_string())
    {
      charMatrix strings = value.char_matrix_value();
      octave_idx_type count = strings.rows();
      if (count == 0)
        return pure_matrix_rowsl(0);
      if (count == 1)
        {
          std::string string = strings.row_as_string(0);
          return pure_cstring_dup(string.c_str());
        }
      std::vector<pure_expr *> elements(static_cast<size_t>(count), nullptr);
      for (octave_idx_type index = 0; index < count; ++index)
        {
          std::string string = strings.row_as_string(index);
          elements[static_cast<size_t>(index)] = pure_cstring_dup(string.c_str());
        }
      return pure_matrix_rowsv(static_cast<uint32_t>(count), elements.data());
    }

  return try_octave_to_pure(value);
}

static std::unique_ptr<octave_value>
try_pure_to_octave(pure_expr *expression)
{
  if (!expression || !converters_enabled || converter_recursive)
    return nullptr;

  int32_t converter_tag = pure_sym("__pure2oct__");
  pure_expr *converter = pure_symbol(converter_tag);
  if (!converter)
    return nullptr;

  pure_expr *exception = nullptr;
  pure_expr *converted;
  {
    converter_scope scope;
    converted = pure_appx(converter, expression, &exception);
  }
  if (!converted)
    {
      if (exception)
        {
          char *message = str(exception);
          set_exception_error("Pure converter failed", message);
          std::free(message);
          pure_freenew(exception);
        }
      return nullptr;
    }

  octave_value *wrapped = nullptr;
  if (is_octave_pointer(converted, &wrapped))
    {
      auto result = std::make_unique<octave_value>(*wrapped);
      pure_freenew(converted);
      return result;
    }

  pure_expr *function = nullptr;
  pure_expr *argument = nullptr;
  if (pure_is_app(converted, &function, &argument) &&
      function->tag == converter_tag && argument == expression)
    {
      pure_freenew(converted);
      return nullptr;
    }

  std::unique_ptr<octave_value> result;
  {
    converter_scope scope;
    result = pure_to_octave(converted);
  }
  pure_freenew(converted);
  return result;
}

static std::unique_ptr<octave_value>
pure_to_octave(pure_expr *expression)
{
  double real_value;
  double complex_value[2];
  int int_value;
  char *string = nullptr;
  void *pointer = nullptr;
  octave_value *wrapped = nullptr;

  if (pure_is_double(expression, &real_value))
    return std::make_unique<octave_value>(real_value);
  if (pure_is_int(expression, &int_value))
    return std::make_unique<octave_value>(octave_int32(int_value));
  if (pure_is_complex(expression, complex_value))
    return std::make_unique<octave_value>(
      std::complex<double>(complex_value[0], complex_value[1]));

  if (pure_is_double_matrix(expression, &pointer))
    {
      gsl_matrix *source = static_cast<gsl_matrix *>(pointer);
      Matrix matrix(source->size1, source->size2);
      double *values = matrix.fortran_vec();
      for (size_t row = 0; row < source->size1; ++row)
        for (size_t column = 0; column < source->size2; ++column)
          values[column * source->size1 + row] =
            source->data[row * source->tda + column];
      return std::make_unique<octave_value>(matrix);
    }

  if (pure_is_int_matrix(expression, &pointer))
    {
      gsl_matrix_int *source = static_cast<gsl_matrix_int *>(pointer);
      dim_vector dimensions(source->size1, source->size2);
      int32NDArray matrix(dimensions);
      octave_int32 *values = matrix.fortran_vec();
      for (size_t row = 0; row < source->size1; ++row)
        for (size_t column = 0; column < source->size2; ++column)
          values[column * source->size1 + row] =
            octave_int32(source->data[row * source->tda + column]);
      return std::make_unique<octave_value>(matrix);
    }

  if (pure_is_complex_matrix(expression, &pointer))
    {
      gsl_matrix_complex *source = static_cast<gsl_matrix_complex *>(pointer);
      ComplexMatrix matrix(source->size1, source->size2);
      std::complex<double> *values = matrix.fortran_vec();
      for (size_t row = 0; row < source->size1; ++row)
        for (size_t column = 0; column < source->size2; ++column)
          {
            size_t offset = 2 * (row * source->tda + column);
            values[column * source->size1 + row] =
              std::complex<double>(source->data[offset], source->data[offset + 1]);
          }
      return std::make_unique<octave_value>(matrix);
    }

  if (pure_is_cstring_dup(expression, &string))
    {
      std::unique_ptr<char, decltype(&std::free)> owner(string, &std::free);
      return std::make_unique<octave_value>(charMatrix(string));
    }

  if (pure_is_symbolic_matrix(expression, &pointer))
    {
      gsl_matrix_symbolic *source = static_cast<gsl_matrix_symbolic *>(pointer);
      if (source->size1 == 0 || source->size2 != 1)
        return try_pure_to_octave(expression);
      string_vector strings(source->size1);
      for (size_t row = 0; row < source->size1; ++row)
        {
          char *element = nullptr;
          if (!pure_is_cstring_dup(source->data[row * source->tda], &element))
            return try_pure_to_octave(expression);
          std::unique_ptr<char, decltype(&std::free)> owner(element, &std::free);
          strings[static_cast<octave_idx_type>(row)] = element;
        }
      return std::make_unique<octave_value>(charMatrix(strings));
    }

  if (is_octave_pointer(expression, &wrapped))
    return std::make_unique<octave_value>(*wrapped);

  return try_pure_to_octave(expression);
}

static const char pure_call_help[] =
  "RES = pure_call(NAME, ARG, ...)\n"
  "[RES, ...] = pure_call(NAME, ARG, ...)\n\n"
  "Execute the Pure function named NAME with the given arguments.";

static octave_value_list
pure_call_error(const std::string& message)
{
  error("%s", message.c_str());
  return octave_value_list();
}

struct pure_expression_deleter
{
  void operator()(pure_expr *expression) const noexcept
  {
    if (expression)
      pure_freenew(expression);
  }
};

using pure_expression_owner =
  std::unique_ptr<pure_expr, pure_expression_deleter>;

DEFUN_DLD(pure_call, args, nargout, pure_call_help)
{
  const octave_idx_type nargin = args.length();
  if (nargin < 1 || !args(0).is_string())
    return pure_call_error(
      "pure_call: NAME must be a single-row character string");

  charMatrix characters = args(0).char_matrix_value();
  if (characters.rows() != 1)
    return pure_call_error(
      "pure_call: NAME must be a single-row character string");
  const std::string name = characters.row_as_string(0);

  const int function_number = pure_getsym(name.c_str());
  if (function_number <= 0)
    return pure_call_error(
      "pure_call: unknown Pure function '" + name + "'");

  std::vector<pure_expression_owner> pure_arguments;
  pure_arguments.reserve(static_cast<size_t>(nargin - 1));
  for (octave_idx_type index = 1; index < nargin; ++index)
    {
      pure_expression_owner converted(octave_to_pure(args(index)));
      if (!converted)
        return pure_call_error(
          "pure_call: argument " + std::to_string(index) +
          " could not be converted for '" + name + "'");
      pure_arguments.push_back(std::move(converted));
    }

  pure_expr *raw_exception = nullptr;
  pure_expression_owner result(
    pure_symbolx(function_number, &raw_exception));
  pure_expression_owner exception(raw_exception);
  for (size_t index = 0; result && index < pure_arguments.size(); ++index)
    {
      pure_expr *next_exception = nullptr;
      pure_expr *next_result =
        pure_appx(result.release(), pure_arguments[index].release(),
                  &next_exception);
      result.reset(next_result);
      exception.reset(next_exception);
    }

  if (!result)
    {
      std::string detail = "unknown Pure exception";
      if (exception)
        {
          std::unique_ptr<char, decltype(&std::free)>
            text(str(exception.get()), &std::free);
          if (text)
            detail = text.get();
        }
      return pure_call_error(
        "pure_call: Pure exception in '" + name + "': " + detail);
    }

  size_t result_count = 0;
  pure_expr **pure_results = nullptr;
  pure_is_tuplev(result.get(), &result_count, &pure_results);
  std::unique_ptr<pure_expr *, decltype(&std::free)>
    result_elements(pure_results, &std::free);

  if (nargout > 0 && result_count != static_cast<size_t>(nargout))
    {
      const std::string message =
        "pure_call: wrong number of results from '" + name +
        "' (expected " + std::to_string(nargout) + ", got " +
        std::to_string(result_count) + ")";
      return pure_call_error(message);
    }

  std::vector<octave_value> converted_results;
  converted_results.reserve(result_count);
  for (size_t index = 0; index < result_count; ++index)
    {
      std::unique_ptr<octave_value> converted =
        pure_to_octave(pure_results[index]);
      if (!converted)
        {
          const std::string message =
            "pure_call: result " + std::to_string(index + 1) +
            " from '" + name + "' could not be converted";
          return pure_call_error(message);
        }
      converted_results.push_back(*converted);
    }

  octave_value_list returned;
  for (size_t index = 0; index < converted_results.size(); ++index)
    returned(static_cast<octave_idx_type>(index)) =
      converted_results[index];
  return returned;
}

static void
install_pure_call()
{
  octave_value function(
    new octave_builtin(Fpure_call, "pure_call", "embed.cc", pure_call_help));
  interpreter->get_symbol_table().install_built_in_function(
    "pure_call", function);
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
      interpreter->initialize_history(false);
      interpreter->read_user_files(false);
      interpreter->inhibit_startup_message(true);
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
      install_pure_call();

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

template <typename Function>
static pure_expr *
guarded_expression_export(const char *operation, Function function) noexcept
{
  try
    {
      clear_error();
      return function();
    }
  catch (const octave::exit_exception& exception)
    {
      set_exception_error(operation, exception.what());
      recover_after_exception();
    }
  catch (const octave::execution_exception& exception)
    {
      set_exception_error(operation, exception.what());
      recover_after_exception();
    }
  catch (const std::exception& exception)
    {
      set_exception_error(operation, exception.what());
      recover_after_exception();
    }
  catch (...)
    {
      set_exception_error(operation, "unknown exception");
      recover_after_exception();
    }
  return nullptr;
}

template <typename Function>
static int
guarded_integer_export(const char *operation, int failure, Function function) noexcept
{
  try
    {
      clear_error();
      return function();
    }
  catch (const octave::exit_exception& exception)
    {
      set_exception_error(operation, exception.what());
      recover_after_exception();
    }
  catch (const octave::execution_exception& exception)
    {
      set_exception_error(operation, exception.what());
      recover_after_exception();
    }
  catch (const std::exception& exception)
    {
      set_exception_error(operation, exception.what());
      recover_after_exception();
    }
  catch (...)
    {
      set_exception_error(operation, "unknown exception");
      recover_after_exception();
    }
  return failure;
}

extern "C" PURE_OCTAVE_IMPL_API pure_expr *
pure_octave_impl_get(const char *id)
{
  return guarded_expression_export("Octave global lookup failed", [id]() {
    if (!interpreter || !id)
      {
        set_error(!interpreter ? "Octave interpreter is not initialized" :
                  "Octave global name is null");
        return static_cast<pure_expr *>(nullptr);
      }
    octave_value value = interpreter->global_varval(id);
    pure_expr *result = octave_to_pure(value);
    if (!result)
      set_error(value.is_defined() ? "Octave value conversion failed" :
                "Octave global is undefined");
    return result;
  });
}

extern "C" PURE_OCTAVE_IMPL_API pure_expr *
pure_octave_impl_set(const char *id, pure_expr *expression)
{
  return guarded_expression_export("Octave global assignment failed",
                                    [id, expression]() {
    if (!interpreter || !id || !expression)
      {
        set_error(!interpreter ? "Octave interpreter is not initialized" :
                  "Octave global assignment has a null argument");
        return static_cast<pure_expr *>(nullptr);
      }
    std::unique_ptr<octave_value> value = pure_to_octave(expression);
    if (!value)
      {
        set_error("Pure value conversion failed");
        return static_cast<pure_expr *>(nullptr);
      }
    interpreter->global_assign(id, *value);
    return expression;
  });
}

extern "C" PURE_OCTAVE_IMPL_API pure_expr *
pure_octave_impl_call(pure_expr *function, int nargout, pure_expr *arguments)
{
  return guarded_expression_export("Octave function call failed",
                                    [function, nargout, arguments]() {
    if (!interpreter || !function || !arguments || nargout < 0)
      {
        set_error(!interpreter ? "Octave interpreter is not initialized" :
                  "Octave call has invalid arguments");
        return static_cast<pure_expr *>(nullptr);
      }

    size_t argument_count = 0;
    pure_expr **pure_arguments = nullptr;
    if (!pure_is_tuplev(arguments, &argument_count, &pure_arguments))
      {
        set_error("Octave call arguments are not a tuple");
        return static_cast<pure_expr *>(nullptr);
      }
    std::unique_ptr<pure_expr *, decltype(&std::free)>
      argument_owner(pure_arguments, &std::free);

    octave_value_list octave_arguments;
    for (size_t index = 0; index < argument_count; ++index)
      {
        std::unique_ptr<octave_value> value = pure_to_octave(pure_arguments[index]);
        if (!value)
          {
            if (last_error[0] == '\0')
              set_error("Pure argument conversion failed");
            return static_cast<pure_expr *>(nullptr);
          }
        octave_arguments(static_cast<octave_idx_type>(index)) = *value;
      }

    octave_value_list returned;
    octave_value *wrapped = nullptr;
    char *name = nullptr;
    if (is_octave_pointer(function, &wrapped))
      {
        if (!wrapped->is_function_handle() && !wrapped->is_inline_function())
          {
            set_error("Octave value is not callable");
            return static_cast<pure_expr *>(nullptr);
          }
        returned = interpreter->feval(*wrapped, octave_arguments, nargout);
      }
    else if (pure_is_cstring_dup(function, &name))
      {
        std::unique_ptr<char, decltype(&std::free)> name_owner(name, &std::free);
        returned = interpreter->feval(name, octave_arguments, nargout);
      }
    else
      {
        set_error("Octave function must be a string or function value");
        return static_cast<pure_expr *>(nullptr);
      }

    size_t result_count = std::min(static_cast<size_t>(returned.length()),
                                   static_cast<size_t>(nargout));
    std::vector<pure_expr *> results(result_count, nullptr);
    for (size_t index = 0; index < result_count; ++index)
      {
        results[index] =
          octave_to_pure(returned(static_cast<octave_idx_type>(index)));
        if (!results[index])
          {
            for (size_t prior = 0; prior < index; ++prior)
              pure_freenew(results[prior]);
            set_error("Octave result conversion failed");
            return static_cast<pure_expr *>(nullptr);
          }
      }
    return pure_tuplev(result_count, results.data());
  });
}

extern "C" PURE_OCTAVE_IMPL_API pure_expr *
pure_octave_impl_func(pure_expr *function)
{
  return guarded_expression_export("Octave function creation failed", [function]() {
    if (!interpreter || !function)
      {
        set_error(!interpreter ? "Octave interpreter is not initialized" :
                  "Octave function description is null");
        return static_cast<pure_expr *>(nullptr);
      }

    char *name = nullptr;
    if (pure_is_cstring_dup(function, &name))
      {
        std::unique_ptr<char, decltype(&std::free)> owner(name, &std::free);
        octave_value handle = interpreter->make_function_handle(name);
        pure_expr *result = octave_pointer(handle);
        if (!result)
          set_error("Could not wrap Octave function handle");
        return result;
      }

    size_t argument_count = 0;
    pure_expr **pure_arguments = nullptr;
    if (!pure_is_tuplev(function, &argument_count, &pure_arguments) ||
        argument_count == 0)
      {
        set_error("Octave anonymous function description is not a nonempty tuple");
        return static_cast<pure_expr *>(nullptr);
      }
    std::unique_ptr<pure_expr *, decltype(&std::free)>
      argument_owner(pure_arguments, &std::free);
    std::vector<std::string> description(argument_count);
    for (size_t index = 0; index < argument_count; ++index)
      {
        char *part = nullptr;
        if (!pure_is_cstring_dup(pure_arguments[index], &part))
          {
            set_error("Anonymous function description contains a non-string");
            return static_cast<pure_expr *>(nullptr);
          }
        std::unique_ptr<char, decltype(&std::free)> owner(part, &std::free);
        description[index] = part;
      }

    std::string source = "@(";
    for (size_t index = 1; index < description.size(); ++index)
      {
        if (index > 1)
          source += ',';
        source += description[index];
      }
    source += ") ";
    source += description[0];

    int parse_status = 0;
    octave_value_list returned =
      interpreter->eval_string(source, false, parse_status, 1);
    if (parse_status != 0 || returned.length() != 1 ||
        !returned(0).is_function_handle())
      {
        set_error("Octave anonymous function compilation failed");
        return static_cast<pure_expr *>(nullptr);
      }
    pure_expr *result = octave_pointer(returned(0));
    if (!result)
      set_error("Could not wrap Octave anonymous function");
    return result;
  });
}

extern "C" PURE_OCTAVE_IMPL_API int
pure_octave_impl_valuep(pure_expr *expression)
{
  return guarded_integer_export("Octave value predicate failed", 0,
    [expression]() { return is_octave_pointer(expression, nullptr) ? 1 : 0; });
}

extern "C" PURE_OCTAVE_IMPL_API void
pure_octave_impl_free(void *value)
{
  try
    {
      clear_error();
      delete static_cast<octave_value *>(value);
    }
  catch (const octave::exit_exception& exception)
    {
      set_exception_error("Octave value finalization failed", exception.what());
      recover_after_exception();
    }
  catch (const octave::execution_exception& exception)
    {
      set_exception_error("Octave value finalization failed", exception.what());
      recover_after_exception();
    }
  catch (const std::exception& exception)
    {
      set_exception_error("Octave value finalization failed", exception.what());
      recover_after_exception();
    }
  catch (...)
    {
      set_error("Octave value finalization failed: unknown exception");
      recover_after_exception();
    }
}

extern "C" PURE_OCTAVE_IMPL_API int
pure_octave_impl_converters(int enable)
{
  return guarded_integer_export("Octave converter setting failed", 0, [enable]() {
    int previous = converters_enabled ? 1 : 0;
    converters_enabled = enable != 0;
    return previous;
  });
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
