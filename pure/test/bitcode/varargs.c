#include <stdarg.h>

int bc_varargs(int count, ...)
{
  int result = 0;
  va_list arguments;
  va_start(arguments, count);
  while (count-- > 0) result += va_arg(arguments, int);
  va_end(arguments);
  return result;
}
