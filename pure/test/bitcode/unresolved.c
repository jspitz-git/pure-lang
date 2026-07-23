extern int bc_missing_dependency(int value);

int bc_unresolved(int value)
{
  return bc_missing_dependency(value);
}
