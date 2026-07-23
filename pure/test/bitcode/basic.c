static int helper(int value)
{
  return value * 2;
}

int bc_add_one(int value)
{
  return value + 1;
}

int bc_call_helper(int value)
{
  return helper(value);
}
