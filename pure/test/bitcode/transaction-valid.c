extern int printf(const char *format, ...);

int pure_transaction_state = 41;

int pure_transaction_value(void)
{
  return ++pure_transaction_state;
}

void pure_transaction_print(int value)
{
  printf("%d\n", value);
}
