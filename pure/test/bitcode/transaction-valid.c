extern int printf(const char *format, ...);

static int pure_transaction_state;

static void pure_transaction_initialize(void) __attribute__((constructor));

static void pure_transaction_initialize(void)
{
  pure_transaction_state = 41;
}

static int *pure_transaction_used __attribute__((used)) =
  &pure_transaction_state;

int pure_transaction_value(void)
{
  return ++pure_transaction_state;
}

void pure_transaction_print(int value)
{
  printf("%d\n", value);
}
