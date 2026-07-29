#include <iostream>

#include <octave/oct.h>
#include <octave/octave.h>
#include <octave/interpreter.h>

int main ()
{
  octave::interpreter interpreter;
  int status = interpreter.execute();
  if (status != 0)
    return status;

  octave_value_list in;
  in(0) = 10;
  in(1) = 15;
  octave_value_list out = interpreter.feval("gcd", in, 1);
  if (out.length() != 1 || out(0).double_value() != 5)
    return 1;

  std::cout << "PURE_OCTAVE_EMBED_PROBE_OK:5\n";
  return 0;
}
