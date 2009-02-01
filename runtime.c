
signed int add(signed int a, signed int b)
{
  return a + b;
}

signed int sub(signed int a, signed int b)
{
  return a - b;
}

signed int div(signed int a, signed int b)
{
  return a / b;
}

signed int mul(signed int a, signed int b)
{
  return a * b;
}

signed int ne(signed int a, signed int b)
{
  return a != b;
}

signed int eq(signed int a, signed int b)
{
  return a == b;
}

signed int not(signed int a)
{
  return !a;
}

// Note that our "and" won't shortcircuit, as the
// evaluation happens before this function is called.
signed int and(signed int a, signed int b)
{
  return a && b;
}

signed int gt(signed int a, signed int b)
{
  return a > b;
}

signed int lt(signed int a, signed int b)
{
  return a < b;
}

