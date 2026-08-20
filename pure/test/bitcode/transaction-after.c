extern int printf(const char *format, ...);

void pure_transaction_after(void)
{
  printf("42\n");
}
