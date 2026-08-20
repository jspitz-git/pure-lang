extern int printf(const char *format, ...);

int pure_transaction_value(void)
{
  return 42;
}

void pure_transaction_print(int value)
{
  printf("%d\n", value);
}
