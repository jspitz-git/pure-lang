extern int pure_transaction_missing(void);

int pure_transaction_value(void)
{
  return 7;
}

int pure_transaction_invalid(void)
{
  return pure_transaction_missing();
}
