#include <locale.h>

extern void pure_transaction_custom_main(int argc, char **argv);
extern void pure_finalize(void);

int main(int argc, char **argv)
{
  setlocale(LC_ALL, "");
  pure_transaction_custom_main(argc, argv);
  pure_finalize();
  return 0;
}
